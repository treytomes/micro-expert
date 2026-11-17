// The micro-expert test suite.
//
// Run: 3rd-party\miniscript-win\miniscript.exe test\run.ms
// Exit code 0 means every check passed.
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
import "harness"
import "display"
import "proofs"
import "absence"
import "recursion"
import "relations"

triples = globals["../src/triples"]
// rule.ms holds the Rule class; the cases build the rules they test with it.
rules = globals["../src/rule"]

if triples == null or rules == null then
	print "error: could not import ../src/triples and ../src/rule"
	exit 1
end if

// A partly loaded module would otherwise surface as a puzzling error inside one
// case, so check the surface the suite relies on up front.
for name in ["SpoTriple", "proveGoals", "substitute", "NotEqual", "proofLines", "standardizeApart"]
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

harness.summary()
