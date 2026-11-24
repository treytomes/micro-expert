// Cases for recursive rules: a chain of ancestors, and cycles that must stop.

run = function(t, rules, h)
	"Checks recursion and loop detection, against the shared copies in t and rules."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	v = function(name)
		return t.var(name)
	end function
	rule = function(head, body)
		return rules.Rule.make(head, body)
	end function
	answerText = function(goal, answer)
		return t.substitute(goal, answer.binds).text
	end function

	// ── The ancestor rule ───────────────────────────────────────────────────

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
		return t.proveGoals(spo(a, "ancestor", b), chain, ancestorRules, 6)
	end function

	h.check("bill is an ancestor of anna", ancestorsOf("bill", "anna").len == 1)
	h.check("susan is an ancestor of anna", ancestorsOf("susan", "anna").len == 1)
	h.check("anna is not an ancestor of bill", ancestorsOf("anna", "bill").len == 0)
	h.check("depth bounds the recursion", t.proveGoals(spo("bill", "ancestor", "anna"),
		chain, ancestorRules, 1).len == 0)
	h.check("rules are not mutated after use",
		ancestorRec.text == "ancestor(?x, ?z) => parent(?x, ?y), ancestor(?y, ?z)")

	goal = spo(v("a"), "ancestor", v("b"))
	pairs = {}
	for answer in t.proveGoals(goal, chain, ancestorRules, 6)
		pairs[answerText(goal, answer)] = 1
	end for
	h.check("exactly six ancestor pairs", pairs.len == 6)
	h.check("bill reaches anna", pairs.hasIndex("ancestor(bill, anna)") == 1)
	h.check("bill reaches susan", pairs.hasIndex("ancestor(bill, susan)") == 1)
	h.check("tim reaches anna", pairs.hasIndex("ancestor(tim, anna)") == 1)

	// ── Cycles stop the branch ──────────────────────────────────────────────

	// A rule that only ever proves itself would otherwise recurse until the depth
	// ran out; it now stops at the first repeat.
	loopsOnItself = rule(spo(v("x"), "loop", v("x")), [spo(v("x"), "loop", v("x"))])
	h.check("a self-proving rule answers nothing",
		t.proveGoals(spo("a", "loop", "a"), [], [loopsOnItself], 50).len == 0)

	// Two rules chasing each other's tails.
	aToB = rule(spo(v("x"), "a", v("y")), [spo(v("x"), "b", v("y"))])
	bToA = rule(spo(v("x"), "b", v("y")), [spo(v("x"), "a", v("y"))])
	h.check("a two-rule cycle stops",
		t.proveGoals(spo("p", "a", "q"), [], [aToB, bToA], 50).len == 0)

	// A cycle that only appears under the bindings: with parent(a, a), the ancestor
	// rule asks for ancestor(a, ?z) again, in different variable names.
	selfParent = [spo("a", "parent", "a"), spo("a", "parent", "b")]
	ancestorOnlyRecursive = rule(spo(v("x"), "ancestor", v("z")),
		[spo(v("x"), "parent", v("y")), spo(v("y"), "ancestor", v("z"))])
	h.check("a cycle under the bindings stops",
		t.proveGoals(spo("a", "ancestor", v("z")), selfParent, [ancestorOnlyRecursive], 50).len == 0)

	// Legitimate recursion along a cycle-free chain still answers.
	h.check("real recursion still answers", ancestorsOf("bill", "anna").len == 1)
end function
