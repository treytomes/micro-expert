// micro-expert — a little expert system for MiniScript 2.
//
// Sample command-line options: two string types, two numbers, a repeatable list,
// and a flag. Declaring them here is all it takes — cli.ms parses the arguments
// and generates --help and --version from the same declarations.

import "cli"
import "triples"
import "logging"

// ── Logging ──────────────────────────────────────────────────────────────────
// Console output plus a daily rolling file under logs/ (app-YYYYMMDD.log, with
// the last seven kept), reproducing the Serilog setup used by NLP.REPL.

log = logging.newLogger({"name": "micro-expert"})

// ── Rules ────────────────────────────────────────────────────────────────────

cmd = cli.newCommand("micro-expert", "0.1.0", "A little expert system for MiniScript 2.")

finish = function(code=0)
	"Logs the exit and stops the program with the given status code."
	log.info("{App} exiting with code {Code}", {"App": cmd.name, "Code": code})
	exit code
end function

cli.add(cmd, {
	"name": "depth",
	"aliases": ["--depth"],
	"type": "number",
	"default": 8,
	"description": "Maximum backward-chaining depth.",
})
cli.add(cmd, {
	"name": "verbose",
	"aliases": ["--verbose"],
	"type": "flag",
	"default": 1,
	"description": "Print extra progress detail.",
})
cli.add(cmd, {
	"name": "log-level",
	"aliases": ["--log-level"],
	"type": "string",
	"default": "information",
	"description": "Lowest level to log: debug, information, warning, error, fatal.",
})

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

// ── Shorthands ───────────────────────────────────────────────────────────────
// Globals, so an importing script can write fact(...) and var(...) directly; the
// classes live here so the program shares one copy of each and `isa` agrees.

fact = function(subject, predicate, object)
	"Builds a Subject-Predicate-Object triple."
	return triples.SpoTriple.make(subject, predicate, object)
end function

var = function(name)
	"Builds a logic variable, e.g. var(""x"") for ?x."
	return triples.Var.make(name)
end function

notEqual = function(left, right)
	"Shorthand for NotEqual.make, for use inside a rule body."
	return triples.NotEqual.make(left, right)
end function

runQuery = function(query)
	print "Query: " + query.text
	for proof in triples.proveGoals(query, facts, rules, options.values.depth)
		if options.values.verbose then
			for line in triples.proofLines(query, proof, "  ")
				print line
			end for
		else
			print "  " + triples.substitute(query, proof.binds).text
		end if
	end for
end function

// ── Facts and rules ──────────────────────────────────────────────────────────

// The family tree lives in facts.ms and the reasoning in rules.ms. Both build their
// arrays on request instead of at load time, because the triples have to come from
// this file's copy of triples.ms: a module that imports it gets a copy of its own,
// and the solver does not recognize another copy's classes. So both are handed this
// file's copy.

import "facts"
import "rules"

// The arrays themselves, not the module maps that hold them.
facts = globals["facts"].build(triples)
rules = globals["rules"].build(triples)

// 'known', not 'fact': a top-level loop variable is a global here, so naming it
// fact would overwrite the fact() shorthand with a triple as soon as the loop ran.
// Facts are debug detail: they are logged, not printed, so a normal run shows the
// answers and --log-level debug shows what they were drawn from.
for known in facts
	log.debug "(fact) {Fact}", {"Fact": known.text}
end for

// Rules are debug detail too, so they are logged in the order search tries them.
for r in rules
	log.debug "(rule) {Rule}", {"Rule": r.text}
end for

// ── Answering a query ────────────────────────────────────────────────────────
// Backward chaining: a goal is proved by the facts, and by the head of each rule
// whose body can then be proved in turn. The body is what matches facts - childOf
// says "?y is the parent of ?x", which is what a parent fact asserts - and the head
// is the shape of the answer, so substituting a proof's bindings into it gives the
// fact that was proved.
//
// --depth bounds how many rules deep the search may go; 0 means facts only.

// runQuery fact(var("x"), "child-of", var("y"))
runQuery fact("bill", "uncle-of", var("?p"))

finish 0
