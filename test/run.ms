// The micro-expert test suite.
//
// Run: 3rd-party\miniscript-win\miniscript.exe test\run.ms
// Exit code 0 means every check passed.
//
// The API layer's cases are here too: the split of a command line into options and the
// words a program reads itself, the parameter table's checks, both services' reply classes
// and the .env reader. That layer is part of this program rather than a library with a suite
// of its own, so its cases share this runner, its --file names and its totals.
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
// reader reach temporal.ms by bare import, rules.ms and facts.ms name their neighbours the
// same way, and session.ms reaches the repl library likewise, since a
// two-segment import inside a module binds no name. The interpreter resolves a bare import
// inside a module against the entry folder, which is this one, so without the path none of
// those would be found. The library loads before the session, as src/session.ms requires; its
// header says why. The path is put back afterwards, so the case modules below load as they
// would alone.
savedImportPath = env["MS_IMPORT_PATH"]
// src/notebook.ms imports the service maps, which reach the API client and the bundled json
// beside the interpreter, and a src-only path hides that folder: it goes on the path too, so the
// same load order works here as it does when the notebook is the program.
env["MS_IMPORT_PATH"] = "src:3rd-party/miniscript-linux/lib"
import "cli/cli"
import "repl/repl"
import "../src/triples"
import "../src/rule"
import "../src/knowledge"
import "../src/temporal"
import "../src/domain"
import "../src/options"
import "../src/session"
import "../src/engine"
import "../src/notebook"
import "../src/rules"
import "../src/facts"
import "../src/schema"
import "../src/mermaid"
env["MS_IMPORT_PATH"] = savedImportPath

// The API layer's client reaches the bundled json and stringUtil libraries, which a src/-only
// import path hides, so it loads here, with the .env reader beside it.
import "../src/api/http_client"
// Importing the .env reader puts the repository's .env into env; the suite pins the one setting
// a declaration reads there, so a check never passes on this machine's file and fails on another's.
// The geocoder's cases set and clear the variable themselves; every other request sees this value.
import "../src/dotenv"
env["GEOCODE_MAPS_API_KEY"] = "test-key"
import "../src/uid"
import "../src/location"
// The declared writer and the loader that reads the three service documents beside it;
// `declared` below is the case module.
import "../src/services/declared"
import "../src/services/loader"
// A declaration as a file: the reader, the writer, groups and arguments.
import "../src/services/document"
// The registry the service maps declare their capabilities in.
import "../src/providers"

import "harness"
import "display"
import "proofs"
import "absence"
import "recursion"
import "relations"
import "session"
import "knowledge"
import "temporal"
import "repl"
import "schema"
import "mermaid"
import "loaders"
import "serviceLoader"
import "document"
import "domain"
import "options"
import "arguments"
import "parameters"
import "dotenv"
import "uid"
import "location"
import "declared"
import "geocoder"
import "openmeteo"
import "providers"
import "notebook"

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
// `temporal` is this suite's own case module for the date types, so the module itself is
// aliased to `dates` and reached as `dateCases` below.
dates = globals["../src/temporal"]
dateCases = globals["temporal"]
// The Mermaid exporter's cases, aliased away from the module they test the same way.
mermaidCases = globals["mermaid"]
// domain.ms places the three data files a run reads; it is aliased away from the case
// module below, which is named domain.ms too.
domainModule = globals["../src/domain"]
// options.ms is the program's option table; `options` is this suite's case module for it.
optionsModule = globals["../src/options"]
// The API layer's shared client, for the cases about the argument split and the parameter
// engine. `arguments` and `parameters` are this suite's case modules for it.
apiClient = globals["../src/api/http_client"]
argumentCases = globals["arguments"]
parameterCases = globals["parameters"]
// src/dotenv.ms puts the .env's settings into env; `dotenv` is this suite's case module.
dotenvModule = globals["../src/dotenv"]
dotenvCases = globals["dotenv"]
// src/uid.ms generates the term an entity is named by; `uid` is this suite's case module for it.
uidModule = globals["../src/uid"]
uidCases = globals["uid"]
// src/location.ms turns a lookup into facts about the session; `location` is this suite's case
// module for it, named away from the session module the cases must not be confused with.
locationModule = globals["../src/location"]
locationCases = globals["location"]
// src/services/declared.ms is the shared writer; `declared` is this suite's case module for it.
declaredModule = globals["../src/services/declared"]
declaredCases = globals["declared"]
// `geocoder` and `openmeteo` are this suite's case modules for the two documents the loader reads
// beside it.
geocoderCases = globals["geocoder"]
openmeteoCases = globals["openmeteo"]
// src/services/loader.ms finds every service document in a folder and reads it; `document` below
// is this suite's case module for the reader it reads them with, and `serviceLoader` its case
// module for the loader itself.
loaderModule = globals["../src/services/loader"]
serviceLoaderCases = globals["serviceLoader"]
// src/services/document.ms reads and writes a declaration as a file; `document` is this suite's
// case module for it.
documentModule = globals["../src/services/document"]
documentCases = globals["document"]
// The three shipped services are documents in ./services, so one call reads them all. The loader
// places that folder through knowledge.resolvePath, the way the domain's data files are placed, and
// a refused file is an error beside its name rather than a stop - so a document left unreadable
// fails by name here rather than in a round trip later.
loaded = loaderModule.load(documentModule, globals["../src/knowledge"])
harness.require("the loader reads every .grfon in ./services", loaded isa map, loaded)
if not (loaded isa map) then
	print "error: could not load the service documents in src/services"
	exit 1
end if
for name in ["ipwhois.grfon", "geocode.grfon", "openmeteo.grfon"]
	if not loaded.hasIndex(name) then
		print "error: the loader did not find " + name
		exit 1
	end if
	if loaded[name] isa error then
		print "error: " + loaded[name].message
		exit 1
	end if
end for
// Each document declares the service it is meant to, so a file standing beside the wrong name is
// caught here.
for pair in [["ipwhois.grfon", "ipwho.is"], ["geocode.grfon", "geocode.maps.co"],
		["openmeteo.grfon", "open-meteo"]]
	harness.require(pair[0] + " reads as " + pair[1],
		loaded[pair[0]] isa map and loaded[pair[0]].service == pair[1], loaded[pair[0]])
end for
// Read once here, so the cases below take the map rather than the module.
ipwhoisDecl = loaded["ipwhois.grfon"]
geocodeDecl = loaded["geocode.grfon"]
openmeteoDecl = loaded["openmeteo.grfon"]
// src/providers.ms is the registry of what those maps say they can answer; `providers` is this
// suite's case module for it.
providersModule = globals["../src/providers"]
providersCases = globals["providers"]

// The library and the session module, both loaded by the block above.
replLibrary = globals["repl/repl"]
// The argument parser, for the checks that read the program's option table back.
cliLibrary = globals["cli/cli"]
sessionModule = globals["../src/session"]
// engine.ms builds the session a run is made of, and notebook.ms serves that session to a
// notebook; `notebook` is this suite's case module for the protocol, so the module itself is
// aliased away the same way.
engineModule = globals["../src/engine"]
notebookModule = globals["../src/notebook"]
notebookCases = globals["notebook"]

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
	print "error: could not import ../src/api/http_client"
	exit 1
end if
if dotenvModule == null or dotenvModule.hasIndex("load") == 0 then
	print "error: could not import ../src/dotenv"
	exit 1
end if
if uidModule == null or uidModule.hasIndex("of") == 0 then
	print "error: could not import ../src/uid"
	exit 1
end if
if locationModule == null or locationModule.hasIndex("sessionFacts") == 0 then
	print "error: could not import ../src/location"
	exit 1
end if
if declaredModule == null or declaredModule.hasIndex("read") == 0 then
	print "error: could not import ../src/services/declared"
	exit 1
end if
if loaderModule == null or loaderModule.hasIndex("load") == 0 then
	print "error: could not import ../src/services/loader"
	exit 1
end if

if providersModule == null or providersModule.hasIndex("registry") == 0 then
	print "error: could not import ../src/providers"
	exit 1
end if

if engineModule == null or engineModule.hasIndex("build") == 0 then
	print "error: could not import ../src/engine"
	exit 1
end if
if notebookModule == null or notebookModule.hasIndex("serve") == 0 then
	print "error: could not import ../src/notebook"
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
	"needsConditions",
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
serviceLoaderCases.run(loaderModule, documentModule, globals["../src/knowledge"], harness)
globals["domain"].run(domainModule, harness)
globals["options"].run(cliLibrary, optionsModule, harness)
argumentCases.run(cliLibrary, apiClient, harness)
parameterCases.run(apiClient, harness)
dotenvCases.run(dotenvModule, harness)
uidCases.run(uidModule, triples, harness)
locationCases.run(locationModule, uidModule, triples, apiClient, declaredModule, ipwhoisDecl, harness)
declaredCases.run(declaredModule, ipwhoisDecl, apiClient, triples, uidModule, harness)
documentCases.run(documentModule, geocodeDecl, openmeteoDecl, ipwhoisDecl, harness)
geocoderCases.run(declaredModule, geocodeDecl, apiClient, triples, uidModule, schemaLoader, harness)
openmeteoCases.run(declaredModule, openmeteoDecl, apiClient, triples, uidModule, schemaLoader, harness)
providersCases.run(providersModule, declaredModule, apiClient, triples, uidModule, ipwhoisDecl,
	geocodeDecl, openmeteoDecl, sessionModule, rules, engineModule, cliLibrary, optionsModule, parser,
	harness)
notebookCases.run(notebookModule, engineModule, sessionModule, triples, rules, cliLibrary, optionsModule, harness)

harness.summary()
