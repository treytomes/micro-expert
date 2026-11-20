// Cases for the prompt library on its own: the loop, the command table, and the text it
// hands back to the host. Nothing here knows what a fact is, which is the point - the only
// things in these sessions are lines and the functions they are given to.

run = function(prompt, h)
	"Checks the loop, the command dispatch, the handoff and the components, against scripted sessions."
	said = function(lines, text)
		"Whether a transcript holds this line exactly."
		return lines.indexOf(text) != null
	end function

	// A session over a script of typed lines, recording what it printed, asked, and what the
	// host's handle was given. options say whether this session has commands of its own and
	// whether it paints at all; the library has to work with neither.
	scripted = function(module, script, options)
		seen = {"lines": [], "asked": [], "handled": [], "at": 0}
		reader = function(question)
			seen.asked.push(question)
			// Running out of script is what a reader returning null means.
			if seen.at >= script.len then return null
			seen.at = seen.at + 1
			return script[seen.at - 1]
		end function
		writer = function(line)
			seen.lines.push(line)
		end function
		session = {"prompt": module, "io": {"read": @reader, "say": @writer}}
		if options.hasIndex("commands") then
			// A command takes the session, its own record and the rest of the line, and
			// answers whether the session should end. Which command it is, it reads from
			// the record, so one function could serve several.
			echo = function(given, command, argument)
				seen.lines.push("  " + command.name + " " + argument)
				return false
			end function
			stop = function(given, command, argument)
				return true
			end function
			// A note is the host's to add: /stop has none, and is listed by its name alone.
			session.commands = [
				{"name": "/echo", "note": "say the line back", "run": @echo},
				{"name": "/stop", "run": @stop}]
		end if
		if options.hasIndex("paint") then
			session.paint = function(given, role, text)
				return role + ":" + text
			end function
		end if
		if options.hasIndex("components") then
			// Two described files: one written from what the session holds, and one that
			// holds nothing and so has nothing to save. Their lines are plain words, since
			// the library is meant not to know a format.
			session.things = ["alpha", "beta"]
			if not options.hasIndex("nopaths") then session.paths = {}
			if options.hasIndex("path") then session.paths["things"] = options.path
			session.pathFor = function(given, name)
				// The host's own rule, kept tiny: a name without a dot gets .kb.
				if file.name(name).indexOf(".") == null then return name + ".kb"
				return name
			end function
			lines = function(given)
				return given.things
			end function
			missing = function(given)
				// The other answer a write can give: text saying why there is nothing to save.
				return "no empties to save"
			end function
			blank = function(given)
				// And a list with no lines in it, which is a file rather than nothing to save.
				return []
			end function
			read = function(given, path)
				given.things = ["one", "two", "three"]
				return given.things
			end function
			session.components = [
				{"name": "things", "singular": "thing", "write": @lines, "read": @read},
				{"name": "empties", "singular": "empty", "possessive": "its",
					"write": @missing, "read": @read},
				{"name": "blanks", "singular": "blank", "write": @blank, "read": @read},
			]
		end if
		// The one thing the host must supply: what to do with a line that is not a command.
		if not options.hasIndex("nohandle") then
			session.handle = function(given, line)
				seen.handled.push(line)
			end function
		end if
		if options.hasIndex("promptText") then session.promptText = options.promptText
		if options.hasIndex("exitWords") then session.exitWords = options.exitWords
		module.run(session)
		return seen
	end function

	// ── A line that is not a command ─────────────────────────────────────────

	plain = scripted(prompt, ["hello", "  spaced  ", "", "q"], {})
	h.check("a line that is not a command goes to the host's handle",
		plain.handled == ["hello", "spaced"])
	h.check("the host is given the line trimmed, not as typed", plain.handled[1] == "spaced")
	h.check("a blank line is skipped rather than handed over",
		plain.handled.len == 2 and plain.asked.len == 4)
	h.check("the loop asks with the prompt it was given", plain.asked[0] == "? ")
	h.check("q leaves before the next line is read", plain.asked.len == 4)
	short = scripted(prompt, ["only"], {})
	h.check("a reader that runs out ends the session", short.handled == ["only"] and
		short.asked.len == 2)

	// ── The command table ────────────────────────────────────────────────────

	echoed = scripted(prompt, ["/echo hi there", "q"], {"commands": 1})
	h.check("a command is called with its own record and the rest of the line",
		echoed.lines == ["  /echo hi there"] and echoed.handled.len == 0)
	h.check("a command's name is matched whatever its case",
		scripted(prompt, ["/ECHO Hi", "q"], {"commands": 1}).lines == ["  /echo Hi"])
	stopped = scripted(prompt, ["/stop", "never"], {"commands": 1})
	h.check("a command that answers true ends the session", stopped.asked.len == 1 and
		stopped.handled.len == 0)
	helped = scripted(prompt, ["/help", "q"], {"commands": 1})
	h.check("/help lists the library's commands first",
		helped.lines[0] == "  /exit  leave the session" and
			helped.lines[1] == "  /help  list these commands")
	h.check("/help lists the host's commands after them, in the table's order",
		helped.lines[2] == "  /echo  say the line back" and helped.lines[3] == "  /stop")
	h.check("/help says nothing else", helped.lines.len == 4)

	// A session that holds no commands is still a session: /exit and /help are the
	// library's, so a host with nothing of its own to answer need not build a table.
	alone = scripted(prompt, ["/help", "q"], {})
	h.check("a session with no commands still answers /help", alone.lines.len == 2 and
		alone.lines[0] == "  /exit  leave the session")
	unknown = scripted(prompt, ["/nope", "after"], {})
	h.check("an unknown command is refused", unknown.lines ==
		["  no such command: /nope (/help lists them)"])
	h.check("and the loop carries on with the next line", unknown.handled == ["after"])

	// ── What a host may change, and what it must supply ──────────────────────
	// The loop asks for the pieces it needs before it reads a line, so a forgotten one is
	// a sentence rather than a failure on a line the host has never seen.

	askedText = scripted(prompt, ["/help", "q"], {"promptText": "notes> "})
	h.check("a host chooses the text its prompt shows", askedText.asked[0] == "notes> ")
	mine = scripted(prompt, ["q", "done"], {"exitWords": ["done"]})
	h.check("a host chooses the words that leave, so q is then just a line",
		mine.handled == ["q"] and mine.asked.len == 2)

	seamless = scripted(prompt, ["a line"], {"nohandle": 1})
	h.check("a session with no handle says so and does not start",
		seamless.lines.len == 1 and seamless.asked.len == 0 and
			said(seamless.lines, "  the session cannot start without a handle, which every line that is not a command is given to"))
	pathless = scripted(prompt, ["a line"], {"components": 1, "nopaths": 1})
	h.check("a session with components and no paths says which piece is missing",
		said(pathless.lines, "  the session cannot start without a paths map, which is where each component's file is kept"))

	// ── Painting, once the host says how ─────────────────────────────────────

	painted = scripted(prompt, ["/help", "/echo x", "q"], {"commands": 1, "paint": 1})
	h.check("the prompt is painted when the session paints", painted.asked[0] == "prompt:? ")
	h.check("and so is every line the library says", painted.lines[0] == "note:  /exit  leave the session" and
		painted.lines[4] == "  /echo x")

	// ── Components ───────────────────────────────────────────────────────────
	// A component is a description, and the library builds the commands from it: no name is
	// written anywhere else, and one save serves every component.

	temp = "."
	if env.hasIndex("TEMP") then temp = env["TEMP"]
	if env.hasIndex("TMP") then temp = env["TMP"]
	scratch = function(name)
		return file.child(temp, "micro-expert-prompt-" + name)
	end function

	thingsPath = scratch("things.kb")
	leftover = file.delete(thingsPath)
	saved = scripted(prompt, ["/save-things " + thingsPath, "q"], {"components": 1})
	back = file.readLines(thingsPath)
	leftover = file.delete(thingsPath)
	h.check("a save writes the lines the component gives", back == ["alpha", "beta"])
	h.check("a save says how many it wrote", said(saved.lines, "  wrote 2 things to " + thingsPath))

	// The name typed at the prompt is the host's to read, so .kb is added by its rule, not
	// the library's, and the path reported back is the one that was written.
	bare = scratch("bare")
	bareFile = bare + ".kb"
	leftover = file.delete(bareFile)
	namedSave = scripted(prompt, ["/save-things " + bare, "q"], {"components": 1})
	named = file.exists(bareFile)
	leftover = file.delete(bareFile)
	h.check("a bare name is left to the session's own path rule", named == 1)
	h.check("and the path it was written to is the one reported",
		said(namedSave.lines, "  wrote 2 things to " + bareFile))

	thingsPath = scratch("again.kb")
	leftover = file.delete(thingsPath)
	remembered = scripted(prompt, ["/save-things " + thingsPath, "/save-things", "q"],
		{"components": 1})
	leftover = file.delete(thingsPath)
	h.check("a save remembers its file, so a bare save goes there again",
		remembered.lines.len == 2 and remembered.lines[1] == "  wrote 2 things to " + thingsPath)

	// A file the session started with is a path it already holds, not a name typed at the
	// prompt: an extensionless one is written where it is, rather than gaining .kb and
	// landing beside itself. This session says nothing about finding a path either.
	extensionless = scratch("named-without-extension")
	leftover = file.delete(extensionless)
	leftover = file.delete(extensionless + ".kb")
	plainSave = scripted(prompt, ["/save-things", "q"], {"components": 1, "path": extensionless})
	inPlace = file.exists(extensionless)
	beside = file.exists(extensionless + ".kb")
	leftover = file.delete(extensionless)
	leftover = file.delete(extensionless + ".kb")
	h.check("a component's own file is used as it is, with no extension added",
		inPlace == 1 and beside == 0)
	h.check("and the save says it wrote there",
		said(plainSave.lines, "  wrote 2 things to " + extensionless))

	unnamed = scripted(prompt, ["/save-things", "q"], {"components": 1})
	h.check("a component with no file to fall back on says how to name one",
		said(unnamed.lines, "  no things file to use: name one, as /save-things FILE"))
	emptySave = scripted(prompt, ["/save-empties " + scratch("empties.kb"), "q"], {"components": 1})
	h.check("a component that says it has nothing to save says so in its own words",
		said(emptySave.lines, "  no empties to save"))

	// An empty list is not "nothing to save": it is a file with no lines in it, which is how a
	// session empties a file it no longer holds anything for.
	blankPath = scratch("blank.kb")
	leftover = file.delete(blankPath)
	blankSave = scripted(prompt, ["/save-blanks " + blankPath, "q"], {"components": 1})
	blankLines = file.readLines(blankPath)
	leftover = file.delete(blankPath)
	h.check("a component that answers no lines writes an empty file",
		blankLines.len == 0 and said(blankSave.lines, "  wrote 0 blanks to " + blankPath))

	thingsPath = scratch("load.kb")
	leftover = file.delete(thingsPath)
	loadedThing = scripted(prompt, ["/load-things " + thingsPath, "/save-things", "q"],
		{"components": 1})
	leftover = file.delete(thingsPath)
	h.check("a load hands the file to the component's read and says how many",
		said(loadedThing.lines, "  loaded 3 things from " + thingsPath))
	h.check("and what it loaded is what the next save writes",
		loadedThing.lines.len == 2 and
			loadedThing.lines[1] == "  wrote 3 things to " + thingsPath)

	// A save is about a file rather than an addition, and arrives in the role that says so:
	// the vocabulary is the library's, and the colors are the host's own.
	paintedPath = scratch("painted.kb")
	leftover = file.delete(paintedPath)
	paintedSave = scripted(prompt, ["/save-things " + paintedPath, "q"],
		{"components": 1, "paint": 1})
	leftover = file.delete(paintedPath)
	h.check("a save is painted as a file, not as an addition",
		said(paintedSave.lines, "file:  wrote 2 things to " + paintedPath))

	// ── The example ──────────────────────────────────────────────────────────
	// examples/notes.ms is a whole program written on this module, so it is what proves the
	// module stands alone in the repository rather than only in an argument. A second import
	// in it would be that claim failing quietly.

	example = file.readLines(file.child("examples", "notes.ms"))
	imports = []
	for line in example
		if line.indexOf("import ") == 0 then imports.push(line)
	end for
	h.check("the notes example imports the prompt library and nothing else",
		example.len > 0 and imports.len == 1 and imports[0].indexOf("src/prompt") != null)

	helpedComponents = scripted(prompt, ["/help", "q"], {"components": 1})
	h.check("/help lists a save and a load per component, after the host's own",
		said(helpedComponents.lines, "  /save-things  write the things to their file, or to one named") and
			said(helpedComponents.lines, "  /save-empties  write the empties to its file, or to one named") and
			said(helpedComponents.lines, "  /load-empties  replace the empties with a file's"))
end function
