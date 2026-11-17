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

// ── Slash commands ───────────────────────────────────────────────────────────
// One line that starts with / is aimed at the session rather than the knowledge
// base. runCommand dispatches by name and commandList is what /help shows, in the
// same order.

commandList = [
	{"name": "/exit", "note": "leave the session"},
	{"name": "/help", "note": "list these commands"},
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
		if not fillMissing(session, options) then return
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

fillMissing = function(session, options)
	"Asks for the first missing fact - its variables, or a yes to add it whole; false when nothing was added."
	found = firstMissing(session, options)
	if found == null then return false
	if not session.triples.hasUnknowns(found.need.triple) then
		return confirmFact(session, found.need.triple)
	end if
	labels = session.triples.reportLabels(options)
	// A rule's fact is shown above its question, because the report listed it among
	// other lines; the query's own shape was named right above the prompt instead.
	if found.option.rule != null then
		style = session.triples.filledStyle(session.style)
		session.io.say("  " + session.triples.neededFactText(found.need, labels, style))
	end if
	binds = {}
	for variable in session.triples.unboundVars(found.need.triple)
		value = askValue(session, variable, labels)
		if value == null then return false
		binds[variable.name] = value
	end for
	addFact(session, session.triples.substitute(found.need.triple, binds))
	return true
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
	"Offers to add a missing fact that has no variables to fill in; false when it is declined."
	session.io.say("  " + session.triples.paint(session.style, "fact", triple.text))
	answer = ask(session, "  add it? [y/N] ")
	if answer == null then return false
	answer = session.triples.trimSpace(answer).lower
	if answer != "y" and answer != "yes" then return false
	addFact(session, triple)
	return true
end function

askValue = function(session, variable, labels)
	"Asks for one value; null when the user leaves it, or names a variable instead."
	while true
		value = ask(session, "  ?" + labels[variable.name] + " = ")
		if value == null then return null
		value = session.triples.trimSpace(value)
		if value == "" then return null
		if value[0] != "?" then return value
		say(session, "warning", "  ?" + labels[variable.name] + " takes a value, not a variable")
	end while
end function
