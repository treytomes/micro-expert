// The micro-expert test suite.
//
// Run: 3rd-party\miniscript-win\miniscript.exe test\run.ms
// Exit code 0 means every check passed.
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
// The command-line parser and the logger are their own repositories now, and each carries
// its own suite; this one covers what the demo itself contains.

import "../src/triples"
import "../src/rule"
import "../src/knowledge"
import "../src/domain"
import "harness"
import "display"
import "proofs"
import "absence"
import "recursion"
import "relations"
import "session"
import "knowledge"
import "repl"
import "schema"
import "loaders"
import "domain"

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
// `session` and `repl` are this suite's own case modules for the two files under test, so the
// modules themselves are aliased to `sessionModule` and `replLibrary` once they are loaded below.
sessionCases = globals["session"]
replCases = globals["repl"]
// knowledge.ms is the parser behind the data files, aliased away for the same reason:
// `knowledge` is this suite's own case module for it.
parser = globals["../src/knowledge"]
// domain.ms places the three data files a run reads; it is aliased away from the case
// module below, which is named domain.ms too.
domainModule = globals["../src/domain"]

// rules.ms and facts.ms name their neighbours by bare import, which the interpreter resolves
// against the entry folder, so src/ goes on the import path for those loads; session.ms reaches
// the repl library the same way, since a two-segment import inside a module binds no name. The
// library loads first, as src/session.ms requires; its header says why. The path is put
// back afterwards, so the suite leaves the environment as it found it.
savedImportPath = env["MS_IMPORT_PATH"]
env["MS_IMPORT_PATH"] = "src"
import "repl/repl"
import "../src/session"
import "../src/rules"
import "../src/facts"
import "../src/schema"
env["MS_IMPORT_PATH"] = savedImportPath

// The library and the session module, both loaded by the block above.
replLibrary = globals["repl/repl"]
sessionModule = globals["../src/session"]

// The loaders themselves, so the cases can read the data files the program ships.
rulesLoader = globals["../src/rules"]
factsLoader = globals["../src/facts"]
// The schema loader, for the checks that read data/schema.kb itself.
schemaLoader = globals["../src/schema"]

if triples == null or rules == null or parser == null or replLibrary == null then
	print "error: could not import ../src/triples, ../src/rule, ../src/knowledge and ../src/repl/repl"
	exit 1
end if
if rulesLoader == null or factsLoader == null or schemaLoader == null then
	print "error: could not import ../src/rules, ../src/facts and ../src/schema"
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
replCases.run(replLibrary, harness)
schema.run(triples, parser, schemaLoader, harness)
loaders.run(triples, rulesLoader, factsLoader, schemaLoader, harness)
globals["domain"].run(domainModule, harness)

harness.summary()
