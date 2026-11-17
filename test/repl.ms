// Cases for the REPL: a rule line read back as a rule, and a session driven by script.

run = function(t, rules, repl, h)
	"Checks rule-line parsing and a session's transcript, against the shared copies."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	v = function(name)
		return t.var(name)
	end function
	readable = function(result)
		return not (result isa error)
	end function
	printed = function(lines, text)
		"Whether a transcript holds this line exactly."
		return lines.indexOf(text) != null
	end function
	holds = function(lines, piece)
		"Whether any transcript line holds this piece of text."
		for line in lines
			if line.indexOf(piece) != null then return true
		end for
		return false
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
	h.check("the session says where the commands are", lines[0].indexOf("/help") != null)
	h.check("a question with no answer says so",
		printed(lines, "  no solution found at depth 8"))
	h.check("the report names the fact still missing",
		printed(lines, "    a fact like parent-of(?p, susan)"))
	h.check("the session asks for the variable the report left open",
		asked.answers.asked[1] == "  ?p = ")
	h.check("the value it is given becomes a fact",
		printed(lines, "  added parent-of(walter, susan)"))
	h.check("the query's own fact is not repeated above the prompt",
		not printed(lines, "  parent-of(?p, susan)"))
	h.check("the fact answers the question on the next pass",
		printed(lines, "  parent-of(walter, susan)"))
	h.check("the fact stays in the session", asked.session.facts.len == 3)

	// A missing fact with two variables is asked about one at a time.
	pair = startSession(family + [], [], ["aunt-of(?p, ?q)", "doris", "nina", "quit"])
	h.check("a two-variable fact is asked for a variable at a time",
		pair.answers.asked[1] == "  ?p = " and pair.answers.asked[2] == "  ?q = ")
	h.check("both answers make the one fact",
		printed(pair.answers.lines, "  added aunt-of(doris, nina)"))
	h.check("the question is answered too",
		printed(pair.answers.lines, "  aunt-of(doris, nina)"))

	// A rule typed at the prompt joins the search.
	ruleLine = "grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)"
	ruled = startSession(family + [], [], [ruleLine, "grandparent(?p, ?y)"])
	h.check("a rule typed at the prompt is added",
		printed(ruled.answers.lines, "  added rule " + ruleLine))
	h.check("the new rule answers the next question",
		printed(ruled.answers.lines, "  grandparent(bill, anna)"))

	// A malformed line is refused, quoted, and the session carries on.
	stumbling = startSession(family + [], [],
		["parent-of(walter", "parent-of(walter, susan)", "parent-of(?p, susan)"])
	h.check("a bad line is refused with the line quoted",
		holds(stumbling.answers.lines, "malformed spo") and
			holds(stumbling.answers.lines, "parent-of(walter"))
	h.check("the session carries on after it",
		printed(stumbling.answers.lines, "  added parent-of(walter, susan)"))

	// ── A rule's own facts are asked for, not the query's shape ────────────

	// The uncle rule is the case where asking the query's own variable would end the
	// session by assertion: ?p is the uncle, so the report needs a parent of Susan and
	// a male sibling of that parent.
	uncleRule = rules.Rule.make(spo(v("x"), "uncle-of", v("y")),
		[spo(v("p"), "parent-of", v("y")), spo(v("x"), "sibling-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	uncle = startSession(family + [], [uncleRule],
		["uncle-of(?p, susan)", "george", "alfonso", "y"])
	uncleLines = uncle.answers.lines
	uncleAsked = uncle.answers.asked
	h.check("a rule's fact is asked for before the query's own shape",
		uncleAsked[1] == "  ?p' = ")
	h.check("the fact being filled is shown above its question",
		printed(uncleLines, "  parent-of(?p', susan)"))
	h.check("that answer is added as a fact",
		printed(uncleLines, "  added parent-of(george, susan)"))
	h.check("the sibling condition follows, named against the parent just given",
		printed(uncleLines, "  sibling-of(?p, george)") and uncleAsked[2] == "  ?p = ")
	h.check("a fact with no variable left is offered instead of asked about",
		printed(uncleLines, "  has-gender(alfonso, male)") and
			uncleAsked[3] == "  add it? [y/N] ")
	h.check("yes adds it and the rules reach the answer from those facts",
		printed(uncleLines, "  added has-gender(alfonso, male)") and
			uncleLines[uncleLines.len - 1] == "  uncle-of(alfonso, susan)")
	h.check("the query's own fact was never asserted", uncle.session.facts.len == 5)

	// Declining the offer leaves the knowledge base as it was.
	declined = startSession(family + [], [uncleRule],
		["uncle-of(?p, susan)", "george", "alfonso", "n"])
	h.check("no leaves the fact out", declined.session.facts.len == 4 and
		not holds(declined.answers.lines, "  added has-gender"))

	// A rule's fact is filled in by the variables it brings itself. ?p is the answer the
	// question asks for, so it is asked about in the question and not again underneath it:
	// filling it in there would assert the answer instead of finding it.
	apart = family + [spo("bill", "sibling-of", "george"), spo("bill", "has-gender", "male")]
	tangled = startSession(apart + [], [uncleRule], ["uncle-of(bill, ?p)", "george", "quit"])
	h.check("a rule's fact is asked about for the variables it introduces",
		printed(tangled.answers.lines, "      parent-of(?p', ?p)") and
			tangled.answers.asked[1] == "  ?p' = " and tangled.answers.asked[2] == "? " and
			tangled.session.facts.len == 4)

	// An answer given under one line of a rule's block is carried to the next: ?p' = sam
	// turns the check below it into a fact with nothing left to fill, so it is kept.
	carried = startSession(apart + [], [uncleRule], ["uncle-of(bill, ?p)", "sam", "y"])
	h.check("an answer is carried to the next fact of the block",
		carried.answers.asked[1] == "  ?p' = " and
			carried.answers.asked[2] == "  add it? [y/N] " and
			printed(carried.answers.lines, "  added sibling-of(bill, sam)") and
			carried.session.facts.len == 5)

	// What was given is remembered for as long as the report stands, so the question that
	// comes round again shows the fact with the value in it and asks only what is left.
	remembered = startSession(apart + [], [uncleRule],
		["uncle-of(bill, ?p)", "sam", "y", "alfonso"])
	h.check("a value given once is not asked for a second time",
		printed(remembered.answers.lines, "  parent-of(sam, ?p)") and
			remembered.answers.asked[3] == "  ?p = " and
			printed(remembered.answers.lines, "  added parent-of(sam, alfonso)") and
			remembered.answers.lines[remembered.answers.lines.len - 1] == "  uncle-of(bill, alfonso)")
	// The block above reads the same way, so the report and the question agree.
	h.check("the report block shows the values already given",
		printed(remembered.answers.lines, "      parent-of(sam, ?p)"))
	// A fact the session can already prove needs nothing added, so the block stops asking
	// for it - though it lists it while it is still only a check.
	h.check("the report stops listing a fact the session holds",
		not holds(remembered.answers.lines, "      sibling-of(bill, sam)") and
			holds(remembered.answers.lines, "      sibling-of(bill, ?p')"))

	// ── The query's own shape is the last thing offered ─────────────────────

	// A rule in the knowledge base that cannot conclude this query leaves the query's
	// own shape as the only fact there is to ask about.
	unrelated = rules.Rule.make(spo(v("x"), "child-of", v("y")),
		[spo(v("y"), "parent-of", v("x"))])
	ownShape = startSession(family + [], [unrelated], ["parent-of(?p, susan)", "walter", "quit"])
	h.check("the query's own shape is asked when no rule can conclude it",
		ownShape.answers.asked[1] == "  ?p = " and
			printed(ownShape.answers.lines, "  added parent-of(walter, susan)"))

	// A goal with no variable at all is a fact to add, not a question to ask, so the
	// ranking above only ever decides between facts that still have one.
	settled = family + [spo("george", "parent-of", "susan")]
	asserted = startSession(settled + [], [uncleRule], ["uncle-of(zed, susan)"])
	h.check("a ground line is a fact, even when nothing proves it",
		printed(asserted.answers.lines, "  added uncle-of(zed, susan)"))

	// Answering by fiat is deliberate but still there: a whole fact typed where a value is
	// asked for is a fact, with the standing any typed fact has, and the question starts
	// again from it.
	fiat = startSession(family + [], [uncleRule], ["uncle-of(bill, ?p)", "uncle-of(bill, zed)"])
	h.check("a fact typed instead of a value is added, and answers the question",
		printed(fiat.answers.lines, "  added uncle-of(bill, zed)") and
			fiat.answers.lines[fiat.answers.lines.len - 1] == "  uncle-of(bill, zed)")

	// A line that parses but still holds a variable is neither a fact to add nor a value
	// to bind, so it is refused and the question is put again.
	refused = startSession(family + [], [],
		["parent-of(?p, susan)", "parent-of(walter, ?x)", "walter", "quit"])
	h.check("a fact-shaped line with a variable is refused at a value prompt",
		printed(refused.answers.lines,
			"  parent-of(walter, ?x) still holds a variable: type a value, or a fact without one") and
			refused.answers.asked.len == 4 and refused.answers.asked[2] == "  ?p = " and
			printed(refused.answers.lines, "  added parent-of(walter, susan)"))

	// ── --verbose gives the tree behind each answer, as a run does ──────────

	verbose = startSession(family + [], [], ["parent-of(?p, susan)", "walter", "quit"], null, 1)
	h.check("a verbose session prints the proof tree behind an answer",
		printed(verbose.answers.lines, "  parent-of(walter, susan)  <- fact"))
	verboseRule = startSession(family + [], [], [ruleLine, "grandparent(bill, ?y)"], null, 1)
	h.check("a verbose answer names the rule behind it",
		holds(verboseRule.answers.lines, "  <- rule grandparent(?x, ?y)"))

	// ── Slash commands ──────────────────────────────────────────────────────

	commands = startSession(family + [], [uncleRule],
		["/help", "/facts", "/rules", "/nope", "/exit", "parent-of(?p, susan)"])
	commandLines = commands.answers.lines
	h.check("/help lists every command",
		printed(commandLines, "  /exit  leave the session") and
			printed(commandLines, "  /undo  take back the last fact added") and
			printed(commandLines, "  /rules  list the rules"))
	h.check("/facts lists the facts it holds",
		printed(commandLines, "  2 facts") and printed(commandLines, "    parent-of(bill, tim)"))
	h.check("/rules lists the rules it holds",
		printed(commandLines, "  1 rule") and
			holds(commandLines, "    uncle-of(?x, ?y) <- parent-of(?p, ?y)"))
	h.check("an unknown command is refused",
		printed(commandLines, "  no such command: /nope (/help lists them)"))
	h.check("/exit leaves before the next line is read", commands.answers.asked.len == 5)

	// ── Taking a fact back ───────────────────────────────────────────────────

	taken = startSession(family + [], [], ["parent-of(walter, susan)", "/undo", "/undo"])
	h.check("/undo takes back the fact just added",
		printed(taken.answers.lines, "  took back parent-of(walter, susan)"))
	h.check("the knowledge base loses it again", taken.session.facts.len == 2)
	h.check("/undo with nothing to take back says so",
		printed(taken.answers.lines, "  nothing to take back"))

	// A wrong answer can be taken back while the session is still asking, and the
	// question is put again.
	wrong = startSession(family + [], [],
		["parent-of(walter, susan)", "aunt-of(?p, susan)", "/undo", "nina"])
	h.check("a wrong fact is taken back from inside a question",
		printed(wrong.answers.lines, "  took back parent-of(walter, susan)") and
			wrong.answers.asked[2] == "  ?p = " and wrong.answers.asked[3] == "  ?p = ")
	h.check("the question is asked again and answered",
		printed(wrong.answers.lines, "  added aunt-of(nina, susan)") and
			wrong.session.facts.len == 3)

	// ── Painting is the same style table, so it is opt-in the same way ──────

	mark = {"prompt": "<p>", "added": "<a>", "answer": "<n>", "warning": "<w>", "normal": "</>"}
	painted = startSession(family + [], [], ["parent-of(?p, susan)", "walter", "quit"], mark)
	h.check("a painted prompt opens and closes", painted.answers.asked[0] == "<p>? </>")
	h.check("a painted gap warning closes its line",
		printed(painted.answers.lines, "<w>  no solution found at depth 8</>"))
	h.check("a painted added fact is marked as such",
		printed(painted.answers.lines, "<a>  added parent-of(walter, susan)</>"))
	h.check("a painted answer wraps the whole line",
		printed(painted.answers.lines, "<n>  parent-of(walter, susan)</>"))
end function
