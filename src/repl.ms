// repl.ms — a prompt that takes facts and rules, and asks for what is missing.
//
// The session starts from the arrays main.ms already builds and adds to them in
// memory, so a fact or a rule typed at the prompt is searchable straight away and
// nothing is written back to source:
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
//       "depth": 8, "verbose": 0, "style": style, "io": {"read": reader, "say": writer}}
//
// io is how a session talks, and the reason its checks need no terminal: read takes
// the prompt and returns a line (null ends the session), say takes a finished line.
//
// A line starting with / is a command for the session itself (see commandList); any
// other line is knowledge or a question, and the report already draws the difference:
// a line with <- is a rule, a line with a variable in it is a question, and a ground
// line is a fact.
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

// What askValue answers when the user takes a fact back instead of giving a value:
// a map, so a typed value can never be mistaken for it.
undoMark = {"undo": 1}

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
]

runCommand = function(session, line)
	"Runs one slash command, answering whether the session should end."
	name = line.split(" ")[0].lower
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
	say(session, "warning", "  no such command: " + name + " (/help lists them)")
	return false
end function

countText = function(count, singular)
	"Says '1 rule' or '2 rules'."
	if count == 1 then return "1 " + singular
	return str(count) + " " + singular + "s"
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
	say(session, "note", "  " + countText(session.facts.len, "fact"))
	for known in session.facts
		session.io.say("    " + session.triples.paint(session.style, "fact", known.text))
	end for
end function

listRules = function(session)
	"Prints every rule the session holds, in the order search tries them."
	say(session, "note", "  " + countText(session.rules.len, "rule"))
	for candidate in session.rules
		session.io.say("    " + session.triples.paint(session.style, "rule", candidate.text))
	end for
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
	if session.triples.hasUnknowns(triple) then
		askGoal(session, triple)
	else
		addFact(session, triple)
	end if
end function

addFact = function(session, triple)
	"Adds a fact to the session's knowledge base, and says which one."
	session.facts.push(triple)
	say(session, "added", "  added " + triple.text)
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
	lastReport = null
	while true
		proofs = session.triples.proveGoals(goal, session.facts, session.rules, session.depth)
		if proofs.len > 0 then
			showProofs(session, goal, proofs)
			return
		end if
		// One walk over the goal feeds both the report and the question, so the
		// variables asked about are the ones the report showed.
		options = session.triples.needsFor(goal, session.facts, session.rules, session.depth)
		report = session.triples.reportLines(options, session.style)
		// The report changes as facts are added, so it is repeated only when it has
		// something new to say.
		if report.join("\n") != lastReport then
			say(session, "warning", "  no solution found at depth " + session.depth)
			for line in report
				session.io.say(line)
			end for
			lastReport = report.join("\n")
		end if
		// Taking a fact back changes the knowledge base as much as adding one does, so
		// that round starts over too.
		if fillMissing(session, options, goal) == "stopped" then return
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

fillMissing = function(session, options, goal)
	"Asks for the first missing fact; says whether it was added, taken back, or given up on."
	found = firstMissing(session, options)
	if found == null then return "stopped"
	triple = found.need.triple
	if not session.triples.hasUnknowns(triple) then
		return confirmFact(session, triple)
	end if
	labels = session.triples.reportLabels(options)
	// A rule's fact is shown above its question, because the report listed it among
	// other lines; the query's own shape was named right above the prompt instead.
	if found.option.rule != null then
		style = session.triples.filledStyle(session.style)
		session.io.say("  " + session.triples.neededFactText(found.need, labels, style))
	end if
	binds = {}
	for variable in askedVars(session, triple, goal)
		value = askValue(session, variable, labels)
		if value == null then return "stopped"
		if value == undoMark then return "undone"
		binds[variable.name] = value
	end for
	filled = session.triples.substitute(triple, binds)
	// What is left is the question's own variable, so this fact cannot be completed from
	// here: filling it in would assert the answer rather than find it.
	if session.triples.hasUnknowns(filled) then
		session.io.say("  " + session.triples.paint(session.style, "fact", filled.text) +
			session.triples.paint(session.style, "note", "  (not added: what is left is the question's own)"))
		return "stopped"
	end if
	addFact(session, filled)
	return "added"
end function

askedVars = function(session, triple, goal)
	"The variables to ask about for a missing fact: the ones it brings itself, or all of them when it brings none."
	own = session.triples.unboundVars(triple)
	goalVars = {}
	for variable in session.triples.unboundVars(goal)
		goalVars[variable.name] = 1
	end for
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
	"Offers to add a missing fact that has no variables to fill in; says what was chosen."
	session.io.say("  " + session.triples.paint(session.style, "fact", triple.text))
	answer = ask(session, "  add it? [y/N] ")
	if answer == null then return "stopped"
	answer = session.triples.trimSpace(answer).lower
	if answer == "/undo" then
		if undo(session) then return "undone"
		return "stopped"
	end if
	if answer != "y" and answer != "yes" then return "stopped"
	addFact(session, triple)
	return "added"
end function

askValue = function(session, variable, labels)
	"Asks for one value; null when the user leaves it, undoMark when they take a fact back."
	while true
		value = ask(session, "  ?" + labels[variable.name] + " = ")
		if value == null then return null
		value = session.triples.trimSpace(value)
		if value == "" then return null
		if value == "/undo" then
			if undo(session) then return undoMark
			continue
		end if
		if value[0] != "?" then return value
		say(session, "warning", "  ?" + labels[variable.name] + " takes a value, not a variable")
	end while
end function
