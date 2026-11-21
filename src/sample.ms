// sample.ms — worked examples: the fixed questions the program used to ask.
//
// main.ms is a session at the prompt now, so the questions it used to ask live here
// and stay runnable. Run this file with the interpreter, or point ENTRY_POINT in .env
// at it to start the runner here:
//
//   miniscript src/sample.ms
//   miniscript src/sample.ms --verbose
//   miniscript src/sample.ms --depth 1
//
// What it does is what any host of the engine does: import triples.ms, build the
// knowledge base with that copy of it, and ask. It declares its own options with the
// same cli library, because --depth and --verbose change what an answer reads like.

import "cli/cli"
import "triples"
import "vt"
import "facts"
import "rules"

cli = globals["cli/cli"]

cmd = cli.newCommand("micro-expert", "0.2.0", "Micro-expert worked examples.")

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
	"default": 0,
	"description": "Print the proof tree behind each answer.",
})

options = cli.parse(cmd, shellArgs)

if options.help then
	print cli.helpText(cmd)
	exit 0
end if

if options.version then
	print cli.versionLine(cmd)
	exit 0
end if

if not options.ok then
	print "error: " + options.error
	print "Run " + cmd.name + " --help for usage."
	exit 1
end if

depth = options.values.depth
verbose = options.values.verbose

// ── Shorthands ───────────────────────────────────────────────────────────────
// Globals, so the questions at the bottom read the way the facts are written.

fact = function(subject, predicate, object)
	"Builds a Subject-Predicate-Object triple."
	return triples.SpoTriple.make(subject, predicate, object)
end function

var = function(name)
	"Builds a logic variable, e.g. var(""x"") for ?x."
	return triples.Var.make(name)
end function

// ── Report colors ────────────────────────────────────────────────────────────
// The missing-fact report paints its parts through the bundled vt module: one color
// for the facts it asks for, one for the rule that would use them, and dimmed
// variables inside the facts. NO_COLOR (https://no-color.org) turns every escape
// code off, so a redirected run stays plain text.

style = null
if not env.hasIndex("NO_COLOR") then
	style = {
		"warning": vt.textColor(vt.color.red),
		"fact": vt.textColor(vt.color.aqua),
		"rule": vt.textColor(vt.color.olive),
		"var": vt.dim,
		"note": vt.dim,
		"normal": vt.normal,
	}
end if

// ── Facts and rules ──────────────────────────────────────────────────────────
// Both files build their arrays on request and are handed this file's copy of
// triples.ms, because a module that imports it gets a copy of its own, and the solver
// only recognizes triples from the copy it holds.

facts = globals["facts"].build(triples)
if facts isa error then
	print "error: " + facts.message
	exit 1
end if
rules = globals["rules"].build(triples)
if rules isa error then
	print "error: " + rules.message
	exit 1
end if

// ── Answering a query ────────────────────────────────────────────────────────
// Backward chaining: a goal is proved by the facts, and by the head of each rule
// whose body can then be proved in turn. --depth bounds how many rules deep the
// search may go; 0 means facts only.

runQuery = function(query)
	"Prints every answer to a question, or the report of the facts one would need."
	print "Query: " + query.text
	proofs = triples.proveGoals(query, facts, rules, depth)
	// A quiet empty answer set is a dead end: say so, and say which facts would
	// turn it into an answer, so the missing knowledge is the result.
	if proofs.len == 0 then
		print triples.paint(style, "warning", "  no solution found at depth " + depth)
		for line in triples.neededFactLines(query, facts, rules, depth, style)
			print line
		end for
		return
	end if
	for proof in proofs
		// The answer is said rather than shown: the predicate's dashes are the spaces of the
		// sentence, so the query prints a line of English under its own aim. --verbose hangs
		// the proof tree under that sentence rather than printing it in the sentence's place.
		print "  " + triples.substitute(query, proof.binds).sentence
		if verbose then
			for line in triples.proofLines(proof, "  ")
				print line
			end for
		end if
	end for
end function

// ── The examples ─────────────────────────────────────────────────────────────
// A predicate reads "?x is the relation of ?y", so the variable goes where the
// unknown is: is-uncle-of(bill, ?p) asks who Bill is an uncle of. The lines above that
// are commented out are the other shapes worth reading: no variables in the subject,
// none in the object, and one in each.

// runQuery fact(var("x"), "is-child-of", var("y"))
// runQuery fact("bill", "is-uncle-of", var("?p"))
// runQuery fact(var("?p"), "is-parent-of", "susan")
runQuery fact("susan", "is-parent-of", var("?p"))
runQuery fact(var("?p"), "is-grandpa-of", "susan")
runQuery fact(var("?p"), "is-uncle-of", "susan")
