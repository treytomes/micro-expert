// Tests for triples, unification and proof search.
//
// Run: 3rd-party\miniscript-win\miniscript.exe src\tests.ms
// (the interpreter path is MINISCRIPT_EXE_PATH in .env). Exit code 0 means every
// check passed; a failure exits 1 so a script or CI step can rely on it.

import "triples"
import "rules"

spo = function(s, p, o)
	return triples.SpoTriple.make(s, p, o)
end function
v = function(name)
	return triples.var(name)
end function
rule = function(head, body)
	return rules.Rule.make(head, body)
end function
answerText = function(goal, answer)
	return triples.substitute(goal, answer.binds).text
end function

tally = {"passed": 0, "failed": 0}

check = function(name, ok)
	"Records one expectation, printing it so a failure names itself."
	if ok then
		tally.passed = tally.passed + 1
		print "PASS  " + name
	else
		tally.failed = tally.failed + 1
		print "FAIL  " + name
	end if
end function

// ── One fact, two derivations ────────────────────────────────────────────────

family = [
	spo("bill", "parent", "susan"),
	spo("bill", "guardian", "susan"),
	spo("susan", "parent", "tim"),
]
childFromParent = rule(spo(v("x"), "child", v("y")), [spo(v("y"), "parent", v("x"))])
childFromGuardian = rule(spo(v("x"), "child", v("y")), [spo(v("y"), "guardian", v("x"))])
childRules = [childFromParent, childFromGuardian]

who = spo(v("x"), "child", v("y"))
answers = triples.proveGoals(who, family, childRules, 4)

check("one entry per answer", answers.len == 2)
check("first answer", answerText(who, answers[0]) == "spo(susan | child | bill)")
check("second answer", answerText(who, answers[1]) == "spo(tim | child | susan)")
check("both derivations kept", answers[0].reasons.len == 2)
check("derivation one is the parent rule", answers[0].reasons[0].rule.text == childFromParent.text)
check("derivation two is the guardian rule", answers[0].reasons[1].rule.text == childFromGuardian.text)
check("the single answer keeps one derivation", answers[1].reasons.len == 1)

lines = triples.proofLines(who, answers[0], "")
check("tree renders every derivation", lines.len == 4)
check("tree line one", lines[0] == "spo(susan | child | bill)  <- rule spo(?x | child | ?y) <- spo(?y | parent | ?x)")
check("tree line two", lines[1] == "  spo(bill | parent | susan)  <- fact")
check("tree line three", lines[2] == "spo(susan | child | bill)  <- rule spo(?x | child | ?y) <- spo(?y | guardian | ?x)")
check("tree line four", lines[3] == "  spo(bill | guardian | susan)  <- fact")

// The same fact listed twice is still one answer, with both derivations.
twice = [spo("bill", "parent", "susan"), spo("bill", "parent", "susan")]
q = spo(v("x"), "parent", v("y"))
duplicated = triples.proveGoals(q, twice, [], 0)
check("duplicate facts are one answer", duplicated.len == 1)
check("both fact derivations kept", duplicated[0].reasons.len == 2)

// ── The ancestor rule ────────────────────────────────────────────────────────

chain = [
	spo("bill", "parent", "susan"),
	spo("susan", "parent", "tim"),
	spo("tim", "parent", "anna"),
]
ancestorBase = rule(spo(v("x"), "ancestor", v("y")), [spo(v("x"), "parent", v("y"))])
ancestorRec = rule(spo(v("x"), "ancestor", v("z")),
	[spo(v("x"), "parent", v("y")), spo(v("y"), "ancestor", v("z"))])
ancestorRules = [ancestorBase, ancestorRec]

ancestorsOf = function(a, b)
	return triples.proveGoals(spo(a, "ancestor", b), chain, ancestorRules, 6)
end function

check("bill is an ancestor of anna", ancestorsOf("bill", "anna").len == 1)
check("susan is an ancestor of anna", ancestorsOf("susan", "anna").len == 1)
check("anna is not an ancestor of bill", ancestorsOf("anna", "bill").len == 0)
check("depth bounds the recursion", triples.proveGoals(spo("bill", "ancestor", "anna"),
	chain, ancestorRules, 1).len == 0)
check("rules are not mutated after use",
	ancestorRec.text == "spo(?x | ancestor | ?z) <- spo(?x | parent | ?y), spo(?y | ancestor | ?z)")

goal = spo(v("a"), "ancestor", v("b"))
pairs = {}
for answer in triples.proveGoals(goal, chain, ancestorRules, 6)
	pairs[answerText(goal, answer)] = 1
end for
check("exactly six ancestor pairs", pairs.len == 6)
check("bill reaches anna", pairs.hasIndex("spo(bill | ancestor | anna)") == 1)
check("bill reaches susan", pairs.hasIndex("spo(bill | ancestor | susan)") == 1)
check("tim reaches anna", pairs.hasIndex("spo(tim | ancestor | anna)") == 1)

// ── A nested proof tree ──────────────────────────────────────────────────────

deepGoal = spo("bill", "ancestor", "tim")
deep = triples.proveGoals(deepGoal, chain, ancestorRules, 4)
check("one nested answer", deep.len == 1)
nested = triples.proofLines(deepGoal, deep[0], "")
check("nested tree depth", nested.len == 4)
check("nested root uses the recursive rule",
	nested[0] == "spo(bill | ancestor | tim)  <- rule spo(?x | ancestor | ?z) <- spo(?x | parent | ?y), spo(?y | ancestor | ?z)")
check("nested step uses the base rule",
	nested[2] == "  spo(susan | ancestor | tim)  <- rule spo(?x | ancestor | ?y) <- spo(?x | parent | ?y)")
check("nested leaf is a fact", nested[3] == "    spo(susan | parent | tim)  <- fact")

// ── Summary ─────────────────────────────────────────────────────────────────

print ""
print tally.passed + " passed, " + tally.failed + " failed"
if tally.failed > 0 then exit 1
exit 0
