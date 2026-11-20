// notes.ms — a host for the repl library that is not a knowledge base.
//
// The prompt library says of itself that nothing in it knows what a fact is. This is that claim
// kept in the repository rather than argued: a session of notes, built on the repl library and
// nothing else. No triples, no facts, no rules, no schema, no colors and no path finding - the library
// asks for none of them unless a session says it has them.
//
// What comes from the library: the loop, /help, /exit, the refusal of an unknown command, and
// the whole of /save-notes and /load-notes, since the notes are described as a component. What
// the host brings: what a line means, two commands of its own, and one file.
//
//   ./3rd-party/miniscript-win/miniscript.exe examples/notes.ms
//
// Anything typed becomes a note. /count says how many, /clear forgets them, /save-notes writes
// them out and /load-notes reads one back. After /clear a save writes a file with no lines in
// it: a list with nothing in it is still a list, which is a different answer from a component
// saying it has nothing to save, and the two are kept apart on purpose.

import "../src/repl/repl"

repl = globals["../src/repl/repl"]

// ── The session's own state ──────────────────────────────────────────────────

countCommand = function(session, command, argument)
	"Says how many notes there are."
	repl.say(session, "note", "  " + repl.countText(session.notes.len, "note"))
	return false
end function

clearCommand = function(session, command, argument)
	"Forgets every note."
	session.notes = []
	// "added" is this host's own role, not one of the library's: a change to what the session
	// holds. A painter it does not know is a painter the example does not need.
	repl.say(session, "added", "  cleared the notes")
	return false
end function

// ── The component ────────────────────────────────────────────────────────────

notesLines = function(session)
	"One line per note, which is what a save writes."
	return session.notes
end function

notesRead = function(session, path)
	"Replaces the notes with the file's lines, answering them, or an error."
	loaded = file.readLines(path)
	if loaded isa error then return loaded
	session.notes = loaded
	return loaded
end function

notesPath = function(session, name)
	"A name typed at the prompt: .txt added to a bare name."
	if file.name(name).indexOf(".") == null then return name + ".txt"
	return name
end function

// ── What a line means ────────────────────────────────────────────────────────

fallback = function(session, line)
	"A line that is not a command is one more note."
	session.notes.push(line)
	repl.say(session, "added", "  noted: " + line)
end function

// ── Wiring, then the loop ────────────────────────────────────────────────────

session = {
	"notes": ["a first note"],
	"paths": {},
	"io": {
		"read": function(question)
			return input(question)
		end function,
		"say": function(line)
			print line
		end function,
	},
}

session.fallback = @fallback
session.commands = [
	{"name": "/count", "note": "say how many notes there are", "run": @countCommand},
	{"name": "/clear", "note": "forget the notes", "run": @clearCommand},
]
session.components = [
	{"name": "notes", "singular": "note", "write": @notesLines, "read": @notesRead},
]
session.pathFor = @notesPath

repl.say(session, "note", "Every line is a note. /count, /clear, /save-notes, /help, /exit.")
repl.run(session)
