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

	single = parseOneRule("is-child-of(?x, ?y) => is-parent-of(?y, ?x)")
	h.check("a rule line parses", not (single isa error))
	h.check("one rule line is one rule", single.len == 1)
	h.check("the head reads back", single[0].head.text == "is-child-of(?x, ?y)")
	h.check("one condition is a body of one", single[0].body.len == 1)
	h.check("the condition reads back", single[0].body[0].text == "is-parent-of(?y, ?x)")

	// ── The implied and, said out loud ───────────────────────────────────────

	implied = parseOneRule("is-uncle-of(?x, ?y) => is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)")
	spoken = parseOneRule("is-uncle-of(?x, ?y) => and(is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male))")
	h.check("a comma list is one condition per comma", implied[0].body.len == 3)
	h.check("and(...) holds the same three", spoken[0].body.len == 3)
	h.check("both forms read alike", bodyText(implied[0]) == bodyText(spoken[0]))
	h.check("the head is the same either way", implied[0].head.text == spoken[0].head.text)

	nested = parseOneRule("is-uncle-of(?x, ?y) => and(is-parent-of(?p, ?y), and(is-sibling-of(?x, ?p), has-gender(?x, male)))")
	h.check("and(...) nests", nested[0].body.len == 3)

	// ── Constraints ──────────────────────────────────────────────────────────

	constrained = parseOneRule("is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))")
	h.check("a constraint parses inside and(...)", constrained[0].body.len == 3)
	h.check("a constraint reads as a call",
		constrained[0].body[2].text == "not-equal(?x, ?y)")
	h.check("a constraint is not a triple", not (constrained[0].body[2] isa t.SpoTriple))

	equal = parseOneRule("shares-age-group-with(?x, ?y) => and(belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h))")
	h.check("equal parses as a constraint", equal[0].body[1] isa t.Equal)
	h.check("equal is not a triple", not (equal[0].body[1] isa t.SpoTriple))
	h.check("equal reads back as a call",
		bodyText(equal[0]) == "belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h)")

	// ── Lines ────────────────────────────────────────────────────────────────

	// MiniScript has no escape in a string literal, so "\t" is a backslash and a t rather
	// than the tab an indent is: char(9) is the tab, and these lines are indented with one.
	tab = char(9)
	spread = knowledge.parseRules(t, [
		"// A rule may run over several lines.",
		"is-uncle-of(?x, ?y) => and(",
		tab + "is-parent-of(?p, ?y),",
		tab + "is-sibling-of(?x, ?p),",
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

	choice = parseOneRule("is-in-law-of(?x, ?y) => or(married-to(?x, ?p), is-sibling-of(?p, ?y))")
	h.check("or(...) parses", not (choice isa error))
	h.check("or(...) is one condition", choice[0].body.len == 1)
	h.check("or(...) is a choice, not a triple", choice[0].body[0] isa t.Or)
	h.check("or(...) reads back",
		bodyText(choice[0]) == "or(married-to(?x, ?p), is-sibling-of(?p, ?y))")

	either = parseOneRule("close(?x, ?y) => and(or(is-sibling-of(?x, ?y), married-to(?x, ?y)), not-equal(?x, ?y))")
	h.check("or(...) sits among other conditions", either[0].body.len == 2)
	h.check("the choice keeps its alternatives", either[0].body[0].alternatives.len == 2)

	paired = parseOneRule("is-in-law-of(?x, ?y) => or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), is-sibling-of(?x, ?y))")
	h.check("an alternative of several conditions reads as and(...)", not (paired isa error))
	h.check("or(...) holds an and(...) alternative",
		bodyText(paired[0]) ==
			"or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), is-sibling-of(?x, ?y))")

	// ── not: a body that must not hold ───────────────────────────────────────

	negated = parseOneRule("is-only-child-of(?x, ?y) => and(is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q)))")
	h.check("not(...) parses", not (negated isa error))
	h.check("not(...) sits among other conditions", negated[0].body.len == 2)
	h.check("not(...) is a negation, not a triple", negated[0].body[1] isa t.Not)
	h.check("not(...) holds the body it negates",
		negated[0].body[1].body.len == 1 and negated[0].body[1].body[0].text == "is-sibling-of(?x, ?q)")
	h.check("not(...) reads back",
		bodyText(negated[0]) == "is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q))")

	whole = parseOneRule("a(?x, ?y) => not(and(b(?x, ?p), c(?p, ?y)))")
	h.check("not(...) around several conditions reads as and(...)",
		whole[0].body[0].text == "not(and(b(?x, ?p), c(?p, ?y)))")
	h.check("not(...) keeps both conditions of its body", whole[0].body[0].body.len == 2)

	// ── Refusals ─────────────────────────────────────────────────────────────

	h.check("a line without an arrow is refused", failure("is-parent-of(?x, ?y)") != null)
	h.check("a rule with no body is refused", failure("is-parent-of(?x, ?y) => ") != null)
	h.check("not(...) with no condition is refused", failure("a(?x, ?y) => not()") != null)
	several = failure("a(?x, ?y) => not(b(?x, ?y), c(?x, ?y))")
	h.check("not(...) of several conditions is refused", several != null)
	if several != null then
		h.check("the refusal says how to write it", several.message.indexOf("not(and(") != null)
	end if
	h.check("a broken part refuses the whole rule",
		failure("is-grandparent-of(?x, ?y) => is-parent-of(?x, ?p") != null)

	broken = knowledge.parseRules(t, ["// A rule", "is-grandparent-of(?x, ?y) => is-parent-of(?x, ?p"])
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
		"is-parent-of(walter, bill)",
	])
	h.check("comments and blank lines are skipped in a facts document", factLines.len == 2)
	h.check("facts keep their order", factLines[1].text == "is-parent-of(walter, bill)")

	// A file's predicate is a name in the same shape a typed line's is, since the shape is the
	// solver's one check and the reader here hands it the caller's copy of the solver.
	shaped = knowledge.parseFacts(t, ["has-1-child(oliver, true)"])
	h.check("a fact may open a later section with a digit", not (shaped isa error))
	renamed = knowledge.parseFacts(t, ["Parent-Of(walter, bill)"])
	h.check("a fact's predicate is held to its shape", renamed isa error)
	if renamed isa error then
		h.check("and the refusal says a name is lower case", renamed.message.indexOf("lower-case") != null)
	end if

	brokenFact = knowledge.parseFacts(t, ["// A fact", "is-parent-of(walter)"])
	h.check("a malformed fact is refused", brokenFact isa error)
	if brokenFact isa error then
		h.check("the fact's refusal names its line", brokenFact.message.indexOf("line 2") != null)
	end if

	// ── A fact's annotations ─────────────────────────────────────────────────
	// A fact may be followed by `@`, saying when it holds, and by `~`, saying how confident
	// we are of it. Both are optional, either may stand first, and what each adds is kept on
	// the triple: `at` is the text as it was written, or null when the fact is not
	// time-bound, and `confidence` is a number, 100 when the fact says nothing. The temporal
	// one is any text the date reader parses as a DateTime or a TimeSpan, so the short shapes
	// a person writes are read here as they are there.

	annotated = function(text)
		"One fact read from a one-line document, or null when the line would not parse."
		parsed = knowledge.parseFacts(t, [text])
		if parsed isa error then return null
		if parsed.len != 1 then return null
		return parsed[0]
	end function
	annotationsOf = function(text)
		"One fact's annotations as 'at=...; confidence=...', or null when the line would not parse."
		fact = annotated(text)
		if fact == null then return null
		if not fact.hasIndex("at") or not fact.hasIndex("confidence") then return null
		at = "none"
		if fact.at != null then at = fact.at
		return "at=" + at + "; confidence=" + str(fact.confidence)
	end function
	refusedFact = function(text)
		"Says whether a one-line facts document is refused."
		return knowledge.parseFacts(t, [text]) isa error
	end function
	writtenAnnotations = function(text)
		"What factsLines writes for a fact written this way, or null when it would not parse."
		fact = annotated(text)
		if fact == null then return null
		lines = knowledge.factsLines([fact])
		if lines.len != 1 then return null
		return lines[0]
	end function

	// What no annotation says: not time-bound, and fully confident.
	h.check("a fact with no annotation is not time-bound and fully confident",
		annotationsOf("has-age(walter, 78)") == "at=none; confidence=100")
	h.check("a fact with a time is fully confident unless it says otherwise",
		annotationsOf("won-prize(bill, sprint) @ 2002-04-05") ==
			"at=2002-04-05; confidence=100")
	h.check("a fact with a confidence is not time-bound unless it says otherwise",
		annotationsOf("works-at(tim, school) ~ 80%") == "at=none; confidence=80")

	// Any text the date reader takes, so each of the three kinds and a span.
	h.check("a date annotates a fact",
		annotationsOf("won-prize(bill, sprint) @ 2002-04-05") ==
			"at=2002-04-05; confidence=100")
	h.check("a time annotates a fact",
		annotationsOf("wakes-up(anna, early) @ 07:30:00") == "at=07:30:00; confidence=100")
	h.check("a datetime annotates a fact",
		annotationsOf("works-at(tim, school) @ 2019-04-01 09:00:00") ==
			"at=2019-04-01 09:00:00; confidence=100")
	h.check("a span annotates a fact",
		annotationsOf("works-at(tim, school) @ [2019-04-01 09:00:00, 2019-04-01 17:00:00]") ==
			"at=[2019-04-01 09:00:00, 2019-04-01 17:00:00]; confidence=100")

	// A part may be left short, the way the reader takes one, and the fact keeps the text it
	// was written as rather than the full shape the reader fills in.
	h.check("a short date annotates a fact",
		annotationsOf("won-prize(bill, sprint) @ 2019-04") == "at=2019-04; confidence=100")
	h.check("a date with one-digit parts annotates a fact",
		annotationsOf("won-prize(bill, sprint) @ 2019-4-1") == "at=2019-4-1; confidence=100")
	h.check("a short time annotates a fact",
		annotationsOf("wakes-up(anna, early) @ 9:30") == "at=9:30; confidence=100")
	h.check("a span of two short dates annotates a fact",
		annotationsOf("works-at(tim, school) @ [2019-04-01, 2019-04-03]") ==
			"at=[2019-04-01, 2019-04-03]; confidence=100")

	// Confidence is any floating point number from 0 to 100.
	h.check("a whole confidence reads as a number",
		annotationsOf("works-at(tim, school) ~ 50%") == "at=none; confidence=50")
	h.check("a fractional confidence reads as it was written",
		annotationsOf("works-at(tim, school) ~ 87.5%") == "at=none; confidence=87.5")
	h.check("a confidence may be 0%", annotationsOf("works-at(tim, school) ~ 0%") ==
		"at=none; confidence=0")
	h.check("a confidence may be 100%", annotationsOf("works-at(tim, school) ~ 100%") ==
		"at=none; confidence=100")
	h.check("a confidence written with a trailing zero is the same 100%",
		annotationsOf("works-at(tim, school) ~ 100.0%") == "at=none; confidence=100")

	// The two are independent, so either may stand first.
	h.check("the annotations may stand either way round",
		annotationsOf("works-at(tim, school) @ [2019-04-01, 2019-04-03] ~ 80%") ==
			"at=[2019-04-01, 2019-04-03]; confidence=80" and
			annotationsOf("works-at(tim, school) ~ 80% @ [2019-04-01, 2019-04-03]") ==
				"at=[2019-04-01, 2019-04-03]; confidence=80")
	h.check("no space is needed after the sign",
		annotationsOf("won-prize(bill, sprint)@2002-04-05~80%") ==
			"at=2002-04-05; confidence=80")

	// What a service's answer carries: which service and endpoint gave the fact, and the day.
	provenance = annotated("has-location(session, Fort Worth) # ipwho.is/lookup 2026-11-21")
	h.check("a fact may say which service answered it, and when",
		provenance != null and provenance.source == "ipwho.is/lookup" and
			provenance.fetched == "2026-11-21")
	h.check("and factsLines writes it back as the fact it is",
		writtenAnnotations("has-location(session, Fort Worth) # ipwho.is/lookup 2026-11-21") ==
			"has-location(session, Fort Worth) # ipwho.is/lookup 2026-11-21")
	h.check("while a fact with no '#' names no service",
		annotated("has-age(walter, 78)").source == null)

	// The annotations come after the call, so a quoted field and a comment beside them are
	// unaffected.
	mark = char(34)
	h.check("an annotation follows a quoted field",
		annotationsOf("has-home-town(guid, " + mark + "Dallas, TX" + mark + ") @ 2002-04-05") ==
			"at=2002-04-05; confidence=100")
	h.check("a comment after an annotation is still a comment",
		annotationsOf("won-prize(bill, sprint) @ 2002-04-05 // the sprint") ==
			"at=2002-04-05; confidence=100")

	// Anything the reader would not take is refused, rather than making a fact look as if it
	// holds at a time it does not.
	h.check("an annotation that is not a moment is refused",
		refusedFact("won-prize(bill, sprint) @ the sprint"))
	h.check("a date the calendar does not have is refused",
		refusedFact("won-prize(bill, sprint) @ 2019-02-30"))
	h.check("a time the clock does not have is refused",
		refusedFact("wakes-up(anna, early) @ 25:00:00"))
	h.check("a span needs two moments",
		refusedFact("works-at(tim, school) @ [2019-04-01 09:00:00]"))
	h.check("a span of three moments is refused",
		refusedFact("works-at(tim, school) @ [2019-04-01, 2019-04-02, 2019-04-03]"))
	h.check("a span needs its comma",
		refusedFact("works-at(tim, school) @ [2019-04-01 2019-04-03]"))
	h.check("a span does not run on to the next line",
		knowledge.parseFacts(t, ["works-at(tim, school) @ [2019-04-01,", "2019-04-03]"]) isa error)
	h.check("a confidence over 100 is refused",
		refusedFact("works-at(tim, school) ~ 100.1%"))
	h.check("a negative confidence is refused",
		refusedFact("works-at(tim, school) ~ -0.5%"))
	h.check("a confidence needs its number", refusedFact("works-at(tim, school) ~ %"))
	h.check("a confidence needs its '%'", refusedFact("works-at(tim, school) ~ 80"))
	h.check("a confidence that is not a number is refused",
		refusedFact("works-at(tim, school) ~ high%"))
	h.check("a fact may carry one '@'",
		refusedFact("won-prize(bill, sprint) @ 2002-04-05 @ 2003-04-05"))
	h.check("a fact may carry one '~'", refusedFact("works-at(tim, school) ~ 50% ~ 60%"))
	h.check("a bare '@' is refused", refusedFact("won-prize(bill, sprint) @"))
	h.check("a bare '~' is refused", refusedFact("works-at(tim, school) ~"))
	h.check("an annotation the grammar does not have is refused",
		refusedFact("won-prize(bill, sprint) # 2002-04-05"))
	h.check("nothing follows the annotations",
		refusedFact("won-prize(bill, sprint) @ 2002-04-05 extra"))

	// A rule says what follows rather than when a fact holds, so its head and body carry no
	// annotation.
	h.check("a rule's head takes no annotation",
		knowledge.parseRules(t, ["is-anything(?x, ?y) @ 2002-04-05 => is-parent-of(?y, ?x)"]) isa error)
	h.check("a rule's body takes no annotation",
		knowledge.parseRules(t, ["is-anything(?x, ?y) => is-parent-of(?y, ?x) @ 2002-04-05"]) isa error)

	// /save-facts writes the annotations back, and what it writes reads again.
	h.check("an annotated fact is written with its annotations",
		writtenAnnotations("won-prize(bill, sprint) @ 2002-04-05 ~ 80%") ==
			"won-prize(bill, sprint) @ 2002-04-05 ~ 80%")
	savedAnnotated = writtenAnnotations("won-prize(bill, sprint) ~ 80% @ 2002-04-05")
	savedReadBack = null
	if savedAnnotated != null then savedReadBack = annotationsOf(savedAnnotated)
	h.check("an annotated fact reads back after a save",
		savedAnnotated != null and savedReadBack == "at=2002-04-05; confidence=80")
	h.check("a fact with no annotation is written as it was",
		writtenAnnotations("has-age(walter, 78)") == "has-age(walter, 78)")

	// ── Quoted values ────────────────────────────────────────────────────────
	// A field may be written in double quotes, so a value holds what the format would
	// otherwise read itself: a comma, a bracket, the '//' that opens a comment. The quotes
	// are not part of the value, and a value that needs them is written with them, so a
	// fact a session saves is one the file loads again.

	q = char(34)
	inQuotes = function(text)
		return q + text + q
	end function

	towns = parseOneFact("has-home-town(guid, " + inQuotes("Dallas, TX") + ")")
	h.check("a quoted comma is one field", not (towns isa error) and
		towns[0].object == "Dallas, TX")
	h.check("it reads as it was written",
		towns[0].text == "has-home-town(guid, " + inQuotes("Dallas, TX") + ")")

	// /save-facts writes facts through factsLines, and the file it writes has to load
	// again: a value that needs quotes is the one thing the call form cannot say bare.
	savedTowns = knowledge.factsLines(towns)
	reloadedTowns = knowledge.parseFacts(t, savedTowns)
	h.check("a fact with a comma survives a save and a reload",
		not (reloadedTowns isa error) and reloadedTowns[0].object == "Dallas, TX" and
			reloadedTowns[0].text == towns[0].text)

	// The bare spelling is the same value, so a file written before quotes existed reads
	// as it always did, and a value that needs no quotes is still written without them.
	bareTown = parseOneFact("has-home-town(guid, Dallas)")
	h.check("a value with no comma is written bare",
		knowledge.factsLines(bareTown)[0] == "has-home-town(guid, Dallas)")
	quotedTown = knowledge.parseFacts(t, ["has-home-town(guid, " + inQuotes("Dallas") + ")"])
	h.check("a quoted value is the value its bare spelling is",
		not (quotedTown isa error) and quotedTown[0].text == bareTown[0].text)

	// The quotes promise text, so they are how an all-digit value sits in a `text` field:
	// the number would be refused there, and the text keeps its quotes through a save.
	houseNumber = parseOneFact("has-house-number(way/1, " + inQuotes("5") + ")")
	h.check("a quoted number is text in a data file",
		not (houseNumber isa error) and houseNumber[0].object == "5" and
			not (houseNumber[0].object isa number))
	h.check("and it is written back in quotes",
		knowledge.factsLines(houseNumber)[0] ==
			"has-house-number(way/1, " + inQuotes("5") + ")")

	// A subject is a value like any other, so it takes quotes the same way.
	place = parseOneFact("has-resident(" + inQuotes("Dallas, TX") + ", guid)")
	h.check("a quoted subject parses in a data file", not (place isa error) and
		place[0].subject == "Dallas, TX")
	h.check("and it is written back with its quotes",
		knowledge.factsLines(place)[0] ==
			"has-resident(" + inQuotes("Dallas, TX") + ", guid)")

	pages = parseOneFact("has-home-page(guid, " + inQuotes("http://example.com/x") + ")")
	h.check("a quoted '//' is not a comment", not (pages isa error) and
		pages[0].object == "http://example.com/x")
	noted = parseOneFact("has-home-page(guid, " + inQuotes("http://example.com/x") +
		") // where the page is")
	h.check("a comment after a quoted value is still a comment", not (noted isa error) and
		noted[0].object == "http://example.com/x")

	nested = parseOneFact("born-in(oliver, " + inQuotes("Round Rock (north)") + ")")
	h.check("a quoted bracket does not close the call", not (nested isa error) and
		nested[0].object == "Round Rock (north)")
	h.check("and it does not run on to the next line",
		knowledge.parseFacts(t, ["born-in(oliver, " + inQuotes("Round Rock (north)") + ")",
			"has-gender(oliver, male)"]).len == 2)

	// A rule's value takes quotes too, and the arrow inside one is not the rule's arrow.
	townRule = parseOneRule("has-town-resident(?p, ?t) => lives-in(?p, " +
		inQuotes("Dallas, TX") + ")")
	h.check("a quoted value in a rule body parses", not (townRule isa error) and
		townRule[0].body[0].object == "Dallas, TX")
	h.check("and the rule is written back so it reads again",
		not (knowledge.parseRules(t, knowledge.rulesLines(townRule)) isa error))
	arrowRule = parseOneRule("a(?x, ?y) => b(?x, " + inQuotes("x => y") + ")")
	h.check("a quoted arrow is not the rule's arrow", not (arrowRule isa error) and
		arrowRule[0].body[0].object == "x => y")

	// A quote that is never closed would swallow the rest of the entry, so the entry is
	// refused rather than read as something else.
	openQuote = knowledge.parseFacts(t, ["has-home-town(guid, " + q + "Dallas, TX)"])
	h.check("an unclosed quote is refused", openQuote isa error and
		openQuote.message.indexOf("quote") != null)

	// ── A condition that compares numbers ────────────────────────────────────

	aged = parseOneRule("belongs-to-age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))")
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
		parseOneRule("is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))")[0],
		parseOneRule("is-in-law-of(?x, ?y) => or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))")[0],
		parseOneRule("is-only-child-of(?x, ?y) => and(is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q)))")[0],
	]
	ruleLines = knowledge.rulesLines(writtenRules)
	h.check("rules are written with '=>', as the file spells it", ruleLines[0] ==
		"is-sibling-of(?x, ?y) => is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y)")
	h.check("a rule's alternatives read back as or(...)", ruleLines[1] ==
		"is-in-law-of(?x, ?y) => or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))")
	h.check("a rule's negation reads back", ruleLines[2] ==
		"is-only-child-of(?x, ?y) => is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q))")
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
