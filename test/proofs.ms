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
	h.check("tree line one", lines[0] == "child(susan, bill)  => rule child(?x, ?y) => parent(?y, ?x)")
	h.check("tree line two", lines[1] == "  parent(bill, susan)  => fact")
	h.check("tree line three", lines[2] == "child(susan, bill)  => rule child(?x, ?y) => guardian(?y, ?x)")
	h.check("tree line four", lines[3] == "  guardian(bill, susan)  => fact")

	// The same tree said as sentences: --nlp asks proofLines for the words, so the fact and
	// the rule behind it are both read in the form an answer is said in.
	said = t.proofLines(answers[0], "", 1)
	h.check("a said tree turns a fact into its sentence",
		said[1] == "  bill parent susan  => fact")
	h.check("and says the rule it came from the same way",
		said[0] == "susan child bill  => rule ?x child ?y => ?y parent ?x")

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
		nested[0] == "ancestor(bill, tim)  => rule ancestor(?x, ?z) => parent(?x, ?y), ancestor(?y, ?z)")
	h.check("nested step uses the base rule",
		nested[2] == "  ancestor(susan, tim)  => rule ancestor(?x, ?y) => parent(?x, ?y)")
	h.check("nested leaf is a fact", nested[3] == "    parent(susan, tim)  => fact")

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

	// ── A conclusion keeps the readings' annotation ─────────────────────────
	// A reading says when it holds and how sure it is; a rule concluding from it is
	// concluding about that same reading, so the conclusion carries its span and confidence
	// instead of arriving bare - which is what is-cold(place, value) lost before.
	hour = "[2026-11-22 00:00, 2026-11-22 01:00]"
	hourly = [t.SpoTriple.make("berlin", "has-temperature-2m", 4.1, hour, 80)]
	coldRule = rule(spo(v("p"), "is-cold", v("t")), [spo(v("p"), "has-temperature-2m", v("t"))])
	coldGoal = spo(v("p"), "is-cold", v("t"))
	cold = t.proveGoals(coldGoal, hourly, [coldRule], 1)
	h.check("a rule's answer carries the span of the reading it stood on",
		cold.len == 1 and cold[0].at == hour)
	h.check("and the confidence that reading had", cold[0].confidence == 80)
	h.check("so the answer's line reads with both",
		t.answerTriple(coldGoal, cold[0].binds, cold[0].at, cold[0].confidence).text ==
			"is-cold(berlin, 4.1) @ " + hour + " ~ 80%")
	// Two readings under one rule: the span is the first one's, the confidence the weakest,
	// so a conclusion is never surer than the least sure thing it stands on.
	pairRule = rule(spo(v("p"), "read", v("t")), [spo(v("p"), "has-temperature-2m", v("t")),
		spo(v("p"), "has-wind-speed-10m", v("w"))])
	pairFacts = [t.SpoTriple.make("berlin", "has-temperature-2m", 4.1, hour, 90),
		t.SpoTriple.make("berlin", "has-wind-speed-10m", 11,
			"[2026-11-22 03:00, 2026-11-22 04:00]", 60)]
	paired = t.proveGoals(spo(v("p"), "read", v("t")), pairFacts, [pairRule], 1)
	h.check("a rule over two readings keeps the first span and the weaker confidence",
		paired.len == 1 and paired[0].at == hour and paired[0].confidence == 60)
	// Bare facts say nothing about when, and a rule whose body is all bare facts concludes
	// nothing about when either: it adds no annotation it did not receive.
	swapped = rule(spo(v("c"), "child-of", v("p")), [spo(v("p"), "is-parent-of", v("c"))])
	bared = t.proveGoals(spo("bill", "child-of", v("x")),
		[spo("walter", "is-parent-of", "bill")], [swapped], 1)
	h.check("a body of bare facts concludes nothing about when or from where",
		bared.len == 1 and bared[0].at == null and bared[0].confidence == 100 and
			bared[0].source == null and bared[0].fetched == null)

	// Where a reading came from travels the same way: the service that answered it and the
	// day it was read are part of the fact, so a rule concluding from it says both.
	served = [t.SpoTriple.make("berlin", "has-temperature-2m", 4.1, hour, 80,
		"open-meteo/forecast", "2026-11-22")]
	servedCold = t.proveGoals(coldGoal, served, [coldRule], 1)
	h.check("a rule's answer keeps the service that answered the reading",
		servedCold.len == 1 and servedCold[0].source == "open-meteo/forecast")
	h.check("and the day it was read", servedCold[0].fetched == "2026-11-22")
	h.check("so the conclusion's line carries all four annotations",
		t.answerTriple(coldGoal, servedCold[0].binds, servedCold[0].at, servedCold[0].confidence,
			servedCold[0].source, servedCold[0].fetched).text ==
			"is-cold(berlin, 4.1) @ " + hour + " ~ 80% # open-meteo/forecast 2026-11-22")
	// A fact's own answer says it too: the annotation is the reading's, and asking for the
	// reading is not a way to lose it.
	readingGoal = spo("berlin", "has-temperature-2m", v("t"))
	readingAnswer = t.proveGoals(readingGoal, served, [], 0)
	h.check("a fact answers with the service and day it was read",
		readingAnswer.len == 1 and readingAnswer[0].source == "open-meteo/forecast" and
			readingAnswer[0].fetched == "2026-11-22" and
			t.answerTriple(readingGoal, readingAnswer[0].binds, readingAnswer[0].at,
				readingAnswer[0].confidence, readingAnswer[0].source, readingAnswer[0].fetched).text ==
				"has-temperature-2m(berlin, 4.1) @ " + hour +
					" ~ 80% # open-meteo/forecast 2026-11-22")
	// Two services answering the same reading for the same hour are two answers, not one with
	// two derivations: the line each was read from differs.
	services = [t.SpoTriple.make("berlin", "has-temperature-2m", 4.1, hour, 100,
		"open-meteo/forecast", "2026-11-22"),
		t.SpoTriple.make("berlin", "has-temperature-2m", 4.1, hour, 100,
			"another/forecast", "2026-11-23")]
	h.check("two services answering one reading are two answers",
		t.proveGoals(readingGoal, services, [], 0).len == 2)
end function
