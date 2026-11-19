// Cases for the knowledge data format: the parser behind facts.data and rules.data.

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

	constrained = parseOneRule("sibling-of(?x, ?y) => and(parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y)")
	h.check("a constraint parses inside and(...)", constrained[0].body.len == 3)
	h.check("a constraint reads as ?x != ?y", constrained[0].body[2].text == "?x != ?y")
	h.check("a constraint is not a triple", not (constrained[0].body[2] isa t.SpoTriple))

	// ── Lines ────────────────────────────────────────────────────────────────

	spread = knowledge.parseRules(t, [
		"// A rule may run over several lines.",
		"uncle-of(?x, ?y) => and(",
		"\tparent-of(?p, ?y),",
		"\tsibling-of(?x, ?p),",
		"\thas-gender(?x, male))",
		"",
		"married-to(?y, ?x) =>",
		"\tmarried-to(?x, ?y)",
	])
	h.check("comments and blank lines are skipped", spread.len == 2)
	h.check("a rule may run over several lines", spread[0].body.len == 3)
	h.check("and again after the arrow", spread[1].head.text == "married-to(?y, ?x)")
	h.check("the rule after the break is whole", spread[1].body.len == 1)

	// ── Refusals ─────────────────────────────────────────────────────────────

	h.check("a line without an arrow is refused", failure("parent-of(?x, ?y)") != null)
	h.check("a rule with no body is refused", failure("parent-of(?x, ?y) => ") != null)
	h.check("a broken part refuses the whole rule",
		failure("grandparent(?x, ?y) => parent-of(?x, ?p") != null)

	unsupported = failure("a(?x, ?y) => or(b(?x, ?y), c(?x, ?y))")
	h.check("a grouping the engine cannot use is refused", unsupported != null)
	if unsupported != null then
		h.check("a refusal names the grouping", unsupported.message.indexOf("or(...)") != null)
	end if

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

	factLines = knowledge.parseFacts(t, [
		"// A person",
		"",
		"has-gender(walter, male)",
		"parent-of(walter, bill)",
	])
	h.check("comments and blank lines are skipped in a facts document", factLines.len == 2)
	h.check("facts keep their order", factLines[1].text == "parent-of(walter, bill)")

	brokenFact = knowledge.parseFacts(t, ["// A fact", "parent-of(walter)"])
	h.check("a malformed fact is refused", brokenFact isa error)
	if brokenFact isa error then
		h.check("the fact's refusal names its line", brokenFact.message.indexOf("line 2") != null)
	end if
end function
