// notebook.ms — a knowledge session served to a notebook: one cell in, its marked answer out.
//
// A notebook has no terminal to type at, so a run of this program is not the prompt main.ms
// is. The front end writes a cell between two markers, this file answers it through the same
// session the prompt runs, and marks where the answer ended. That framing is the whole
// difference: what a fact, a rule and a question are, where the data files are and how a line
// is read all come from session.ms and engine.ms.
//
//   <<kbnb:cell>>                 the front end writes this, then the cell's lines,
//   is-parent-of(?p, tim)         then the end marker.
//   <<kbnb:end>>
//   <<kbnb:out>>                  this file writes the answer's markers, and what the cell
//   ...                           printed between them - the interpreter's own text,
//   <<kbnb:end-out>>              colored by nothing, since a notebook draws it.
//   <<kbnb:failed>>               when a line of the cell said a warning
//   <<kbnb:draw:image/svg+xml>>   when the cell drew a picture: the type as its MIME,
//   <svg ...>                     then the document.
//   <<kbnb:end-draw>>
//   <<kbnb:done>>                 and this one whatever the cell did.
//
// A question with no answer runs the prompt's own ask-for-a-value loop, so the cell asks
// rather than going quiet: the ask is written where the prompt happened, inside the cell's
// output, and the cell waits for the answer. An answer line carries the value; a decline,
// or an input that ends, leaves the question where the report put it, says so in the cell,
// and lets the next cell run rather than taking the session down with it.
//
//   <<kbnb:ask:1>>                 the ask's number, then the prompt it is waiting at and
//     ?p =                          what a value there stands for, so the box can say why
//   the parent of ?p, needed to answer is-uncle-of(oliver, ?p)
//   <<kbnb:end-ask>>               even when the report above it has scrolled away
//   <<kbnb:answer:1>> walter       what the front end writes back, or
//   <<kbnb:decline:1>>             this, to leave the question unanswered
//
// A cell is several lines, run in order, so a cell can add a fact and ask about it. It is one
// session the cells share, as the prompt is one session the lines share, so what one cell
// learns the next holds. A line that starts with / is a command, as at the prompt, except
// /exit: a notebook is restarted by its own toolbar, so no cell can leave the session. A cell
// of just /mermaid draws the diagram instead of printing it - the fence a Markdown renderer
// draws, then the picture mermaid.svg answers, which every VS Code shows.
//
// Nothing is printed but the marks above, and nothing reaches the network or the log: no
// lookup asks where the session is and no log file is opened, so a notebook starts from the
// domain's files and says only what its cells ask for. The style is null for the same reason
// - the front end draws the text, not a terminal - which leaves the answers plain.
//
// Imported, this file only defines what the suite pins. A run's shellArgs[0] is this file, and
// a suite's is not, which is what the guard at the end reads.

import "cli/cli"
// The loop comes before the session that reads it from the globals they share; src/session.ms
// says why.
import "repl/repl"
import "triples"
import "rule"
import "engine"
import "session"
import "mermaid"
import "options"

cli = globals["cli/cli"]
repl = globals["repl/repl"]
// The session module, under a name a function's own `session` parameter cannot take.
sessionModule = session
diagrams = mermaid

// What a front end writes and reads. The two ends of the cell are its request; the rest is
// this file's answer, and the answer to one cell ends at its own done marker.
CELL_START = "<<kbnb:cell>>"
CELL_END = "<<kbnb:end>>"
OUT_START = "<<kbnb:out>>"
OUT_END = "<<kbnb:end-out>>"
DRAW_START = "<<kbnb:draw:"
DRAW_END = "<<kbnb:end-draw>>"
FAILED = "<<kbnb:failed>>"
DONE = "<<kbnb:done>>"
// A question that needs a value, and the two lines a front end answers it with. The ask's
// number is what keeps an answer to one prompt from being taken for another's.
ASK_START = "<<kbnb:ask:"
ASK_END = "<<kbnb:end-ask>>"
ANSWER_START = "<<kbnb:answer:"
DECLINE_START = "<<kbnb:decline:"

// ── Serving ──────────────────────────────────────────────────────────────────

serve = function(session, read, write)
	"Serves one notebook: each cell read from read and answered into write, until the input ends."
	// The session's own text goes to the notebook, not to a terminal, and a value the prompt
	// asks for goes there too: what the session reads is this ask, never a cell's lines, so a
	// question waiting for a value cannot eat the protocol that follows it. The number it
	// counts is one per serving, so an answer names the prompt it belongs to.
	tasks = {"next": 0}
	// A function defined inside another cannot see this module's own functions - only the
	// one it sits in - so the asker is fetched into a local the ask below can call.
	valueAsker = @askForValue
	// The prompt names the variable and nothing else; what a value there stands for is the
	// session's askWhy, since the box can be all a reader sees once the cell has scrolled.
	ask = function(question)
		return valueAsker(session, question, session.askWhy, tasks, @read, @write)
	end function
	session.io = {"read": @ask, "say": @write}
	// What the prompt's loop does before it reads anything - the commands, the components,
	// the fallback and the paint - is done here once, and the cells are dispatched the way
	// that loop dispatches a line.
	sessionModule.prepare(session)
	while true
		// A function is invoked as soon as it is read as a value, so handing read and write
		// on takes @, the way the prompt library hands a command's run and a component's
		// write. Calling one by name, as serveCell does, needs no mark.
		lines = readCell(@read)
		if lines == null then break
		serveCell(session, lines, @write)
	end while
end function

readCell = function(read)
	"One cell's lines, between its two markers; null when the input has no whole cell left."
	// Anything before a start marker is not a cell and is not answered, so a front end that
	// writes a blank line between cells does not shift every answer by one.
	while true
		line = read()
		if line == null then return null
		if line == CELL_START then break
	end while
	lines = []
	while true
		line = read()
		if line == null then return null
		if line == CELL_END then break
		lines.push(line)
	end while
	return lines
end function

serveCell = function(session, lines, write)
	"One cell's answer: what it printed, the mark if it said a warning, and the picture it drew."
	session.cellFailed = 0
	session.paint = @notebookPaint
	diagram = diagramCell(lines)
	write(OUT_START)
	if diagram then
		drawMermaid(session, @write)
	else
		for line in lines
			serveLine(session, line)
		end for
	end if
	write(OUT_END)
	if session.cellFailed then write(FAILED)
	if diagram then drawPicture(session, @write)
	write(DONE)
end function

askForValue = function(session, question, why, tasks, read, write)
	"Asks the notebook for one value: the question in its own block, then the value answered or null."
	tasks.next = tasks.next + 1
	id = str(tasks.next)
	write(ASK_START + id + ">>")
	write(question)
	// What the value stands for goes in the block with the prompt, not only in the report
	// above it: the box can outlive that report, so it has to explain itself.
	if why != null and why != "" then write(why)
	write(ASK_END)
	value = readAnswer(id, @read)
	if value == null then
		// A decline and an input that ended mean the same thing to the question: nothing came
		// back, so it stops where the report left it. Saying so marks the cell failed and
		// leaves the session standing for the cell after it.
		repl.say(session, "warning", "  the question needs a value and none was given")
	end if
	return value
end function

readAnswer = function(id, read)
	"The value the front end answered this ask with, or null for a decline or an input that ended."
	answered = ANSWER_START + id + ">>"
	declined = DECLINE_START + id + ">>"
	while true
		line = read()
		if line == null then return null
		line = repl.trimSpace(line)
		if line == declined then return null
		if line.indexOf(answered) == 0 then return repl.trimSpace(line[answered.len:])
		// Anything else is not this ask's: an answer meant for a prompt already gone, or a
		// line from a front end that is out of step, is passed over rather than taken as the
		// value this question is waiting for.
	end while
end function

serveLine = function(session, line)
	"One line of a cell, read the way the prompt reads it: a command, or knowledge."
	line = repl.trimSpace(line)
	if line == "" then return
	if line == "/exit" then
		repl.say(session, "warning", "  /exit would end the session; restart it from the notebook instead")
		return
	end if
	if line[0] == "/" then
		repl.runCommand(session, line)
		return
	end if
	session.fallback(session, line)
end function

notebookPaint = function(session, role, text)
	"A warning is what a notebook marks: the cell it was said from is the cell that failed. The report of what would answer a question is said in its own role, so it does not mark the cell that goes on to ask."
	if role == "warning" then session.cellFailed = 1
	return session.triples.paint(session.style, role, text)
end function

// ── The diagram ─────────────────────────────────────────────────────────────
// /mermaid already prints the diagram and /mermaid FILE writes it and its picture. A notebook
// wants both forms under the cell, so a cell of just /mermaid is drawn here rather than sent
// to the command: the same mermaid.build and mermaid.svg the command calls, in the two forms
// a notebook can show.

diagramCell = function(lines)
	"Whether the cell asks for the diagram under it: /mermaid alone, so /mermaid FILE still writes files."
	asked = 0
	for line in lines
		trimmed = repl.trimSpace(line)
		if trimmed == "" then continue
		if trimmed.lower != "/mermaid" then return false
		asked = asked + 1
	end for
	return asked == 1
end function

drawMermaid = function(session, write)
	"The diagram the session holds, in the fence a Markdown renderer draws."
	write("```mermaid")
	for line in diagrams.build(session.facts, sessionModule.heldTypes(session), session.rules)
		write(line)
	end for
	write("```")
end function

drawPicture = function(session, write)
	"The same diagram as an SVG document, which a notebook shows whatever VS Code it runs in."
	write(DRAW_START + "image/svg+xml>>")
	for line in diagrams.svg(session.facts, sessionModule.heldTypes(session), session.rules)
		write(line)
	end for
	write(DRAW_END)
end function

// ── The program ─────────────────────────────────────────────────────────────

main = function
	"The run: the options a front end passes, the session they name, then the cells it writes."
	cmd = cli.newCommand("micro-expert-notebook", "0.2.0", "A knowledge session served to a notebook.")
	options.declare(cli, cmd)
	parsed = cli.parse(cmd, shellArgs)
	if parsed.help then
		print cli.helpText(cmd)
		exit 0
	end if
	if parsed.version then
		print cli.versionLine(cmd)
		exit 0
	end if
	if not parsed.ok then
		print "error: " + parsed.error
		exit 1
	end if
	session = engine.build(triples, globals["rule"].Rule, parsed, null)
	if session isa error then
		print "error: " + session.message
		exit 1
	end if
	serve(session, @readLine, @sayLine)
	exit 0
end function

readLine = function
	"One line of the protocol from the front end, or null when it has closed the pipe."
	return input
end function

sayLine = function(line)
	print line
end function

// Run, this file serves a notebook; imported by the suite, it only defines what the cases pin.
if shellArgs.len > 0 and file.name(shellArgs[0]) == "notebook.ms" then main()
