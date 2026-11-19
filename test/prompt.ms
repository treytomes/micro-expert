// Cases for the prompt library on its own: the loop, the command table, and the text it
// hands back to the host. Nothing here knows what a fact is, which is the point - the only
// things in these sessions are lines and the functions they are given to.

run = function(prompt, h)
	"Checks the loop, the command dispatch and the handoff, against scripted sessions."

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
			session.commands = [
				{"name": "/echo", "note": "say the line back", "run": @echo},
				{"name": "/stop", "note": "leave quietly", "run": @stop},
			]
		end if
		if options.hasIndex("paint") then
			session.paint = function(given, role, text)
				return role + ":" + text
			end function
		end if
		// The one thing the host must supply: what to do with a line that is not a command.
		session.handle = function(given, line)
			seen.handled.push(line)
		end function
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
		helped.lines[2] == "  /echo  say the line back" and
			helped.lines[3] == "  /stop  leave quietly")
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

	// ── Painting, once the host says how ─────────────────────────────────────

	painted = scripted(prompt, ["/help", "/echo x", "q"], {"commands": 1, "paint": 1})
	h.check("the prompt is painted when the session paints", painted.asked[0] == "prompt:? ")
	h.check("and so is every line the library says", painted.lines[0] == "note:  /exit  leave the session" and
		painted.lines[4] == "  /echo x")
end function
