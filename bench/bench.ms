// bench/bench.ms — times the queries a speedup is measured against.
//
// Run from the project root:
//
//   "3rd-party/miniscript-win/miniscript.exe" bench/bench.ms
//
// Each query runs one untimed warm-up and then `benchRuns` timed runs. Quote the median:
// this machine's timings swing by tens of percent run to run, and a single pass is not
// evidence. The depth is the program's default, and the answer counts are printed beside
// the times, so a change that alters what the solver finds shows up as well as one that
// alters how long it takes.
//
// The last line of setup is what lets a script outside src/ load the program at all: the
// interpreter resolves bare imports against the entry script's own folder, and rules.ms
// imports rule that way, so src/ goes on the search path first.

env["MS_IMPORT_PATH"] = "src"

import "triples"
import "facts"
import "rules"

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

benchDepth = 8
benchRuns = 6

padRight = function(text, width)
	"text, then spaces, so a column lines up."
	padding = width - text.len
	if padding <= 0 then return text
	return text + " " * padding
end function

millis = function(value)
	"One decimal place: the digit after it is the noise floor here."
	return round(value * 10) / 10
end function

query = function(subject, predicate, object)
	"One triple to prove, with '?x' fields made into variables."
	return triples.SpoTriple.make(subject, predicate, object)
end function

timeOnce = function(goal)
	"One proveGoals call in milliseconds, and how many answers it found."
	t0 = time
	answers = triples.proveGoals(goal, facts, rules, benchDepth)
	return {"ms": (time - t0) * 1000, "answers": answers.len}
end function

report = function(label, goal)
	"Times one query and prints its answer count, minimum, median and maximum."
	timeOnce(goal)
	samples = []
	answers = 0
	for attempt in range(1, benchRuns)
		timed = timeOnce(goal)
		samples.push timed.ms
		answers = timed.answers
	end for
	samples.sort
	print padRight(label, 24) + padRight(str(answers), 9) +
		padRight(str(millis(samples[0])), 9) +
		padRight(str(millis(samples[floor(samples.len / 2)])), 9) +
		str(millis(samples[-1]))
end function

print "depth " + benchDepth + ", " + benchRuns + " runs after a warm-up; milliseconds"
print ""
print padRight("query", 24) + padRight("answers", 9) + padRight("min", 9) +
	padRight("median", 9) + "max"

// A fact-level answer, a rule chain, and the deep one the solver was profiled against.
report "parent-of(susan, ?p)", query("susan", "parent-of", triples.var("p"))
report "grandpa-of(?p, ?y)", query(triples.var("p"), "grandpa-of", triples.var("y"))
report "uncle-of(bill, ?p)", query("bill", "uncle-of", triples.var("p"))
