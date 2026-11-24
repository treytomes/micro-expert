// micro-expert — a little expert system for MiniScript 2.
//
// The program is a session at the prompt; the fixed questions it used to ask are
// worked examples now, in sample.ms.
//
// The options are declared in options.ms and the cli library parses the arguments and
// generates --help and --version from that table; it lives apart so the suite can pin it.

import "cli/cli"
import "triples"
import "logging/logging"
import "vt"
// The library comes before the session module, which takes it from globals as it loads; why is in
// session.ms, and the suite pins the order.
import "repl/repl"
import "session"
import "rule"
import "engine"
import "options"
// The API layer and the location module are here for --where: the option asks ipwho.is where this
// session is, and location.ms turns that answer into facts about the session subject.
import "api/client"
import "api/ipwhois"
import "uid"
import "location"

// src/cli and src/logging are submodules, so their modules live at <folder>/<file>:
// import names the resulting map after the path it was given, so each is aliased back
// to the plain name the rest of this file uses.
cli = globals["cli/cli"]
logging = globals["logging/logging"]

// ── Logging ──────────────────────────────────────────────────────────────────
// Console output plus a daily rolling file under logs/ (app-YYYYMMDD.log, with
// the last seven kept), reproducing the Serilog setup used by NLP.REPL.

log = logging.newLogger({"name": "micro-expert"})

// ── Command line ────────────────────────────────────────────────────────────

cmd = cli.newCommand("micro-expert", "0.2.0", "A little expert system for MiniScript 2.")

finish = function(code=0)
	"Logs the exit and stops the program with the given status code."
	log.info("{App} exiting with code {Code}", {"App": cmd.name, "Code": code})
	exit code
end function

globals["options"].declare(cli, cmd)

options = cli.parse(cmd, shellArgs)

if options.help then
	print cli.helpText(cmd)
	finish 0
end if

if options.version then
	print cli.versionLine(cmd)
	finish 0
end if

if not options.ok then
	print "error: " + options.error
	print "Run " + cmd.name + " --help for usage."
	finish 1
end if

// The threshold is set before the first event, so --log-level governs them all.
level = options.values["log-level"]
if logging.levelRank(level) == null then
	print "error: unknown log level: " + level
	print "Use one of: " + logging.levels.join(", ").lower
	finish 1
end if
log.setMinimumLevel(level)

log.info("{App} {Version} starting", {"App": cmd.name, "Version": cmd.version})
arguments = shellArgs[1:]
argumentText = arguments.join(" ")
if argumentText == "" then argumentText = "(none)"
log.info("Command-line arguments ({Count}): {Arguments}", {"Count": arguments.len, "Arguments": argumentText})

// ── Report what was parsed ────────────────────────────────────────────────────

showValue = function(value)
	if value == null then return "(not given)"
	if value isa list then
		if value.len == 0 then return "(none)"
		return value.join(", ")
	end if
	return str(value)
end function

width = 0
for option in cmd.options
	if option.name.len > width then width = option.name.len
end for

for option in cmd.options
	if options.values[option.name] != null then
		log.info option.name + ":" + " " * (width - option.name.len + 2) + showValue(options.values[option.name])
	end if
end for

if options.values.verbose then
	print ""
	print "Verbose run: depth " + options.values.depth
end if

// ── Report colors ────────────────────────────────────────────────────────────
// The session paints its parts through the bundled vt module: one color for the
// facts it asks for, one for the rule that would use them, and dimmed variables
// inside the facts.
// NO_COLOR (https://no-color.org) turns every escape code off, so a redirected run
// stays plain text; the logger reads it the same way.

reportStyle = function
	"The paint the report and the session at the prompt use, or null when colors are off."
	if env.hasIndex("NO_COLOR") then return null
	return {
		"header": vt.bold,
		"warning": vt.textColor(vt.color.red),
		"missing": vt.textColor(vt.color.red),
		"fact": vt.textColor(vt.color.aqua),
		"rule": vt.textColor(vt.color.olive),
		"var": vt.dim,
		"note": vt.dim,
		"prompt": vt.bold,
		"added": vt.textColor(vt.color.olive),
		"file": vt.textColor(vt.color.olive),
		"answer": vt.textColor(vt.color.green),
		"normal": vt.normal,
	}
end function

// ── The session ──────────────────────────────────────────────────────────────
// engine.ms reads the domain's schema, facts and rules and answers the session they make;
// what is left here is the terminal a session talks through and the log it writes to.

// The Rule class, so a rule typed at the prompt joins the search like the ones
// rules.ms loads: the same class, the same .text, the same solver.
Rule = globals["rule"].Rule

engineSession = engine.build(triples, Rule, options, reportStyle())
if engineSession isa error then
	print "error: " + engineSession.message
	finish 1
end if

// ── Where the session is ─────────────────────────────────────────────────────
// A run asks ipwho.is where this session reaches the network from and adds the place's facts
// under the session subject, so the prompt answers has-location(session, ?p) and the domain's
// is-a rule types the place. A machine with no network still gets a session: the lookup's failure
// is a warning, and the facts are simply not there.

engine.includePlace(engineSession, globals["location"], globals["uid"],
	globals["api/client"], globals["api/ipwhois"], log)

// 'known', not 'fact': a top-level loop variable is a global here, so naming it
// fact would overwrite the fact() shorthand with a triple as soon as the loop ran.
// Facts are debug detail: they are logged, not printed, so a normal run shows the
// answers and --log-level debug shows what they were drawn from.
for known in engineSession.facts
	log.debug "(fact) {Fact}", {"Fact": known.text}
end for

// Rules are debug detail too, so they are logged in the order search tries them.
for r in engineSession.rules
	log.debug "(rule) {Rule}", {"Rule": r.text}
end for

// ── A session at the prompt ──────────────────────────────────────────────────
// The program is this session: it takes facts, rules and questions. It starts from
// the arrays engine.ms built and adds to them in memory, so what the prompt learns lasts for
// the run and no source file is touched. --depth bounds its search, --verbose prints the
// proof tree before each answer, and --nlp says each answer as a sentence instead of a fact -
// the tree above it too, so a run reads as one account rather than two forms.

engineSession.io = {
	"read": function(question)
		return input(question)
	end function,
	"say": function(line)
		print line
	end function,
}

session.run(engineSession)

finish 0
