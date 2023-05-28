/**

	C++ to Haxe Script

	Given a directory containing C++ header files, this program
	attempts to generate Haxe externs. The Haxe externs are not
	meant to be perfect and will likely not function, but work
	as a good starting point for writing manual C++ externs.

	Intended to be used with the Reflaxe/C++ target.

	(c) Robert Borghese 2023

	MIT License

**/

import haxe.io.Path;
import sys.io.Process;
import sys.io.File;
import sys.FileSystem;

using StringTools;

/**
	Quick way to write `DynamicAccess`.
**/
typedef ItDyn = haxe.DynamicAccess<Dynamic>;

/**
	The name of the directory
**/
final OUTPUT_DIR = "hx_out";

/**
	The directory the script was called in.
**/
var CWD = "";

/**
	Save file relative to `CWD`.
**/
function saveFile(path: String, content: String) {
	File.saveContent(Path.join([CWD, path]), content);
}

/**
	Create dir relative to `CWD`.
**/
function createDir(path: String) {
	final p = Path.join([CWD, path]);
	if(!FileSystem.exists(p))
		FileSystem.createDirectory(p);
}

/**
	Runs the script.
**/
function main() {
	final args = Sys.args();
	if(args.length < 2) {
		print("There are missing arguments:");
		print("haxelib run cxx2hx <folder_with_headers> [include_prepend_path]");
		Sys.exit(1);
	}

	final folder = args[0];
	if(!FileSystem.exists(folder)) {
		print('`$folder` does not exist.');
		Sys.exit(1);
	} else if(!FileSystem.isDirectory(folder)) {
		print('`$folder` is not a directory.');
		Sys.exit(1);
	}

	CWD = {
		final lastArg = args[args.length - 1];
		if(args.length > 1 && FileSystem.exists(lastArg) && FileSystem.isDirectory(lastArg)) {
			lastArg;
		} else {
			Sys.getCwd();
		}
	}

	final out = Path.join([CWD, OUTPUT_DIR]);
	if(FileSystem.exists(out) && args[1] != "true") {
		print('Please note `$out` exists already. Please delete before running this script.');
		Sys.exit(1);
	}

	printTitle();
	print("Generates basic Reflaxe/C++ externs. Please note these externs will NOT be perfect and should be used as a starting point for manually creating externs.");
	
	line();

	print("First... let us check that you have Python installed...");

	{
		final cmd = "python --version";
		printCommand(cmd);
		final p = new Process(cmd);
		if(p.exitCode(true) == 0) {
			print("✅ Python found!");
		} else {
			print("❌ Python could not be found? Please install Python and/or add it to your PATH.");
			Sys.exit(1);
		}
	}

	line();

	print("Next... let us check if `robotpy-cppheaderparser` is installed on Pip...");

	{
		final cmd = "python -m pip show robotpy-cppheaderparser";
		printCommand(cmd);
		final p = new Process(cmd);
		if(p.exitCode(true) == 0) {
			print("✅ robotpy-cppheaderparser found!");
		} else {
			print("❌ robotpy-cppheaderparser could not be found? Please install by running the following command:");
			print("python -m pip install robotpy-cppheaderparser");
			Sys.exit(1);
		}
	}

	line();

	print("Look good! Time to start extern generation!");

	final files = getAllHeaders(folder);

	print('Found ${files.length} header files!');
	
	if(!FileSystem.exists(out)) {
		FileSystem.createDirectory(out);
	}

	for(f in files) {
		final p = new Process('python Main.py "${Path.join([folder, f])}"');
		final ec = p.exitCode(true);
		if(ec == 0) {
			generateExtern(f);
		} else {
			print("Python returned code: " + ec);
			print(p.stderr.readAll().toString());
		}
	}

	print("Done. Thank you for using!");
}

// ---

function dataJsonPath(info: Null<haxe.PosInfos> = null) {
	return "./data.json";
}

/**
	Generate all content from the header file at `filePath`.
**/
function generateExtern(filePath: String) {
	final json = try {
		File.getContent(dataJsonPath());
	} catch(e) {
		print(e.message);
		return;
	}

	final data = try {
		haxe.Json.parse(json);
	} catch(e) {
		print(e.message);
		return;
	}

	if(data.classes != null) {
		final classes: haxe.DynamicAccess<Dynamic> = data.classes;
		for(_ => cls in classes) {
			compileClass(cls, filePath);
		}
	}

	if(data.enums != null) {
		final it = data.enums.iterator();
		while(it.hasNext()) {
			final e = it.next();
			compileEnum(e, filePath);
		}
	}

	if(data.functions != null) {
		final functions = [];
		final it = data.functions.iterator();
		while(it.hasNext()) {
			final n = it.next();
			functions.push(n);
		}
		compileFunctions(functions, filePath);
	}
}

/**
	Convert a C++ namespace into a list of lower-case members:

	MyCPP::NameSpace -> ["mycpp", "namespace"]
**/
function getNamespaceMembers(ns: String): Array<String> {
	return ns
		.split("::")
		.filter(s -> s != null && s.length > 0)
		.map(s -> s.toLowerCase());
}

/**
	Works the same as `getNamespaceMembers`, but the last member
	of the pack is used to provide a Haxe-compliant class name to
	be used to wrap top-level functions.
**/
function getFuncNamespaceMembers(ns: String): { pack: Array<String>, name: String } {
	final members = ns.split("::").filter(s -> s != null && s.length > 0);
	return {
		pack: members.slice(0, -1).map(s -> s.toLowerCase()),
		name: members[members.length - 1]
	}
}

/**
	Ensures the C++ variable name is a valid Haxe variable name.
**/
function generateVarName(name: Null<String>): String {
	if(name != null && name.length > 0 && ~/^[A-Za-z0-9_]+$/.match(name)) {
		return name;
	}
	return "_";
}

/**
	Generate an extern enum in Haxe from the enum data
	from C++.
**/
function compileEnum(e: Dynamic, filePath: String) {
	if(e == null) return;
	if(!shouldGenClass(e)) return;
	if(e.values.length == 0) return; // if no values, assume forward declare?

	replacementTypes = [];

	final ns = getNamespaceMembers(e.namespace);
	final folder = Path.join([OUTPUT_DIR].concat(ns));
	createDir(folder);

	// Generate Haxe version of name
	final clsName: String = e.name;
	final haxeName = haxeifyTypeName(clsName);

	// Generate meta
	final meta = [];
	meta.push([":native", ns.concat([clsName]).join("::")]);
	meta.push([":valueType"]);
	meta.push([":include", filePath]);

	final metas = generateMeta(meta);

	// Values
	final members = [];
	{
		final it = e.values.iterator();
		while(it.hasNext()) {
			final v = it.next();
			members.push(v.name + ";");
		}
	}

	// Put it all together
	final hx = 'package ${ns.join(".")};

$metas
extern enum $haxeName {
	${members.join("\n\t")}
}';

	saveFile(folder + "/" + haxeName + ".hx", hx);
}

/**
	From a list of top-level C++ functions, generate an extern
	class with a bunch of static functions.
**/
function compileFunctions(functions: Array<Dynamic>, filePath: String) {
	final funcs: Map<String, Array<Dynamic>> = [];

	replacementTypes = [];

	for(f in functions) {
		final fList = funcs.get(f.namespace) ?? [];
		fList.push(f);
		funcs.set(f.namespace, fList);
	}

	for(namespace => funcList in funcs) {
		final funcNs = getFuncNamespaceMembers(namespace);
		final ns = funcNs.pack;
		final clsName = funcNs.name;
		final folder = Path.join([OUTPUT_DIR].concat(ns));
		createDir(folder);

		final haxeName = haxeifyTypeName(clsName);

		// Generate meta
		final meta = [];
		meta.push([":native", ns.concat([clsName]).join("::")]);
		meta.push([":valueType"]);
		meta.push([":include", filePath]);

		final metas = generateMeta(meta);

		// Functions
		final count: Map<String, Int> = [];
		for(func in funcList) {
			count.set(func.name, (count.get(func.name) ?? 0) + 1);
		}

		final methods = [];
		for(func in funcList) {
			Reflect.setField(func, "static", true);
			final isOverload = count.get(func.name) > 1;
			final m = genMethod(func, isOverload);
			if(m != null) methods.push(m);
		}

		// Put it all together
	final hx = 'package ${ns.join("::")};

$metas
extern class $haxeName {
	${methods.join("\n\t")}
}';
		
		saveFile(folder + "/" + haxeName + ".hx", hx);
	}
}

/**
	If a type is generated that exists as a key in
	this Map, it is replaced with the Map's value.
**/
var replacementTypes: Map<String, String> = [];

/**
	Generate a Haxe extern class using the data from
	the C++ class.
**/
function compileClass(cls: Dynamic, filePath: String) {
	if(cls == null) return;
	if(!shouldGenClass(cls)) return;
	if(
		cls.properties.length == 0 &&
		cls.methods.length == 0 &&
		cls.enums.length == 0 &&
		cls.nested_classes.length == 0
	) return; // is probably forward declare

	// Generate Haxe version of name
	final clsName: String = cls.name;
	final haxeName = haxeifyTypeName(clsName);

	// Compile the enums
	if(cls.enums != null) {
		final it = Reflect.getProperty(cls.enums, "public").iterator();
		while(it.hasNext()) {
			final e = it.next();
			compileEnum(e, filePath);
		}
	}

	replacementTypes = [];

	final usings = Reflect.field(cls, "using");
	if(usings != null) {
		for(field in Reflect.fields(usings)) {
			final name = field;
			final data = Reflect.field(usings, field);
			replacementTypes.set(name, data.type);
		}
	}

	final ns = getNamespaceMembers(cls.namespace);
	final folder = Path.join([OUTPUT_DIR].concat(ns));
	createDir(folder);

	// Generate meta
	final meta = [];
	meta.push([":native", [cls.namespace, clsName].join("::")]);
	meta.push([":valueType"]);
	meta.push([":include", filePath]);

	final metas = generateMeta(meta);

	// Variables
	final properties = [];
	for(section => props in (cls.properties : ItDyn)) {
		if(props != null && section == "public") {
			if(props.length > 0) {
				final it = props.iterator();
				while(it.hasNext()) {
					final prop = it.next();
					if(prop != null) {
						final v = genVariable(prop);
						if(v != null) properties.push(v);
					}
				}
			}
		}
	}

	// Methods
	final methodData: Array<Dynamic> = [];
	final constructors: Array<Dynamic> = [];
	final count: Map<String, Int> = [];
	for(section => props in (cls.methods : ItDyn)) {
		if(props != null && section == "public") {
			if(props.length > 0) {
				final it = props.iterator();
				while(it.hasNext()) {
					final prop = it.next();
					if(prop != null) {
						final isConstructor = prop.constructor;
						final isDestructor = prop.destructor;
						if(isConstructor) {
							constructors.push(prop);
						} else if(!isDestructor) {
							methodData.push(prop);
							count.set(prop.name, (count.get(prop.name) ?? 0) + 1);
						}
					}
				}
			}
		}
	}

	var mainConstructor: Null<Dynamic> = null;
	var mainConstructorArgCount: Int = 99999;
	for(c in constructors) {
		final paramLen = c.parameters?.length ?? 0;
		if(paramLen < mainConstructorArgCount) {
			mainConstructor = c;
			mainConstructorArgCount = paramLen;
		}
	}

	final methods = [];

	if(mainConstructor != null) {
		constructors.remove(mainConstructor);
		final m = genMethod(mainConstructor, false);
		if(m != null) methods.push(m);
	}

	final multipleConstructors = constructors.length > 1;
	for(c in constructors) {
		Reflect.setField(c, "name", "construct");
		Reflect.setField(c, "static", true);
		Reflect.setField(c, "constructor", false);
		final m = genMethod(c, multipleConstructors, [[":constructor"]]);
		if(m != null) methods.push(m);
	}
	
	final methodKeys: Map<String, Bool> = [];
	for(i in 0...methodData.length) {
		final prop = methodData[i];
		final isOverload = count.get(prop.name) > 1;

		// Make sure there aren't any obvious repeats
		final key = prop.name + "(" + prop.parameters.map(p -> p.name).join(", ") + ")";
		if(methodKeys.exists(key)) {
			continue;
		} else {
			methodKeys.set(key, true);
		}

		final m = genMethod(prop, isOverload);
		if(m != null) methods.push(m);
	}

	var typeArgs = null;
	final template = Reflect.field(cls, "template");
	if(template != null && template.length > 0) {
		final r = ~/^template\s*<\s*(.*)\s*>$/;
		if(r.match(template)) {
			final cppTypeArgs = r.matched(1).split(",").map(s -> s.trim());
			for(cta in cppTypeArgs) {
				final argReg = ~/^typename\s*([A-Za-z0-9_]+)$/;
				if(argReg.match(cta)) {
					final name = argReg.matched(1);
					if(typeArgs == null) typeArgs = [];
					typeArgs.push(name);
				}
			}
		}
	}

	final typeArgCpp = typeArgs != null ? ("<" + typeArgs.map(t -> t + " = Void").join(", ") + ">") : "";

	// Put it all together
	final hx = 'package ${cls.namespace};

$metas
extern class $haxeName$typeArgCpp {
	${properties.concat(methods).join("\n\t")}
}';

	saveFile(folder + "/" + haxeName + ".hx", hx);
}

/**
	Generate Haxe metadata from an array of string arrays:

	[
		[":metaName"],
		[":anotherMeta", "arg1", "arg2"]
	]
**/
function generateMeta(meta: Array<Array<String>>, tab: Bool = false): String {
	return meta.map(function(m) {
		return m.length == 1 ? '@${m[0]}' : '@${m[0]}("${m.slice(1).join(", ")}")';
	}).join(tab ? "\n\t" : "\n");
}

/**
	Returns `true` if the class data should be used to
	generate an extern class in Haxe.
**/
function shouldGenClass(cls: Dynamic): Bool {
	final n: String = cls.name;
	if(n == null) return false;
	return !n.contains("<");
}

/**
	Provides the Haxe code for the C++ class field.
**/
function genVariable(varData: Dynamic): Null<String> {
	if(varData.name == null) return null;
	final t = genType(varData.type);
	if(t == null) return null;
	return 'public var ${varData.name}: $t;';
}

/**
	Provides the Haxe code for the C++ function/method.
**/
function genMethod(funcData: Dynamic, isOverload: Bool, extraMeta: Null<Array<Array<String>>> = null): Null<String> {
	final args = [];
	if(funcData.parameters != null) {
		final it = funcData.parameters.iterator();
		while(it.hasNext()) {
			final p = it.next();
			final t = genType(p.type);
			if(t == null) return null;
			final name = generateVarName(p.name);
			args.push('$name: $t');
		}
	}

	final p = args.join(", ");

	if(funcData.name == null) return null;
	final name = haxeifyFunctionName(funcData.name);
	if(name == "") return null;
	var haxeName = name ?? funcData.name;
	if(funcData.constructor) {
		haxeName = "new";
	}

	final meta = extraMeta ?? [];
	if(name != null) {
		meta.push([":nativeName", funcData.name]);
	}

	final keywords = [];
	if(Reflect.getProperty(funcData, "static"))
		keywords.push("static");
	if(Reflect.getProperty(funcData, "override"))
		keywords.push("override");
	if(isOverload)
		keywords.push("overload");
	if(Reflect.getProperty(funcData, "inline"))
		meta.push([":cppInline"]);
	if(Reflect.getProperty(funcData, "const"))
		meta.push([":const"]);
	if(Reflect.getProperty(funcData, "noexcept"))
		meta.push([":noExcept"]);

	var metaHx = generateMeta(meta, true);
	if(metaHx.length > 0) metaHx = "\n\t" + metaHx + "\n\t";

	final t = genType(funcData.rtnType);
	if(t == null) return null;
	final attr = keywords.length > 0 ? keywords.join(" ") + " " : "";
	return metaHx + 'public ${attr}function ${haxeName}(${p}): $t;';
}

/**
	Generates the Haxe equivalent of the C++ type string.
**/
function genType(typeName: String): Null<String> {
	typeName = typeName.trim();
	if(replacementTypes.exists(typeName)) {
		typeName = replacementTypes.get(typeName);
	}
	
	final wraps = [];
	function unwrapExtras(n: String): String {
		final t = n.trim();
		if(t.startsWith("const")) {
			// not implemented in Reflaxe/C++ yet
			// wraps.unshift("cxx.Const");
			return unwrapExtras(t.substring(5));
		} else if(t.endsWith("&")) {
			wraps.unshift("cxx.Ref");
			return unwrapExtras(t.substring(0, t.length - 1));
		} else if(t.endsWith("*")) {
			wraps.unshift("cxx.Ptr");
			return unwrapExtras(t.substring(0, t.length - 1));
		}
		return t;
	}

	typeName = unwrapExtras(typeName);

	function unwrapTypeParams(n: String): String {
		final t = n.trim();
		final r = ~/^([A-Za-z0-9_]+)<\s*(.+)\s*>$/;
		if(r.match(t)) {
			wraps.unshift(haxeifyTypeName(r.matched(1)));
			return genType(r.matched(2));
		}
		return haxeifyTypeName(t);
	}

	final unwrapped = unwrapTypeParams(typeName);
	if(unwrapped == null) return null;
	typeName = unwrapped;

	for(w in wraps) {
		typeName = w + "<" + typeName + ">";
	}

	if(typeName.contains(" ")) {
		return null;
	}
	return typeName;
}

/**
	Transforms a name using underscore style to capital camel case.
**/
function haxeifyTypeName(n: String): String {
	var ntrim = n.trim();

	final namePieces: Array<String> = ntrim.split("_");
	var result = "";
	for(piece in namePieces) {
		result += piece.substring(0, 1).toUpperCase() + piece.substring(1);
	}

	final members = result.split("::");
	result = "";
	for(i in 0...members.length) {
		result += (i < members.length - 1) ? (members[i].toLowerCase() + ".") : {
			final temp = members[i];
			temp.substring(0, 1).toUpperCase() + temp.substring(1);
		}
	}

	return result;
}

/**
	Transforms a name using underscore style to camel case.	
**/
function haxeifyFunctionName(n: String): Null<String> {
	if(n == null) throw "Null error";
	return if(~/^[A-Za-z0-9_]+$/.match(n)) {
		if(n.contains("_")) {
			var result = haxeifyTypeName(n);
			result = result.substring(0, 1).toLowerCase() + result.substring(1);
			result;
		} else {
			null;
		}
	} else if(n.contains("operator")) {
		//"customOperator";
		""; // Ignore operators for now
	} else {
		~/[^A-Za-z0-9_]+/g.split(n).join("_");
	}
}

// ---

/**
	Recurisvely file all the .h files in a directory.
**/
function getAllHeaders(path: String, relativePath: String = ""): Array<String> {
	final result = [];
	if(FileSystem.exists(path) && FileSystem.isDirectory(path)) {
		final files = FileSystem.readDirectory(path);
		for(file in files) {
			final fullPath = Path.join([path, file]);
			if(FileSystem.isDirectory(fullPath)) {
				for(i in getAllHeaders(fullPath, file)) {
					result.push(i);
				}
			} else {
				final ext = Path.extension(file);
				if(ext == "h" || ext == "hpp") {
					result.push(Path.join([relativePath, file]));
				}
			}
		}
	}
	return result;
}

// ---

/**
	Print line separator.
**/
function line() {
	newline();
	print("---");
	newline();
}

/**
	Print blank new-line.
**/
function newline() {
	Sys.println("");
}

/**
	Print line.
**/
function print(p: String) {
	Sys.println(p);
}

/**
	Print line with "> " in front of it.
**/
function printCommand(p: String) {
	Sys.println("> " + p);
}

/**
	Prints the title of the program
**/
function printTitle() {
	print("
     ___   _      _         __     _   _    __    _  _  ____ 
    / __)_| |_  _| |_    ___\\ \\   ( )_( )  /__\\  ( \\/ )( ___)
   ( (__(_   _)(_   _)  (___)> >   ) _ (  /(__)\\  )  (  )__) 
    \\___) |_|    |_|        /_/   (_) (_)(__)(__)(_/\\_)(____)
");
}
