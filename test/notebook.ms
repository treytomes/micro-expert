// Cases for src/notebook.ms: the markers a notebook front end writes and reads.
//
// The session served is the one a run builds - engine.ms over the data/ the repository ships -
// so these cases pin the framed protocol rather than a second kind of session: a cell is
// several lines read in order, one process holds them all, a warning is the mark that a cell
// failed, and /mermaid draws the diagram instead of printing it.
//
// Nothing here opens a terminal: serve is handed a reader over a script and a writer into a
// list, which is the same seam main() has, so the whole protocol runs without a pipe.

run = function(notebook, engine, sessionModule, triples, rules, cli, options, h)
	"Checks the cell protocol and what a served session answers."

	// The arguments a front end writes, parsed the way notebook.ms parses them, so the
	// options are the program's own rather than a shape this module made up.
	parsed = function(arguments)
		cmd = cli.newCommand("micro-expert-notebook", "0.2.0", "the suite")
		options.declare(cli, cmd)
		return cli.parse(cmd, ["notebook.ms"] + arguments)
	end function

	// A fresh session over the repository's data, the way a notebook starts: no style, so the
	// answers are plain text, and no lookup, so nothing is asked of the network.
	startSession = function
		return engine.build(triples, rules.Rule, parsed(["--domain", "data"]), null)
	end function

	// One serving of these protocol lines, its answers collected as the front end would read
	// them. A script is what the front end writes: cells, and the answers it gives a cell
	// that is waiting for a value.
	serveScript = function(session, script)
		tally = {"at": 0, "out": []}
		read = function
			if tally.at >= script.len then return null
			tally.at = tally.at + 1
			return script[tally.at - 1]
		end function
		write = function(line)
			tally.out.push(line)
		end function
		notebook.serve(session, @read, @write)
		return tally.out
	end function

	// A cell's source as the front end writes it, framed by the two markers.
	cellLines = function(cell)
		lines = [notebook.CELL_START]
		for line in cell
			lines.push(line)
		end for
		lines.push(notebook.CELL_END)
		return lines
	end function

	// One serving of these cells, and nothing else in the script.
	transcript = function(session, cells)
		script = []
		for cell in cells
			script = script + cellLines(cell)
		end for
		return serveScript(session, script)
	end function

	cellsOf = function(out)
		"Each cell's answer, cut at the marker that ends one."
		cells = []
		current = null
		for line in out
			if line == notebook.DONE then
				if current != null then cells.push(current)
				current = null
			else
				if current == null then current = []
				current.push(line)
			end if
		end for
		return cells
	end function

	textOf = function(cell)
		"What the cell printed, without the markers around it."
		inside = 0
		lines = []
		for line in cell
			if line == notebook.OUT_START then
				inside = 1
			else if line == notebook.OUT_END then
				inside = 0
			else if inside then
				lines.push(line)
			end if
		end for
		return lines
	end function

	holds = function(lines, piece)
		for line in lines
			if line.indexOf(piece) != null then return true
		end for
		return false
	end function

	// Whether the cell drew a document of this type, and bracketed it as a draw.
	pictureIn = function(cell, mime)
		return cell.indexOf(notebook.DRAW_START + mime + ">>") != null and
			cell.indexOf(notebook.DRAW_END) != null
	end function

	countOf = function(facts, text)
		found = 0
		for fact in facts
			if fact.text == text then found = found + 1
		end for
		return found
	end function

	first = startSession()
	h.check("a notebook's session is the domain's", not (first isa error))
	// engine.build answers no registry and the notebook attaches one only when a cell runs
	// /online, so a cell that asks where the session is prompts rather than reaching the network.
	h.check("a notebook's session asks no service until it is told to",
		not (first isa error) and first.providers == null)

	// ── The services are a cell's choice ────────────────────────────────────
	// /online is what attaches the registry: a notebook asks nothing until a cell runs it, and a
	// serving handed no switch, or one told --offline, says so rather than letting a question go
	// out.
	// The switch a program hands over is a function over the session, so what it did is what the
	// session holds afterwards.
	switchOn = function(session)
		session.providers = [{"service": "example.com", "endpoint": "answer"}]
	end function
	online = startSession()
	// The program leaves its switch on the session before serving, and the @ is what keeps it a
	// function rather than calling it, so the cases do the same.
	online.askServices = @switchOn
	onlineOut = transcript(online, [["/online"]])
	h.check("a cell of /online is what attaches the services",
		online.providers != null and online.providers.len == 1)
	h.check("and a serving with no switch to turn on says so",
		holds(textOf(cellsOf(transcript(startSession(), [["/online"]]))[0]),
			"no services to ask"))
	offlineSession = startSession()
	offlineSession.offline = 1
	offlineSession.askServices = @switchOn
	offlineOut = transcript(offlineSession, [["/online"]])
	h.check("while --offline refuses the switch and asks nothing",
		offlineSession.providers == null and
			holds(textOf(cellsOf(offlineOut)[0]), "--offline refuses every call"))

	// ── One cell, one marked answer ─────────────────────────────────────────

	single = transcript(startSession(), [["is-parent-of(?p, tim)"]])
	cells = cellsOf(single)
	h.check("a cell is answered once", cells.len == 1)
	h.check("the answer is bracketed, so a front end can cut it out",
		single[0] == notebook.OUT_START and single.indexOf(notebook.OUT_END) != null)
	h.check("and the question is answered", holds(textOf(cells[0]), "bill"))
	h.check("a served session does not greet a reader", not holds(textOf(cells[0]), "/help"))
	h.check("the cell ends with its done marker", single[single.len - 1] == notebook.DONE)

	// ── What one cell learns, the next one holds ───────────────────────────

	session = startSession()
	// The two lines of one cell are run in order, so the second can build on the first, and the
	// cell after the cell already finds what it wrote: one process holds them both.
	shared = transcript(session, [["is-parent-of(casey, sam)", "is-parent-of(drew, casey)"],
		["is-parent-of(?p, sam)"]])
	pair = cellsOf(shared)
	h.check("a fact added in one cell is a fact in the next",
		pair.len == 2 and holds(textOf(pair[1]), "casey"))
	h.check("and both of a cell's lines took", countOf(session.facts, "is-parent-of(casey, sam)") == 1 and
		countOf(session.facts, "is-parent-of(drew, casey)") == 1)

	// ── A warning is the mark that a cell failed ───────────────────────────

	failing = transcript(startSession(), [["is-parent-of(casey, sam)"], ["is-parent-of(casey,"],
		["is-parent-of(?p, sam)"]])
	cells = cellsOf(failing)
	h.check("a cell whose line will not read is marked failed",
		cells.len == 3 and cells[1].indexOf(notebook.FAILED) != null)
	h.check("the cell that read is not", cells[0].indexOf(notebook.FAILED) == null)
	h.check("and the session carries on into the next cell",
		holds(textOf(cells[2]), "casey") and cells[2].indexOf(notebook.FAILED) == null)

	// /exit is the one command a notebook does not take: the session is one process, and the
	// notebook's own toolbar is where it is restarted.
	left = transcript(startSession(), [["/exit"], ["is-parent-of(?p, tim)"]])
	cells = cellsOf(left)
	h.check("a cell cannot leave the session", cells.len == 2 and cells[0].indexOf(notebook.FAILED) != null)
	h.check("and the cell after it is answered", holds(textOf(cells[1]), "bill"))

	// ── The diagram, drawn rather than printed ─────────────────────────────

	drawn = transcript(startSession(), [["/mermaid"]])
	cell = cellsOf(drawn)[0]
	text = textOf(cell)
	h.check("a /mermaid cell prints the diagram as a mermaid fence",
		holds(text, "```mermaid") and holds(text, "flowchart TD"))
	h.check("and draws the picture beside it",
		pictureIn(cell, "image/svg+xml") and holds(cell, "<svg xmlns") and
			cell.indexOf(notebook.DRAW_END) > cell.indexOf(notebook.DRAW_START + "image/svg+xml>>"))
	h.check("with the drawing no failure", cell.indexOf(notebook.FAILED) == null)

	// ── A question that needs a value asks the front end for one ────────────
	// The prompt's own ask-for-a-value loop runs inside the cell, so the notebook hands that
	// prompt the front end instead of reading the protocol as if it were a typed value.

	session = startSession()
	asked = serveScript(session, cellLines(["is-parent-of(?p, susan)"]) +
		[notebook.ANSWER_START + "1>> walter"])
	cells = cellsOf(asked)
	h.check("a question with no answer asks for a value", cells.len == 1 and
		cells[0].indexOf(notebook.ASK_START + "1>>") != null and
		cells[0].indexOf(notebook.ASK_END) != null)
	h.check("the ask carries the prompt it is waiting at", holds(cells[0], "  ?p = "))
	// The box has to explain itself: the report above it is the cell's text, and a cell that
	// has scrolled away leaves the box alone, so what the value stands for rides with the ask.
	askedAt = cells[0].indexOf(notebook.ASK_START + "1>>")
	endedAt = cells[0].indexOf(notebook.ASK_END)
	reasonAt = cells[0].indexOf("the parent of susan")
	h.check("and what a value there stands for",
		askedAt != null and endedAt != null and reasonAt != null and
			reasonAt > askedAt and reasonAt < endedAt)
	h.check("and it stands where the prompt happened, after the report",
		cells[0].indexOf(notebook.ASK_START + "1>>") > cells[0].indexOf("  no solution found at depth 8"))
	h.check("the answer completes the proof",
		cells[0].indexOf("  is-parent-of(walter, susan)") > cells[0].indexOf(notebook.ASK_END) and
			countOf(session.facts, "is-parent-of(walter, susan)") == 1)
	h.check("and the cell that asked is not a failed one", cells[0].indexOf(notebook.FAILED) == null)

	// An answer numbers the prompt it belongs to, so one meant for a prompt already gone is
	// not taken for this value.
	stale = serveScript(startSession(), cellLines(["is-parent-of(?p, susan)"]) +
		[notebook.ANSWER_START + "7>> greg", notebook.ANSWER_START + "1>> walter"])
	h.check("an answer for another ask is passed over",
		holds(textOf(cellsOf(stale)[0]), "is-parent-of(walter, susan)"))

	// ── A declined ask leaves the question and the session standing ────────

	session = startSession()
	declined = serveScript(session, cellLines(["is-parent-of(?p, susan)"]) +
		[notebook.DECLINE_START + "1>>"] + cellLines(["is-parent-of(?p, tim)"]))
	cells = cellsOf(declined)
	h.check("a declined ask ends the cell and says why", cells.len == 2 and
		cells[0].indexOf(notebook.FAILED) != null and holds(cells[0], "needs a value"))
	h.check("and the cell after it is answered", holds(textOf(cells[1]), "bill"))

	// An input that ends while a question waits is the same decline: the cell closes with
	// its markers instead of the session dying inside the prompt.
	silent = serveScript(startSession(), cellLines(["is-parent-of(?p, susan)"]))
	cells = cellsOf(silent)
	h.check("an ask with nothing to answer it ends the cell rather than the process",
		cells.len == 1 and cells[0].indexOf(notebook.FAILED) != null and
			silent[silent.len - 1] == notebook.DONE)

	// ── A // note is a comment, as in the file a cell mirrors ──────────────

	// A cell's line is read the way a .kb file reads it, so notes can be written beside the
	// knowledge they explain and a line that is only a note is skipped rather than read as a
	// command that does not exist - which is what marked the first cell of a new notebook
	// failed, and why the starter hint moved above the cell.
	session = startSession()
	noted = transcript(session, [["// the family", "is-parent-of(casey, sam) // a note"],
		["is-parent-of(?p, sam)"]])
	cells = cellsOf(noted)
	h.check("a note-only line is skipped, not refused",
		cells.len == 2 and cells[0].indexOf(notebook.FAILED) == null)
	h.check("and a note after a fact is not part of the fact",
		countOf(session.facts, "is-parent-of(casey, sam)") == 1)
	h.check("so the cell after it is answered", holds(textOf(cells[1]), "casey"))

	// A cell with nothing in it is still a cell: the front end gets an empty answer, not a
	// missing one, so a row it adds and runs does not wait for a mark that never comes.
	empty = cellsOf(transcript(startSession(), [[""]]))
	h.check("an empty cell is answered with nothing and does not fail",
		empty.len == 1 and textOf(empty[0]).len == 0 and empty[0].indexOf(notebook.FAILED) == null)
end function
