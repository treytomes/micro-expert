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

	// ── Backtracking: a failed branch leaves nothing behind ────────────────
	// The solver walks the facts and the rules in turn, so a branch that binds a variable and
	// then fails must not carry that binding into the next one. The first fact here fails the
	// rule's second condition after binding ?x, and the answer has to come from the second.
	ranks = [spo("one", "has-rank", 1), spo("two", "has-rank", 2)]
	named = [spo("two", "has-name", "second")]
	// The second condition is a real test of the candidate, not a term meeting itself: only
	// "two" has a name, and the name rides in its own variable, so the branch stops for want
	// of a fact.
	pickedRule = rule(spo(v("x"), "picked", v("n")),
		[spo(v("x"), "has-rank", v("n")), spo(v("x"), "has-name", v("z"))])
	pickedGoal = spo(v("x"), "picked", v("n"))
	picked = t.proveGoals(pickedGoal, ranks + named, [pickedRule], 2)
	h.check("a binding made on a failing branch does not survive it", picked.len == 1)
	h.check("and the answer is the candidate that carried through",
		picked.len == 1 and answerText(pickedGoal, picked[0]) == "picked(two, 2)")

	// The same at the rule level: the first rule meets the goal and fails inside its body, so
	// the second has to answer - and the failed rule leaves no derivation on the answer.
	needsBoth = rule(spo(v("x"), "child", v("y")),
		[spo(v("y"), "parent", v("x")), spo(v("y"), "guardian", v("x"))])
	childFromParent = rule(spo(v("x"), "child", v("y")), [spo(v("y"), "parent", v("x"))])
	family = [spo("bill", "parent", "susan"), spo("doris", "guardian", "tim")]
	childGoal = spo(v("x"), "child", v("y"))
	children = t.proveGoals(childGoal, family, [needsBoth, childFromParent], 2)
	h.check("a rule that fails in its body lets the next rule answer", children.len == 1)
	h.check("the answer cites the rule that succeeded, once",
		children.len == 1 and children[0].reasons.len == 1 and
			children[0].reasons[0].rule.text == childFromParent.text)
	h.check("and it is the fact the succeeding rule reached",
		children.len == 1 and answerText(childGoal, children[0]) == "child(susan, bill)")

	// An or(...) is backtracking written inside one body: the first alternative finds nothing,
	// the second answers, and the choice costs no binding of its own.
	either = t.parseRule("getter(?x, ?w) => or(has-boat(?x, ?w), has-car(?x, ?w))")
	h.check("an or(...) rule parses", not (either isa error))
	h.check("with the two alternatives its body holds",
		not (either isa error) and either.body.len == 1 and either.body[0] isa t.Or and
			either.body[0].alternatives.len == 2)
	owns = [spo("zed", "has-car", "bike")]
	getterGoal = spo(v("x"), "getter", v("w"))
	getters = t.proveGoals(getterGoal, owns, [either], 2)
	h.check("the second alternative answers when the first fails",
		getters.len == 1 and answerText(getterGoal, getters[0]) == "getter(zed, bike)")

	// ── Negation is a test, not a query ─────────────────────────────────────
	// not(...) is met when its body has no proof, so the body is searched with the bindings
	// the rule already made and nothing it settles comes back out: a variable that lives only
	// inside the negation never reaches an answer.
	people = [spo("walter", "is-parent-of", "bill"), spo("doris", "is-parent-of", "bill"),
		spo("walter", "is-parent-of", "george"), spo("doris", "is-parent-of", "george"),
		spo("bill", "is-parent-of", "tim")]
	siblingOf = t.parseRule("is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), " +
		"is-parent-of(?p, ?y), not-equal(?x, ?y))")
	onlyChild = t.parseRule("is-only-child-of(?x, ?y) => and(is-parent-of(?y, ?x), " +
		"not(is-sibling-of(?x, ?q)))")
	onlyGoal = spo(v("x"), "is-only-child-of", v("y"))
	only = t.proveGoals(onlyGoal, people, [siblingOf, onlyChild], 3)
	h.check("an only child is proved by finding no sibling", only.len == 1)
	h.check("and the variable the negation searched with stays inside it",
		only.len == 1 and only[0].binds.hasIndex("q") == 0 and
			answerText(onlyGoal, only[0]) == "is-only-child-of(tim, bill)")
	// An inner body naming a variable the rule already bound does not overwrite it: ?y inside
	// the negation is the parent the first condition settled, not a sibling found there.
	keepsOuter = t.parseRule("is-child-only-of(?x, ?y) => and(is-parent-of(?y, ?x), " +
		"not(is-sibling-of(?x, ?y)))")
	keptGoal = spo("tim", "is-child-only-of", v("y"))
	kept = t.proveGoals(keptGoal, people, [siblingOf, keepsOuter], 3)
	h.check("a negation does not overwrite a binding the rule already made",
		kept.len == 1 and answerText(keptGoal, kept[0]) == "is-child-only-of(tim, bill)")

	// ── Running out of depth is not an absence ──────────────────────────────
	// The negation's body is proved with the depth the rule had, so a chain longer than that
	// fails to prove and reads as false - the cost of negation as failure, pinned here so it
	// cannot change quietly.
	chain = [spo("ann", "is-parent-of", "bill"), spo("bill", "is-parent-of", "casey"),
		spo("casey", "is-parent-of", "dana")]
	step = rule(spo(v("a"), "ancestor-of", v("b")), [spo(v("a"), "is-parent-of", v("b"))])
	stepThen = rule(spo(v("a"), "ancestor-of", v("b")),
		[spo(v("a"), "is-parent-of", v("m")), spo(v("m"), "ancestor-of", v("b"))])
	stranger = t.parseRule("is-stranger-to(?a, ?b) => not(ancestor-of(?a, ?b))")
	strangerGoal = spo("ann", "is-stranger-to", "dana")
	shallow = t.proveGoals(strangerGoal, chain, [step, stepThen, stranger], 2)
	h.check("a body that runs out of depth proves nothing, so the negation holds",
		shallow.len == 1 and answerText(strangerGoal, shallow[0]) == "is-stranger-to(ann, dana)")
	deep = t.proveGoals(strangerGoal, chain, [step, stepThen, stranger], 5)
	h.check("and at a depth that reaches the end the same negation fails", deep.len == 0)
	// A pair with no chain between it is a real absence, so it answers at either depth.
	absent = t.proveGoals(spo("ann", "is-stranger-to", "zed"), chain,
		[step, stepThen, stranger], 5)
	h.check("where nobody is an ancestor the negation holds at any depth", absent.len == 1)

	// ── A binding map cannot bind a variable to itself ──────────────────────
	// The solver binds only after dereferencing both sides, so the map it builds is a forest. A
	// map built by hand can hold a cycle, and walking one used to overflow the stack: the walk
	// now stops where it started, and unification refuses the alias rather than adding it.
	selfBound = {"x": t.var("x")}
	stood = t.deref(t.var("x"), selfBound)
	h.check("a variable bound to itself derefs to itself instead of overflowing",
		stood isa t.Var and stood.name == "x")
	ring = {"x": t.var("y"), "y": t.var("x")}
	h.check("a ring of two variables ends on a variable, not on a stack overflow",
		t.deref(t.var("x"), ring) isa t.Var and t.deref(t.var("y"), ring) isa t.Var)
	refused = t.unifyTerms(t.var("x"), t.var("x"), selfBound)
	h.check("unifying a variable with itself leaves the map as it was",
		refused != null and refused["x"] isa t.Var and refused["x"].name == "x")
	aliased = {"x": t.var("x")}
	refusedAlias = t.unifyTerms(t.var("x"), t.var("y"), aliased)
	h.check("a variable is not bound to an alias it already stands for",
		refusedAlias != null and refusedAlias.indexes.len == 1 and refusedAlias.hasIndex("x") and
			not refusedAlias.hasIndex("y"))
	// A question asked under a hand-built cycle still answers: the binding derefs to the
	// variable itself, which the fact then settles.
	cycleFacts = [spo("zed", "has-rank", 1)]
	cycleGoal = spo(v("x"), "has-rank", v("n"))
	cycled = t.proveGoals(cycleGoal, cycleFacts, [], 0, selfBound)
	h.check("and a goal asked under one still answers",
		cycled.len == 1 and answerText(cycleGoal, cycled[0]) == "has-rank(zed, 1)")

	// ── A question may name the moment it wants ─────────────────────────────
	// '@' is a field of the question like any other, so the fact's moment is bound to it and a
	// reading can be picked by its hour rather than by taking a day and reading annotations.
	hourFacts = [t.SpoTriple.make("berlin", "has-temperature-2m", 4.1, "[2026-11-22 00:00, 2026-11-22 01:00]"),
		t.SpoTriple.make("berlin", "has-temperature-2m", 9.8, "[2026-11-22 20:00, 2026-11-22 21:00]")]
	whenGoal = t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ ?when")
	h.check("a question reads a variable where the moment goes",
		not (whenGoal isa error) and whenGoal.at isa t.Var)
	h.check("and it reads as a question rather than a fact", t.hasUnknowns(whenGoal))
	whenAnswers = t.proveGoals(whenGoal, hourFacts, [], 0)
	h.check("every reading answers with the hour it holds for", whenAnswers.len == 2 and
		answerText(whenGoal, whenAnswers[0]) ==
			"has-temperature-2m(berlin, 4.1) @ [2026-11-22 00:00, 2026-11-22 01:00]")
	h.check("a moment asked for picks the reading whose span holds it",
		t.proveGoals(t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ 2026-11-22 20:30"),
			hourFacts, [], 0).len == 1)
	h.check("and a moment no span holds matches nothing",
		t.proveGoals(t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ 2026-11-22 23:30"),
			hourFacts, [], 0).len == 0)
	h.check("a moment asked for exactly picks that reading",
		t.proveGoals(t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ [2026-11-22 20:00, 2026-11-22 21:00]"),
			hourFacts, [], 0).len == 1)
	h.check("a reading with no moment answers no moment question",
		t.proveGoals(whenGoal, [spo("berlin", "has-temperature-2m", 4.1)], [], 0).len == 0)
	h.check("and a rule's head and conditions still take no annotation",
		t.parseRule("warm(?p, ?t) => has-temperature-2m(?p, ?t) @ ?when") isa error)
	bodyLine = "and(has-temperature-2m(?p, ?t) @ ?when, has-location(session, ?p))"
	body = t.parseBodyPart(bodyLine, bodyLine, 1)
	h.check("an and(...) question names the moment its reading has to hold for",
		not (body isa error) and body.len == 2 and body[0].at isa t.Var)
	h.check("while a rule body keeps its conditions bare",
		t.parseBodyPart("has-temperature-2m(?p, ?t) @ ?when", "a rule line") isa error)

	// ── The clock: a moment worked out from the time it is ──────────────────
	// A question names its hour as a call: has-time reads the clock into ?now, add-hours moves
	// it, and the moment that comes out matches the reading whose span holds it. The clock is
	// pinned here the way the day is pinned elsewhere, so the check cannot drift.
	t.clock = "2026-11-25 11:45:00"
	clockFacts = [
		t.SpoTriple.make("berlin", "has-temperature-2m", 7.3, "[2026-11-25 17:00, 2026-11-25 18:00]"),
		t.SpoTriple.make("berlin", "has-temperature-2m", 9.8, "[2026-11-25 20:00, 2026-11-25 21:00]"),
		t.SpoTriple.make("berlin", "has-temperature-2m", 10.1, "[2026-11-25 21:00, 2026-11-25 22:00]")]
	clockGoal = t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ add-hours(has-time(session, ?now), 9)")
	h.check("a question names its hour as a call",
		clockGoal.at isa t.Call and
			clockGoal.at.text == "add-hours(has-time(session, ?now), 9)")
	clockAnswers = t.proveGoals(clockGoal, clockFacts, [], 0)
	h.check("nine hours from the clock is the reading that covers it",
		clockAnswers.len == 1 and clockAnswers[0].binds["t"] == 9.8 and
			clockAnswers[0].binds["now"] == "2026-11-25 11:45:00")
	h.check("a moment a call reaches is matched where no span holds it",
		t.proveGoals(t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ add-hours(has-time(session, ?now), 2)"),
			clockFacts, [], 0).len == 0)
	// The clock is a value, not a fact: asking it answers, and it is never something to add.
	h.check("the time can be asked for on its own",
		len(t.proveGoals(t.SpoTriple.parse("has-time(session, ?now)"), [], [], 8)) == 1)
	h.check("a clock question asks for no fact at all",
		t.needsFor(t.SpoTriple.parse("has-time(session, ?now)"), [], [], 8).len == 0)
	h.check("a call is not a constraint a rule body checks",
		not t.isConstraint("add-hours") and not t.isConstraint("has-time"))
	h.check("add-hours moves a moment, day and all",
		t.evaluate(t.Call.make("add-hours", ["2026-11-25 20:00:00", 6]), {}).value == "2026-11-26 02:00:00")
	// A body asked with no facts yet still asks for the reading, whose call promises ?now.
	coldBody = t.parseBodyPart("and(has-temperature-2m(berlin, ?t) @ add-hours(has-time(session, ?now), 9))",
		"a cold question", 1)
	coldNeeds = t.needsConditions(coldBody, [], [], 8)
	h.check("a cold body asks for the reading the call settles",
		coldNeeds.len == 1 and coldNeeds[0].needs.len == 1 and
			coldNeeds[0].needs[0].triple.text == "has-temperature-2m(berlin, ?t) @ add-hours(has-time(session, ?now), 9)")
	// ── The place's clock ───────────────────────────────────────────────
	// has-time takes where as well as session: the clock at the place the machine is in is the
	// machine's own, and another place's is that clock moved by how far the two stand from UTC.
	t.sessionPlace = "berlin"
	t.machineOffset = -21600
	t.placeOffsets = {"berlin": -21600, "tokyo": 32400}
	placeClock = function(where)
		return t.evaluate(t.Call.make("has-time", [where, t.var("now")]), {})
	end function
	h.check("the clock at the place the machine is in is its own",
		placeClock("berlin").value == "2026-11-25 11:45:00")
	h.check("another place's clock is moved by how far the two stand from UTC",
		placeClock("tokyo").value == "2026-11-26 02:45:00")
	h.check("a place with no known clock has none", placeClock("lima") == null)
	t.clock = "2026-11-25 17:45:00"
	threeAtPlace = t.SpoTriple.parse("has-temperature-2m(berlin, ?t) @ add-hours(has-time(berlin, ?now), 3)")
	h.check("three hours from the place's clock is the reading that covers it",
		t.proveGoals(threeAtPlace, clockFacts, [], 0).len == 1 and
			t.proveGoals(threeAtPlace, clockFacts, [], 0)[0].binds["t"] == 9.8)
	t.sessionPlace = null
	t.machineOffset = null
	t.placeOffsets = {}
	// ── A call in a constraint field is a value ─────────────────────────
	fieldCall = t.constraintOf("equal(?x, add-hours(2026-11-25 20:00:00, 2))")
	bound = t.applyConstraint(fieldCall, {})
	h.check("a call in a constraint field is worked out before it is compared",
		bound != null and bound["x"] == "2026-11-25 22:00:00")
	h.check("and the check reads the value it yields",
		t.holdsConstraint(t.constraintOf("not-equal(add-hours(2026-11-25 20:00:00, 2), 2026-11-25 20:00:00)"), {}) and
			not t.holdsConstraint(t.constraintOf("not-equal(add-hours(2026-11-25 20:00:00, 2), 2026-11-25 22:00:00)"), {}))
	h.check("a call written with the wrong number of fields is refused where it is read",
		t.constraintOf("equal(?x, add-hours(1))") isa error and
			t.parseBodyPart("and(has-temperature-2m(berlin, ?t) @ add-hours(1))", "a bad call", 1) isa error)
	t.clock = null

	// ── Number arithmetic is a call too ─────────────────────────────────
	// add, subtract, multiply and divide work out a number where a value is wanted, which is a
	// constraint field: '@' holds a moment, so a conversion is written beside the reading it
	// converts rather than in its place.
	arithmetic = function(name, a, b)
		called = t.evaluate(t.Call.make(name, [a, b]), {})
		if called == null then return null
		return called.value
	end function
	h.check("the four arithmetic calls work out their two fields",
		arithmetic("add", 2, 3) == 5 and arithmetic("subtract", 2, 3) == -1 and
			arithmetic("multiply", 2, 3) == 6 and arithmetic("divide", 6, 4) == 1.5)
	h.check("and nest, which is how a conversion is written",
		arithmetic("add", arithmetic("divide", arithmetic("multiply", 10.4, 9), 5), 32) == 50.72)
	h.check("a field that is not a number has no value at all",
		arithmetic("add", "berlin", 2) == null and
			arithmetic("multiply", "2026-11-25 20:00:00", 2) == null)
	h.check("and a division by zero is no value rather than an infinity",
		arithmetic("divide", 1, 0) == null)
	h.check("arithmetic is not a constraint a body checks, nor a fact a line stores",
		not t.isConstraint("add") and t.isCallName("add") and
			t.callProblem(t.Call.make("add", [1])) != null)
	conversion = t.parseRule("has-fahrenheit-value(?p, ?f) => has-temperature-2m(?p, ?c), " +
		"equal(?f, add(divide(multiply(?c, 9), 5), 32))")
	reading = t.SpoTriple.make("berlin", "has-temperature-2m", 10.4,
		"[2026-11-25 15:00, 2026-11-25 16:00]")
	converted = t.proveGoals(t.SpoTriple.parse("has-fahrenheit-value(berlin, ?f)"),
		[reading], [rule(conversion.head, conversion.body)], 2)
	h.check("a rule converts through arithmetic, and the value is a number to compare",
		converted.len == 1 and converted[0].binds["f"] == 50.72)
	back = t.parseRule("has-celsius-value(?p, ?c) => has-fahrenheit-value(?p, ?f), " +
		"equal(?c, divide(multiply(subtract(?f, 32), 5), 9))")
	roundTrip = t.proveGoals(t.SpoTriple.parse("has-celsius-value(berlin, ?c)"),
		[spo("berlin", "has-fahrenheit-value", 50.72)], [rule(back.head, back.body)], 2)
	h.check("and the rule back again lands a floating hair from the reading it started from",
		roundTrip.len == 1 and abs(roundTrip[0].binds["c"] - 10.4) < 0.000001)
end function
