// session.ms — a prompt that takes facts and rules, and asks for what is missing.
//
// The session starts from the arrays main.ms already builds and adds to them in
// memory, so a fact or a rule typed at the prompt is searchable straight away, and
// nothing is written back to source unless a /save-* command asks:
//
//   import "session"
//   session.run(session)
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
//       "paths": paths, "knowledge": knowledge,
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
// The loop, the talk with the reader, the slash commands and the saving and loading of the
// components described below come from repl/repl.ms, none of which knows what a fact is. It is
// imported rather than handed in - a fallback is a function, not a class, so a second copy would
// still agree with this one - and what this module gives it back is the reading of a line of
// knowledge (session.fallback), the commands the session answers itself, and the three
// components, so the library dispatches a table it was handed rather than names it knows.
//
// Nothing here knows what a color is either: paint comes from triples.ms, and the one
// style map main.ms builds carries the report's roles and the session's alike, so a
// single NO_COLOR leaves the whole run plain.

// The library is a path rather than a name: a two-segment import binds no name of its own inside
// a module in this interpreter, so the map is read from the globals the entry script shares. The
// entry therefore imports "repl/repl" before it imports this module - main.ms and the suite both
// do - and `repl` below is that same map.
import "repl/repl"

repl = globals["repl/repl"]

// ── What the prompt library is given ────────────────────────────────────────
// The library knows the loop and nothing about a fact, so the session gives it the two
// pointers it asks for - paint and fallback - and the command table it dispatches. They are
// module-level functions, never closures - a function defined inside another cannot see this
// module's own functions in this interpreter, only the one it sits in.

paint = function(session, role, text)
	"One piece of text in a role's color: the style map and the painter both come from the session."
	return session.triples.paint(session.style, role, text)
end function

// What askValue answers when the user changes the knowledge base rather than giving a
// value - taking a fact back, or asserting one. A map, so a typed value can never be
// mistaken for it, and both mean the same thing to the fill: start the round again.
changedMark = {"changed": 1}

// ── Slash commands ───────────────────────────────────────────────────────────
// One line that starts with / is aimed at the session rather than the knowledge base, and
// the repl library dispatches it: the table below is what this session answers, and /help prints it
// beside the library's own /exit and /help. A command takes the session and whatever
// followed the name, and answers whether the session should end - which none of these do.

commandTable = function()
	"Every command this session answers itself, in the order /help lists them; its saves and loads come from its components."
	return [
		{"name": "/undo", "note": "take back the last fact added", "run": @undoCommand},
		{"name": "/facts", "note": "list the facts", "run": @listFacts},
		{"name": "/rules", "note": "list the rules", "run": @listRules},
	]
end function

undoCommand = function(session, command, argument)
	"Takes back the last fact, as /undo; the session carries on either way."
	undo(session)
	return false
end function

undo = function(session)
	"Takes back the last fact the session added; says so, or that there is none."
	if session.facts.len <= session.baseFacts then
		repl.say(session, "warning", "  nothing to take back")
		return false
	end if
	removed = session.facts.pop
	repl.say(session, "added", "  took back " + removed.text)
	return true
end function

listFacts = function(session, command, argument)
	"Prints every fact the session holds, in the order search tries them."
	repl.say(session, "note", "  " + repl.countText(session.facts.len, "fact"))
	for known in session.facts
		session.io.say("    " + session.triples.paint(session.style, "fact", known.text))
	end for
	return false
end function

depthCommand = function(session, command, argument)
	"Says how deep the search goes, which --depth set before the loop started."
	repl.say(session, "note", "  searching to depth " + session.depth)
	return false
end function

listRules = function(session, command, argument)
	"Prints every rule the session holds, in the order search tries them."
	repl.say(session, "note", "  " + repl.countText(session.rules.len, "rule"))
	for candidate in session.rules
		session.io.say("    " + session.triples.paint(session.style, "rule", candidate.text))
	end for
	return false
end function

// ── The components ───────────────────────────────────────────────────────────
// The three data files the session is made of, described the way the repl library builds its save and
// load commands from: what each is called, one of them for the messages, and the two calls that
// put it in a file and take it back out. Where each file is stays in session.paths, which the
// library moves after a save, so /save-facts with no name writes where it last went.

components = function()
	"The session's three data files, as the prompt library describes a component."
	return [
		{"name": "facts", "singular": "fact",
			"write": @factsLines, "read": @factsRead},
		{"name": "rules", "singular": "rule",
			"write": @rulesLines, "read": @rulesRead},
		// A schema is one, not many: the help reads "the schema to its file".
		{"name": "schema", "singular": "predicate", "possessive": "its",
			"write": @schemaLines, "read": @schemaRead},
	]
end function

componentPath = function(session, name)
	"A name typed at the prompt, as this session reads it: .kb added to a bare name, then found from the domain's folder."
	return session.knowledge.resolvePath(session.knowledge.withExtension(name))
end function

resolveComponent = function(session, path)
	"A path the session already holds, found the same way - but not a name, so nothing is added to it."
	return session.knowledge.resolvePath(path)
end function

// A component's write answers the lines a save writes, which may be none (an empty file is a
// thing a session can want), or a line of text saying why there is nothing to save at all; its
// read puts the file in place and answers what is held now, or an error. Between them they are
// the component's whole knowledge of its own format.

factsLines = function(session)
	"One facts-file line per fact the session holds."
	return session.knowledge.factsLines(session.facts)
end function

factsRead = function(session, path)
	"Replaces the session's facts with the file at path, answering them, or an error."
	loaded = session.knowledge.loadFactsAt(session.triples, path)
	if loaded isa error then return loaded
	session.facts = loaded
	// What was loaded is the knowledge base now, so /undo no longer reaches back past it.
	session.baseFacts = session.facts.len
	return loaded
end function

rulesLines = function(session)
	"One rules-file line per rule the session holds."
	return session.knowledge.rulesLines(session.rules)
end function

rulesRead = function(session, path)
	"Replaces the session's rules with the file at path, answering them, or an error."
	pieces = session.knowledge.loadRulesAt(session.triples, path)
	if pieces isa error then return pieces
	loaded = []
	for piece in pieces
		loaded.push(session.Rule.make(piece.head, piece.body))
	end for
	session.rules = loaded
	return loaded
end function

schemaLines = function(session)
	"One schema line per predicate the session types, or the reason there is nothing to save."
	// A session given no schema at all has nothing to save, which is not the same as a schema
	// with no predicates in it: the first says so in words, the second writes an empty file.
	if session.types == null then return "no schema to save"
	return session.knowledge.schemaLines(session.types)
end function

schemaRead = function(session, path)
	"Replaces the session's field types with the file at path, answering them, or an error."
	loaded = session.knowledge.loadSchemaAt(path)
	if loaded isa error then return loaded
	session.types = loaded
	return loaded
end function

// ── The session loop ─────────────────────────────────────────────────────────

run = function(session)
	"Reads lines until the user leaves, adding facts and rules and answering questions."
	// Only what the session adds can be taken back, never the knowledge base it
	// started from.
	session.baseFacts = session.facts.len
	// What the library needs from this module: how to read a line that is not a command,
	// and the commands the session answers itself. The loop is the repl library's.
	session.fallback = @handleLine
	session.commands = commandTable()
	session.components = components()
	session.pathFor = @componentPath
	session.resolvePath = @resolveComponent
	session.paint = @paint
	// Registered rather than seeded: this is the program's own use of the call a session makes
	// while it is running, and it lands after the component commands the table was built from.
	registered = repl.addCommand(session, {"name": "/depth",
		"note": "say how deep the search goes", "run": @depthCommand})
	repl.say(session, "note",
		"Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.")
	repl.run(session)
end function

handleLine = function(session, line)
	"Does what one line asks: adds a fact, asks a question, or adds a rule."
	if line.indexOf("<-") != null then
		addRule(session, line)
		return
	end if
	triple = session.triples.SpoTriple.parse(line)
	if triple isa error then
		repl.say(session, "warning", "  " + triple.message)
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
		repl.say(session, "note", "  already known: " + triple.text)
		return false
	end if
	session.facts.push(triple)
	repl.say(session, "added", "  added " + triple.text)
	return true
end function

refuseConstraint = function(session, triple)
	"Says a constraint's name is not a predicate a line stores or asks about, and whether it was one."
	if not session.triples.isConstraint(triple.predicate) then return false
	repl.say(session, "warning", "  refused: " + triple.text +
		": the predicate is a constraint, checked in a rule body rather than stored or asked")
	return true
end function

fitsSchema = function(session, triple)
	"Says whether a typed fact or question matches the schema, saying what it misses when it does not."
	if not session.hasIndex("types") then return true
	if session.types == null then return true
	problem = session.schema.misfit(session.types, triple)
	if problem == null then return true
	repl.say(session, "warning", "  refused: " + triple.text + ": " + problem)
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
		repl.say(session, "warning", "  " + pieces.message)
		return
	end if
	added = session.Rule.make(pieces.head, pieces.body)
	session.rules.push(added)
	repl.say(session, "added", "  added rule " + added.text)
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
			repl.say(session, "warning", "  no solution found at depth " + session.depth)
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
			repl.say(session, "answer", "  " + session.triples.substitute(goal, proof.binds).text)
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
			value = askValue(session, triple, variable, labels)
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
	answer = repl.ask(session, "  add it? [y/N] ")
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

// ── Choosing a value ────────────────────────────────────────────────────────
// Text is typed and a number is typed, but a boolean or a list of values is a small set
// the schema already names. For those fields the prompt lists the values, numbered, and
// takes either a number or the value itself. The set comes from the schema line of the
// predicate the variable stands in, so a predicate the schema does not name - and a field
// it types text or number - is asked for exactly as before.

fieldType = function(session, triple, variable)
	"The schema's type for the field a variable stands in, or null when the schema does not type it."
	if not session.hasIndex("types") then return null
	if session.types == null then return null
	// A variable predicate names no schema line, so there is nothing to look up.
	if not (triple.predicate isa string) then return null
	if session.types.hasIndex(triple.predicate) == 0 then return null
	fields = session.types[triple.predicate]
	if standsIn(session, triple.subject, variable) then return fields[0]
	if standsIn(session, triple.object, variable) then return fields[1]
	return null
end function

standsIn = function(session, term, variable)
	"Says whether a field is the variable being asked about, rather than a value already given."
	if not (term isa session.triples.Var) then return false
	return term.name == variable.name
end function

choiceValues = function(session, triple, variable)
	"The values a field is chosen from when its type is boolean or a '|' list; null when it is typed."
	type = fieldType(session, triple, variable)
	if type == null then return null
	if type == "boolean" then return ["true", "false"]
	if type.indexOf("|") == null then return null
	return type.split("|")
end function

showChoices = function(session, choices)
	"Lists the values a field is chosen from, numbered, so one can be typed by its number."
	if choices == null then return
	for at in range(0, choices.len - 1)
		session.io.say("  " + str(at + 1) + ") " + choices[at])
	end for
end function

chosenValue = function(session, value, choices)
	"The choice a typed line names, by the value itself or by its number; null when it names none."
	lowered = value.lower
	for at in range(0, choices.len - 1)
		if choices[at].lower == lowered then return choices[at]
	end for
	// A local called 'number' would shadow the type name the isa check wants.
	at = session.triples.termOf(value)
	if not (at isa number) then return null
	if at != floor(at) then return null
	if at < 1 or at > choices.len then return null
	return choices[at - 1]
end function

askValue = function(session, triple, variable, labels)
	"Asks for one value, from a numbered list when its field is a boolean or a list; null when the user leaves it, changedMark when they change the knowledge base instead."
	while true
		choices = choiceValues(session, triple, variable)
		showChoices(session, choices)
		value = repl.ask(session, "  ?" + labels[variable.name] + " = ")
		if value == null then return null
		value = session.triples.trimSpace(value)
		if value == "" then return null
		if value == "/undo" then
			if undo(session) then return changedMark
			continue
		end if
		typed = session.triples.SpoTriple.parse(value)
		// A whole fact is a fact wherever it is typed, so asserting one here is how to
		// answer by fiat: it is added, and the question starts again from it.
		if not (typed isa error) and not session.triples.hasUnknowns(typed) then
			addFact(session, typed)
			return changedMark
		end if
		// A value is a name, so a fact that still holds a variable - or a variable itself -
		// is neither a fact nor a value: it is refused and the question is put again.
		if not (typed isa error) then
			repl.say(session, "warning", "  " + value + " still holds a variable: type a value, or a fact without one")
			continue
		end if
		if value[0] == "?" then
			repl.say(session, "warning", "  ?" + labels[variable.name] + " takes a value, not a variable")
			continue
		end if
		if choices == null then return value
		picked = chosenValue(session, value, choices)
		if picked != null then return picked
		// The schema named the values, so a word that is none of them is refused here
		// rather than stored and refused as a completed fact, which would end the question.
		repl.say(session, "warning", "  " + value + " is not one of: " + choices.join(", "))
	end while
end function
