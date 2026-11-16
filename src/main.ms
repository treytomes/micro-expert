// micro-expert — a little expert system for MiniScript 2.
//
// Sample command-line options: two string types, two numbers, a repeatable list,
// and a flag. Declaring them here is all it takes — cli.ms parses the arguments
// and generates --help and --version from the same declarations.

import "cli"
import "triples"
import "rules"
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

rule = function(head, body=null)
	"Defines a rule: head is the then-part, body one condition or a list of them."
	if body == null then return rules.Rule.make(head, [])
	if body isa list then return rules.Rule.make(head, body)
	return rules.Rule.make(head, [body])
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
// An imaginary family: Walter and Doris, their three married sons, and the sons'
// one, two and four children. Marriage is recorded once per couple and a rule turns
// it around, while every child has both parents, so a query can start from either
// person. Genders and ages are facts like any other, so a rule can range over them.

facts = [
	// Walter and Doris.
	fact("walter", "has-gender", "male"),
	fact("walter", "has-age", 78),
	fact("doris", "has-gender", "female"),
	fact("doris", "has-age", 76),
	fact("walter", "married-to", "doris"),

	// Their three sons.
	fact("walter", "parent-of", "bill"),
	fact("doris", "parent-of", "bill"),
	fact("walter", "parent-of", "george"),
	fact("doris", "parent-of", "george"),
	fact("walter", "parent-of", "henry"),
	fact("doris", "parent-of", "henry"),
	fact("bill", "has-gender", "male"),
	fact("bill", "has-age", 54),
	fact("george", "has-gender", "male"),
	fact("george", "has-age", 51),
	fact("henry", "has-gender", "male"),
	fact("henry", "has-age", 47),

	// Bill and Susan, with one son.
	fact("bill", "married-to", "susan"),
	fact("susan", "has-gender", "female"),
	fact("susan", "has-age", 52),
	fact("bill", "parent-of", "tim"),
	fact("susan", "parent-of", "tim"),
	fact("tim", "has-gender", "male"),
	fact("tim", "has-age", 24),

	// George and Diane, with a daughter and a son.
	fact("george", "married-to", "diane"),
	fact("diane", "has-gender", "female"),
	fact("diane", "has-age", 49),
	fact("george", "parent-of", "anna"),
	fact("diane", "parent-of", "anna"),
	fact("george", "parent-of", "mark"),
	fact("diane", "parent-of", "mark"),
	fact("anna", "has-gender", "female"),
	fact("anna", "has-age", 21),
	fact("mark", "has-gender", "male"),
	fact("mark", "has-age", 18),

	// Henry and Rachel, with two daughters and two sons.
	fact("henry", "married-to", "rachel"),
	fact("rachel", "has-gender", "female"),
	fact("rachel", "has-age", 45),
	fact("henry", "parent-of", "clara"),
	fact("rachel", "parent-of", "clara"),
	fact("henry", "parent-of", "jack"),
	fact("rachel", "parent-of", "jack"),
	fact("henry", "parent-of", "nina"),
	fact("rachel", "parent-of", "nina"),
	fact("henry", "parent-of", "oliver"),
	fact("rachel", "parent-of", "oliver"),
	fact("clara", "has-gender", "female"),
	fact("clara", "has-age", 15),
	fact("jack", "has-gender", "male"),
	fact("jack", "has-age", 13),
	fact("nina", "has-gender", "female"),
	fact("nina", "has-age", 10),
	fact("oliver", "has-gender", "male"),
	fact("oliver", "has-age", 7),
]

// 'known', not 'fact': a top-level loop variable is a global here, so naming it
// fact would overwrite the fact() shorthand with a triple as soon as the loop ran.
// Facts are debug detail: they are logged, not printed, so a normal run shows the
// answers and --log-level debug shows what they were drawn from.
for known in facts
	log.debug "(fact) {Fact}", {"Fact": known.text}
end for

// (<- (child-of ?x ?y) (parent-of ?y ?x)): if y is a parent of x, x is the child of y.
childOf = rule(
	fact(var("x"), "child-of", var("y")),
	fact(var("y"), "parent-of", var("x")))

// (<- (married-to ?y ?x) (married-to ?x ?y)): marriage is a two-way street, so one
// fact per couple can answer from either side.
marriedBothWays = rule(
	fact(var("y"), "married-to", var("x")),
	fact(var("x"), "married-to", var("y")))

// (<- (sibling-of ?x ?y) (parent-of ?p ?x) (parent-of ?p ?y) (?x != ?y)): two
// people are siblings when they share at least one parent, so half-siblings count
// too, and nobody is their own sibling.
siblingOf = rule(
	fact(var("x"), "sibling-of", var("y")),
	[
		fact(var("p"), "parent-of", var("x")),
		fact(var("p"), "parent-of", var("y")),
		notEqual(var("x"), var("y")),
	])

rules = [childOf, marriedBothWays, siblingOf]

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

runQuery fact(var("x"), "child-of", var("y"))

finish 0
