// Cases for the session at the prompt: a rule line read back as a rule, and a session driven by
// script, through the prompt library it is handed.

run = function(t, rules, host, h, schema, knowledge, library)
	"Checks rule-line parsing, a session's transcript, and saving its components."
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

	constrained = t.parseRule("sibling-of(?x, ?y) <- parent-of(?p, ?x), not-equal(?x, ?y)")
	h.check("a constraint in a body is read as a constraint",
		readable(constrained) and constrained.body[1].text == "not-equal(?x, ?y)")
	h.check("a line without an arrow is refused", t.parseRule("parent-of(?x, susan)") isa error)
	h.check("a rule with no conditions is refused", t.parseRule("parent-of(?x, ?y) <- ") isa error)
	h.check("a broken condition refuses the whole line",
		t.parseRule("grandparent(?x, ?y) <- parent-of(?x, ?p") isa error)

	// The line data/rules.kb prints for in-law-of, so a rule the session shows can be
	// typed back in: or(...) around two and(...) alternatives.
	choice = "in-law-of(?x, ?y) <- or(and(married-to(?x, ?p), sibling-of(?p, ?y)), and(sibling-of(?x, ?p), married-to(?p, ?y)))"
	chosen = t.parseRule(choice)
	h.check("a rule line with or(...) parses", readable(chosen))
	h.check("or(...) is one condition holding two and(...) alternatives",
		readable(chosen) and chosen.body.len == 1 and chosen.body[0].alternatives.len == 2 and
			chosen.body[0].alternatives[0].len == 2)
	h.check("Rule.text gets an or(...) line back",
		readable(chosen) and rules.Rule.make(chosen.head, chosen.body).text == choice)

	// The line data/rules.kb prints for only-child-of, so a negation can be typed back in.
	single = "only-child-of(?x, ?y) <- parent-of(?y, ?x), not(sibling-of(?x, ?q))"
	negated = t.parseRule(single)
	h.check("a rule line with not(...) parses", readable(negated) and negated.body.len == 2)
	h.check("not(...) is one condition holding the body it negates",
		readable(negated) and negated.body[1] isa t.Not and negated.body[1].body.len == 1)
	h.check("Rule.text gets a not(...) line back",
		readable(negated) and rules.Rule.make(negated.head, negated.body).text == single)

	// ── A scripted session ───────────────────────────────────────────────────

	// A session over a script of typed lines, recording what it printed and asked.
	startSession = function(facts, ruleList, script, style=null, verbose=0, types=null, paths=null)
		if paths == null then paths = {}
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
			"depth": 8, "verbose": verbose, "style": style, "schema": schema, "types": types,
			"paths": paths, "knowledge": knowledge,
			"io": {"read": @reader, "say": @writer}}
		host.run(session)
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

	// A value given for a variable the rule introduces is progress, even when the rest of
	// that rule's conditions already hold: naming the sibling lets the next pass ask for the
	// one fact really missing, instead of the session giving up because nothing was added.
	apart = family + [spo("bill", "sibling-of", "george"), spo("bill", "has-gender", "male")]
	tangled = startSession(apart + [], [uncleRule], ["uncle-of(bill, ?p)", "george", "zed", "quit"])
	h.check("a rule's fact is asked about for the variables it introduces",
		printed(tangled.answers.lines, "      parent-of(?p', ?p)") and
			tangled.answers.asked[1] == "  ?p' = ")
	h.check("naming the introduced variable carries the loop to the fact really missing",
		tangled.answers.asked[2] == "  ?p = " and
			printed(tangled.answers.lines, "  added parent-of(george, zed)") and
			tangled.answers.lines[tangled.answers.lines.len - 1] == "  uncle-of(bill, zed)" and
			tangled.session.facts.len == 5)

	// A condition a rule already derives - not a stored fact, but provable from the rules -
	// is treated the same as one already stored: the fill does not offer to add it, and the
	// loop still reaches the one fact that is genuinely missing. Here bill and george are
	// derivably siblings, so only a child for george is missing.
	siblingRule = rules.Rule.make(spo(v("x"), "sibling-of", v("y")),
		[spo(v("p"), "parent-of", v("x")), spo(v("p"), "parent-of", v("y")),
			t.NotEqual.make(v("x"), v("y"))])
	// Two sets of parents keep parent-of(?p, ?y) open in the report, so the fill asks for the
	// sibling by name; oliver and clara are derivably siblings through henry, so once the
	// sibling is named the only fact still missing is a child for clara.
	kin = [spo("henry", "parent-of", "oliver"), spo("henry", "parent-of", "clara"),
		spo("walter", "parent-of", "bill"), spo("walter", "parent-of", "george"),
		spo("oliver", "has-gender", "male")]
	derivable = startSession(kin + [], [siblingRule, uncleRule],
		["uncle-of(oliver, ?y)", "clara", "zed", "quit"])
	h.check("a derivable condition is not offered as a fact to add",
		not holds(derivable.answers.asked, "add it?"))
	h.check("and the loop still reaches the fact that is really missing",
		printed(derivable.answers.lines, "  added parent-of(clara, zed)") and
			derivable.answers.lines[derivable.answers.lines.len - 1] == "  uncle-of(oliver, zed)")

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
	h.check("/help lists the save and load commands",
		printed(commandLines, "  /save-facts [FILE]  write the facts to their file, or to one named") and
			printed(commandLines, "  /load-facts [FILE]  replace the facts with a file's") and
			printed(commandLines, "  /save-schema [FILE]  write the schema to its file, or to one named"))

	// The block as the program itself prints it, pinned line for line: the first line is the
	// greeting the session gives before the loop, the twelve after it are /help. The labels are
	// the library's and the notes are this host's, so this is where the two meet - a change to
	// either shows up here, rather than only in a run someone happens to be watching.
	pinned = startSession([], [], ["/help", "q"])
	h.check("the program's greeting and /help block are exactly these thirteen lines",
		pinned.answers.lines == [
		"Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.",
		"  /exit  leave the session",
		"  /help [NAME]  list these commands",
		"  /undo  take back the last fact added",
		"  /facts  list the facts",
		"  /rules  list the rules",
		"  /save-facts [FILE]  write the facts to their file, or to one named",
		"  /load-facts [FILE]  replace the facts with a file's",
		"  /save-rules [FILE]  write the rules to their file, or to one named",
		"  /load-rules [FILE]  replace the rules with a file's",
		"  /save-schema [FILE]  write the schema to its file, or to one named",
		"  /load-schema [FILE]  replace the schema with a file's",
		"  /depth  say how deep the search goes",
	])

	// The line /help lists last is the program's own registration: src/session.ms adds /depth
	// through the library's call after the component commands the table was built from.
	depthed = startSession([], [], ["/depth", "q"])
	h.check("/depth says the depth the session searches to",
		printed(depthed.answers.lines, "  searching to depth 8"))
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

	// ── Numbers, and the schema a typed fact is held against ─────────────────

	// An age is stored as a number, so a number typed in a question has to meet one:
	// the prompt reads a field with the same term parser the loaders use.
	aged = startSession([spo("bill", "has-age", 54)], [], ["has-age(?p, 54)"])
	h.check("a number typed in a question meets the fact it was stored as",
		printed(aged.answers.lines, "  has-age(bill, 54)"))

	ageTypes = {"has-age": ["text", "number"]}
	missed = startSession([spo("bill", "has-age", 54)], [], ["has-age(bill, twenty)"],
		null, 0, ageTypes)
	h.check("a fact that misses the schema is refused",
		printed(missed.answers.lines,
			"  refused: has-age(bill, twenty): the object should be a number"))
	h.check("and a refused fact is not stored", missed.session.facts.len == 1)
	fitted = startSession([], [], ["has-gender(walter, boy)"], null, 0,
		{"has-gender": ["text", "male|female"]})
	h.check("a value outside the schema's list is refused",
		printed(fitted.answers.lines, "  refused: has-gender(walter, boy): the object should be one of: male, female"))
	h.check("a fact that fits the schema is added",
		startSession([], [], ["has-age(tim, 24)"], null, 0, ageTypes).session.facts.len == 1)

	// A question is held against the schema before it is searched, so a field already given
	// as a value that no fact could ever carry is refused at once: the search would find
	// nothing, and asking the question's own variable would only set up a fact the same
	// check refuses.
	asked = startSession([spo("bill", "has-age", 54)], [], ["has-age(?a, twenty)"],
		null, 0, ageTypes)
	h.check("a question whose value misses the schema is refused",
		printed(asked.answers.lines,
			"  refused: has-age(?a, twenty): the object should be a number"))
	h.check("and a refused question asks for nothing",
		asked.answers.asked.len == 2 and asked.answers.asked[1] == "? " and
			not holds(asked.answers.lines, "no solution"))

	// A value that completes a fact the schema refuses changes nothing, so the question
	// stops there rather than asking the same variable again.
	refused = startSession([], [], ["has-age(tim, ?n)", "twenty"], null, 0, ageTypes)
	h.check("a value that makes a refused fact is refused",
		printed(refused.answers.lines,
			"  refused: has-age(tim, twenty): the object should be a number"))
	h.check("and the question ends instead of asking again",
		refused.answers.asked.len == 3 and refused.answers.asked[2] == "? ")

	// A question may name its predicate with a variable, which no schema can type, so that
	// question is searched as it always was.
	open = startSession([], [], ["?p(?a, ?b)"], null, 0, ageTypes)
	h.check("a question with a variable predicate is not refused",
		not holds(open.answers.lines, "refused"))

	// A comparison's name is a shape a rule body checks, not a predicate a fact stores, so
	// typing one as a fact is refused rather than filed away as something the solver proves.
	stored = startSession([], [], ["less-than-or-equal(5, 3)"])
	h.check("a constraint cannot be stored as a fact",
		printed(stored.answers.lines,
			"  refused: less-than-or-equal(5, 3): the predicate is a constraint, checked in a rule body rather than stored or asked") and
			stored.session.facts.len == 0)
	// A comparison asked as a question is refused the same way, before the search: no fact
	// could ever carry it, so the report and its prompts would only be asking for nonsense.
	question = startSession([], [], ["less-than-or-equal(?n, 18)"])
	h.check("a constraint cannot be asked as a question",
		printed(question.answers.lines,
			"  refused: less-than-or-equal(?n, 18): the predicate is a constraint, checked in a rule body rather than stored or asked") and
			question.answers.asked.len == 2 and not holds(question.answers.lines, "no solution"))

	// ── Saving and loading the domain's components ──────────────────────────
	// The commands write what the session holds in the format the loaders read, so these
	// cases write real files under the temp folder and read them back.

	temp = "."
	if env.hasIndex("TEMP") then temp = env["TEMP"]
	if env.hasIndex("TMP") then temp = env["TMP"]
	scratch = function(name)
		"Where a case's file goes: the temp folder, under a name only this suite uses."
		return file.child(temp, "micro-expert-test-" + name)
	end function
	quoted = function(path)
		"A path as a command line holds it: quoted, so a temp folder with a space in it is one word."
		return "'" + path + "'"
	end function
	writeFile = function(path, lines)
		handle = file.open(path, "w")
		if handle isa error then return handle
		for line in lines
			handle.writeLine(line)
		end for
		handle.close
		return null
	end function
	readBack = function(path)
		lines = file.readLines(path)
		if lines isa error then return []
		return lines
	end function

	// A save with no name writes to the file the component came from.
	factsPath = scratch("facts.kb")
	savedFacts = startSession(family + [], [], ["/save-facts"], null, 0, null,
		{"facts": factsPath})
	written = readBack(factsPath)
	file.delete(factsPath)
	h.check("/save-facts writes the facts to their file", written.len == 2 and
		written[0] == "parent-of(bill, tim)" and written[1] == "parent-of(tim, anna)")
	h.check("and says how many it wrote",
		holds(savedFacts.answers.lines, "  wrote 2 facts to " + factsPath))

	// A name given at the prompt is used, with .kb added when it has no extension, and
	// becomes the file the next save writes.
	namedPath = scratch("named")
	named = startSession(family + [], [], ["/save-facts " + quoted(namedPath)], null, 0, null, {})
	namedFile = namedPath + ".kb"
	namedLines = readBack(namedFile)
	file.delete(namedFile)
	h.check("a name with no extension gets .kb", namedLines.len == 2)
	h.check("and becomes the facts file the session saves to",
		named.session.paths.facts == namedFile)

	// Loading replaces what the session holds, and what was loaded is the base /undo can
	// no longer reach past.
	loadedPath = scratch("loaded-facts.kb")
	writeFile(loadedPath, ["has-gender(walter, male)", "parent-of(walter, bill)"])
	loaded = startSession([], [], ["/load-facts " + quoted(loadedPath), "/undo"], null, 0, null, {})
	file.delete(loadedPath)
	h.check("/load-facts replaces the facts with the file's", loaded.session.facts.len == 2 and
		loaded.session.facts[1].text == "parent-of(walter, bill)")
	h.check("the loaded facts are the base /undo cannot reach past",
		printed(loaded.answers.lines, "  nothing to take back"))
	h.check("and it says what it read", holds(loaded.answers.lines, "  loaded 2 facts from "))

	// Rules are written as the data file spells them, with => between head and body.
	uncle = "uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)"
	unclePieces = t.parseRule(uncle)
	rulePath = scratch("rules.kb")
	savedRules = startSession(family + [], [rules.Rule.make(unclePieces.head, unclePieces.body)],
		["/save-rules"], null, 0, null, {"rules": rulePath})
	writtenRule = readBack(rulePath)
	file.delete(rulePath)
	h.check("/save-rules writes the rule as 'head => conditions'", writtenRule.len == 1 and
		writtenRule[0] == "uncle-of(?x, ?y) => parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)")
	h.check("and says how many rules it wrote",
		holds(savedRules.answers.lines, "  wrote 1 rule to "))

	// A loaded rule joins the search, which is the point of keeping the format writeable.
	rulePath = scratch("loaded-rules.kb")
	writeFile(rulePath, ["grandparent(?x, ?y) => parent-of(?x, ?p), parent-of(?p, ?y)"])
	loadedRules = startSession(family + [], [],
		["/load-rules " + quoted(rulePath), "grandparent(bill, ?who)"], null, 0, null, {})
	file.delete(rulePath)
	h.check("/load-rules replaces the rules with the file's", loadedRules.session.rules.len == 1 and
		loadedRules.session.rules[0].text ==
			"grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)")
	h.check("and the loaded rule answers a question",
		printed(loadedRules.answers.lines, "  grandparent(bill, anna)"))

	// The schema is written and read the same way, and a loaded one is used at once.
	schemaPath = scratch("schema.kb")
	savedSchema = startSession([], [], ["/save-schema"], null, 0,
		{"has-age": ["text", "number"]}, {"schema": schemaPath})
	writtenSchema = readBack(schemaPath)
	file.delete(schemaPath)
	h.check("/save-schema writes one predicate per line", writtenSchema.len == 1 and
		writtenSchema[0] == "has-age(text, number)")

	schemaPath = scratch("loaded-schema.kb")
	writeFile(schemaPath, ["has-age(text, number)"])
	loadedSchema = startSession([], [],
		["/load-schema " + quoted(schemaPath), "has-age(tim, twenty)"], null, 0, null, {})
	file.delete(schemaPath)
	h.check("/load-schema replaces the schema", loadedSchema.session.types.hasIndex("has-age") == 1)
	h.check("and the loaded schema refuses a fact that misses it",
		printed(loadedSchema.answers.lines,
			"  refused: has-age(tim, twenty): the object should be a number"))

	// What cannot be saved says why, and the session carries on.
	noSchema = startSession([], [], ["/save-schema"], null, 0, null,
		{"schema": scratch("empty.kb")})
	h.check("a session with no schema has nothing to save",
		printed(noSchema.answers.lines, "  no schema to save"))
	unset = startSession([], [], ["/save-facts"], null, 0, null, {})
	h.check("with no file set and none named, a save says how to name one",
		printed(unset.answers.lines, "  no facts file to use: name one, as /save-facts FILE"))
	missing = startSession([], [], ["/load-facts " + quoted(scratch("absent"))], null, 0, null, {})
	h.check("a missing file is reported and the session carries on",
		holds(missing.answers.lines, "  could not read ") and missing.answers.asked.len == 2)

	// A save builds its file under another name and swaps it in, so a write that fails
	// leaves the file that was already there whole. A folder where the temp file goes is
	// a write that cannot start.
	keptPath = scratch("kept-facts.kb")
	writeFile(keptPath, ["parent-of(bill, tim)"])
	blocked = keptPath + ".tmp"
	made = file.makedir(blocked)
	blockedSave = startSession(family + [], [], ["/save-facts"], null, 0, null, {"facts": keptPath})
	kept = readBack(keptPath)
	stillThere = file.info(blocked).isDirectory
	removed = file.delete(blocked)
	file.delete(keptPath)
	h.check("a failed save says so and leaves the old file whole",
		holds(blockedSave.answers.lines, "  could not write ") and kept.len == 1 and
			kept[0] == "parent-of(bill, tim)")
	h.check("and the folder that stood where the temp file goes is still there", stillThere == 1)

	// The name the old file is moved aside to is cleared for a file an interrupted swap
	// left there, but a folder at that name is nobody's leftover: the save cannot swap its
	// file in, says so, and leaves the folder and the old file where they are.
	oldPath = scratch("kept-old-facts.kb")
	writeFile(oldPath, ["parent-of(bill, tim)"])
	made = file.makedir(oldPath + ".old")
	oldBlocked = startSession(family + [], [], ["/save-facts"], null, 0, null, {"facts": oldPath})
	keptOld = readBack(oldPath)
	oldStillThere = file.info(oldPath + ".old").isDirectory
	removed = file.delete(oldPath + ".old")
	file.delete(oldPath)
	h.check("a folder where the old copy is moved aside to stays, and the save says why",
		holds(oldBlocked.answers.lines, "  could not write ") and oldStillThere == 1 and
			keptOld.len == 1 and keptOld[0] == "parent-of(bill, tim)")

	// A swap that cannot put its temp file in place puts the old one back: the session's
	// file is where it was, and no copy of it is left beside it. A temp file that is not
	// there is a swap that cannot finish.
	restorePath = scratch("restore-facts.kb")
	writeFile(restorePath, ["parent-of(bill, tim)"])
	putBack = library.swapIn(scratch("vanished"), restorePath)
	restored = readBack(restorePath)
	oldLeft = file.exists(restorePath + ".old")
	file.delete(restorePath)
	h.check("a swap that cannot finish puts the old file back", putBack isa error and
		restored.len == 1 and restored[0] == "parent-of(bill, tim)" and oldLeft == 0)

	// A save that works leaves neither the temp file nor the copy of the one it replaced.
	cleanPath = scratch("clean-facts.kb")
	startSession(family + [], [], ["/save-facts"], null, 0, null, {"facts": cleanPath})
	leftovers = file.exists(cleanPath + ".tmp") + file.exists(cleanPath + ".old")
	file.delete(cleanPath)
	h.check("a finished save leaves nothing else behind", leftovers == 0)

	// ── The entry's import order ─────────────────────────────────────────────
	// The library is bound to nothing inside this module: it is read out of the entry's globals
	// when this file loads, so a program that imports this module first hands it null and every
	// call through it fails - which is what the header above says, and why a host imports
	// "repl/repl" before it imports this module. No case can see that short of launching the
	// program, so main.ms's two lines are pinned as text, in order.

	entry = file.readLines(file.child("src", "main.ms"))
	// A string literal holds no escapes here, so the quote an import line ends in is char(34).
	quoteMark = char(34)
	libraryLine = "import " + quoteMark + "repl/repl" + quoteMark
	sessionLine = "import " + quoteMark + "session" + quoteMark
	libraryAt = null
	sessionAt = null
	for i in range(0, entry.len - 1)
		if entry[i].indexOf(libraryLine) == 0 and libraryAt == null then libraryAt = i
		if entry[i].indexOf(sessionLine) == 0 and sessionAt == null then sessionAt = i
	end for
	// Found and in order, so a missing import and a flipped one fail the same check and the name
	// still says what broke: the order.
	ordered = 0
	if libraryAt != null and sessionAt != null then
		if libraryAt < sessionAt then ordered = 1
	end if
	h.check("the main entry imports the repl library before the session module", ordered)
end function
