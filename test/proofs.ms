// Cases for answering a goal: one fact proved two ways, and the proof trees.

run = function(t, rules, h)
	"Checks answer merging and proof trees, against the shared copies in t and rules."
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

	// ── One fact, two derivations ───────────────────────────────────────────

	family = [
		spo("bill", "parent", "susan"),
		spo("bill", "guardian", "susan"),
		spo("susan", "parent", "tim"),
	]
	childFromParent = rule(spo(v("x"), "child", v("y")), [spo(v("y"), "parent", v("x"))])
	childFromGuardian = rule(spo(v("x"), "child", v("y")), [spo(v("y"), "guardian", v("x"))])
	childRules = [childFromParent, childFromGuardian]

	who = spo(v("x"), "child", v("y"))
	answers = t.proveGoals(who, family, childRules, 4)

	h.check("one entry per answer", answers.len == 2)
	h.check("first answer", answerText(who, answers[0]) == "child(susan, bill)")
	h.check("second answer", answerText(who, answers[1]) == "child(tim, susan)")
	h.check("both derivations kept", answers[0].reasons.len == 2)
	h.check("derivation one is the parent rule", answers[0].reasons[0].rule.text == childFromParent.text)
	h.check("derivation two is the guardian rule", answers[0].reasons[1].rule.text == childFromGuardian.text)
	h.check("the single answer keeps one derivation", answers[1].reasons.len == 1)

	lines = t.proofLines(answers[0], "")
	h.check("tree renders every derivation", lines.len == 4)
	h.check("tree line one", lines[0] == "child(susan, bill)  <- rule child(?x, ?y) <- parent(?y, ?x)")
	h.check("tree line two", lines[1] == "  parent(bill, susan)  <- fact")
	h.check("tree line three", lines[2] == "child(susan, bill)  <- rule child(?x, ?y) <- guardian(?y, ?x)")
	h.check("tree line four", lines[3] == "  guardian(bill, susan)  <- fact")

	// The same tree said as sentences: --nlp asks proofLines for the words, so the fact and
	// the rule behind it are both read in the form an answer is said in.
	said = t.proofLines(answers[0], "", 1)
	h.check("a said tree turns a fact into its sentence",
		said[1] == "  bill parent susan  <- fact")
	h.check("and says the rule it came from the same way",
		said[0] == "susan child bill  <- rule ?x child ?y <- ?y parent ?x")

	// The same fact listed twice is still one answer, with both derivations.
	twice = [spo("bill", "parent", "susan"), spo("bill", "parent", "susan")]
	duplicated = t.proveGoals(spo(v("x"), "parent", v("y")), twice, [], 0)
	h.check("duplicate facts are one answer", duplicated.len == 1)
	h.check("both fact derivations kept", duplicated[0].reasons.len == 2)

	// ── A nested proof tree ─────────────────────────────────────────────────

	chain = [
		spo("bill", "parent", "susan"),
		spo("susan", "parent", "tim"),
		spo("tim", "parent", "anna"),
	]
	ancestorBase = rule(spo(v("x"), "ancestor", v("y")), [spo(v("x"), "parent", v("y"))])
	ancestorRec = rule(spo(v("x"), "ancestor", v("z")),
		[spo(v("x"), "parent", v("y")), spo(v("y"), "ancestor", v("z"))])

	deepGoal = spo("bill", "ancestor", "tim")
	deep = t.proveGoals(deepGoal, chain, [ancestorBase, ancestorRec], 4)
	h.check("one nested answer", deep.len == 1)
	nested = t.proofLines(deep[0], "")
	h.check("nested tree depth", nested.len == 4)
	h.check("nested root uses the recursive rule",
		nested[0] == "ancestor(bill, tim)  <- rule ancestor(?x, ?z) <- parent(?x, ?y), ancestor(?y, ?z)")
	h.check("nested step uses the base rule",
		nested[2] == "  ancestor(susan, tim)  <- rule ancestor(?x, ?y) <- parent(?x, ?y)")
	h.check("nested leaf is a fact", nested[3] == "    parent(susan, tim)  <- fact")

	// ── A goal with a variable predicate ────────────────────────────────────
	// Regression: the top level of a query derefs the goal's predicate with no bindings yet
	// (candidateFacts, predicatesMeet). A variable predicate is the one term that reaches
	// that deref, so it must not crash; it matches every fact carrying the goal's subject.
	props = [spo("oliver", "has-gender", "male"), spo("oliver", "lives-in", "dublin"),
		spo("henry", "parent", "oliver")]
	anyPred = spo("oliver", v("p"), v("c"))
	predAnswers = t.proveGoals(anyPred, props, [], 0)
	h.check("a variable predicate matches each fact with that subject", predAnswers.len == 2)
	h.check("a variable predicate binds the predicate and object it found",
		answerText(anyPred, predAnswers[0]) == "has-gender(oliver, male)" and
			answerText(anyPred, predAnswers[1]) == "lives-in(oliver, dublin)")
end function
