# cxx2hx - C++ -> Haxe Externs

Generate [Reflaxe/C++](https://github.com/RobertBorghese/reflaxe.CPP) Haxe externs from C++ header files (for use with target)

This is, and will always be, an imperfect project. The externs generated from this are not meant to be used directly; rather, they should be used as a base that are manually tweaked to remove any Haxe errors that may occur.

All the bloated, repetitive stuff is taken care of, but the minor tweaks and details still need to be taken care of.

ALSO PLEASE NOTE this is not generating externs for the Haxe/C++ target (this could still help with that, but some metadata will need to be replaced manually).

## How to use

Install using Haxelib:

```
haxelib install cxx2hx
```

Run the script:

```
haxelib run cxx2hx <path_to_directory_with_header_files>
```
