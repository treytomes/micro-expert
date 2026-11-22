// The shared API layer's suite: argument splitting, parameter validation, .env reading.
//
// Run: 3rd-party/miniscript-linux/miniscript src/api/test/run.ms
// Exit code 0 means every check passed. Nothing here touches the network: the split and the
// parameter table are pure, and the .env cases read a fixture beside them.
//
// A test runner asks for part of the suite instead:
//
//   miniscript src/api/test/run.ms --json --filter "a bare word" --file arguments.ms
//
// --filter takes a substring of a check's name, --file the name of a case module, and
// --json adds the ##TEST/##END records a runner reads. See ../../../test/harness.ms.

// The cli library is not under this folder and a bare import resolves against the entry
// folder, so the path is put back afterwards.
savedImportPath = env["MS_IMPORT_PATH"]
env["MS_IMPORT_PATH"] = "src"
import "cli/cli"
env["MS_IMPORT_PATH"] = savedImportPath

import "../../../test/harness"
harnessSource = globals["../../../test/harness"]
import "../client"
import "../dotenv"
import "arguments"
import "parameters"
import "dotenv"

// shellArgs[0] is this script, so the options start at index 1.
wanted = {"json": 0, "filters": [], "files": []}
at = 1
while at < shellArgs.len
	arg = shellArgs[at]
	if arg == "--filter" or arg == "--file" then
		if at + 1 >= shellArgs.len then
			print "error: " + arg + " needs a value"
			exit 1
		end if
		if arg == "--filter" then
			wanted.filters.push(shellArgs[at + 1])
		else
			wanted.files.push(shellArgs[at + 1])
		end if
		at = at + 2
	else if arg == "--json" then
		wanted.json = 1
		at = at + 1
	else
		print "error: unknown argument " + arg + " (--filter NAME, --file MODULE, --json)"
		exit 1
	end if
end while

harnessSource.options.json = wanted.json
harnessSource.options.filters = wanted.filters
harnessSource.options.files = wanted.files

cliSource = globals["cli/cli"]
clientSource = globals["../client"]
dotenvSource = globals["../dotenv"]
argumentCases = globals["arguments"]
parameterCases = globals["parameters"]
dotenvCases = globals["dotenv"]

// A module that loaded without the one function its cases lean on would otherwise surface
// as a puzzling error inside a case, so check that much up front.
if cliSource == null or clientSource.hasIndex("splitArguments") == 0 or dotenvSource.hasIndex("find") == 0 then
	print "error: a module the suite needs did not load"
	exit 1
end if

argumentCases.run(cliSource, clientSource, harnessSource)
parameterCases.run(clientSource, harnessSource)
dotenvCases.run(dotenvSource, harnessSource)

harnessSource.summary()
