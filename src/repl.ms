// repl.ms — a prompt that takes facts and rules, and asks for what is missing.
//
// The session starts from the arrays main.ms already builds and adds to them in
// memory, so a fact or a rule typed at the prompt is searchable straight away, and
// nothing is written back to source unless a /save-* command asks:
//
//   import "repl"
//   repl.run(session)
//
// Like facts.ms and rules.ms, this module is handed the host's copies of triples.ms
// and rule.ms rather than importing them, for the same reason: a module that imports
// triples.ms gets its own copy of its classes, and the solver only agrees with itself.
//
// A session is one record, so the functions below can hand each other what they share
// without a seven-argument list:
//
//   session = {"triples": triples, "Rule": Rule, "facts": facts, "rules": rules,
//       "depth": 8, "verbose": 0, "style": style, "schema": schema, "types": types,
//       "paths": paths, "knowledge": knowledge, "prompt": prompt,
//       "io": {"read": reader, "say": writer}}
//
// schema is schema.ms, the module that knows the field-type format, and types is what it
// loaded from data/schema.kb - or null for a session that checks nothing. A fact typed
// at the prompt is held against the types before it is stored. Like triples and Rule,
// the module is handed in rather than imported: a bare import resolves against the
// entry script's folder, so this file would find a same-named module of the suite's
// (or a host's) instead of the one beside it.
//
// paths is where each of the three data files came from, and knowledge.ms is the parser
// and writer for their format: it reads and writes the files, and names a file typed at
// the prompt (adding the .kb a bare name leaves off). So /save-* and /load-* work on the
// domain the run started with, or on a file named there.
//
// io is how a session talks, and the reason its checks need no terminal: read takes
// the prompt and returns a line (null ends the session), say takes a finished line.
//
// A line starting with / is a command for the session itself (see commandList); any
// other line is knowledge or a question, and the report already draws the difference:
// a line with <- is a rule, a line with a variable in it is a question, and a ground
// line is a fact.
//
// prompt is prompt.ms, the part of the prompt that knows nothing about the domain: it keeps
// a data file whole across a save, and says how many of something a session holds. It is
// handed in like triples and Rule, and the rest of the prompt - the loop, the talk with the
// reader, the slash commands - is still here until it moves.
//
// Nothing here knows what a color is either: paint comes from triples.ms, and the one
// style map main.ms builds carries the report's roles and the session's alike, so a
// single NO_COLOR leaves the whole run plain.

say = function(session, role, text)
	"Prints one line in a role's color through the session's output."
	session.io.say(session.triples.paint(session.style, role, text))
end function

ask = function(session, question)
	"Shows a prompt and reads what is typed after it."
	return session.io.read(session.triples.paint(session.style, "prompt", question))
end function

// What askValue answers when the user changes the knowledge base rather than giving a
// value - taking a fact back, or asserting one. A map, so a typed value can never be
// mistaken for it, and both mean the same thing to the fill: start the round again.
changedMark = {"changed": 1}

// ── Slash commands ───────────────────────────────────────────────────────────
// One line that starts with / is aimed at the session rather than the knowledge
// base. runCommand dispatches by name and commandList is what /help shows, in the
// same order.

commandList = [
	{"name": "/exit", "note": "leave the session"},
	{"name": "/help", "note": "list these commands"},
	{"name": "/undo", "note": "take back the last fact added"},
	{"name": "/facts", "note": "list the facts"},
	{"name": "/rules", "note": "list the rules"},
	{"name": "/save-facts", "note": "write the facts to their file, or to one named"},
	{"name": "/load-facts", "note": "replace the facts with a file's"},
	{"name": "/save-rules", "note": "write the rules to their file, or to one named"},
	{"name": "/load-rules", "note": "replace the rules with a file's"},
	{"name": "/save-schema", "note": "write the schema to its file, or to one named"},
	{"name": "/load-schema", "note": "replace the schema with a file's"},
]

runCommand = function(session, line)
	"Runs one slash command, answering whether the session should end."
	name = line.split(" ")[0].lower
	argument = session.triples.trimSpace(line[name.len:])
	if name == "/exit" then return true
	if name == "/help" then
		for command in commandList
			say(session, "note", "  " + command.name + "  " + command.note)
		end for
		return false
	end if
	if name == "/undo" then
		undo(session)
		return false
	end if
	if name == "/facts" then
		listFacts(session)
		return false
	end if
	if name == "/rules" then
		listRules(session)
		return false
	end if
	for part in ["facts", "rules", "schema"]
		if name == "/save-" + part then
			savePart(session, part, argument)
			return false
		end if
		if name == "/load-" + part then
			loadPart(session, part, argument)
			return false
		end if
	end for
	say(session, "warning", "  no such command: " + name + " (/help lists them)")
	return false
end function

undo = function(session)
	"Takes back the last fact the session added; says so, or that there is none."
	if session.facts.len <= session.baseFacts then
		say(session, "warning", "  nothing to take back")
		return false
	end if
	removed = session.facts.pop
	say(session, "added", "  took back " + removed.text)
	return true
end function

listFacts = function(session)
	"Prints every fact the session holds, in the order search tries them."
	say(session, "note", "  " + session.prompt.countText(session.facts.len, "fact"))
	for known in session.facts
		session.io.say("    " + session.triples.paint(session.style, "fact", known.text))
	end for
end function

listRules = function(session)
	"Prints every rule the session holds, in the order search tries them."
	say(session, "note", "  " + session.prompt.countText(session.rules.len, "rule"))
	for candidate in session.rules
		session.io.say("    " + session.triples.paint(session.style, "rule", candidate.text))
	end for
end function

// ── Saving and loading a component ───────────────────────────────────────────
// The session holds the domain it started with in memory; these commands write one
// component back to the file it came from, or to a file named, and read one back in its
// place. A name without an extension gets .kb, so /save-facts family writes family.kb.

countOf = function(session, part)
	"How many items of this component the session holds."
	if part == "facts" then return session.facts.len
	if part == "rules" then return session.rules.len
	return session.types.len
end function

countName = function(session, part, count)
	"Names what this component holds, in the plural the count needs."
	if part == "facts" then return session.prompt.countText(count, "fact")
	if part == "rules" then return session.prompt.countText(count, "rule")
	return session.prompt.countText(count, "predicate")
end function

componentLines = function(session, part)
	"One data-file line per item the session holds of this component."
	if part == "facts" then return session.knowledge.factsLines(session.facts)
	if part == "rules" then return session.knowledge.rulesLines(session.rules)
	return session.knowledge.schemaLines(session.types)
end function

targetPath = function(session, part, argument, command)
	"Where a save or load goes: the file named, or the one this component came from."
	if argument != "" then return session.knowledge.withExtension(argument)
	path = null
	if session.paths.hasIndex(part) then path = session.paths[part]
	if path == null or path == "" then
		say(session, "warning", "  no " + part + " file to use: name one, as " + command + " FILE")
		return null
	end if
	return path
end function

readComponent = function(session, part, path)
	"Parses one data file into the shape the session holds that component in."
	if part == "facts" then return session.knowledge.loadFactsAt(session.triples, path)
	if part == "rules" then
		pieces = session.knowledge.loadRulesAt(session.triples, path)
		if pieces isa error then return pieces
		loaded = []
		for piece in pieces
			loaded.push(session.Rule.make(piece.head, piece.body))
		end for
		return loaded
	end if
	return session.knowledge.loadSchemaAt(path)
end function

savePart = function(session, part, argument)
	"Writes one component to its file, or to the file named."
	if part == "schema" and session.types == null then
		say(session, "warning", "  no schema to save")
		return
	end if
	path = targetPath(session, part, argument, "/save-" + part)
	if path == null then return
	path = session.knowledge.resolvePath(path)
	problem = session.prompt.writeLines(path, componentLines(session, part))
	if problem isa error then
		say(session, "warning", "  could not write " + path + ": " + problem.message)
		return
	end if
	session.paths[part] = path
	say(session, "added", "  wrote " + countName(session, part, countOf(session, part)) + " to " + path)
end function

loadPart = function(session, part, argument)
	"Replaces one component with the contents of its file, or of the file named."
	path = targetPath(session, part, argument, "/load-" + part)
	if path == null then return
	path = session.knowledge.resolvePath(path)
	loaded = readComponent(session, part, path)
	if loaded isa error then
		say(session, "warning", "  could not read " + path + ": " + loaded.message)
		return
	end if
	if part == "facts" then
		session.facts = loaded
		// What was loaded is the knowledge base now, so /undo no longer reaches back
		// past it.
		session.baseFacts = session.facts.len
	else if part == "rules" then
		session.rules = loaded
	else
		session.types = loaded
	end if
	session.paths[part] = path
	say(session, "added", "  loaded " + countName(session, part, countOf(session, part)) + " from " + path)
end function

// ── The session loop ─────────────────────────────────────────────────────────

run = function(session)
	"Reads lines until the user leaves, adding facts and rules and answering questions."
	// Only what the session adds can be taken back, never the knowledge base it
	// started from.
	session.baseFacts = session.facts.len
	say(session, "note",
		"Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.")
	while true
		line = ask(session, "? ")
		if line == null then break
		line = session.triples.trimSpace(line)
		if line == "" then continue
		if line == "q" or line == "quit" then break
		if line[0] == "/" then
			if runCommand(session, line) then break
			continue
		end if
		handleLine(session, line)
	end while
end function

handleLine = function(session, line)
	"Does what one line asks: adds a fact, asks a question, or adds a rule."
	if line.indexOf("<-") != null then
		addRule(session, line)
		return
	end if
	triple = session.triples.SpoTriple.parse(line)
	if triple isa error then
		say(session, "warning", "  " + triple.message)
		return
	end if
	// A constraint's name is a shape, not a predicate: a line that names one is refused
	// before it is searched, and addFact refuses one before it is stored.
	if refuseConstraint(session, triple) then return
	if session.triples.hasUnknowns(triple) then
		// A question is held against the schema too, so a field already given as a value
		// that could never be stored is refused before the search starts, rather than
		// after the reader has filled in the question's own variable for nothing.
		if not fitsSchema(session, triple) then return
		askGoal(session, triple)
	else
		addFact(session, triple)
	end if
end function

addFact = function(session, triple)
	"Adds a fact to the session's knowledge base, and says which one; nothing is added twice."
	if refuseConstraint(session, triple) then return false
	if not fitsSchema(session, triple) then return false
	if alreadyKnown(session, triple) then
		say(session, "note", "  already known: " + triple.text)
		return false
	end if
	session.facts.push(triple)
	say(session, "added", "  added " + triple.text)
	return true
end function

refuseConstraint = function(session, triple)
	"Says a constraint's name is not a predicate a line stores or asks about, and whether it was one."
	if not session.triples.isConstraint(triple.predicate) then return false
	say(session, "warning", "  refused: " + triple.text +
		": the predicate is a constraint, checked in a rule body rather than stored or asked")
	return true
end function

fitsSchema = function(session, triple)
	"Says whether a typed fact or question matches the schema, saying what it misses when it does not."
	if not session.hasIndex("types") then return true
	if session.types == null then return true
	problem = session.schema.misfit(session.types, triple)
	if problem == null then return true
	say(session, "warning", "  refused: " + triple.text + ": " + problem)
	return false
end function

alreadyKnown = function(session, triple)
	"Says whether the session already holds this fact."
	for known in session.facts
		if known.text == triple.text then return true
	end for
	return false
end function

addRule = function(session, line)
	"Adds the rule a line spells out, or says why the line is not one."
	pieces = session.triples.parseRule(line)
	if pieces isa error then
		say(session, "warning", "  " + pieces.message)
		return
	end if
	added = session.Rule.make(pieces.head, pieces.body)
	session.rules.push(added)
	say(session, "added", "  added rule " + added.text)
end function

askGoal = function(session, goal)
	"Answers a question, asking for the variables that would complete a missing fact."
	printed = null
	shape = null
	// What has been given for this question already, by the label the report shows each
	// variable under: the question comes round again, and nothing is asked for twice.
	given = {}
	while true
		proofs = session.triples.proveGoals(goal, session.facts, session.rules, session.depth)
		if proofs.len > 0 then
			showProofs(session, goal, proofs)
			return
		end if
		// One walk over the goal feeds both the report and the question, so the variables
		// asked about are the ones the report showed - with the values given so far in
		// them, and without the facts the session can already prove, which need nothing.
		options = session.triples.needsFor(goal, session.facts, session.rules, session.depth)
		shown = withoutHeld(session, withGiven(session, options, goal, given))
		report = session.triples.reportLines(shown, session.style)
		// The report changes as facts are added and as values are given, so it is
		// repeated only when it has something new to say.
		if report.join("\n") != printed then
			say(session, "warning", "  no solution found at depth " + session.depth)
			for line in report
				session.io.say(line)
			end for
			// A different shape labels its variables differently, so what was given
			// before no longer names anything in it.
			whole = session.triples.reportLines(options, session.style).join("\n")
			if shape != null and whole != shape then given = {}
			shape = whole
			printed = report.join("\n")
		end if
		// Taking a fact back changes the knowledge base as much as adding one does, so
		// that round starts over too.
		if fillMissing(session, shown, goal, given) == "stopped" then return
	end while
end function

showProofs = function(session, goal, proofs)
	"Prints each answer - the proof tree behind it too, when the session is verbose."
	for proof in proofs
		if session.verbose then
			for line in session.triples.proofLines(proof, "  ")
				session.io.say(line)
			end for
		else
			say(session, "answer", "  " + session.triples.substitute(goal, proof.binds).text)
		end if
	end for
end function

withGiven = function(session, options, goal, given)
	"The options as they read with the values given so far put in, so the report and the question agree."
	if given.len == 0 then return options
	goalVars = nameSet(session, goal)
	labels = session.triples.reportLabels(options)
	answers = []
	for option in options
		needs = []
		for need in option.needs
			// The question's own variables stay as they are: they are what the search is
			// solving for, and naming one would be asserting the answer.
			values = {}
			for variable in session.triples.unboundVars(need.triple)
				if goalVars.hasIndex(variable.name) == 0 and given.hasIndex(labels[variable.name]) then
					values[variable.name] = given[labels[variable.name]]
				end if
			end for
			needs.push({"triple": session.triples.substitute(need.triple, values),
				"settled": need.settled})
		end for
		answers.push({"rule": option.rule, "needs": needs})
	end for
	return answers
end function

withoutHeld = function(session, options)
	"The options without the facts the session can already prove, which need nothing from the reader."
	remaining = []
	for option in options
		needs = []
		for need in option.needs
			held = not session.triples.hasUnknowns(need.triple) and proved(session, need.triple)
			if not held then needs.push(need)
		end for
		// A rule with nothing left to add is no longer a way to answer.
		if needs.len > 0 then remaining.push({"rule": option.rule, "needs": needs})
	end for
	// A report with nothing in it is not a report, so the alternatives are kept as they
	// were rather than emptied.
	if remaining.len == 0 then return options
	return remaining
end function

proved = function(session, triple)
	"Says whether the session can already prove this fact."
	return session.triples.proveGoals(triple, session.facts, session.rules, session.depth).len > 0
end function

nameSet = function(session, triple)
	"The names of a triple's variables, as a set."
	names = {}
	for variable in session.triples.unboundVars(triple)
		names[variable.name] = 1
	end for
	return names
end function

fillMissing = function(session, options, goal, given)
	"Asks for the facts of the best missing rule one after another, carrying each answer to the next; says whether it stopped or changed the knowledge base."
	found = firstMissing(session, options)
	if found == null then return "stopped"
	labels = session.triples.reportLabels(options)
	style = session.triples.filledStyle(session.style)
	binds = {}
	changed = false
	gaveValue = false
	// The facts of one rule share their variables, so an answer given under one of them is
	// carried to the rest: what was a check becomes a fact with nothing left to fill.
	for need in found.option.needs
		triple = session.triples.substitute(need.triple, binds)
		if not session.triples.hasUnknowns(triple) then
			// Already a stored fact, or derivable from the facts and rules the session holds:
			// either way there is nothing to add, so the fill passes over it rather than
			// offering it. The report side drops the same conditions in withoutHeld.
			if alreadyKnown(session, triple) or proved(session, triple) then continue
			if confirmFact(session, triple) == "stopped" then return "stopped"
			changed = true
			continue
		end if
		// A rule's fact is shown above its question, because the report listed it among
		// other lines; the query's own shape was named right above the prompt instead.
		if found.option.rule != null then
			session.io.say("  " + session.triples.neededFactText(
				{"triple": triple, "settled": need.settled}, labels, style))
		end if
		for variable in askedVars(session, triple, goal)
			value = askValue(session, variable, labels)
			if value == null then return "stopped"
			if value == changedMark then return "changed"
			binds[variable.name] = value
			given[labels[variable.name]] = value
			gaveValue = true
		end for
		filled = session.triples.substitute(triple, binds)
		// What is left is the question's own variable, so this fact cannot be completed
		// from here - filling it in would assert the answer rather than find it. The
		// answers so far still count for the facts after it.
		if session.triples.hasUnknowns(filled) then
			session.io.say("  " + session.triples.paint(session.style, "fact", filled.text) +
				session.triples.paint(session.style, "note", "  (not added: what is left is the question's own)"))
			continue
		end if
		// A completed fact the schema refuses adds nothing, so the question stops where it
		// is: asking for the same value again would only collect the same refusal, and the
		// report is left standing the way an empty value leaves it.
		if not fitsSchema(session, filled) then return "stopped"
		if addFact(session, filled) then changed = true
	end for
	if changed then return "changed"
	// A value given for a variable the rule introduces is progress too: the next pass shows
	// the report with that value in it and asks for what is still open, rather than giving up
	// because no fact happened to be added on this one. Each such value closes a variable, so
	// the report shrinks pass by pass and the loop still terminates.
	if gaveValue then return "changed"
	return "stopped"
end function

askedVars = function(session, triple, goal)
	"The variables to ask about for a missing fact: the ones it brings itself, or all of them when it brings none."
	own = session.triples.unboundVars(triple)
	goalVars = nameSet(session, goal)
	introduced = []
	for variable in own
		if goalVars.hasIndex(variable.name) == 0 then introduced.push(variable)
	end for
	// The question's own variables are the answer being looked for, so they are asked
	// about only for a fact that brings nothing itself: naming them is then the only way
	// to complete it from the prompt.
	if introduced.len == 0 then return own
	return introduced
end function

firstMissing = function(session, options)
	"The missing fact to ask about: a rule's before the query's own shape, one with a variable before one without."
	best = null
	for option in options
		for need in option.needs
			// A fact shaped like the query asserts the answer instead of giving the rules
			// what they need, so a rule's fact is always the better one to ask about.
			rank = session.triples.hasUnknowns(need.triple) + 2 * (option.rule != null)
			if best == null or rank > best.rank then
				best = {"option": option, "need": need, "rank": rank}
			end if
		end for
	end for
	return best
end function

confirmFact = function(session, triple)
	"Offers to add a missing fact that has no variables to fill in; says whether that changed the knowledge base."
	session.io.say("  " + session.triples.paint(session.style, "fact", triple.text))
	answer = ask(session, "  add it? [y/N] ")
	if answer == null then return "stopped"
	answer = session.triples.trimSpace(answer).lower
	if answer == "/undo" then
		if undo(session) then return "changed"
		return "stopped"
	end if
	if answer != "y" and answer != "yes" then return "stopped"
	if addFact(session, triple) then return "changed"
	return "stopped"
end function

askValue = function(session, variable, labels)
	"Asks for one value; null when the user leaves it, changedMark when they change the knowledge base instead."
	while true
		value = ask(session, "  ?" + labels[variable.name] + " = ")
		if value == null then return null
		value = session.triples.trimSpace(value)
		if value == "" then return null
		if value == "/undo" then
			if undo(session) then return changedMark
			continue
		end if
		triple = session.triples.SpoTriple.parse(value)
		// A whole fact is a fact wherever it is typed, so asserting one here is how to
		// answer by fiat: it is added, and the question starts again from it.
		if not (triple isa error) and not session.triples.hasUnknowns(triple) then
			addFact(session, triple)
			return changedMark
		end if
		// A value is a name, so a fact that still holds a variable - or a variable itself -
		// is neither a fact nor a value: it is refused and the question is put again.
		if not (triple isa error) then
			say(session, "warning", "  " + value + " still holds a variable: type a value, or a fact without one")
			continue
		end if
		if value[0] != "?" then return value
		say(session, "warning", "  ?" + labels[variable.name] + " takes a value, not a variable")
	end while
end function
