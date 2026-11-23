// The micro-expert test suite.
//
// Run: 3rd-party\miniscript-win\miniscript.exe test\run.ms
// Exit code 0 means every check passed.
//
// The API layer's cases are here too: the split of a command line into options and the
// words a program reads itself, the parameter table's checks, the geocode reply classes and
// the .env reader. That layer is part of this program rather than a library with a suite of
// its own, so its cases share this runner, its --file names and its totals.
//
// A test runner asks for part of the suite instead:
//
//   miniscript.exe test\run.ms --json --filter "a rule line parses" --file session.ms
//
// --filter takes a substring of a check's name, --file the name of a case module, and
// --json adds the ##TEST/##END records a runner reads. See harness.ms.
//
// src/ is imported once, here, because a module that imports another module gets
// its own copy of it and `isa` checks only agree inside one copy. Each case
// module is handed this same copy rather than importing it itself; the import
// binds its path as the global name, so it is aliased below.
//
// The command-line parser, the logger and the repl library are their own repositories now, and
// each carries its own suite in its own test folder (src/cli/test, src/logging/test,
// src/repl/test), run from there by the same interpreter. This one covers what the demo itself
// contains, so it imports none of theirs; the single check it keeps about the library is in
// test/repl.ms, and it is about this repository's notes example rather than the library.

// The program's own modules load first, with src/ on the import path: the solver and the data
// reader reach datetimes.ms by bare import, rules.ms and facts.ms name their neighbours the
// same way, and session.ms reaches the repl library likewise, since a
// two-segment import inside a module binds no name. The interpreter resolves a bare import
// inside a module against the entry folder, which is this one, so without the path none of
// those would be found. The library loads before the session, as src/session.ms requires; its
// header says why. The path is put back afterwards, so the case modules below load as they
// would alone.
savedImportPath = env["MS_IMPORT_PATH"]
env["MS_IMPORT_PATH"] = "src"
import "cli/cli"
import "repl/repl"
import "../src/triples"
import "../src/rule"
import "../src/knowledge"
import "../src/datetimes"
import "../src/domain"
import "../src/options"
import "../src/session"
import "../src/rules"
import "../src/facts"
import "../src/schema"
import "../src/mermaid"
env["MS_IMPORT_PATH"] = savedImportPath

// The API layer's client reaches the bundled json and stringUtil libraries, which a src/-only
// import path hides, so it loads here, with the .env reader beside it. geocode.ms imports
// nothing, and is here for the cases about the reply it reads the service's JSON into.
import "../src/api/client"
import "../src/api/geocode"
import "../src/dotenv"

import "harness"
import "display"
import "proofs"
import "absence"
import "recursion"
import "relations"
import "session"
import "knowledge"
import "datetimes"
import "repl"
import "schema"
import "mermaid"
import "loaders"
import "domain"
import "options"
import "arguments"
import "parameters"
import "replies"
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

harness.options.json = wanted.json
harness.options.filters = wanted.filters
harness.options.files = wanted.files

triples = globals["../src/triples"]
// rule.ms holds the Rule class; the cases build the rules they test with it.
rules = globals["../src/rule"]
// `session` is this suite's own case module for the file under test, so the module itself is
// aliased to `sessionModule` once it is loaded below. `repl` keeps the one check about this
// repository's notes example; the library's own cases stay in the submodule and run there.
sessionCases = globals["session"]
replCases = globals["repl"]
// knowledge.ms is the parser behind the data files, aliased away for the same reason:
// `knowledge` is this suite's own case module for it.
parser = globals["../src/knowledge"]
// `datetimes` is this suite's own case module for the date types, so the module itself is
// aliased to `dates` and reached as `dateCases` below.
dates = globals["../src/datetimes"]
dateCases = globals["datetimes"]
// The Mermaid exporter's cases, aliased away from the module they test the same way.
mermaidCases = globals["mermaid"]
// domain.ms places the three data files a run reads; it is aliased away from the case
// module below, which is named domain.ms too.
domainModule = globals["../src/domain"]
// options.ms is the program's option table; `options` is this suite's case module for it.
optionsModule = globals["../src/options"]
// The API layer's shared client, for the cases about the argument split and the parameter
// engine. `arguments` and `parameters` are this suite's case modules for it.
apiClient = globals["../src/api/client"]
argumentCases = globals["arguments"]
parameterCases = globals["parameters"]
// geocode.ms is the geocoder's surface and the classes its replies come back as; `replies`
// is this suite's case module for those classes.
geocode = globals["../src/api/geocode"]
replyCases = globals["replies"]
// src/dotenv.ms reads .env files and finds settings; `dotenv` is this suite's case module.
dotenvModule = globals["../src/dotenv"]
dotenvCases = globals["dotenv"]

// The library and the session module, both loaded by the block above.
replLibrary = globals["repl/repl"]
// The argument parser, for the checks that read the program's option table back.
cliLibrary = globals["cli/cli"]
sessionModule = globals["../src/session"]

// The loaders themselves, so the cases can read the data files the program ships.
rulesLoader = globals["../src/rules"]
factsLoader = globals["../src/facts"]
// The schema loader, for the checks that read data/schema.kb itself.
schemaLoader = globals["../src/schema"]
// mermaid.ms draws the facts a session holds; `mermaid` below is this suite's case module.
mermaidModule = globals["../src/mermaid"]

if triples == null or rules == null or parser == null or replLibrary == null then
	print "error: could not import ../src/triples, ../src/rule, ../src/knowledge and ../src/repl/repl"
	exit 1
end if
if rulesLoader == null or factsLoader == null or schemaLoader == null then
	print "error: could not import ../src/rules, ../src/facts and ../src/schema"
	exit 1
end if
if cliLibrary == null or optionsModule == null or optionsModule.hasIndex("declare") == 0 then
	print "error: could not import cli/cli and ../src/options"
	exit 1
end if

if apiClient == null or apiClient.hasIndex("splitArguments") == 0 then
	print "error: could not import ../src/api/client"
	exit 1
end if
if geocode == null or geocode.hasIndex("reply") == 0 then
	print "error: could not import ../src/api/geocode"
	exit 1
end if
if dotenvModule == null or dotenvModule.hasIndex("find") == 0 then
	print "error: could not import ../src/dotenv"
	exit 1
end if

if mermaidModule == null or mermaidModule.hasIndex("build") == 0 then
	print "error: could not import ../src/mermaid"
	exit 1
end if

// A partly loaded module would otherwise surface as a puzzling error inside one
// case, so check the surface the suite relies on up front.
for name in ["SpoTriple", "proveGoals", "substitute", "NotEqual", "Equal", "Comparison", "isConstraint",
	"constraintOf", "proofLines", "Or", "Not", "standardizeApart", "parseRule", "needsFor",
	"reportLines", "reportLabels", "unboundVars", "paint"]
	if triples.hasIndex(name) == 0 then
		print "error: ../src/triples loaded without " + name
		exit 1
	end if
end for
if rules.hasIndex("Rule") == 0 then
	print "error: ../src/rule loaded without Rule"
	exit 1
end if
for name in ["run", "runCommand", "say", "ask", "trimSpace", "writeLines", "saveCommand",
	"loadCommand", "componentCommands"]
	if replLibrary.hasIndex(name) == 0 then
		print "error: ../src/repl/repl loaded without " + name
		exit 1
	end if
end for

display.run(triples, harness)
knowledge.run(triples, parser, harness)
proofs.run(triples, rules, harness)
absence.run(triples, rules, harness)
recursion.run(triples, rules, harness)
relations.run(triples, rules, harness)
sessionCases.run(triples, rules, sessionModule, harness, schemaLoader, parser, replLibrary)
replCases.run(harness)
dateCases.run(triples, parser, dates, harness)
schema.run(triples, parser, schemaLoader, harness)
mermaidCases.run(triples, mermaidModule, parser, schemaLoader, factsLoader, rulesLoader, harness)
loaders.run(triples, rulesLoader, factsLoader, schemaLoader, harness)
globals["domain"].run(domainModule, harness)
globals["options"].run(cliLibrary, optionsModule, harness)
argumentCases.run(cliLibrary, apiClient, harness)
parameterCases.run(apiClient, harness)
replyCases.run(geocode, harness)
dotenvCases.run(dotenvModule, harness)

harness.summary()
