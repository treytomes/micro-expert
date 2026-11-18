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
import "harness"
import "display"
import "proofs"
import "absence"
import "recursion"
import "relations"
import "repl"

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

if triples == null or rules == null then
	print "error: could not import ../src/triples and ../src/rule"
	exit 1
end if

// A partly loaded module would otherwise surface as a puzzling error inside one
// case, so check the surface the suite relies on up front.
for name in ["SpoTriple", "proveGoals", "substitute", "NotEqual", "proofLines",
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
proofs.run(triples, rules, harness)
absence.run(triples, rules, harness)
recursion.run(triples, rules, harness)
relations.run(triples, rules, harness)
repl.run(triples, rules, prompt, harness)

harness.summary()
