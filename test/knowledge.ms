// Cases for the knowledge data format: the parser and writer behind data/facts.kb and
// data/rules.kb, and where a data file is found or named.

run = function(t, knowledge, h)
	"Checks the data parser, against the shared copy of triples."
	parseOneRule = function(text)
		return knowledge.parseRules(t, [text])
	end function
	parseOneFact = function(text)
		return knowledge.parseFacts(t, [text])
	end function
	failure = function(text)
		"One rule line's parse failure, or null when it parsed."
		parsed = parseOneRule(text)
		if parsed isa error then return parsed
		return null
	end function
	bodyText = function(piece)
		texts = []
		for condition in piece.body
			texts.push(condition.text)
		end for
		return texts.join(", ")
	end function

	// ── A rule's head and body ───────────────────────────────────────────────

	single = parseOneRule("child-of(?x, ?y) => parent-of(?y, ?x)")
	h.check("a rule line parses", not (single isa error))
	h.check("one rule line is one rule", single.len == 1)
	h.check("the head reads back", single[0].head.text == "child-of(?x, ?y)")
	h.check("one condition is a body of one", single[0].body.len == 1)
	h.check("the condition reads back", single[0].body[0].text == "parent-of(?y, ?x)")

	// ── The implied and, said out loud ───────────────────────────────────────

	implied = parseOneRule("uncle-of(?x, ?y) => parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)")
	spoken = parseOneRule("uncle-of(?x, ?y) => and(parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male))")
	h.check("a comma list is one condition per comma", implied[0].body.len == 3)
	h.check("and(...) holds the same three", spoken[0].body.len == 3)
	h.check("both forms read alike", bodyText(implied[0]) == bodyText(spoken[0]))
	h.check("the head is the same either way", implied[0].head.text == spoken[0].head.text)

	nested = parseOneRule("uncle-of(?x, ?y) => and(parent-of(?p, ?y), and(sibling-of(?x, ?p), has-gender(?x, male)))")
	h.check("and(...) nests", nested[0].body.len == 3)

	// ── Constraints ──────────────────────────────────────────────────────────

	constrained = parseOneRule("sibling-of(?x, ?y) => and(parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y))")
	h.check("a constraint parses inside and(...)", constrained[0].body.len == 3)
	h.check("a constraint reads as a call",
		constrained[0].body[2].text == "not-equal(?x, ?y)")
	h.check("a constraint is not a triple", not (constrained[0].body[2] isa t.SpoTriple))

	equal = parseOneRule("same-age-group-as(?x, ?y) => and(age-group(?x, ?g), equal(?g, ?h), age-group(?y, ?h))")
	h.check("equal parses as a constraint", equal[0].body[1] isa t.Equal)
	h.check("equal is not a triple", not (equal[0].body[1] isa t.SpoTriple))
	h.check("equal reads back as a call",
		bodyText(equal[0]) == "age-group(?x, ?g), equal(?g, ?h), age-group(?y, ?h)")

	// ── Lines ────────────────────────────────────────────────────────────────

	// MiniScript has no escape in a string literal, so "\t" is a backslash and a t rather
	// than the tab an indent is: char(9) is the tab, and these lines are indented with one.
	tab = char(9)
	spread = knowledge.parseRules(t, [
		"// A rule may run over several lines.",
		"uncle-of(?x, ?y) => and(",
		tab + "parent-of(?p, ?y),",
		tab + "sibling-of(?x, ?p),",
		tab + "has-gender(?x, male))",
		"",
		"married-to(?y, ?x) =>",
		tab + "married-to(?x, ?y)",
	])
	h.check("comments and blank lines are skipped", spread.len == 2)
	h.check("a rule may run over several lines", spread[0].body.len == 3)
	h.check("and again after the arrow", spread[1].head.text == "married-to(?y, ?x)")
	h.check("the rule after the break is whole", spread[1].body.len == 1)

	// ── or: a body that offers a choice ──────────────────────────────────────

	choice = parseOneRule("in-law-of(?x, ?y) => or(married-to(?x, ?p), sibling-of(?p, ?y))")
	h.check("or(...) parses", not (choice isa error))
	h.check("or(...) is one condition", choice[0].body.len == 1)
	h.check("or(...) is a choice, not a triple", choice[0].body[0] isa t.Or)
	h.check("or(...) reads back",
		bodyText(choice[0]) == "or(married-to(?x, ?p), sibling-of(?p, ?y))")

	either = parseOneRule("close(?x, ?y) => and(or(sibling-of(?x, ?y), married-to(?x, ?y)), not-equal(?x, ?y))")
	h.check("or(...) sits among other conditions", either[0].body.len == 2)
	h.check("the choice keeps its alternatives", either[0].body[0].alternatives.len == 2)

	paired = parseOneRule("in-law-of(?x, ?y) => or(and(married-to(?x, ?p), sibling-of(?p, ?y)), sibling-of(?x, ?y))")
	h.check("an alternative of several conditions reads as and(...)", not (paired isa error))
	h.check("or(...) holds an and(...) alternative",
		bodyText(paired[0]) ==
			"or(and(married-to(?x, ?p), sibling-of(?p, ?y)), sibling-of(?x, ?y))")

	// ── not: a body that must not hold ───────────────────────────────────────

	negated = parseOneRule("only-child-of(?x, ?y) => and(parent-of(?y, ?x), not(sibling-of(?x, ?q)))")
	h.check("not(...) parses", not (negated isa error))
	h.check("not(...) sits among other conditions", negated[0].body.len == 2)
	h.check("not(...) is a negation, not a triple", negated[0].body[1] isa t.Not)
	h.check("not(...) holds the body it negates",
		negated[0].body[1].body.len == 1 and negated[0].body[1].body[0].text == "sibling-of(?x, ?q)")
	h.check("not(...) reads back",
		bodyText(negated[0]) == "parent-of(?y, ?x), not(sibling-of(?x, ?q))")

	whole = parseOneRule("a(?x, ?y) => not(and(b(?x, ?p), c(?p, ?y)))")
	h.check("not(...) around several conditions reads as and(...)",
		whole[0].body[0].text == "not(and(b(?x, ?p), c(?p, ?y)))")
	h.check("not(...) keeps both conditions of its body", whole[0].body[0].body.len == 2)

	// ── Refusals ─────────────────────────────────────────────────────────────

	h.check("a line without an arrow is refused", failure("parent-of(?x, ?y)") != null)
	h.check("a rule with no body is refused", failure("parent-of(?x, ?y) => ") != null)
	h.check("not(...) with no condition is refused", failure("a(?x, ?y) => not()") != null)
	several = failure("a(?x, ?y) => not(b(?x, ?y), c(?x, ?y))")
	h.check("not(...) of several conditions is refused", several != null)
	if several != null then
		h.check("the refusal says how to write it", several.message.indexOf("not(and(") != null)
	end if
	h.check("a broken part refuses the whole rule",
		failure("grandparent(?x, ?y) => parent-of(?x, ?p") != null)

	broken = knowledge.parseRules(t, ["// A rule", "grandparent(?x, ?y) => parent-of(?x, ?p"])
	h.check("a refusal names the line", broken isa error)
	if broken isa error then
		h.check("the line is the one that broke", broken.message.indexOf("line 2") != null)
	end if

	// ── Facts ────────────────────────────────────────────────────────────────

	fact = parseOneFact("has-age(walter, 78)")
	h.check("a fact line parses", not (fact isa error))
	h.check("the fact reads back", fact[0].text == "has-age(walter, 78)")
	h.check("a number stays a number", fact[0].object + 1 == 79)
	fraction = parseOneFact("has-age(tim, 24.5)")
	h.check("a fraction is a number too",
		fraction[0].object isa number and fraction[0].object == 24.5)
	scaled = parseOneFact("has-age(tim, 1e3)")
	h.check("an exponent is a number too",
		scaled[0].object isa number and scaled[0].object == 1000)

	factLines = knowledge.parseFacts(t, [
		"// A person",
		"",
		"has-gender(walter, male)",
		"parent-of(walter, bill)",
	])
	h.check("comments and blank lines are skipped in a facts document", factLines.len == 2)
	h.check("facts keep their order", factLines[1].text == "parent-of(walter, bill)")

	// A file's predicate is a name in the same shape a typed line's is, since the shape is the
	// solver's one check and the reader here hands it the caller's copy of the solver.
	shaped = knowledge.parseFacts(t, ["has-1-child(oliver, true)"])
	h.check("a fact may open a later section with a digit", not (shaped isa error))
	renamed = knowledge.parseFacts(t, ["Parent-Of(walter, bill)"])
	h.check("a fact's predicate is held to its shape", renamed isa error)
	if renamed isa error then
		h.check("and the refusal says a name is lower case", renamed.message.indexOf("lower-case") != null)
	end if

	brokenFact = knowledge.parseFacts(t, ["// A fact", "parent-of(walter)"])
	h.check("a malformed fact is refused", brokenFact isa error)
	if brokenFact isa error then
		h.check("the fact's refusal names its line", brokenFact.message.indexOf("line 2") != null)
	end if

	// ── A condition that compares numbers ────────────────────────────────────

	aged = parseOneRule("age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))")
	h.check("a comparison parses", not (aged isa error))
	h.check("a comparison is a constraint, not a fact", aged[0].body[1] isa t.Comparison)
	h.check("a comparison reads back",
		bodyText(aged[0]) == "has-age(?x, ?n), less-than-or-equal(?n, 18)")
	h.check("the symbol is kept", aged[0].body[1].symbol == "<=")
	h.check("a number on the right is a number", aged[0].body[1].right isa number and
		aged[0].body[1].right == 18)

	greater = parseOneRule("a(?x, ?y) => and(b(?x, ?n), greater-than-or-equal(?n, 19))")
	h.check("greater-than-or-equal parses",
		greater[0].body[1].text == "greater-than-or-equal(?n, 19)")
	h.check("less-than and greater-than parse",
		parseOneRule("a(?x, ?y) => and(b(?x, ?n), less-than(?n, 2))")[0].body[1].text ==
			"less-than(?n, 2)" and
			parseOneRule("a(?x, ?y) => and(b(?x, ?n), greater-than(?n, 2))")[0].body[1].text ==
				"greater-than(?n, 2)")
	h.check("a comparison does not disturb the not-equal constraint",
		parseOneRule("a(?x, ?y) => and(b(?x, ?y), not-equal(?x, ?y))")[0].body[1] isa t.NotEqual)
	// A comparison is a call shape, not a predicate with a meaning of its own, so one that
	// is not two fields is refused rather than read as a fact.
	h.check("a constraint with one field is refused",
		failure("a(?x, ?y) => less-than-or-equal(?n)") != null and
			failure("a(?x, ?y) => not-equal(?n)") != null and
			failure("a(?x, ?y) => equal(?n)") != null)

	// ── Writing the format back ──────────────────────────────────────────────
	// /save-* writes what the session holds through these, so the two halves have to
	// agree: what one writes, the other reads back as the same knowledge.

	factsWritten = knowledge.factsLines(factLines)
	h.check("facts are written one per line", factsWritten.len == 2 and
		factsWritten[0] == "has-gender(walter, male)")
	rereadFacts = knowledge.parseFacts(t, factsWritten)
	h.check("written facts read back", not (rereadFacts isa error) and
		rereadFacts[1].text == factLines[1].text)

	writtenRules = [
		parseOneRule("sibling-of(?x, ?y) => and(parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y))")[0],
		parseOneRule("in-law-of(?x, ?y) => or(and(married-to(?x, ?p), sibling-of(?p, ?y)), and(sibling-of(?x, ?p), married-to(?p, ?y)))")[0],
		parseOneRule("only-child-of(?x, ?y) => and(parent-of(?y, ?x), not(sibling-of(?x, ?q)))")[0],
	]
	ruleLines = knowledge.rulesLines(writtenRules)
	h.check("rules are written with '=>', as the file spells it", ruleLines[0] ==
		"sibling-of(?x, ?y) => parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)")
	h.check("a rule's alternatives read back as or(...)", ruleLines[1] ==
		"in-law-of(?x, ?y) => or(and(married-to(?x, ?p), sibling-of(?p, ?y)), and(sibling-of(?x, ?p), married-to(?p, ?y)))")
	h.check("a rule's negation reads back", ruleLines[2] ==
		"only-child-of(?x, ?y) => parent-of(?y, ?x), not(sibling-of(?x, ?q))")
	rereadRules = knowledge.parseRules(t, ruleLines)
	h.check("written rules read back", not (rereadRules isa error) and
		rereadRules.len == 3 and bodyText(rereadRules[0]) == bodyText(writtenRules[0]))

	schemaTypes = knowledge.parseSchema(["has-age(text, number)", "has-gender(text, male|female)"])
	schemaWritten = knowledge.schemaLines(schemaTypes)
	h.check("the schema is written one predicate per line", schemaWritten.len == 2 and
		schemaWritten[0] == "has-age(text, number)")
	h.check("a '|' list is written back", schemaWritten[1] == "has-gender(text, male|female)")
	rereadSchema = knowledge.parseSchema(schemaWritten)
	h.check("written schema reads back", not (rereadSchema isa error) and
		rereadSchema["has-gender"][1] == "male|female")
	h.check("a session with no schema writes nothing", knowledge.schemaLines(null).len == 0)

	// ── Naming a data file ───────────────────────────────────────────────────

	// A name typed at /save-* or /load-* gets .kb when it has no extension of its own,
	// while a name that has one - or a folder with a dot in it - is left alone.
	h.check("a bare name gets .kb", knowledge.withExtension("family") == "family.kb")
	h.check("a name that has .kb keeps it", knowledge.withExtension("family.kb") == "family.kb")
	h.check("another extension is left alone", knowledge.withExtension("family.txt") == "family.txt")
	h.check("a dot in a folder name is not an extension",
		knowledge.withExtension("v1.2/family") == "v1.2/family.kb")
	h.check("an empty name stays empty", knowledge.withExtension("") == "")

	// --facts ~/draft.kb reaches the home folder, however the platform spells it. HOME is
	// set for the check, so it reads the same on a machine that has only USERPROFILE, and
	// put back afterwards.
	savedHome = null
	if env.hasIndex("HOME") then savedHome = env["HOME"]
	env["HOME"] = "test-home"
	h.check("a ~/ path expands under the home folder",
		knowledge.expandHome("~/draft.kb") == file.child("test-home", "draft.kb"))
	h.check("a path without ~ is left alone",
		knowledge.expandHome("data/facts.kb") == "data/facts.kb")
	if savedHome == null then
		removed = env.remove("HOME")
	else
		env["HOME"] = savedHome
	end if
end function
