import sys
import os
import CppHeaderParser

if len(sys.argv) <= 1:
	print("Header file path missing.");
	sys.exit(1);

outpath = os.path.dirname(__file__) + "/data.json"

includeFile = sys.argv[1];

header = CppHeaderParser.CppHeader(includeFile);

f = open(outpath, "w");
try:
	f.write(header.toJSON());
except:
	print("Could not generate JSON or write file for: " + includeFile)
finally:
	f.close();
