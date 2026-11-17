// Cases for the REPL: a rule line read back as a rule, and a session driven by script.

run = function(t, rules, repl, h)
	"Checks rule-line parsing and a session's transcript, against the shared copies."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	readable = function(result)
		return not (result isa error)
	end function

	// ── A rule line is the line Rule.text prints ─────────────────────────────

	line = "grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)"
	parsed = t.parseRule(line)
	h.check("a rule line parses", readable(parsed))
	h.check("the head is the triple before the arrow",
		parsed.head.text == "grandparent(?x, ?y)")
	h.check("the body takes one condition per comma", parsed.body.len == 2)
	h.check("a condition reads back as it was written",
		parsed.body[1].text == "parent-of(?p, ?y)")
	h.check("Rule.text gets its own line back",
		rules.Rule.make(parsed.head, parsed.body).text == line)

	constrained = t.parseRule("sibling-of(?x, ?y) <- parent-of(?p, ?x), ?x != ?y")
	h.check("a constraint in a body is read as a constraint",
		readable(constrained) and constrained.body[1].text == "?x != ?y")
	h.check("a line without an arrow is refused", t.parseRule("parent-of(?x, susan)") isa error)
	h.check("a rule with no conditions is refused", t.parseRule("parent-of(?x, ?y) <- ") isa error)
	h.check("a broken condition refuses the whole line",
		t.parseRule("grandparent(?x, ?y) <- parent-of(?x, ?p") isa error)

	// ── A scripted session ───────────────────────────────────────────────────

	// A session over a script of typed lines, recording what it printed and asked.
	startSession = function(facts, ruleList, script, style=null, verbose=0)
		answers = {"lines": [], "asked": [], "at": 0}
		reader = function(question)
			answers.asked.push(question)
			if answers.at >= script.len then return null
			answers.at = answers.at + 1
			return script[answers.at - 1]
		end function
		writer = function(line)
			answers.lines.push(line)
		end function
		session = {"triples": t, "Rule": rules.Rule, "facts": facts, "rules": ruleList,
			"depth": 8, "verbose": verbose, "style": style,
			"io": {"read": @reader, "say": @writer}}
		repl.run(session)
		return {"session": session, "answers": answers}
	end function

	family = [spo("bill", "parent-of", "tim"), spo("tim", "parent-of", "anna")]

	// A question nothing answers, and the one value it asks for.
	asked = startSession(family + [], [], ["parent-of(?p, susan)", "walter", "quit"])
	lines = asked.answers.lines
	h.check("the session opens with what it takes", lines[0].indexOf("'quit' leaves") != null)
	h.check("a question with no answer says so",
		lines[1] == "  no solution found at depth 8")
	h.check("the report names the fact still missing",
		lines[3] == "    a fact like parent-of(?p, susan)")
	h.check("the session asks for the variable the report left open",
		asked.answers.asked[1] == "  ?p = ")
	h.check("the value it is given becomes a fact",
		lines[4] == "  added parent-of(walter, susan)")
	h.check("the fact answers the question on the next pass",
		lines[5] == "  parent-of(walter, susan)")
	h.check("the fact stays in the session", asked.session.facts.len == 3)

	// A missing fact with two variables is asked about one at a time.
	pair = startSession(family + [], [], ["aunt-of(?p, ?q)", "doris", "nina", "quit"])
	h.check("a two-variable fact is asked for a variable at a time",
		pair.answers.asked[1] == "  ?p = " and pair.answers.asked[2] == "  ?q = ")
	h.check("both answers make the one fact",
		pair.answers.lines[4] == "  added aunt-of(doris, nina)")
	h.check("the question is answered too", pair.answers.lines[5] == "  aunt-of(doris, nina)")

	// A rule typed at the prompt joins the search.
	ruleLine = "grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)"
	ruled = startSession(family + [], [], [ruleLine, "grandparent(?p, ?y)"])
	h.check("a rule typed at the prompt is added",
		ruled.answers.lines[1] == "  added rule " + ruleLine)
	h.check("the new rule answers the next question",
		ruled.answers.lines[2] == "  grandparent(bill, anna)")

	// A malformed line is refused, quoted, and the session carries on.
	stumbling = startSession(family + [], [],
		["parent-of(walter", "parent-of(walter, susan)", "parent-of(?p, susan)"])
	h.check("a bad line is refused with the line quoted",
		stumbling.answers.lines[1].indexOf("malformed spo") != null and
			stumbling.answers.lines[1].indexOf("parent-of(walter") != null)
	h.check("the session carries on after it",
		stumbling.answers.lines[3] == "  parent-of(walter, susan)")

	// ── --verbose gives the tree behind each answer, as a run does ──────────

	verbose = startSession(family + [], [], ["parent-of(?p, susan)", "walter", "quit"], null, 1)
	h.check("a verbose session prints the proof tree behind an answer",
		verbose.answers.lines[5] == "  parent-of(walter, susan)  <- fact")
	verboseRule = startSession(family + [], [], [ruleLine, "grandparent(bill, ?y)"], null, 1)
	h.check("a verbose answer names the rule behind it",
		verboseRule.answers.lines[2].indexOf("  <- rule grandparent(?x, ?y)") != null)

	// ── Painting is the same style table, so it is opt-in the same way ──────

	mark = {"prompt": "<p>", "added": "<a>", "answer": "<n>", "warning": "<w>", "normal": "</>"}
	painted = startSession(family + [], [], ["parent-of(?p, susan)", "walter", "quit"], mark)
	h.check("a painted prompt opens and closes", painted.answers.asked[0] == "<p>? </>")
	h.check("a painted gap warning closes its line",
		painted.answers.lines[1] == "<w>  no solution found at depth 8</>")
	h.check("a painted added fact is marked as such",
		painted.answers.lines[4] == "<a>  added parent-of(walter, susan)</>")
	h.check("a painted answer wraps the whole line",
		painted.answers.lines[5] == "<n>  parent-of(walter, susan)</>")
end function
