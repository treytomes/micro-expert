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

	// One serving of these cells, written out as the lines a front end would read: the
	// markers around each cell, and this file's answers after it.
	transcript = function(session, cells)
		script = []
		for cell in cells
			script.push(notebook.CELL_START)
			for line in cell
				script.push(line)
			end for
			script.push(notebook.CELL_END)
		end for
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

	// A cell with nothing in it is still a cell: the front end gets an empty answer, not a
	// missing one, so a row it adds and runs does not wait for a mark that never comes.
	empty = cellsOf(transcript(startSession(), [[""]]))
	h.check("an empty cell is answered with nothing and does not fail",
		empty.len == 1 and textOf(empty[0]).len == 0 and empty[0].indexOf(notebook.FAILED) == null)
end function
