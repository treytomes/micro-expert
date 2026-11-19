// prompt.ms — the session at the prompt, and none of what a session is about.
//
// A prompt is a loop over one record: read a line, dispatch it when it names a command, and
// hand anything else back to whoever owns the text. That is all this module knows, so any
// program with a session can use it:
//
//   import "prompt"
//   session = {"prompt": globals["prompt"],
//       "io": {"read": @readLine, "say": @printLine},
//       "paint": @paintOneLine,        // may be left out
//       "handle": @readOneLine,
//       "commands": [{"name": "/facts", "note": "list the facts", "run": @listFacts}]}
//   session.prompt.run(session)
//
// Three things are handed in on the session, and each is a function pointer rather than a
// name this module would have to know: handle takes the session and every line that is not
// a command, so the prompt hands parsing back to the host instead of reaching into it; paint
// takes the session, a role and a piece of text, and a session without one prints what it is
// given; and commands is the host's own table, which joins the two the library answers
// itself. A session that holds no commands still runs, with /exit and /help.
//
// A command is a record of the name typed at the prompt, the note /help prints beside it, and
// run, the function the prompt calls with the session, the record itself, and whatever
// followed the name. The record comes along so that one function can serve several commands:
// the part a save writes is a field of the entry, not something a closure would have to bind.
// run answers whether the session should end, so /exit is a function that returns true and
// every other command returns false.
//
// Like triples.ms and rule.ms, this module is handed to the session rather than imported by
// repl.ms, for the reason the rest of the engine is: a bare import resolves against the entry
// script's folder, so repl.ms would find the suite's own module of the same name instead of
// the one beside it. Nothing here holds a class, so a copy is only a copy of its functions.
//
// What is here is the loop, the two commands it answers itself, the words it says them in,
// and the file-safe save a host's own commands use. repl.ms is the knowledge base on top.

// ── Talking to the reader ────────────────────────────────────────────────────
// The session holds how to read and how to write; this module decides only what to say, and
// asks paint to color it, so a prompt can be colored without the library knowing what a
// color is.

say = function(session, role, text)
	"Prints one line in a role's color through the session's output."
	session.io.say(paint(session, role, text))
end function

ask = function(session, question)
	"Shows a prompt and reads what is typed after it."
	return session.io.read(paint(session, "prompt", question))
end function

paint = function(session, role, text)
	"One piece of text in its role's color, or as it is when the session paints nothing."
	if not session.hasIndex("paint") then return text
	return session.paint(session, role, text)
end function

// ── Commands ─────────────────────────────────────────────────────────────────
// A line that starts with / is aimed at the prompt rather than at the program. The table is
// what knows the commands: a name, the note /help prints, and the function to call. The
// library's own two come first, the host's after them, so /help lists a session's commands
// without the loop knowing one of them.

leaveCommand = function(session, command, argument)
	"Says the session should end; the loop reads the answer."
	return true
end function

helpCommand = function(session, command, argument)
	"Prints every command the session answers, in the order the table holds them."
	for command in allCommands(session)
		say(session, "note", "  " + command.name + "  " + command.note)
	end for
	return false
end function

ownCommands = [
	{"name": "/exit", "note": "leave the session", "run": @leaveCommand},
	{"name": "/help", "note": "list these commands", "run": @helpCommand},
]

allCommands = function(session)
	"Every command a session answers: the library's two, then whatever the host added."
	if not session.hasIndex("commands") then return ownCommands
	return ownCommands + session.commands
end function

runCommand = function(session, line)
	"Runs the command this line names, answering whether the session should end."
	name = line.split(" ")[0].lower
	// The name is one word, so what follows it is the argument, trimmed, and may be empty.
	argument = trimSpace(line[name.len:])
	for command in allCommands(session)
		if command.name == name then
			// A command answers whether the session should end, and only /exit says so.
			if command.run(session, command, argument) then return true
			return false
		end if
	end for
	say(session, "warning", "  no such command: " + name + " (/help lists them)")
	return false
end function

// ── The loop ─────────────────────────────────────────────────────────────────
// One line has one meaning: a command if it starts with /, otherwise whatever the host's
// handle makes of it. q and quit leave as /exit does, since a session is closed by the same
// keystrokes whatever program it belongs to.

run = function(session)
	"Reads lines until the session ends: commands here, every other line to the session's handle."
	while true
		line = ask(session, "? ")
		if line == null then break
		line = trimSpace(line)
		if line == "" then continue
		if line == "q" or line == "quit" then break
		if line[0] == "/" then
			if runCommand(session, line) then break
			continue
		end if
		session.handle(session, line)
	end while
end function

// ── Counting ─────────────────────────────────────────────────────────────────

countText = function(count, singular)
	"Says '1 rule' or '2 rules'."
	if count == 1 then return "1 " + singular
	return str(count) + " " + singular + "s"
end function

// ── Writing a data file ──────────────────────────────────────────────────────
// A save writes a temp file and swaps it in, so the file that is already there is only
// replaced once the new one is whole: a save that fails part way through leaves the
// domain's facts.kb as it was rather than truncated to nothing. Only a file the save
// wrote itself is ever removed, and a swap that cannot put the old copy back says where
// it was left.

writeLines = function(path, lines)
	"Replaces the file at path with these lines, or returns an error."
	temp = path + ".tmp"
	problem = writeFresh(temp, lines)
	if problem != null then return problem
	problem = swapIn(temp, path)
	// A temp file is swept up only once the save has finished writing it, which is what
	// makes it this save's own to remove: what went wrong with the save is already the
	// answer, so the sweep's own failure has nowhere to go. Nothing else is ever cleared,
	// so a folder called facts.kb.tmp outlives a save that could not start.
	if problem != null then leftover = file.delete(temp)
	return problem
end function

writeFresh = function(path, lines)
	"Writes the lines to a new file at path, or returns an error, taking away the part-written file it made."
	handle = file.open(path, "w")
	if handle isa error then return handle
	for line in lines
		problem = handle.writeLine(line)
		if problem isa error then
			handle.close
			// The open worked, so the file at path is this write's own and a part-written
			// temp file must not be left to be taken for a whole one later. An open that
			// failed returns above, leaving whatever is at path alone.
			leftover = file.delete(path)
			return problem
		end if
	end for
	handle.close
	return null
end function

swapIn = function(temp, path)
	"Puts the finished temp file where the old file was, moving the old one aside until the new one is there."
	if not file.exists(path) then return moveFile(temp, path)
	// Windows will not move a file onto one that exists, so the old file is moved aside
	// first and put back if the new one cannot take its place: at no point is there no
	// copy of what the session started with.
	old = path + ".old"
	// A copy left by an interrupted swap is cleared so the old file can go there, but
	// only a file is one of ours: a folder named facts.kb.old is left where it is, and
	// the move below then fails with nothing lost.
	if file.exists(old) and file.info(old).isDirectory == 0 then leftover = file.delete(old)
	problem = file.move(path, old)
	if problem isa error then return problem
	problem = moveFile(temp, path)
	if problem == null then
		leftover = file.delete(old)
		return null
	end if
	// The old file goes back where it was, so the session still has what it started with.
	// If even that cannot be done, path is empty and the copy is at old, so the error says
	// where to find it rather than only why the move failed.
	restored = file.move(old, path)
	if restored isa error then return err(problem.message + "; the copy it replaced is at " + old)
	return problem
end function

moveFile = function(from, to)
	"Moves a file, answering an error or null, since file.move does not answer null on success."
	problem = file.move(from, to)
	if problem isa error then return problem
	return null
end function

// ── Helpers ──────────────────────────────────────────────────────────────────
// The loop trims what it reads, so it needs the same few lines triples.ms and knowledge.ms
// keep. It is written out here rather than handed in, so that this module stands alone - it
// is the piece meant to travel.

trimSpace = function(text)
	"Trims leading and trailing spaces and tabs."
	start = 0
	while start < text.len
		if not isSpace(text[start]) then break
		start = start + 1
	end while
	last = text.len - 1
	while last >= start
		if not isSpace(text[last]) then break
		last = last - 1
	end while
	return text[start:last + 1]
end function

isSpace = function(c)
	return c == " " or c == char(9)
end function
