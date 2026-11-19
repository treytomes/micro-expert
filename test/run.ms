// The micro-expert test suite.
//
// Run: 3rd-party\miniscript-win\miniscript.exe test\run.ms
// Exit code 0 means every check passed.
//
// A test runner asks for part of the suite instead:
//
//   miniscript.exe test\run.ms --json --filter "display with variables" --file repl.ms
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
import "../src/repl"
import "../src/knowledge"
import "harness"
import "display"
import "proofs"
import "absence"
import "recursion"
import "relations"
import "repl"
import "knowledge"
import "schema"
import "loaders"

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
// repl.ms holds no classes, but it is handed over all the same, so every case works
// with the one copy of everything. It is aliased away from `repl`, because that name
// belongs to this suite's own repl.ms case module.
prompt = globals["../src/repl"]
// knowledge.ms is the parser behind the data files, aliased away for the same reason:
// `knowledge` is this suite's own case module for it.
parser = globals["../src/knowledge"]

// rules.ms and facts.ms name their neighbours by bare import, which the interpreter
// resolves against the entry folder, so src/ goes on the import path for these two
// loads. It is put back afterwards, so the suite leaves the environment as it found it.
savedImportPath = env["MS_IMPORT_PATH"]
env["MS_IMPORT_PATH"] = "src"
import "../src/rules"
import "../src/facts"
import "../src/schema"
env["MS_IMPORT_PATH"] = savedImportPath

// The loaders themselves, so the cases can read the data files the program ships.
rulesLoader = globals["../src/rules"]
factsLoader = globals["../src/facts"]
// The schema loader, for the checks that read data/schema.kb itself.
schemaLoader = globals["../src/schema"]

if triples == null or rules == null or parser == null then
	print "error: could not import ../src/triples, ../src/rule and ../src/knowledge"
	exit 1
end if
if rulesLoader == null or factsLoader == null or schemaLoader == null then
	print "error: could not import ../src/rules, ../src/facts and ../src/schema"
	exit 1
end if

// A partly loaded module would otherwise surface as a puzzling error inside one
// case, so check the surface the suite relies on up front.
for name in ["SpoTriple", "proveGoals", "substitute", "NotEqual", "Comparison", "proofLines", "Or", "Not",
	"standardizeApart", "parseRule", "needsFor", "reportLines", "reportLabels", "unboundVars",
	"paint"]
	if triples.hasIndex(name) == 0 then
		print "error: ../src/triples loaded without " + name
		exit 1
	end if
end for
if rules.hasIndex("Rule") == 0 then
	print "error: ../src/rule loaded without Rule"
	exit 1
end if

display.run(triples, harness)
knowledge.run(triples, parser, harness)
proofs.run(triples, rules, harness)
absence.run(triples, rules, harness)
recursion.run(triples, rules, harness)
relations.run(triples, rules, harness)
repl.run(triples, rules, prompt, harness, schemaLoader)
schema.run(triples, parser, schemaLoader, harness)
loaders.run(triples, rulesLoader, factsLoader, harness)

harness.summary()
