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

	line = "is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)"
	parsed = t.parseRule(line)
	h.check("a rule line parses", readable(parsed))
	h.check("the head is the triple before the arrow",
		parsed.head.text == "is-grandparent-of(?x, ?y)")
	h.check("the body takes one condition per comma", parsed.body.len == 2)
	h.check("a condition reads back as it was written",
		parsed.body[1].text == "is-parent-of(?p, ?y)")
	h.check("Rule.text gets its own line back",
		rules.Rule.make(parsed.head, parsed.body).text == line)

	constrained = t.parseRule("is-sibling-of(?x, ?y) <- is-parent-of(?p, ?x), not-equal(?x, ?y)")
	h.check("a constraint in a body is read as a constraint",
		readable(constrained) and constrained.body[1].text == "not-equal(?x, ?y)")
	h.check("a line without an arrow is refused", t.parseRule("is-parent-of(?x, susan)") isa error)
	h.check("a rule with no conditions is refused", t.parseRule("is-parent-of(?x, ?y) <- ") isa error)
	h.check("a broken condition refuses the whole line",
		t.parseRule("is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p") isa error)

	// The line data/rules.kb prints for is-in-law-of, so a rule the session shows can be
	// typed back in: or(...) around two and(...) alternatives.
	choice = "is-in-law-of(?x, ?y) <- or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))"
	chosen = t.parseRule(choice)
	h.check("a rule line with or(...) parses", readable(chosen))
	h.check("or(...) is one condition holding two and(...) alternatives",
		readable(chosen) and chosen.body.len == 1 and chosen.body[0].alternatives.len == 2 and
			chosen.body[0].alternatives[0].len == 2)
	h.check("Rule.text gets an or(...) line back",
		readable(chosen) and rules.Rule.make(chosen.head, chosen.body).text == choice)

	// The line data/rules.kb prints for is-only-child-of, so a negation can be typed back in.
	single = "is-only-child-of(?x, ?y) <- is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q))"
	negated = t.parseRule(single)
	h.check("a rule line with not(...) parses", readable(negated) and negated.body.len == 2)
	h.check("not(...) is one condition holding the body it negates",
		readable(negated) and negated.body[1] isa t.Not and negated.body[1].body.len == 1)
	h.check("Rule.text gets a not(...) line back",
		readable(negated) and rules.Rule.make(negated.head, negated.body).text == single)

	// ── A scripted session ───────────────────────────────────────────────────

	// A session over a script of typed lines, recording what it printed and asked.
	startSession = function(facts, ruleList, script, style=null, verbose=0, types=null, paths=null, nlp=0)
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
			"depth": 8, "verbose": verbose, "nlp": nlp, "style": style, "schema": schema, "types": types,
			"paths": paths, "knowledge": knowledge,
			"io": {"read": @reader, "say": @writer}}
		host.run(session)
		return {"session": session, "answers": answers}
	end function

	// The same session with --nlp on. Most checks below read answers as sentences, since that
	// is what the flag is for; the fact form the program shows by default is checked in the
	// --verbose block, where the two forms sit closest together.
	saying = function(facts, ruleList, script, style=null, verbose=0, types=null, paths=null)
		return startSession(facts, ruleList, script, style, verbose, types, paths, 1)
	end function

	family = [spo("bill", "is-parent-of", "tim"), spo("tim", "is-parent-of", "anna")]

	// A question nothing answers, and the one value it asks for.
	asked = saying(family + [], [], ["is-parent-of(?p, susan)", "walter", "quit"])
	lines = asked.answers.lines
	h.check("the session says where the commands are", lines[0].indexOf("/help") != null)
	h.check("a question with no answer says so",
		printed(lines, "  no solution found at depth 8"))
	h.check("the report names the fact still missing",
		printed(lines, "    a fact like is-parent-of(?p, susan)"))
	h.check("the session asks for the variable the report left open",
		asked.answers.asked[1] == "  ?p = ")
	h.check("the value it is given becomes a fact",
		printed(lines, "  added is-parent-of(walter, susan)"))
	h.check("the query's own fact is not repeated above the prompt",
		not printed(lines, "  is-parent-of(?p, susan)"))
	h.check("the fact answers the question on the next pass",
		printed(lines, "  walter is parent of susan"))
	h.check("the fact stays in the session", asked.session.facts.len == 3)

	// A missing fact with two variables is asked about one at a time.
	pair = saying(family + [], [], ["is-aunt-of(?p, ?q)", "doris", "nina", "quit"])
	h.check("a two-variable fact is asked for a variable at a time",
		pair.answers.asked[1] == "  ?p = " and pair.answers.asked[2] == "  ?q = ")
	h.check("both answers make the one fact",
		printed(pair.answers.lines, "  added is-aunt-of(doris, nina)"))
	h.check("the question is answered too",
		printed(pair.answers.lines, "  doris is aunt of nina"))

	// A rule typed at the prompt joins the search.
	ruleLine = "is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)"
	ruled = saying(family + [], [], [ruleLine, "is-grandparent-of(?p, ?y)"])
	h.check("a rule typed at the prompt is added",
		printed(ruled.answers.lines, "  added rule " + ruleLine))
	h.check("the new rule answers the next question",
		printed(ruled.answers.lines, "  bill is grandparent of anna"))

	// A predicate's name has a shape, and the prompt is the other door into the knowledge
	// base: a typed line is refused there in the words the file reader uses, since both read
	// through the solver's one check.
	shouted = startSession(family + [], [], ["Parent-Of(tim, susan)"])
	h.check("a typed line whose predicate is not a name is refused",
		holds(shouted.answers.lines, "a predicate is lower-case letters and digits, joined by '-'"))
	h.check("and nothing is stored from it", shouted.session.facts.len == family.len)

	// A fact typed at the prompt takes the annotations a facts file does, through the reader
	// both doors use, so what the prompt stores is the fact the same line in a file would be.
	annotated = startSession(family + [], [], ["has-gender(zed, male) @ 1990-01-01 ~ 80%"])
	timed = annotated.session.facts[annotated.session.facts.len - 1]
	h.check("a typed fact keeps the moment and confidence it was given",
		timed.at == "1990-01-01" and timed.confidence == 80)
	h.check("and is stored as the call it is, without them",
		printed(annotated.answers.lines, "  added has-gender(zed, male)"))
	// The line a save writes is the file form of the same fact, so /save-facts keeps them.
	savedTimed = knowledge.factsLines(annotated.session.facts)
	h.check("the line /save-facts writes carries them back",
		savedTimed[savedTimed.len - 1] == "has-gender(zed, male) @ 1990-01-01 ~ 80%")
	// A question is a search rather than a stored fact, and the search reads neither
	// annotation, so a line that still holds a variable and carries one is refused: answering
	// it would drop what the line says about when it holds and how sure it is.
	askedTimed = startSession(family + [], [], ["is-parent-of(?p, susan) @ 2019-04-01 ~ 80%"])
	h.check("a typed question that carries an annotation is refused, and says why",
		printed(askedTimed.answers.lines,
			"  refused: is-parent-of(?p, susan) @ 2019-04-01 ~ 80%: a line that is not a stored fact takes no annotation"))
	h.check("and nothing is stored or searched from it",
		askedTimed.session.facts.len == family.len and
			not holds(askedTimed.answers.lines, "no solution found"))
	// A constraint line is the other line that reads rather than stores: it is checked and
	// said true or false, so an annotation on one is as meaningless as on a question, and a
	// value in every field does not make the line a fact.
	checkedTimed = startSession(family + [], [], ["not-equal(tim, susan) @ 2019-04-01"])
	h.check("a typed constraint that carries an annotation is refused, and says why",
		printed(checkedTimed.answers.lines,
			"  refused: not-equal(tim, susan) @ 2019-04-01: a line that is not a stored fact takes no annotation"))
	h.check("and it is neither checked nor stored",
		checkedTimed.session.facts.len == family.len and
			not printed(checkedTimed.answers.lines, "  false") and
			not printed(checkedTimed.answers.lines, "  true"))
	// The bare line still checks, so the refusal is the annotation's alone.
	checkedBare = startSession(family + [], [], ["not-equal(tim, susan)"])
	h.check("a typed constraint without one is still checked",
		printed(checkedBare.answers.lines, "  true"))

	// A rule is a line too, and it is the door most likely to be typed: its head and every
	// condition are asked the same question, and the answer says why rather than falling back
	// to the malformed-line message the rest of a rule gets.
	badHead = startSession(family + [], [], ["Parent-Of(?x, ?y) <- is-parent-of(?x, ?y)"])
	h.check("a typed rule whose predicate is not a name is refused, and says why",
		holds(badHead.answers.lines, "a predicate is lower-case letters and digits, joined by '-'") and
			not holds(badHead.answers.lines, "malformed rule"))
	h.check("and no rule is stored from it", badHead.session.rules.len == 0)

	// A malformed line is refused, quoted, and the session carries on.
	stumbling = startSession(family + [], [],
		["is-parent-of(walter", "is-parent-of(walter, susan)", "is-parent-of(?p, susan)"])
	h.check("a bad line is refused with the line quoted",
		holds(stumbling.answers.lines, "malformed spo") and
			holds(stumbling.answers.lines, "is-parent-of(walter"))
	h.check("the session carries on after it",
		printed(stumbling.answers.lines, "  added is-parent-of(walter, susan)"))

	// ── A rule's own facts are asked for, not the query's shape ────────────

	// The uncle rule is the case where asking the query's own variable would end the
	// session by assertion: ?p is the uncle, so the report needs a parent of Susan and
	// a male sibling of that parent.
	uncleRule = rules.Rule.make(spo(v("x"), "is-uncle-of", v("y")),
		[spo(v("p"), "is-parent-of", v("y")), spo(v("x"), "is-sibling-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	uncle = saying(family + [], [uncleRule],
		["is-uncle-of(?p, susan)", "george", "alfonso", "y"])
	uncleLines = uncle.answers.lines
	uncleAsked = uncle.answers.asked
	h.check("a rule's fact is asked for before the query's own shape",
		uncleAsked[1] == "  ?p' = ")
	h.check("the fact being filled is shown above its question",
		printed(uncleLines, "  is-parent-of(?p', susan)"))
	h.check("that answer is added as a fact",
		printed(uncleLines, "  added is-parent-of(george, susan)"))
	h.check("the sibling condition follows, named against the parent just given",
		printed(uncleLines, "  is-sibling-of(?p, george)") and uncleAsked[2] == "  ?p = ")
	h.check("a fact with no variable left is offered instead of asked about",
		printed(uncleLines, "  has-gender(alfonso, male)") and
			uncleAsked[3] == "  add it? [y/N] ")
	h.check("yes adds it and the rules reach the answer from those facts",
		printed(uncleLines, "  added has-gender(alfonso, male)") and
			uncleLines[uncleLines.len - 1] == "  alfonso is uncle of susan")
	h.check("the query's own fact was never asserted", uncle.session.facts.len == 5)

	// Declining the offer leaves the knowledge base as it was.
	declined = startSession(family + [], [uncleRule],
		["is-uncle-of(?p, susan)", "george", "alfonso", "n"])
	h.check("no leaves the fact out", declined.session.facts.len == 4 and
		not holds(declined.answers.lines, "  added has-gender"))

	// A value given for a variable the rule introduces is progress, even when the rest of
	// that rule's conditions already hold: naming the sibling lets the next pass ask for the
	// one fact really missing, instead of the session giving up because nothing was added.
	apart = family + [spo("bill", "is-sibling-of", "george"), spo("bill", "has-gender", "male")]
	tangled = saying(apart + [], [uncleRule], ["is-uncle-of(bill, ?p)", "george", "zed", "quit"])
	h.check("a rule's fact is asked about for the variables it introduces",
		printed(tangled.answers.lines, "      is-parent-of(?p', ?p)") and
			tangled.answers.asked[1] == "  ?p' = ")
	h.check("naming the introduced variable carries the loop to the fact really missing",
		tangled.answers.asked[2] == "  ?p = " and
			printed(tangled.answers.lines, "  added is-parent-of(george, zed)") and
			tangled.answers.lines[tangled.answers.lines.len - 1] == "  bill is uncle of zed" and
			tangled.session.facts.len == 5)

	// A condition a rule already derives - not a stored fact, but provable from the rules -
	// is treated the same as one already stored: the fill does not offer to add it, and the
	// loop still reaches the one fact that is genuinely missing. Here bill and george are
	// derivably siblings, so only a child for george is missing.
	siblingRule = rules.Rule.make(spo(v("x"), "is-sibling-of", v("y")),
		[spo(v("p"), "is-parent-of", v("x")), spo(v("p"), "is-parent-of", v("y")),
			t.NotEqual.make(v("x"), v("y"))])
	// Two sets of parents keep is-parent-of(?p, ?y) open in the report, so the fill asks for the
	// sibling by name; oliver and clara are derivably siblings through henry, so once the
	// sibling is named the only fact still missing is a child for clara.
	kin = [spo("henry", "is-parent-of", "oliver"), spo("henry", "is-parent-of", "clara"),
		spo("walter", "is-parent-of", "bill"), spo("walter", "is-parent-of", "george"),
		spo("oliver", "has-gender", "male")]
	derivable = saying(kin + [], [siblingRule, uncleRule],
		["is-uncle-of(oliver, ?y)", "clara", "zed", "quit"])
	h.check("a derivable condition is not offered as a fact to add",
		not holds(derivable.answers.asked, "add it?"))
	h.check("and the loop still reaches the fact that is really missing",
		printed(derivable.answers.lines, "  added is-parent-of(clara, zed)") and
			derivable.answers.lines[derivable.answers.lines.len - 1] == "  oliver is uncle of zed")

	// An answer given under one line of a rule's block is carried to the next: ?p' = sam
	// turns the check below it into a fact with nothing left to fill, so it is kept.
	carried = startSession(apart + [], [uncleRule], ["is-uncle-of(bill, ?p)", "sam", "y"])
	h.check("an answer is carried to the next fact of the block",
		carried.answers.asked[1] == "  ?p' = " and
			carried.answers.asked[2] == "  add it? [y/N] " and
			printed(carried.answers.lines, "  added is-sibling-of(bill, sam)") and
			carried.session.facts.len == 5)

	// What was given is remembered for as long as the report stands, so the question that
	// comes round again shows the fact with the value in it and asks only what is left.
	remembered = saying(apart + [], [uncleRule],
		["is-uncle-of(bill, ?p)", "sam", "y", "alfonso"])
	h.check("a value given once is not asked for a second time",
		printed(remembered.answers.lines, "  is-parent-of(sam, ?p)") and
			remembered.answers.asked[3] == "  ?p = " and
			printed(remembered.answers.lines, "  added is-parent-of(sam, alfonso)") and
			remembered.answers.lines[remembered.answers.lines.len - 1] == "  bill is uncle of alfonso")
	// The block above reads the same way, so the report and the question agree.
	h.check("the report block shows the values already given",
		printed(remembered.answers.lines, "      is-parent-of(sam, ?p)"))
	// A fact the session can already prove needs nothing added, so the block stops asking
	// for it - though it lists it while it is still only a check.
	h.check("the report stops listing a fact the session holds",
		not holds(remembered.answers.lines, "      is-sibling-of(bill, sam)") and
			holds(remembered.answers.lines, "      is-sibling-of(bill, ?p')"))

	// ── The query's own shape is the last thing offered ─────────────────────

	// A rule in the knowledge base that cannot conclude this query leaves the query's
	// own shape as the only fact there is to ask about.
	unrelated = rules.Rule.make(spo(v("x"), "is-child-of", v("y")),
		[spo(v("y"), "is-parent-of", v("x"))])
	ownShape = startSession(family + [], [unrelated], ["is-parent-of(?p, susan)", "walter", "quit"])
	h.check("the query's own shape is asked when no rule can conclude it",
		ownShape.answers.asked[1] == "  ?p = " and
			printed(ownShape.answers.lines, "  added is-parent-of(walter, susan)"))

	// A goal with no variable at all is a fact to add, not a question to ask, so the
	// ranking above only ever decides between facts that still have one.
	settled = family + [spo("george", "is-parent-of", "susan")]
	asserted = startSession(settled + [], [uncleRule], ["is-uncle-of(zed, susan)"])
	h.check("a ground line is a fact, even when nothing proves it",
		printed(asserted.answers.lines, "  added is-uncle-of(zed, susan)"))

	// Answering by fiat is deliberate but still there: a whole fact typed where a value is
	// asked for is a fact, with the standing any typed fact has, and the question starts
	// again from it.
	fiat = saying(family + [], [uncleRule], ["is-uncle-of(bill, ?p)", "is-uncle-of(bill, zed)"])
	h.check("a fact typed instead of a value is added, and answers the question",
		printed(fiat.answers.lines, "  added is-uncle-of(bill, zed)") and
			fiat.answers.lines[fiat.answers.lines.len - 1] == "  bill is uncle of zed")

	// A line that parses but still holds a variable is neither a fact to add nor a value
	// to bind, so it is refused and the question is put again.
	refused = startSession(family + [], [],
		["is-parent-of(?p, susan)", "is-parent-of(walter, ?x)", "walter", "quit"])
	h.check("a fact-shaped line with a variable is refused at a value prompt",
		printed(refused.answers.lines,
			"  is-parent-of(walter, ?x) still holds a variable: type a value, or a fact without one") and
			refused.answers.asked.len == 4 and refused.answers.asked[2] == "  ?p = " and
			printed(refused.answers.lines, "  added is-parent-of(walter, susan)"))

	// ── --verbose gives the tree, --nlp says it ──────────────────────────

	// Without --nlp an answer is the fact it is, and the tree above it is the same form.
	verbose = startSession(family + [], [], ["is-parent-of(?p, susan)", "walter", "quit"], null, 1)
	h.check("a plain session says an answer as the fact it is",
		printed(verbose.answers.lines, "  is-parent-of(walter, susan)"))
	h.check("and prints the proof tree first",
		printed(verbose.answers.lines, "  is-parent-of(walter, susan)  <- fact"))
	// The tree is the derivation, so it comes before the result it reaches: the answer is the
	// last line of the block, not the first.
	h.check("with the answer on a line under its tree",
		verbose.answers.lines.indexOf("  is-parent-of(walter, susan)  <- fact") <
			verbose.answers.lines.indexOf("  is-parent-of(walter, susan)"))
	verboseRule = startSession(family + [], [], [ruleLine, "is-grandparent-of(bill, ?y)"], null, 1)
	h.check("a verbose answer names the rule behind it",
		holds(verboseRule.answers.lines, "  <- rule is-grandparent-of(?x, ?y)"))

	// With --nlp the answer is a sentence and so is every line of the tree: the facts keep
	// their dashes opened, and the rule behind them is said the same way, from its head to
	// the conditions it asks for. A constraint has no sentence, so it stays as written.
	saidVerbose = saying(family + [], [], ["is-parent-of(?p, susan)", "walter", "quit"], null, 1)
	h.check("--nlp says the answer in words",
		printed(saidVerbose.answers.lines, "  walter is parent of susan"))
	h.check("and says the tree before it too",
		printed(saidVerbose.answers.lines, "  walter is parent of susan  <- fact"))
	saidRule = saying(family + [], [], [ruleLine, "is-grandparent-of(bill, ?y)"], null, 1)
	h.check("a rule in a said tree reads as its own sentences",
		holds(saidRule.answers.lines,
			"  <- rule ?x is grandparent of ?y <- ?x is parent of ?p, ?p is parent of ?y"))

	// ── Slash commands ──────────────────────────────────────────────────────

	commands = startSession(family + [], [uncleRule],
		["/help", "/facts", "/rules", "/nope", "/exit", "is-parent-of(?p, susan)"])
	commandLines = commands.answers.lines
	h.check("/help lists every command",
		printed(commandLines, "  /exit  leave the session") and
			printed(commandLines, "  /undo  take back the last change") and
			printed(commandLines, "  /retract  take a stored fact out") and
			printed(commandLines, "  /rules  list the rules"))
	h.check("/help lists the save and load commands",
		printed(commandLines, "  /save-facts [FILE]  write the facts to their file, or to one named") and
			printed(commandLines, "  /load-facts [FILE]  replace the facts with a file's") and
			printed(commandLines, "  /save-schema [FILE]  write the schema to its file, or to one named"))

	// The block as the program itself prints it, pinned line for line: the first line is the
	// greeting the session gives before the loop, the fourteen after it are /help. The labels are
	// the library's and the notes are this host's, so this is where the two meet - a change to
	// either shows up here, rather than only in a run someone happens to be watching.
	pinned = startSession([], [], ["/help", "q"])
	h.check("the program's greeting and /help block are exactly these fifteen lines",
		pinned.answers.lines == [
		"Type a fact, a question or a rule as 'head <- conditions', or a value to see how it reads. /help lists the commands; /exit leaves.",
		"  /exit  leave the session",
		"  /help [NAME]  list these commands",
		"  /undo  take back the last change",
		"  /retract  take a stored fact out",
		"  /facts  list the facts",
		"  /rules  list the rules",
		"  /mermaid [FILE]  draw the facts as Mermaid, or write them to a file",
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
		printed(commandLines, "  2 facts") and printed(commandLines, "    is-parent-of(bill, tim)"))
	h.check("/rules lists the rules it holds",
		printed(commandLines, "  1 rule") and
			holds(commandLines, "    is-uncle-of(?x, ?y) <- is-parent-of(?p, ?y)"))

	// ── The facts as a diagram ───────────────────────────────────────────────
	// /mermaid draws what the session holds through src/mermaid.ms, so a fact added at the
	// prompt is in the picture: a text object is an edge, and a value the schema types goes on
	// its subject's label rather than standing in the graph as a node of its own.

	typed = {"is-parent-of": ["text", "text"], "has-gender": ["text", "unique(male|female)"]}
	drew = startSession(family + [spo("tim", "has-gender", "male")], [], ["/mermaid", "q"],
		null, 0, typed)
	plot = drew.answers.lines
	h.check("/mermaid draws a flowchart of the facts it holds", printed(plot, "flowchart TD"))
	h.check("a text object is an edge between two nodes",
		printed(plot, "  bill -->|is parent of| tim"))
	h.check("a value the schema types goes on its subject's label",
		printed(plot, "  tim" + char(91) + char(34) + "Tim<br/>male" + char(34) + char(93)))
	h.check("and does not stand as a node of its own",
		not printed(plot, "  male" + char(91)))
	h.check("an unknown command is refused",
		printed(commandLines, "  no such command: /nope (/help lists them)"))
	h.check("/exit leaves before the next line is read", commands.answers.asked.len == 5)

	// ── Taking a fact back ───────────────────────────────────────────────────

	taken = startSession(family + [], [], ["is-parent-of(walter, susan)", "/undo", "/undo"])
	h.check("/undo takes back the fact just added",
		printed(taken.answers.lines, "  took back is-parent-of(walter, susan)"))
	h.check("the knowledge base loses it again", taken.session.facts.len == 2)
	h.check("/undo with nothing to take back says so",
		printed(taken.answers.lines, "  nothing to take back"))

	// ── Retracting a fact by name ────────────────────────────────────────────
	// /undo reaches only the last change; /retract names the fact to take out, wherever it
	// stands, so a fact learned long ago can go without unwinding everything after it.

	pulled = startSession(family + [], [], ["/retract is-parent-of(tim, anna)", "/facts"], null, 0,
		null, {})
	h.check("/retract takes the named fact out",
		printed(pulled.answers.lines, "  retracted is-parent-of(tim, anna)"))
	h.check("and the session holds only the other one",
		pulled.session.facts.len == 1 and pulled.session.facts[0].text == "is-parent-of(bill, tim)")
	h.check("/retract of a fact it does not hold says so",
		printed(startSession(family + [], [], ["/retract is-parent-of(bill, anna)"]).answers.lines,
			"  no such fact: is-parent-of(bill, anna)"))
	h.check("/retract needs a fact to take out",
		printed(startSession(family + [], [], ["/retract"]).answers.lines,
			"  /retract needs a fact, as /retract has-gender(zed, male)"))
	// A variable would say which facts to look for rather than which one to remove, so the
	// command refuses it instead of choosing one.
	h.check("/retract refuses a pattern",
		printed(startSession(family + [], [], ["/retract is-parent-of(?p, tim)"]).answers.lines,
			"  /retract takes a fact, not a pattern: is-parent-of(?p, tim)"))
	// Taking one out is a change like any other, so /undo puts it back where it stood.
	restored = startSession(family + [], [], ["/retract is-parent-of(bill, tim)", "/undo"])
	h.check("/undo puts a retracted fact back", restored.session.facts.len == 2 and
		restored.session.facts[0].text == "is-parent-of(bill, tim)")
	h.check("and says so", printed(restored.answers.lines, "  put is-parent-of(bill, tim) back"))

	// A fact can be taken out while a question is still asking, the way /undo can be used
	// there: the question is put again from the knowledge base the retraction left.
	midQuestion = startSession(family + [], [],
		["is-parent-of(?p, susan)", "/retract is-parent-of(tim, anna)", "walter"])
	h.check("a fact is retracted from inside a question",
		printed(midQuestion.answers.lines, "  retracted is-parent-of(tim, anna)"))
	h.check("and the question is put again", midQuestion.answers.asked.len == 4 and
		midQuestion.answers.asked[1] == "  ?p = " and midQuestion.answers.asked[2] == "  ?p = ")
	h.check("and the answer it is given completes it", midQuestion.session.facts.len == 2 and
		printed(midQuestion.answers.lines, "  added is-parent-of(walter, susan)"))
	// A name the session does not hold says so at the prompt and leaves the question where it
	// stands, rather than ending it over a typo.
	mistyped = startSession(family + [], [],
		["is-parent-of(?p, susan)", "/retract is-parent-of(bill, anna)", "bob"])
	h.check("a retraction the session cannot make leaves the question asking",
		printed(mistyped.answers.lines, "  no such fact: is-parent-of(bill, anna)") and
			mistyped.answers.asked.len == 4 and mistyped.answers.asked[2] == "  ?p = ")

	// The other prompt a question puts is the 'add it?' offer, and it answers the same two
	// commands - one helper, so a command cannot be honoured at one prompt and not the other.
	forty = t.parseRule("forty(?x, 40) <- has-age(?x, 40)")
	addPrompt = startSession([spo("tim", "has-age", 24)], [rules.Rule.make(forty.head, forty.body)],
		["forty(tim, ?n)", "/retract has-age(tim, 24)", "y"])
	h.check("a fact is retracted from the add-it prompt too",
		printed(addPrompt.answers.lines, "  retracted has-age(tim, 24)"))
	h.check("and the offer is made again from what is left",
		addPrompt.answers.asked.len == 4 and
			addPrompt.answers.asked[1] == "  add it? [y/N] " and
			addPrompt.answers.asked[2] == "  add it? [y/N] " and
			printed(addPrompt.answers.lines, "  added has-age(tim, 40)"))

	// A wrong answer can be taken back while the session is still asking, and the
	// question is put again.
	wrong = startSession(family + [], [],
		["is-parent-of(walter, susan)", "is-aunt-of(?p, susan)", "/undo", "nina"])
	h.check("a wrong fact is taken back from inside a question",
		printed(wrong.answers.lines, "  took back is-parent-of(walter, susan)") and
			wrong.answers.asked[2] == "  ?p = " and wrong.answers.asked[3] == "  ?p = ")
	h.check("the question is asked again and answered",
		printed(wrong.answers.lines, "  added is-aunt-of(nina, susan)") and
			wrong.session.facts.len == 3)

	// ── Painting is the same style table, so it is opt-in the same way ──────

	mark = {"prompt": "<p>", "added": "<a>", "answer": "<n>", "warning": "<w>", "normal": "</>"}
	painted = saying(family + [], [], ["is-parent-of(?p, susan)", "walter", "quit"], mark)
	h.check("a painted prompt opens and closes", painted.answers.asked[0] == "<p>? </>")
	h.check("a painted gap warning closes its line",
		printed(painted.answers.lines, "<w>  no solution found at depth 8</>"))
	h.check("a painted added fact is marked as such",
		printed(painted.answers.lines, "<a>  added is-parent-of(walter, susan)</>"))
	h.check("a painted answer wraps the whole line",
		printed(painted.answers.lines, "<n>  walter is parent of susan</>"))

	// ── Numbers, and the schema a typed fact is held against ─────────────────

	// An age is stored as a number, so a number typed in a question has to meet one:
	// the prompt reads a field with the same term parser the loaders use.
	aged = saying([spo("bill", "has-age", 54)], [], ["has-age(?p, 54)"])
	h.check("a number typed in a question meets the fact it was stored as",
		printed(aged.answers.lines, "  bill has age 54"))

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

	// Quotes promise text, so the digits an age needs have to be bare: the quoted line is
	// refused where a number belongs, in the words the fact would have been written in.
	quote = char(34)
	quotedAge = startSession([spo("bill", "has-age", 54)], [],
		["has-age(?a, " + quote + "27" + quote + ")"], null, 0, ageTypes)
	h.check("a quoted number is refused where a number belongs",
		printed(quotedAge.answers.lines,
			"  refused: has-age(?a, " + quote + "27" + quote + "): the object should be a number") and
			quotedAge.session.facts.len == 1)
	// The same quotes in a `text` field are what quotes are for: an all-digit house number is
	// the text it was written as, and the line it is added as says so.
	houseTypes = {"has-house-number": ["text", "text"]}
	house = startSession([], [], ["has-house-number(way/1, " + quote + "5" + quote + ")"],
		null, 0, houseTypes)
	h.check("a quoted number is added where text belongs, and kept as text",
		printed(house.answers.lines,
			"  added has-house-number(way/1, " + quote + "5" + quote + ")") and
			house.session.facts.len == 1 and house.session.facts[0].object == "5" and
			not (house.session.facts[0].object isa number))

	// The three date types are held at the prompt like any other, so a fact they take is
	// stored and one written to another shape is refused where it is typed.
	datedTypes = {"founded-on": ["text", "date"], "opens-at": ["text", "time"],
		"seen-at": ["text", "datetime"]}
	dated = startSession([], [], ["founded-on(acme, 2019-04-01)", "opens-at(acme, 09:30:00)",
		"seen-at(acme, 2019-04-01 09:30:00)"], null, 0, datedTypes)
	h.check("a date, a time and a datetime typed at the prompt are stored",
		dated.session.facts.len == 3 and
			printed(dated.answers.lines, "  added seen-at(acme, 2019-04-01 09:30:00)"))
	shortTime = startSession([], [], ["opens-at(acme, 09:30)"], null, 0, datedTypes)
	h.check("a time short of its seconds is refused at the prompt",
		printed(shortTime.answers.lines,
			"  refused: opens-at(acme, 09:30): the object should be a time") and
			shortTime.session.facts.len == 0)

	// ── A boolean or a list of values is chosen, not typed ──────────────────
	// The schema's type names the set, so the prompt lists it numbered and takes the
	// number beside the value itself. Text and numbers keep the prompt they always had.

	genderTypes = {"has-gender": ["text", "male|female"]}
	chosen = saying([], [], ["has-gender(zed, ?g)", "2"], null, 0, genderTypes)
	chosenLines = chosen.answers.lines
	h.check("an enum field is shown as a numbered list",
		printed(chosenLines, "  1) male") and printed(chosenLines, "  2) female"))
	h.check("typing a number picks that value",
		printed(chosenLines, "  added has-gender(zed, female)") and
			chosen.session.facts[0].text == "has-gender(zed, female)")
	h.check("and the chosen value answers the question",
		chosenLines[chosenLines.len - 1] == "  zed has gender female")

	// The value itself is still accepted, so the list is a shortcut rather than a gate.
	spoken = startSession([], [], ["has-gender(zed, ?g)", "female"], null, 0, genderTypes)
	h.check("the value itself can still be typed",
		printed(spoken.answers.lines, "  added has-gender(zed, female)"))

	// A word outside the list is refused at the prompt and asked for again, rather than
	// completing a fact the schema would refuse and ending the question with it.
	typo = startSession([], [], ["has-gender(zed, ?g)", "boy", "1"], null, 0, genderTypes)
	h.check("a value outside the list is refused where it is typed",
		printed(typo.answers.lines, "  boy is not one of: male, female"))
	h.check("and the question is put again until one of them is given",
		typo.answers.asked.len == 4 and typo.answers.asked[2] == "  ?g = " and
			printed(typo.answers.lines, "  added has-gender(zed, male)"))

	// A boolean is the same set of two words, in the order the schema names them.
	booleanTypes = {"is-adult": ["text", "boolean"]}
	boolean = startSession([], [], ["is-adult(tim, ?a)", "true"], null, 0, booleanTypes)
	h.check("a boolean field is offered true and false",
		printed(boolean.answers.lines, "  1) true") and
			printed(boolean.answers.lines, "  2) false"))
	h.check("typing the word picks it",
		printed(boolean.answers.lines, "  added is-adult(tim, true)"))

	// A text field is chosen from nothing, so it keeps the plain prompt.
	free = startSession([], [], ["is-parent-of(bill, ?c)", "tim"], null, 0,
		{"is-parent-of": ["text", "text"]})
	h.check("a text field is asked for without a list",
		not holds(free.answers.lines, "1) ") and
			printed(free.answers.lines, "  added is-parent-of(bill, tim)"))

	// A number field takes the digits typed at it as the number they spell, so the fact the
	// value completes is one the schema accepts, rather than "24" text it would refuse.
	numeric = startSession([], [], ["has-age(zed, ?n)", "24"], null, 0, ageTypes)
	h.check("a number field takes the digits as a number",
		printed(numeric.answers.lines, "  added has-age(zed, 24)") and
			numeric.session.facts[0].object isa number and
			numeric.session.facts[0].object == 24)

	// ── unique(...): one value per subject ──────────────────────────────────
	// The schema's one statement about how many values a pair takes, and the one check a
	// single term cannot answer: 17 fits an age and is still a second one for zed.

	uniqueAge = {"has-age": ["text", "unique(number)"]}
	again = startSession([spo("zed", "has-age", 24)], [], ["has-age(zed, 17)"], null, 0, uniqueAge)
	h.check("a second value takes the first one's place",
		printed(again.answers.lines, "  replaced has-age(zed, 24) with has-age(zed, 17)"))
	h.check("and the field still holds one value",
		again.session.facts.len == 1 and again.session.facts[0].text == "has-age(zed, 17)")
	// The place matters, because search tries facts in the order they are held: the corrected
	// fact stands where the one it replaced stood rather than moving to the end.
	ordered = startSession([spo("zed", "has-age", 24), spo("ann", "has-age", 30)], [],
		["has-age(zed, 40)"], null, 0, uniqueAge)
	h.check("a replacement stands where the fact it replaced stood",
		ordered.session.facts[0].text == "has-age(zed, 40)" and
			ordered.session.facts[1].text == "has-age(ann, 30)")
	// A replacement is a change like any other, so it can be taken back.
	corrected = startSession([spo("zed", "has-age", 24)], [], ["has-age(zed, 17)", "/undo"],
		null, 0, uniqueAge)
	h.check("/undo takes a replacement back",
		corrected.session.facts[0].text == "has-age(zed, 24)")
	h.check("and says what it put back",
		printed(corrected.answers.lines,
			"  took back has-age(zed, 17), putting has-age(zed, 24) back"))
	// The same value again is the fact already held, which the session says in its own
	// words, so the pair is never reported as a second one when it is the first one twice.
	same = startSession([spo("zed", "has-age", 24)], [], ["has-age(zed, 24)"], null, 0, uniqueAge)
	h.check("the same value again is already known, not a second one",
		printed(same.answers.lines, "  already known: has-age(zed, 24)") and
			same.session.facts.len == 1)
	other = startSession([spo("zed", "has-age", 24)], [], ["has-age(tim, 17)"], null, 0, uniqueAge)
	h.check("another subject is another pair", other.session.facts.len == 2)

	// A value given at the prompt is set the same way one typed at the prompt is: a unique(...)
	// field's value is corrected rather than duplicated. Nobody has 30, so the question is open
	// on who does, and the person named for it already has an age of their own - which the
	// answer takes the place of, and the question is then answered by the fact it left.
	clash = saying([spo("zed", "has-age", 24)], [], ["has-age(?x, 30)", "zed"], null, 0, uniqueAge)
	h.check("a prompted value takes the field's old value out",
		printed(clash.answers.lines, "  replaced has-age(zed, 24) with has-age(zed, 30)"))
	h.check("and the question is answered by the fact it left",
		clash.answers.lines[clash.answers.lines.len - 1] == "  zed has age 30" and
			clash.session.facts.len == 1 and clash.session.facts[0].object == 30)

	// The wrapper says how many, not what, so a wrapped list is still the list the prompt
	// offers: unique(...) does not turn a choice back into a word to remember.
	wrapped = startSession([], [], ["has-gender(zed, ?g)", "2"], null, 0,
		{"has-gender": ["text", "unique(male|female)"]})
	h.check("a wrapped list is still offered as a list",
		printed(wrapped.answers.lines, "  1) male") and
			printed(wrapped.answers.lines, "  2) female"))
	h.check("and the choice is stored", wrapped.session.facts[0].text == "has-gender(zed, female)")

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

	// A constraint's name is a shape a rule body checks, not a predicate a fact stores, so a line
	// with a value in every field is checked at the prompt and said true or false - and said in
	// the words a fact uses, since the schema knows true and false and not MiniScript's 1 and 0.
	checks = startSession([], [], ["less-than-or-equal(5, 3)", "less-than-or-equal(3, 5)",
		"not-equal(tim, bob)", "equal(24, 24)"])
	h.check("a ground constraint that does not hold says false",
		checks.answers.lines[1] == "  false")
	h.check("a ground constraint that holds says true", checks.answers.lines[2] == "  true")
	h.check("not-equal compares the two values", checks.answers.lines[3] == "  true")
	h.check("equal says the two are the same one", checks.answers.lines[4] == "  true")
	h.check("a check stores nothing", checks.session.facts.len == 0)
	// A comparison asked as a question is still refused before the search: no fact could ever
	// carry it, so the report and its prompts would only be asking for nonsense.
	openCheck = startSession([], [], ["less-than-or-equal(?n, 18)"])
	h.check("a constraint that still holds a variable is refused",
		printed(openCheck.answers.lines,
			"  refused: less-than-or-equal(?n, 18): the predicate is a constraint, checked in a rule body rather than stored or asked") and
			openCheck.answers.asked.len == 2 and not holds(openCheck.answers.lines, "no solution"))

	// years-since keeps the meaning the wiki gives it: its first field is a date and its second
	// is the whole years since it, so with both fields ground the prompt checks the count the way
	// a body does. The day is pinned, so the answer cannot change with the host's clock, and a
	// date the calendar does not have has no years at all, which a body reads as a failed check.
	savedToday = t.today
	t.today = {"year": 2026, "month": 11, "day": 21}
	since = startSession([], [], ["years-since(1948-03-14, 78)", "years-since(1948-03-14, 79)",
		"years-since(2019-02-30, 7)"])
	h.check("a ground years-since checks the years it counts",
		since.answers.lines[1] == "  true" and since.answers.lines[2] == "  false")
	h.check("a date the calendar does not have is a check that fails",
		since.answers.lines[3] == "  false")
	h.check("and a check stores nothing", since.session.facts.len == 0)
	sinceQuestion = startSession([], [], ["years-since(2019-04-01, ?n)"])
	h.check("a years-since that still holds a variable is refused",
		printed(sinceQuestion.answers.lines,
			"  refused: years-since(2019-04-01, ?n): the predicate is a constraint, checked in a rule body rather than stored or asked") and
			sinceQuestion.answers.asked.len == 2 and not holds(sinceQuestion.answers.lines, "no solution"))
	t.today = savedToday

	// ── A value typed on its own ─────────────────────────────────────────────
	// A line with no call and no pipe in it is one term, said back the way a fact would write
	// it, so the prompt is where a value's reading is checked before it goes into a fact.

	dq = char(34)
	inQuotes = function(text)
		return dq + text + dq
	end function
	echoed = startSession([], [], ["oliver", inQuotes("Dallas, TX"), "1e3", "?x"])
	h.check("a bare term is said back", echoed.answers.lines[1] == "  oliver")
	h.check("a quoted value is said back in the quotes it needs",
		echoed.answers.lines[2] == "  " + inQuotes("Dallas, TX"))
	h.check("a number is said back as the number it was read as",
		echoed.answers.lines[3] == "  1000")
	h.check("a variable is said back as a variable", echoed.answers.lines[4] == "  ?x")
	h.check("a value line stores nothing", echoed.session.facts.len == 0)
	// A line in brackets is a span rather than a value: it is read into a TimeSpan and said back
	// with the type it came back as, since a span keeps no text of its own to echo.
	spanned = startSession([], [], ["[2026-01-01, 2026-11-01]"])
	h.check("a bracketed line is read as a span",
		spanned.answers.lines[1] == "  TimeSpan 304d 00:00:00 [2026-01-01, 2026-11-01]")
	h.check("and a span line stores nothing", spanned.session.facts.len == 0)
	// A line that reads as a date, a time or a datetime is read before it is taken as text: the
	// reader is tried first, so the short shapes come back in the one full shape, and only a line
	// the reader refuses is said back as the text that was typed.
	moments = startSession([], [], ["2019-4-1 9:30", "2019-04-01", "09:30", "2026-13-01"])
	h.check("a short datetime is said back in its full shape",
		moments.answers.lines[1] == "  DateTime 2019-04-01 09:30:00")
	h.check("a date line is read as a DateTime",
		moments.answers.lines[2] == "  DateTime 2019-04-01")
	h.check("a clock on its own is read as a time",
		moments.answers.lines[3] == "  DateTime 09:30:00")
	h.check("a date the calendar does not have is still text",
		moments.answers.lines[4] == "  2026-13-01")
	h.check("and a DateTime line stores nothing", moments.session.facts.len == 0)
	// A line that is nearly a value is still read as a line, so a broken call keeps its message
	// rather than being echoed as text.
	stillBroken = startSession([], [], ["is-parent-of(bill"])
	h.check("a line with a call in it is still a fact or a question",
		holds(stillBroken.answers.lines, "malformed spo"))

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

	// /mermaid with a name writes the diagram and the picture drawn from it, and prints neither:
	// a name with no extension gets .mmd, and the picture takes the same name with .svg.
	place = scratch("mermaid")
	diagramFile = place + ".mmd"
	pictureFile = place + ".svg"
	drawnTo = startSession(family + [], [], ["/mermaid " + quoted(place)], null, 0, typed)
	diagramText = readBack(diagramFile)
	pictureText = readBack(pictureFile)
	file.delete(diagramFile)
	file.delete(pictureFile)
	h.check("/mermaid writes the diagram to the file it is given",
		diagramText.len > 0 and diagramText[0] == "flowchart TD")
	h.check("and the picture from the same diagram beside it",
		pictureText.len > 0 and pictureText[0][:4] == "<svg")
	h.check("saying what it wrote and drew",
		holds(drawnTo.answers.lines, "  wrote " + diagramText.len + " lines to " + diagramFile) and
			holds(drawnTo.answers.lines, "  drew " + pictureFile))
	h.check("and printing no diagram when it writes a file",
		not printed(drawnTo.answers.lines, "flowchart TD"))

	// A save with no name writes to the file the component came from.
	factsPath = scratch("facts.kb")
	savedFacts = startSession(family + [], [], ["/save-facts"], null, 0, null,
		{"facts": factsPath})
	written = readBack(factsPath)
	file.delete(factsPath)
	h.check("/save-facts writes the facts to their file", written.len == 2 and
		written[0] == "is-parent-of(bill, tim)" and written[1] == "is-parent-of(tim, anna)")
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
	writeFile(loadedPath, ["has-gender(walter, male)", "is-parent-of(walter, bill)"])
	loaded = startSession([], [], ["/load-facts " + quoted(loadedPath), "/undo"], null, 0, null, {})
	file.delete(loadedPath)
	h.check("/load-facts replaces the facts with the file's", loaded.session.facts.len == 2 and
		loaded.session.facts[1].text == "is-parent-of(walter, bill)")
	h.check("the loaded facts are the base /undo cannot reach past",
		printed(loaded.answers.lines, "  nothing to take back"))
	h.check("and it says what it read", holds(loaded.answers.lines, "  loaded 2 facts from "))

	// Rules are written as the data file spells them, with => between head and body.
	uncle = "is-uncle-of(?x, ?y) <- is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)"
	unclePieces = t.parseRule(uncle)
	rulePath = scratch("rules.kb")
	savedRules = startSession(family + [], [rules.Rule.make(unclePieces.head, unclePieces.body)],
		["/save-rules"], null, 0, null, {"rules": rulePath})
	writtenRule = readBack(rulePath)
	file.delete(rulePath)
	h.check("/save-rules writes the rule as 'head => conditions'", writtenRule.len == 1 and
		writtenRule[0] == "is-uncle-of(?x, ?y) => is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)")
	h.check("and says how many rules it wrote",
		holds(savedRules.answers.lines, "  wrote 1 rule to "))

	// A loaded rule joins the search, which is the point of keeping the format writeable.
	rulePath = scratch("loaded-rules.kb")
	writeFile(rulePath, ["is-grandparent-of(?x, ?y) => is-parent-of(?x, ?p), is-parent-of(?p, ?y)"])
	loadedRules = saying(family + [], [],
		["/load-rules " + quoted(rulePath), "is-grandparent-of(bill, ?who)"], null, 0, null, {})
	file.delete(rulePath)
	h.check("/load-rules replaces the rules with the file's", loadedRules.session.rules.len == 1 and
		loadedRules.session.rules[0].text ==
			"is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)")
	h.check("and the loaded rule answers a question",
		printed(loadedRules.answers.lines, "  bill is grandparent of anna"))

	// A rule whose head the schema marks unique(...) has nowhere to refuse a second value,
	// since a fact a rule concludes is never added, so loading one is refused the way startup
	// refuses the schema that marks it: the session keeps the rules it had.
	uniqueHead = {"belongs-to-age-group": ["text", "unique(child|adult)"]}
	rulePath = scratch("unique-rules.kb")
	writeFile(rulePath, ["belongs-to-age-group(?x, child) => has-age(?x, ?n), less-than-or-equal(?n, 18)"])
	refusedRules = startSession(family + [], [], ["/load-rules " + quoted(rulePath)],
		null, 0, uniqueHead, {})
	file.delete(rulePath)
	h.check("/load-rules refuses a rule whose head the schema marks unique(...)",
		holds(refusedRules.answers.lines, "concluded by a rule"))
	h.check("and the session keeps the rules it had", refusedRules.session.rules.len == 0)

	// The same line typed at the prompt is the same hole, so it is refused there too rather
	// than added to a schema that has no place to enforce it.
	typedRule = startSession([], [],
		["belongs-to-age-group(?x, child) <- has-age(?x, ?n), less-than-or-equal(?n, 18)"], null, 0, uniqueHead)
	h.check("a typed rule whose head the schema marks unique(...) is refused",
		holds(typedRule.answers.lines, "concluded by a rule") and typedRule.session.rules.len == 0)

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

	// A schema that marks a predicate the session's rules conclude unique(...) cannot be
	// enforced, since a derived fact is never added, so loading one is refused the way
	// startup refuses it: the session keeps the types it had rather than holding a line it
	// has nowhere to check.
	derivedPath = scratch("derived-schema.kb")
	writeFile(derivedPath, ["belongs-to-age-group(text, unique(child|adult))"])
	older = t.parseRule("belongs-to-age-group(?x, child) <- has-age(?x, ?n), less-than-or-equal(?n, 18)")
	refusedSchema = startSession([], [rules.Rule.make(older.head, older.body)],
		["/load-schema " + quoted(derivedPath)], null, 0, {"has-age": ["text", "number"]}, {})
	file.delete(derivedPath)
	h.check("/load-schema refuses a unique(...) a rule leaves no place to enforce",
		holds(refusedSchema.answers.lines, "concluded by a rule"))
	h.check("and the session keeps the schema it had",
		refusedSchema.session.types.hasIndex("belongs-to-age-group") == 0 and
			refusedSchema.session.types.hasIndex("has-age") == 1)

	// A schema says what the facts already held have to be, so a pair it marks unique(...)
	// that the session already fills twice is refused rather than loaded into a knowledge
	// base that breaks it - the file cannot know what is held, which is why this is the
	// session's check and not the reader's.
	twicePath = scratch("twice-schema.kb")
	writeFile(twicePath, ["has-gender(text, unique(male|female))"])
	twice = startSession([spo("zed", "has-gender", "male"), spo("zed", "has-gender", "female")],
		[], ["/load-schema " + quoted(twicePath)], null, 0, {"has-gender": ["text", "male|female"]}, {})
	file.delete(twicePath)
	h.check("/load-schema refuses a schema the facts already break",
		holds(twice.answers.lines, "already taken"))
	h.check("and the session keeps the schema it had",
		twice.session.types["has-gender"][1] == "male|female")

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
	writeFile(keptPath, ["is-parent-of(bill, tim)"])
	blocked = keptPath + ".tmp"
	made = file.makedir(blocked)
	blockedSave = startSession(family + [], [], ["/save-facts"], null, 0, null, {"facts": keptPath})
	kept = readBack(keptPath)
	stillThere = file.info(blocked).isDirectory
	removed = file.delete(blocked)
	file.delete(keptPath)
	h.check("a failed save says so and leaves the old file whole",
		holds(blockedSave.answers.lines, "  could not write ") and kept.len == 1 and
			kept[0] == "is-parent-of(bill, tim)")
	h.check("and the folder that stood where the temp file goes is still there", stillThere == 1)

	// The name the old file is moved aside to is cleared for a file an interrupted swap
	// left there, but a folder at that name is nobody's leftover: the save cannot swap its
	// file in, says so, and leaves the folder and the old file where they are.
	oldPath = scratch("kept-old-facts.kb")
	writeFile(oldPath, ["is-parent-of(bill, tim)"])
	made = file.makedir(oldPath + ".old")
	oldBlocked = startSession(family + [], [], ["/save-facts"], null, 0, null, {"facts": oldPath})
	keptOld = readBack(oldPath)
	oldStillThere = file.info(oldPath + ".old").isDirectory
	removed = file.delete(oldPath + ".old")
	file.delete(oldPath)
	h.check("a folder where the old copy is moved aside to stays, and the save says why",
		holds(oldBlocked.answers.lines, "  could not write ") and oldStillThere == 1 and
			keptOld.len == 1 and keptOld[0] == "is-parent-of(bill, tim)")

	// A swap that cannot put its temp file in place puts the old one back: the session's
	// file is where it was, and no copy of it is left beside it. A temp file that is not
	// there is a swap that cannot finish.
	restorePath = scratch("restore-facts.kb")
	writeFile(restorePath, ["is-parent-of(bill, tim)"])
	putBack = library.swapIn(scratch("vanished"), restorePath)
	restored = readBack(restorePath)
	oldLeft = file.exists(restorePath + ".old")
	file.delete(restorePath)
	h.check("a swap that cannot finish puts the old file back", putBack isa error and
		restored.len == 1 and restored[0] == "is-parent-of(bill, tim)" and oldLeft == 0)

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
