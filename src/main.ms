// micro-expert — a little expert system for MiniScript 2.
//
// Sample command-line options: two string types, two numbers, a repeatable list,
// and a flag. Declaring them here is all it takes — cli.ms parses the arguments
// and generates --help and --version from the same declarations.

import "cli"
import "triples"
import "rules"

// ── Triples ──────────────────────────────────────────────────────────────────
// Shorthands for the two triplet types and logic variables; the classes live in
// triples.ms so the program shares one copy of each and `isa` checks agree.

spo = function(subject, predicate, object)
	"Builds a Subject-Predicate-Object triple."
	return triples.SpoTriple.make(subject, predicate, object)
end function

oav = function(object, attribute, value)
	"Builds an Object-Attribute-Value triplet."
	return triples.OavTriple.make(object, attribute, value)
end function

var = function(name)
	"Builds a logic variable, e.g. var(""x"") for ?x."
	return triples.Var.make(name)
end function

// ── Rules ────────────────────────────────────────────────────────────────────

rule = function(head, body=null)
	"Defines a rule: head is the then-part, body one condition or a list of them."
	if body == null then return rules.Rule.make(head, [])
	if body isa list then return rules.Rule.make(head, body)
	return rules.Rule.make(head, [body])
end function

cmd = cli.newCommand("micro-expert", "0.1.0", "A little expert system for MiniScript 2.")
cli.add(cmd, {
	"name": "facts",
	"aliases": ["--facts", "-f"],
	"type": "string",
	"description": "A facts file to load.",
})
cli.add(cmd, {
	"name": "rules",
	"aliases": ["--rules", "-r"],
	"type": "string",
	"description": "A rules file to load.",
})
cli.add(cmd, {
	"name": "query",
	"aliases": ["--query"],
	"type": "string",
	"description": "Prove this goal, print the answer, and exit.",
})
cli.add(cmd, {
	"name": "depth",
	"aliases": ["--depth"],
	"type": "number",
	"default": 8,
	"description": "Maximum backward-chaining depth.",
})
cli.add(cmd, {
	"name": "confidence",
	"aliases": ["--confidence"],
	"type": "number",
	"default": 0.6,
	"description": "Minimum confidence for an answer to count.",
})
cli.add(cmd, {
	"name": "include",
	"aliases": ["--include", "-I"],
	"type": "list",
	"description": "An extra file or folder to search; may be repeated.",
})
cli.add(cmd, {
	"name": "verbose",
	"aliases": ["--verbose"],
	"type": "flag",
	"description": "Print extra progress detail.",
})

options = cli.parse(cmd, shellArgs)

if options.help then
	print cli.helpText(cmd)
	exit
end if

if options.version then
	print cli.versionLine(cmd)
	exit
end if

if not options.ok then
	print "error: " + options.error
	print "Run " + cmd.name + " --help for usage."
	exit 1
end if

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

print "Parsed options:"
for option in cmd.options
	print "  " + option.name + ":" + " " * (width - option.name.len + 2) + showValue(options.values[option.name])
end for

if options.values.query != null then
	print ""
	print "Query: " + options.values.query
end if

if options.values.verbose then
	print ""
	print "Verbose run: depth " + options.values.depth + ", confidence " + options.values.confidence
end if

print oav("bill", "gender", "male").text
print oav("susan", "gender", "female").text
print oav("tim", "gender", "male").text
print spo("bill", "parent", "susan").text
print spo("susan", "parent", "tim").text

// (<- (child ?x ?y) (parent ?y ?x)): if y is the parent of x, x is the child of y.
childOf = rule(
	spo(var("x"), "child", var("y")),
	spo(var("y"), "parent", var("x")))
print childOf.text


