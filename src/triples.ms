// triples.ms — the terms, the triple, and the reasoner over them.
//
// The classes live together on purpose: a module that imports another module gets
// its own copy of it, and each copy carries its own class maps, so `isa` would
// fail against a SpoTriple built in a different copy. One module, one class each.
//
//   import "triples"
//   spo = triples.SpoTriple.make("trey", "avoids", "gluten")
//   print spo.text                          // avoids(trey, gluten)
//   print triples.SpoTriple.parse("avoids(trey, gluten)").text   // reads back
//   print triples.SpoTriple.parse("trey | avoids | gluten").text // same triple
//   print triples.SpoTriple.make(triples.var("x"), "child", triples.var("y")).text
//   // child(?x, ?y)
//   print triples.unify(triples.SpoTriple.parse("child(?x, ?y)"),
//       triples.SpoTriple.parse("child(susan, bill)"))   // {"x": "susan", "y": "bill"}

// ── List combinators ─────────────────────────────────────────────────────────
// Small list operations, so the functions below can say what they do with a list
// rather than walk it. mapWith hands each item and one shared argument to f.

mapWith = function(items, f, arg=null)
	"One result per item, in order; f takes the item and the argument."
	results = []
	for item in items
		results.push(f(item, arg))
	end for
	return results
end function

// ── Var: a logic variable, written ?x ────────────────────────────────────────

Var = {}

Var.make = function(name)
	"Builds a logic variable; 'x' and '?x' both name ?x."
	if name[:1] == "?" then name = name[1:]
	v = new Var
	v.name = name
	return v
end function

Var.text = function
	"Formats the variable as '?name'."
	return "?" + self.name
end function

var = function(name)
	"Shorthand for Var.make, for use inside triple fields."
	return Var.make(name)
end function

termText = function(term)
	"Renders one term: a Var as '?x', anything else as it is."
	if term isa Var then return term.text
	return term
end function

// ── SpoTriple: subject, predicate, object ─────────────────────────────────────

SpoTriple = {}

SpoTriple.make = function(subject, predicate, object)
	"Builds a triple from its subject, predicate, and object."
	t = new SpoTriple
	t.subject = subject
	t.predicate = predicate
	t.object = object
	return t
end function

SpoTriple.parse = function(line)
	"Parses 'predicate(subject, object)' or 'subject | predicate | object'; '?x' fields become Vars."
	fields = parseLine(line)
	if fields isa error then return fields
	// A predicate that cannot be said is refused with the line it came on, here and not
	// later: this is the one reader a typed fact, question or rule comes through.
	if fields[1] isa string then
		problem = predicateProblem(fields[1])
		if problem != null then return err(problem + ": " + line)
	end if
	return SpoTriple.make(fields[0], fields[1], fields[2])
end function

SpoTriple.text = function
	"Formats the triple for display as 'predicate(subject, object)'."
	return termText(self.predicate) + "(" + termText(self.subject) + ", " +
		termText(self.object) + ")"
end function

SpoTriple.parts = function
	"Returns the triple as the list [subject, predicate, object]."
	return [self.subject, self.predicate, self.object]
end function

SpoTriple.sentence = function
	"Formats the triple as a sentence, 'oliver has uncle zed': the predicate's dashes read as spaces."
	// A variable predicate is not a name, so the triple keeps the fact form that shows
	// the variable itself rather than inventing a word for it.
	if not (self.predicate isa string) then return self.text
	return termText(self.subject) + " " + self.predicate.split("-").join(" ") + " " +
		termText(self.object)
end function

// ── Predicate names ──────────────────────────────────────────────────────────
// A predicate is written in lower case as sections joined by '-', each section letters
// and digits, and the first section starting with a letter: is-parent-of, has-1-child,
// married-to. Nothing in the search depends on that - the shape is what makes a result
// sayable, since a sentence is the name with its dashes opened to spaces - so a name that
// is not one is refused where the line is read, and the knowledge base holds only names a
// result can say. knowledge.ms checks the same rule on the data files and the schema.
//
// A variable is not a name: ?p(susan, tim) asks what relates the two, and there is
// nothing yet to say.

predicateProblem = function(name)
	"Says what is wrong with a predicate name, as 'a predicate starts with a letter', or null when it is one."
	// A variable is not a name: ?p(susan, tim) asks what relates the two.
	if name[:1] == "?" then return null
	sections = name.split("-")
	for at in range(0, sections.len - 1)
		section = sections[at]
		// Every dash separates two sections, so each one has to be there.
		if section == "" then return "a predicate is sections joined by '-', and none is empty"
		for c in section
			// A name is lower case, so the letters stop at z: an upper-case one is refused here.
			if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")) then
				return "a predicate is lower-case letters and digits, joined by '-'"
			end if
		end for
		// A leading digit would read as a number, so the name starts with a letter and
		// only the sections after it may open with one.
		if at == 0 and section[0] >= "0" and section[0] <= "9" then
			return "a predicate starts with a letter"
		end if
	end for
	return null
end function

// ── Unification ───────────────────────────────────────────────────────────────

// Bindings are extended, never edited: every step returns a new map, so a match
// that fails partway leaves the caller's bindings alone and no defensive copy is
// needed anywhere above.

copyBinds = function(binds)
	"Returns a copy of a bindings map; null becomes an empty map."
	if binds == null then return {}
	return binds + {}
end function

withBinding = function(binds, name, value)
	"A copy of the bindings with one entry added or replaced - never the map itself."
	copied = copyBinds(binds)
	copied[name] = value
	return copied
end function

unify = function(pattern, fact, binds=null)
	"Unifies a pattern against a fact, returning the bindings it adds, or null."
	working = copyBinds(binds)
	if pattern isa SpoTriple then
		if not (fact isa SpoTriple) then return null
		return unifyParts(pattern.parts, fact.parts, working)
	end if
	matches = unifyTerms(pattern, fact, working)
	if matches == null then return null
	return resolveBindings(matches)
end function

unifyParts = function(leftParts, rightParts, binds)
	"Unifies the fields of two triples in turn, left to right; resolved when done."
	if leftParts.len == 0 then return resolveBindings(binds)
	extended = unifyTerms(leftParts[0], rightParts[0], binds)
	if extended == null then return null
	return unifyParts(leftParts[1:], rightParts[1:], extended)
end function

unifyTerms = function(left, right, binds)
	"The bindings extended so the two terms agree, or null when they cannot."
	left = deref(left, binds)
	right = deref(right, binds)
	if left == right then return binds
	if left isa Var then return withBinding(binds, left.name, right)
	if right isa Var then return withBinding(binds, right.name, left)
	return null
end function

deref = function(term, binds)
	"Follows bindings until a non-variable or an unbound variable."
	if not (term isa Var) then return term
	// No bindings yet means nothing is bound, so the variable derefs to itself. The top
	// level of a query derefs a goal's predicate with null binds (candidateFacts,
	// predicatesMeet), and only a variable predicate ever reaches this line.
	if binds == null then return term
	if not binds.hasIndex(term.name) then return term
	return deref(binds[term.name], binds)
end function

resolveBindings = function(binds)
	"Resolves every binding through the others, so no value is a bound variable."
	resolved = {}
	for name in binds.indexes
		resolved[name] = deref(binds[name], binds)
	end for
	return resolved
end function

substitute = function(term, binds)
	"Applies bindings: a new triple with resolved fields, or the resolved term."
	if binds == null then return term
	if term isa SpoTriple then
		return SpoTriple.make(deref(term.subject, binds), deref(term.predicate, binds),
			deref(term.object, binds))
	end if
	return deref(term, binds)
end function

// ── Constraints ──────────────────────────────────────────────────────────────
// A rule body is a list of goals, and it may also hold constraints: conditions that are
// checked against the bindings rather than proved by search. They are written as calls
// like everything else - not-equal(?x, ?y), equal(?n, 18), less-than-or-equal(?n, 18),
// years-since(?b, ?n) - and their names are reserved, so no fact and no question can use one
// as a predicate.

// not-equal and equal read their two terms as they are, whatever type they hold: not-equal
// asks that they differ, equal that they are the same one. Their names are reserved like a
// comparison's: a term never means "check this" in a body and "assert this" as a fact.
//
// equal is the one constraint that can bind. The others only agree or disagree with what the
// conditions before them settled; equal settles a side that is still a variable, so a body
// may write equal(?n, 18) before anything has bound ?n and go on with ?n as 18.
notEqualName = "not-equal"
equalName = "equal"

NotEqual = {}

NotEqual.make = function(left, right)
	"Builds a 'these two terms must differ' constraint."
	c = new NotEqual
	c.left = left
	c.right = right
	return c
end function

NotEqual.text = function
	"Says how the constraint reads: not-equal(?x, ?y)."
	return notEqualName + "(" + termText(self.left) + ", " + termText(self.right) + ")"
end function

Equal = {}

Equal.make = function(left, right)
	"Builds a 'these two terms must be the same one' constraint."
	c = new Equal
	c.left = left
	c.right = right
	return c
end function

Equal.text = function
	"Says how the constraint reads: equal(?x, ?y)."
	return equalName + "(" + termText(self.left) + ", " + termText(self.right) + ")"
end function

// A comparison is the one constraint that reads its terms arithmetically. Text would
// put "9" after "18", and MiniScript will not compare a string with a number at all,
// so a side that is not a number ends the branch rather than passing for a zero.

// A comparison is written as a call, like every other condition in a body, so the format
// keeps one shape: less-than-or-equal(?n, 18). The names are words, as the predicates
// are, and the symbol each stands for is what the check reads.
comparisonNames = {
	"less-than": "<",
	"less-than-or-equal": "<=",
	"greater-than": ">",
	"greater-than-or-equal": ">=",   // this comma is required: the entry ends the line
}

Comparison = {}

Comparison.make = function(symbol, left, right)
	"Builds a numeric comparison: two terms, and the order they must stand in."
	c = new Comparison
	c.symbol = symbol
	c.left = left
	c.right = right
	return c
end function

Comparison.text = function
	"Says how the comparison reads: less-than-or-equal(?n, 18)."
	return comparisonCall(self.symbol) + "(" + termText(self.left) + ", " + termText(self.right) + ")"
end function

comparisonCall = function(symbol)
	"Names a symbol the way a body writes it: '<=' is less-than-or-equal."
	for name in comparisonNames.indexes
		if comparisonNames[name] == symbol then return name
	end for
	return symbol
end function

// years-since is the one constraint that computes: it reads a date and the whole years
// between it and the day the search runs, and binds the side that is still a variable. It is
// what lets a rule work out a value, which the goals alone cannot do - a goal proves a fact,
// and a comparison only reads numbers that are already there. An age is one use of it, a
// birthdate being a date like any other.
//
// The day is the host's today unless a caller pins one, which is what the suite does so a
// check cannot quietly change on somebody's birthday:
//
//   triples.today = {"year": 2019, "month": 4, "day": 1}

sinceName = "years-since"

today = null

dayToday = function
	"The day an age is counted from: the one a caller pinned, or the host's today."
	if today != null then return today
	parts = _dateStr(_dateVal, "yyyy-MM-dd").split("-")
	return {"year": val(parts[0]), "month": val(parts[1]), "day": val(parts[2])}
end function

yearsSince = function(text, on)
	"The whole years from a yyyy-MM-dd date to a day, or null when that is not a date or it has not arrived yet."
	if not (text isa string) then return null
	parts = text.split("-")
	if parts.len != 3 then return null
	if parts[0].len != 4 or parts[1].len != 2 or parts[2].len != 2 then return null
	if not digitsOnly(parts[0]) or not digitsOnly(parts[1]) or not digitsOnly(parts[2]) then return null
	year = val(parts[0])
	month = val(parts[1])
	day = val(parts[2])
	// The calendar is read here rather than by the host, whose dates begin in 1970 and
	// would roll 2019-02-30 forward like any other impossible day.
	if year < 1 or month < 1 or month > 12 then return null
	if day < 1 or day > daysInMonth(year, month) then return null
	years = on.year - year
	if on.month < month or (on.month == month and on.day < day) then years = years - 1
	if years < 0 then return null
	return years
end function

digitsOnly = function(text)
	"Says whether every character is a decimal digit."
	for c in text
		if "0123456789".indexOf(c) == null then return false
	end for
	return true
end function

daysInMonth = function(year, month)
	"How many days a calendar month has, February counting its leap day."
	if month == 2 then
		if leapYear(year) then return 29
		return 28
	end if
	if month == 4 or month == 6 or month == 9 or month == 11 then return 30
	return 31
end function

leapYear = function(year)
	"Every fourth year, but not every hundredth, except every four hundredth."
	if year % 4 != 0 then return false
	if year % 100 != 0 then return true
	return year % 400 == 0
end function

YearsSince = {}

YearsSince.make = function(date, years)
	"Builds a 'this date is this many years before the day the search runs' constraint."
	c = new YearsSince
	c.date = date
	c.years = years
	return c
end function

YearsSince.text = function
	"Says how the constraint reads: years-since(2019-04-01, ?n)."
	return sinceName + "(" + termText(self.date) + ", " + termText(self.years) + ")"
end function

yearsSinceBinds = function(constraint, binds)
	"The bindings that make the years the date's, or null when the branch ends."
	date = substitute(constraint.date, binds)
	wanted = substitute(constraint.years, binds)
	years = yearsSince(date, dayToday())
	if years == null then return null
	if wanted isa Var then return unifyTerms(constraint.years, years, binds)
	if not (wanted isa number) then return null
	if wanted != years then return null
	return binds
end function

isConstraint = function(term)
	"Says whether a term names a constraint, which a body checks rather than a line storing or asking it."
	if not (term isa string) then return false
	return term == notEqualName or term == equalName or term == sinceName or
		comparisonNames.hasIndex(term) != 0
end function

comparisonHolds = function(constraint, binds)
	"Says whether a comparison holds: both sides must be numbers, so another type cannot slip through as zero."
	left = substitute(constraint.left, binds)
	right = substitute(constraint.right, binds)
	if not (left isa number) or not (right isa number) then return false
	if constraint.symbol == "<=" then return left <= right
	if constraint.symbol == ">=" then return left >= right
	if constraint.symbol == "<" then return left < right
	return left > right
end function

holdsConstraint = function(constraint, binds)
	"Says whether a constraint holds under the current bindings."
	if constraint isa Comparison then return comparisonHolds(constraint, binds)
	if constraint isa NotEqual then
		return substitute(constraint.left, binds) != substitute(constraint.right, binds)
	end if
	return false
end function

// equal is applied rather than checked: unifying its two terms returns the bindings the
// equality extends, and null when they cannot agree. unifyTerms already reads two terms the
// one way equal needs - the same value holds, and a variable takes the other side's - so an
// equal is exactly one unification whose bindings are kept.

equalBinds = function(constraint, binds)
	"The bindings that make the two terms the same one, or null when they cannot be."
	return unifyTerms(constraint.left, constraint.right, binds)
end function

applyConstraint = function(constraint, binds)
	"The bindings a constraint leaves, or null when the branch ends: the ones it was given, unless it bound something."
	if constraint isa Equal then return equalBinds(constraint, binds)
	if constraint isa YearsSince then return yearsSinceBinds(constraint, binds)
	if holdsConstraint(constraint, binds) then return binds
	return null
end function

// ── Proof search ─────────────────────────────────────────────────────────────

// proveGoals answers a goal, proveConditions proves a rule body, and the two
// records they pass around have these shapes:
//
//   answer = {"goal": SpoTriple, "binds": map, "reasons": [reason]}
//   reason = {"rule": Rule or null, "conditions": [answer]}
//   results = {"list": [answer], "byText": {rendered goal: answer}}
//
// An answer keeps every way it was proved; a reason is one of them - a fact when
// rule is null, otherwise the rule plus the answers that proved its conditions.
// A results record gathers answers in order and by rendered goal, so a goal that
// is proved several ways still appears once.

// ── Alternatives ─────────────────────────────────────────────────────────────
// A condition is usually one triple, and sometimes a constraint. It can also be a
// choice: or(...) holds one body per alternative, and any one of them settles what
// the condition asks. Each alternative is a list of conditions, so or(...) nests in
// a body the way and(...) does, and may hold and(...) as one of its alternatives.
//
// A not(...) is the other grouping. It holds one body, and the condition holds when that
// body has no proof at all - it says what the facts do not, as in "nobody is ?x's
// sibling". It binds nothing and adds no step to a proof, because an absence has no
// derivation to show, only a search that came back empty.

Or = {}

Or.make = function(alternatives)
	"Builds an 'any one of these bodies holds' condition."
	o = new Or
	o.alternatives = alternatives
	return o
end function

Or.text = function
	"Reads as or(a, b), with and(...) around an alternative that holds several conditions."
	parts = []
	for alternative in self.alternatives
		parts.push(alternativeText(alternative))
	end for
	return "or(" + parts.join(", ") + ")"
end function

alternativeText = function(conditions)
	"One body as it reads: its one condition, or and(...) around several."
	texts = []
	for condition in conditions
		texts.push(condition.text)
	end for
	if texts.len == 1 then return texts[0]
	return "and(" + texts.join(", ") + ")"
end function

Not = {}

Not.make = function(body)
	"Builds a 'this body has no proof' condition."
	n = new Not
	n.body = body
	return n
end function

Not.text = function
	"Reads as not(a), with and(...) around a body that holds several conditions."
	return "not(" + alternativeText(self.body) + ")"
end function

renameCounter = {"uses": 0}

uniqueSuffix = function()
	"A suffix no other rule use has had, so one use cannot shadow another."
	renameCounter.uses = renameCounter.uses + 1
	return "_" + renameCounter.uses
end function

renameTerm = function(term, suffix)
	"Copies a term, renaming every variable: ?x becomes ?x_3."
	if term isa Var then return var(term.name + suffix)
	return term
end function

renameTriple = function(triple, suffix)
	"Copies a triple, renaming the variables in its fields."
	if triple isa SpoTriple then
		return SpoTriple.make(renameTerm(triple.subject, suffix),
			renameTerm(triple.predicate, suffix), renameTerm(triple.object, suffix))
	end if
	return triple
end function

renameConstraint = function(constraint, suffix)
	"Copies a constraint, renaming the variables it mentions."
	if constraint isa YearsSince then
		return YearsSince.make(renameTerm(constraint.date, suffix),
			renameTerm(constraint.years, suffix))
	end if
	if constraint isa Equal then
		return Equal.make(renameTerm(constraint.left, suffix),
			renameTerm(constraint.right, suffix))
	end if
	if constraint isa Comparison then
		return Comparison.make(constraint.symbol, renameTerm(constraint.left, suffix),
			renameTerm(constraint.right, suffix))
	end if
	if constraint isa NotEqual then
		return NotEqual.make(renameTerm(constraint.left, suffix),
			renameTerm(constraint.right, suffix))
	end if
	return constraint
end function

standardizeApart = function(candidate)
	"A fresh {head, body} copy of a rule, safe to use alongside other uses of it."
	suffix = uniqueSuffix()
	return {"head": renameTriple(candidate.head, suffix),
		"body": renameConditions(candidate.body, suffix)}
end function

renameConditions = function(conditions, suffix)
	"Every condition renamed, in order."
	return mapWith(conditions, @renameCondition, suffix)
end function

renameCondition = function(condition, suffix)
	"One condition renamed: a goal as a triple, a grouping by its body, a constraint as it is."
	if condition isa Not then return Not.make(renameConditions(condition.body, suffix))
	if condition isa Or then
		alternatives = []
		for alternative in condition.alternatives
			alternatives.push(renameConditions(alternative, suffix))
		end for
		return Or.make(alternatives)
	end if
	if condition isa SpoTriple then return renameTriple(condition, suffix)
	return renameConstraint(condition, suffix)
end function

canonicalText = function(triple)
	"Renders a triple with its variables numbered by first appearance, so goals that differ only in variable names render the same."
	return canonicalLabels(triple.parts, {}).join("|")
end function

canonicalLabels = function(parts, names)
	"One label per field, numbering each variable the first time it is seen."
	return mapWith(parts, @canonicalLabel, names)
end function

canonicalLabel = function(part, names)
	"One field's label: ?N for a variable, the field itself for anything else."
	if not (part isa Var) then return part
	if names.hasIndex(part.name) == 0 then names[part.name] = "?" + (names.len + 1)
	return names[part.name]
end function

goalKey = function(goal, binds)
	"Identifies a goal as it stands under the current bindings, for loop detection."
	grounded = substitute(goal, binds)
	if grounded isa SpoTriple then return canonicalText(grounded)
	return str(termText(grounded))
end function

proveGoals = function(goal, facts, rules, depth, binds=null, open=null, index=null)
	"Every answer to goal, at most depth rules deep, each with all its derivations; open is the chain of goals being proved, so a loop stops that branch, and index is the facts by predicate, built once and handed down."
	if index == null then index = factsByPredicate(facts)
	path = enterGoal(goal, binds, open)
	if path == null then return []
	results = emptyResults()
	// A fact is a derivation on its own; a rule is one derivation per way its body
	// proves, so both are collected from their matches and merged the same way.
	for matched in matchingFacts(goal, facts, binds, index)
		mergeAnswer(results, goal, matched, {"rule": null, "conditions": []})
	end for
	if depth <= 0 then return results.list
	for candidate in matchingRules(goal, rules, binds)
		for proved in proveConditions(candidate.body, facts, rules, depth - 1, candidate.binds,
			path, index)
			mergeAnswer(results, goal, proved.binds, {"rule": candidate.rule, "conditions": proved.proofs})
		end for
	end for
	return results.list
end function

emptyResults = function()
	"Where answers gather: the list in order, and the same answers by rendered goal."
	return {"list": [], "byText": {}}
end function

enterGoal = function(goal, binds, open)
	"The chain of goals being proved with this one added, or null when it is already on it."
	if open == null then open = {}
	key = goalKey(goal, binds)
	if open.hasIndex(key) then return null
	// A new map, so one branch's ancestors do not prune its siblings.
	return withBinding(open, key, 1)
end function

// A ground predicate can only meet the same one, so those pairs are ruled out before
// anything is copied or unified: standardizeApart builds a fresh copy of every rule it
// is handed, and unifying predicates that cannot agree settles nothing.

predicatesMeet = function(goal, triple, binds)
	"Says whether a goal and a candidate could still agree on their predicates."
	wanted = deref(goal.predicate, binds)
	if wanted isa Var then return true
	// The candidate's variables are renamed before it is used, so they are not this
	// goal's to resolve through its bindings; a variable predicate there meets anything.
	if triple.predicate isa Var then return true
	return wanted == triple.predicate
end function

// A goal whose subject or object has been settled can only be met by a candidate
// carrying that same one. Comparing two fields costs a fraction of the unification it
// can replace, so it happens first. The check is one-sided: a variable anywhere - in
// the goal or in the candidate - can still meet anything.

settledTerm = function(term, binds)
	"The term once the bindings are applied, or null while it is still a variable."
	if not (term isa Var) then return term
	if binds == null then return null
	value = deref(term, binds)
	if value isa Var then return null
	return value
end function

meetsSettled = function(wanted, candidate)
	"Says whether a settled field could still agree with a candidate's."
	if candidate isa Var then return true
	return wanted == candidate
end function

fieldsMeet = function(goal, triple, binds)
	"Says whether the goal's subject and object could still agree with a candidate's."
	wanted = settledTerm(goal.subject, binds)
	if wanted != null then
		if not meetsSettled(wanted, triple.subject) then return false
	end if
	wanted = settledTerm(goal.object, binds)
	if wanted != null then
		if not meetsSettled(wanted, triple.object) then return false
	end if
	return true
end function

// Looking at every fact for every goal is most of what a query costs, and most of
// those looks are hopeless: a goal names one predicate, so only the facts carrying
// it can answer. They are grouped by predicate once per query and handed down, and
// a goal whose predicate is still a variable - or a knowledge base holding a fact
// with a variable predicate - falls back to the whole list.

factsByPredicate = function(facts)
	"The facts grouped by their predicate, or null when one of them has a variable predicate and so could meet any goal."
	index = {}
	for fact in facts
		if fact.predicate isa Var then return null
		if index.hasIndex(fact.predicate) then
			index[fact.predicate].push(fact)
		else
			index[fact.predicate] = [fact]
		end if
	end for
	return index
end function

candidateFacts = function(goal, facts, binds, index)
	"The facts worth trying for this goal: the ones with its predicate, or all of them when that is not settled."
	if index == null then return facts
	wanted = deref(goal.predicate, binds)
	if wanted isa Var then return facts
	if index.hasIndex(wanted) == 0 then return []
	return index[wanted]
end function

matchingFacts = function(goal, facts, binds, index=null)
	"The bindings of every fact that meets the goal, in order."
	matches = []
	for fact in candidateFacts(goal, facts, binds, index)
		if not predicatesMeet(goal, fact, binds) then continue
		if not fieldsMeet(goal, fact, binds) then continue
		matched = unify(goal, fact, binds)
		if matched != null then matches.push(matched)
	end for
	return matches
end function

matchingRules = function(goal, rules, binds)
	"Every rule whose head meets the goal: the rule, a fresh copy of its body, and the bindings."
	matches = []
	for candidate in rules
		if not predicatesMeet(goal, candidate.head, binds) then continue
		fresh = standardizeApart(candidate)
		matched = unify(fresh.head, goal, binds)
		if matched != null then
			matches.push({"rule": candidate, "body": fresh.body, "binds": matched})
		end if
	end for
	return matches
end function

proveConditions = function(conditions, facts, rules, depth, binds, open=null, index=null)
	"Proves each condition in turn: a goal by search, a constraint by checking or binding, or(...) by one alternative, and not(...) by finding no proof."
	// Any one alternative settles the choice, and the rest of the body follows it,
	// so every way through an alternative is a way through the body.
	if conditions.len > 0 and (conditions[0] isa Or) then
		results = []
		for alternative in conditions[0].alternatives
			for proved in proveConditions(alternative + conditions[1:], facts, rules, depth,
				binds, open, index)
				results.push(proved)
			end for
		end for
		return results
	end if
	// A negation is met exactly when the body it holds has no proof, so one proof ends
	// the branch. It binds nothing and proves nothing, so it adds no step to the tree.
	if conditions.len > 0 and (conditions[0] isa Not) then
		if proveConditions(conditions[0].body, facts, rules, depth, binds, open, index).len > 0 then
			return []
		end if
		return proveConditions(conditions[1:], facts, rules, depth, binds, open, index)
	end if
	if conditions.len == 0 then return [{"binds": binds, "proofs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint either holds or the branch ends; it proves nothing, so it
		// contributes no proof to the tree. equal can also bind, and what it leaves is
		// what the conditions after it are judged against.
		settled = applyConstraint(first, binds)
		if settled == null then return []
		return proveConditions(conditions[1:], facts, rules, depth, settled, open, index)
	end if
	results = []
	for proved in proveGoals(first, facts, rules, depth, binds, open, index)
		for rest in proveConditions(conditions[1:], facts, rules, depth, proved.binds, open,
			index)
			results.push({"binds": rest.binds, "proofs": [proved] + rest.proofs})
		end for
	end for
	return results
end function

mergeAnswer = function(results, goal, binds, reason)
	"One entry per answer, holding every way that answer was proved."
	key = substitute(goal, binds).text
	if results.byText.hasIndex(key) == 0 then
		results.byText[key] = {"goal": goal, "binds": binds, "reasons": []}
		results.list.push(results.byText[key])
	end if
	results.byText[key].reasons.push(reason)
end function

speak = function(triple, nlp=0)
	"Says a triple in the form a run asked for: the sentence it reads as when nlp is on, and the fact it is otherwise."
	if nlp then return triple.sentence
	return triple.text
end function

reasonText = function(reason, nlp=0)
	"Where one derivation came from: a fact, or the rule that concluded it - said as sentences when nlp asks for them."
	if reason.rule == null then return "fact"
	if nlp then return "rule " + nlRuleText(reason.rule)
	return "rule " + reason.rule.text
end function

nlRuleText = function(rule)
	"Says a rule the way its parts answer: the head as a sentence, and so each triple of its body - a constraint has no sentence, so it keeps the form it is written in."
	conditions = []
	for condition in rule.body
		if condition isa SpoTriple then
			conditions.push(condition.sentence)
		else
			conditions.push(condition.text)
		end if
	end for
	if conditions.len == 0 then return rule.head.sentence + " <- (no conditions)"
	return rule.head.sentence + " <- " + conditions.join(", ")
end function

proofLines = function(answer, indent="", nlp=0)
	"Describes every derivation of an answer, with the conditions behind each, said as sentences when nlp asks for them."
	lines = []
	appendDerivations(answer.goal, answer.binds, answer.reasons, indent, lines, nlp)
	return lines
end function

appendDerivations = function(goal, binds, reasons, indent, lines, nlp=0)
	"Appends each derivation's line, then the block behind each of its conditions."
	for reason in reasons
		lines.push(indent + speak(substitute(goal, binds), nlp) + "  <- " + reasonText(reason, nlp))
		appendConditions(reason.conditions, indent + "  ", lines, nlp)
	end for
end function

appendConditions = function(conditions, indent, lines, nlp=0)
	"Appends the block behind each proved condition, in order."
	for condition in conditions
		appendDerivations(condition.goal, condition.binds, condition.reasons, indent, lines, nlp)
	end for
end function

// ── What would be needed ──────────────────────────────────────────────────────

// A query can fail because nothing in the knowledge base matches it. Everything
// below answers the question that follows: which facts would have to be added for
// a solution to exist? There is one answer per way the goal could be proved - a
// fact with the goal's own shape, or a rule whose body still needs something - and
// each answer is the facts that way would need, with the rule that would use them.

needsFor = function(goal, facts, rules, depth, binds=null, open=null)
	"Every way goal could still be answered: the facts it needs, and the rule that would use them; asked only for a goal the search could not prove."
	path = enterGoal(goal, binds, open)
	if path == null then return []
	// One more fact, shaped like the goal, would answer it outright.
	options = []
	if matchingFacts(goal, facts, binds).len == 0 then
		options.push({"rule": null, "needs": [missingFact(substitute(goal, binds), false)]})
	end if
	if depth <= 0 then return options
	for candidate in matchingRules(goal, rules, binds)
		for result in bodyResults(candidate, facts, rules, depth, path)
			if result.needs.len > 0 then
				options.push({"rule": candidate.rule, "needs": result.needs})
			end if
		end for
	end for
	return options
end function

bodyResults = function(candidate, facts, rules, depth, path)
	"The ways one rule could answer the goal, re-read when a body claims it needs nothing."
	results = bodyRequirements(candidate.body, facts, rules, depth - 1, candidate.binds, path, {}, 0)
	// The goal has no proof - that is why the report is being asked for - so a body that
	// claims it needs no new fact was met one condition at a time, not all at once. Read
	// again, reporting the conditions the proofs left open, it says what it needs.
	for result in results
		if result.needs.len == 0 then
			return bodyRequirements(candidate.body, facts, rules, depth - 1, candidate.binds, path, {}, 1)
		end if
	end for
	return results
end function

bodyRequirements = function(conditions, facts, rules, depth, binds, open, newVars, reportOpen)
	"Every way of proving a rule body: the bindings it would leave, and the facts it would still need; newVars are the variables the facts found so far would bind, and a not(...) is checked rather than asked for."
	// Each alternative is a body of its own, so it is one more way this body could be
	// met, and it is reported with the facts its own conditions would need.
	if conditions.len > 0 and (conditions[0] isa Or) then
		options = []
		for alternative in conditions[0].alternatives
			for option in bodyRequirements(alternative + conditions[1:], facts, rules, depth,
				binds, open, newVars, reportOpen)
				options.push(option)
			end for
		end for
		return options
	end if
	// A negation asks for no fact: nothing added can make an absence true, so it is
	// checked against what is known, and a body it already proves rules this way out.
	if conditions.len > 0 and (conditions[0] isa Not) then
		if proveConditions(conditions[0].body, facts, rules, depth, binds, open).len > 0 then
			return []
		end if
		return bodyRequirements(conditions[1:], facts, rules, depth, binds, open, newVars, reportOpen)
	end if
	if conditions.len == 0 then return [{"binds": binds, "needs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint is checked here rather than proved, so it asks for no fact; one
		// that binds still settles a variable for the conditions after it.
		settled = applyConstraint(first, binds)
		if settled != null then
			return bodyRequirements(conditions[1:], facts, rules, depth, settled, open, newVars,
				reportOpen)
		end if
		// It may be waiting on a fact this body has already listed, which would settle the
		// field it cannot read yet - the birthdate an age is counted from, say. It asks for
		// nothing itself, and the fact it waits on is already in the report.
		if promisedBy(constraintTerms(first), binds, newVars) then
			return bodyRequirements(conditions[1:], facts, rules, depth, binds, open, newVars,
				reportOpen)
		end if
		return []
	end if
	options = []
	// The bindings a condition proves carry into the conditions after it, so each of
	// them is judged against what this one settled.
	for head in firstRequirements(first, facts, rules, depth, binds, open, newVars, reportOpen)
		for tail in bodyRequirements(conditions[1:], facts, rules, depth, head.binds, open,
			extendVars(newVars, head.needs), reportOpen)
			options.push({"binds": tail.binds, "needs": head.needs + tail.needs})
		end for
	end for
	return options
end function

firstRequirements = function(condition, facts, rules, depth, binds, open, newVars, reportOpen)
	"The ways a body's condition can be met: what it settles, and what it adds to the report."
	grounded = substitute(condition, binds)
	// A fact still to be added would bind these variables, so this condition cannot
	// be judged against what is known. When the facts found so far bind all of them,
	// it is a condition to check rather than a fact to add.
	if newVars.len > 0 and hasUnknowns(grounded) then
		return [{"binds": binds, "needs": [missingFact(grounded, coveredBy(grounded, newVars))]}]
	end if
	proofs = proveGoals(condition, facts, rules, depth, binds, open)
	if proofs.len == 0 then
		return mapWith(needsFor(condition, facts, rules, depth, binds, open), @requirement, binds)
	end if
	settled = agreeingBinds(proofs)
	// Proofs can disagree about a condition's variables, and then it settles nothing for
	// the conditions after it. Asked to report the conditions left open, it is a fact to
	// add instead: no fact of another shape can join this body's conditions into a proof.
	if reportOpen and hasUnknowns(substitute(condition, settled)) then
		return [{"binds": binds, "needs": [missingFact(grounded, false)]}]
	end if
	return [{"binds": settled, "needs": []}]
end function

agreeingBinds = function(proofs)
	"The bindings every proof agrees on, so a report names a value only when the search forces it."
	agreed = proofs[0].binds
	for proof in proofs[1:]
		shared = {}
		for name in agreed.indexes
			if proof.binds.hasIndex(name) and proof.binds[name] == agreed[name] then
				shared[name] = agreed[name]
			end if
		end for
		agreed = shared
	end for
	return agreed
end function

requirement = function(option, binds)
	"One of needsFor's options as a step of a body: its facts, and the bindings that stay as they are."
	return {"binds": binds, "needs": option.needs}
end function

missingFact = function(triple, settled)
	"One fact the report mentions, and whether a fact already listed would settle it."
	return {"triple": triple, "settled": settled}
end function

constraintTerms = function(constraint)
	"The fields a constraint must have settled before it can be judged: years-since binds its second field, so only its date has to be read."
	if constraint isa YearsSince then return [constraint.date]
	return [constraint.left, constraint.right]
end function

promisedBy = function(terms, binds, newVars)
	"Says whether a fact already listed would settle every field still free, so the check can only be judged once that fact exists."
	waiting = false
	for term in terms
		if term isa Var then
			value = substitute(term, binds)
			if value isa Var then
				waiting = true
				if newVars.hasIndex(value.name) == 0 then return false
			end if
		end if
	end for
	return waiting
end function

coveredBy = function(triple, newVars)
	"Says whether the facts already found would bind every variable left in this one."
	for part in unboundVars(triple)
		if newVars.hasIndex(part.name) == 0 then return false
	end for
	return true
end function

extendVars = function(newVars, needs)
	"The variables these missing facts would bind, added to the ones already promised."
	extended = newVars + {}
	for need in needs
		for part in need.triple.parts
			if part isa Var then extended[part.name] = 1
		end for
	end for
	return extended
end function

unboundVars = function(triple)
	"The fields of a triple that are still variables, in order."
	vars = []
	for part in triple.parts
		if part isa Var then vars.push(part)
	end for
	return vars
end function

hasUnknowns = function(triple)
	"Says whether any field of a triple is still a variable."
	return unboundVars(triple).len > 0
end function

// The report is built from pieces, so it can be painted without the engine knowing
// what a color is: a style is a map of role -> the text placed before that role's
// pieces, plus the "normal" text that ends it. A role the caller leaves out gets
// nothing, so the plain style, which is all empty strings, prints exactly as the
// checks expect it. paint is the one place that reads the map, so the report, the
// program that runs one query, and the session at the prompt all paint alike.

plainStyle = {"normal": "", "header": "", "fact": "", "rule": "", "var": "", "note": ""}

filledStyle = function(style)
	"A complete style map: the plain style, with the caller's own text for the roles it names."
	if style == null then return plainStyle + {}
	return plainStyle + style
end function

paint = function(style, role, text)
	"One piece in its role's color, or as it is when the style has nothing for that role."
	if style == null or style.hasIndex(role) == 0 then return text
	return style[role] + text + style.normal
end function

// A variable that came through standardizeApart carries a number in its name, so
// when two of them would read alike the rule's one is given a prime instead of a
// digit: ?p is the name that was asked about, ?p' is the same name inside a rule.

reportVarNames = function(options)
	"Every variable name the alternatives mention, once each, in the order it appears."
	names = []
	seen = {}
	for option in options
		for need in option.needs
			for part in need.triple.parts
				if part isa Var and seen.hasIndex(part.name) == 0 then
					seen[part.name] = 1
					names.push(part.name)
				end if
			end for
		end for
	end for
	return names
end function

isRuleName = function(name)
	"Says whether the name carries the suffix standardizeApart added, so it came from a rule."
	return plainName(name) != name
end function

reportLabels = function(options)
	"One label per variable name the report shows: its own name, or a primed one for a rule's that would read the same."
	names = reportVarNames(options)
	labels = {}
	// The goal's names are claimed first, so a rule's ?p can never take the name of
	// the variable the query actually asked about.
	for name in names
		if not isRuleName(name) then labels[name] = name
	end for
	for name in names
		if isRuleName(name) then labels[name] = freeLabel(labels, plainName(name))
	end for
	return labels
end function

freeLabel = function(labels, base)
	"The name itself when nothing else shows it, else primed once per variable that got there first."
	label = base
	while labels.indexOf(label) != null
		label = label + "'"
	end while
	return label
end function

primedVariable = function(labels)
	"Says whether the report shows a primed name, which its last line explains."
	for label in labels.values
		if label.indexOf("'") != null then return true
	end for
	return false
end function

reportLines = function(options, style=null)
	"The lines that describe these alternatives, painted with style."
	style = filledStyle(style)
	labels = reportLabels(options)
	lines = [paint(style, "header", "  A solution would need one of these:")]
	seen = {}
	for option in options
		block = optionLines(option, labels, style)
		key = block.join("|")
		if seen.hasIndex(key) == 0 then
			seen[key] = 1
			lines = lines + block
		end if
	end for
	if primedVariable(labels) then
		lines.push(paint(style, "note",
			"    (a name ending in ' is the rule's own variable, not one you asked about)"))
	end if
	return lines
end function

neededFactLines = function(goal, facts, rules, depth, style=null)
	"The lines to print when goal has no answer: the facts that would allow one, painted with style."
	return reportLines(needsFor(goal, facts, rules, depth), style)
end function

optionLines = function(option, labels, style)
	"The lines for one alternative: a fact, or a rule and the facts its body would still need."
	if option.rule == null then
		return ["    a fact like " + neededFactText(option.needs[0], labels, style)]
	end if
	block = [paint(style, "rule", "    through rule " + option.rule.text)]
	for needed in option.needs
		block.push("      " + neededFactText(needed, labels, style))
	end for
	return block
end function

neededFactText = function(need, labels, style)
	"One missing fact as it reads, tagged when a fact listed above it would settle the condition."
	triple = need.triple
	fact = paint(style, "fact", shownTerm(triple.predicate, labels, style) + "(" +
		shownTerm(triple.subject, labels, style) + ", " +
		shownTerm(triple.object, labels, style) + ")")
	if not need.settled then return fact
	return fact + paint(style, "note", "  (checked once the facts above exist)")
end function

shownTerm = function(term, labels, style)
	"One field of a needed fact: a value as it is, a variable as the label the report gave it."
	if not (term isa Var) then return term
	plain = "?" + labels[term.name]
	shown = paint(style, "var", plain)
	// Dimming a variable ends the paint it sits in, so a painted fact reopens it.
	if shown == plain then return plain
	return shown + style.fact
end function

plainName = function(name)
	"The variable's name without the numeric suffix standardizeApart added, so ?x_3 reads ?x."
	pieces = name.split("_")
	if pieces.len < 2 then return name
	last = pieces[-1]
	if last == "" then return name
	for c in last
		if c.code < 48 or c.code > 57 then return name
	end for
	return pieces[:-1].join("_")
end function

// ── Parsing ───────────────────────────────────────────────────────────────────

parseLine = function(line)
	"Reads 'predicate(subject, object)' or 'subject | predicate | object', or an error."
	text = trimSpace(line)

	// Text wrapped in one pair of parentheses is a call, and a call that does not
	// fit fails loudly: falling back to the pipe form would put 'oav(bill' in the
	// subject and quietly invent a triple.
	if text[-1] == ")" and text.split("(").len == 2 then
		called = parseCall(text)
		if called == null then return err(badLine(line))
		return called
	end if

	return parsePipe(text, line)
end function

parsePipe = function(text, line)
	"Reads 'subject | predicate | object' into [subject, predicate, object], else an error."
	fields = text.split("|")
	if fields.len != 3 then return err(badLine(line))
	terms = mapWith(fields, @fieldTerm, line)
	for term in terms
		if term isa error then return term
	end for
	return terms
end function

fieldTerm = function(field, line)
	"One pipe-form field as a term: trimmed, non-empty, and a Var when it reads ?x."
	term = trimSpace(field)
	if term == "" then return err("malformed spo: empty field: " + line)
	return termOf(term)
end function

parseCall = function(text)
	"Reads 'predicate(subject, object)' into [subject, predicate, object], else null."
	pieces = text.split("(")
	inner = pieces[1][:-1]
	args = inner.split(",")
	if args.len != 2 then return null
	predicate = trimSpace(pieces[0])
	if predicate == "" then return null
	return [termOf(trimSpace(args[0])), termOf(predicate), termOf(trimSpace(args[1]))]
end function

termOf = function(text)
	"Turns a '?x' field into a Var, a plain number into a number, and leaves every other field its text."
	if text[:1] == "?" then return Var.make(text)
	if isNumber(text) then return val(text)
	return text
end function

isNumber = function(text)
	"Says whether the text is a plain number, which val alone cannot tell: val of a name is 0."
	// A number is a mantissa and an exponent: '1e3' is a thousand, and val alone cannot
	// tell, because it stops reading at the 'e' and keeps the one before it.
	digits = 0          // digits in the mantissa
	dots = 0            // dots in the mantissa: one at most
	exponentAt = null   // where the 'e' sits, once the mantissa has ended
	exponentDigits = 0  // digits after the 'e', which are required and whole
	for at in range(0, text.len - 1)
		c = text[at]
		if exponentAt == null then
			if c == "e" or c == "E" then
				exponentAt = at
			else if c >= "0" and c <= "9" then
				digits = digits + 1
			else if c == "." then
				dots = dots + 1
				if dots > 1 then return false
			else if c != "-" or at != 0 then
				return false
			end if
		else if c >= "0" and c <= "9" then
			exponentDigits = exponentDigits + 1
		else if (c != "+" and c != "-") or at != exponentAt + 1 then
			// A sign may open the exponent, and nothing else may follow it.
			return false
		end if
	end for
	// '' and '-' have no digits at all, 'e3' has none before the 'e', and '1e' has none
	// after it: each stays text rather than becoming the number val would make of it.
	if digits == 0 then return false
	if exponentAt != null and exponentDigits == 0 then return false
	return true
end function

badLine = function(line)
	"One message for every malformed line."
	return "malformed spo: expected 'predicate(subject, object)' or 'subject | predicate | object': " + line
end function

// ── Rules as text ─────────────────────────────────────────────────────────────
// Rule.text prints a rule as 'head <- condition, condition', and the functions here
// read that line back. They return the pieces Rule.make takes rather than a rule, so
// this module never has to hold the Rule class: a caller wraps them in whichever copy
// of it built the rest of its knowledge base.

parseRule = function(line)
	"Reads 'head <- condition, condition' into {head, body}, or an error."
	pieces = line.split("<-")
	if pieces.len != 2 then return err(badRule(line))
	// A head that does not parse keeps its own error: it names the piece that is wrong,
	// where the rule's one message would only repeat the line, and a predicate name it
	// refuses is the one message a typo can act on.
	head = SpoTriple.parse(pieces[0])
	if head isa error then return head
	body = trimSpace(pieces[1])
	if body == "" then return err(badRule(line))
	conditions = []
	for text in splitConditions(body)
		more = parseBodyPart(text, line)
		// Likewise for a condition: a body is where most rule typos are, so the piece's own
		// message says more than the line's.
		if more isa error then return more
		conditions = conditions + more
	end for
	return {"head": head, "body": conditions}
end function

splitConditions = function(text)
	"Splits a rule body at the commas between conditions, not the ones inside them."
	pieces = []
	current = ""
	depth = 0
	for c in text
		if c == "(" then
			depth = depth + 1
		else if c == ")" then
			depth = depth - 1
		else if c == "," and depth == 0 then
			pieces.push(current)
			current = ""
			continue
		end if
		current = current + c
	end for
	pieces.push(current)
	return pieces
end function

parseCondition = function(text, line)
	"Reads one condition of a rule body: a triple, or a constraint such as not-equal(?x, ?y), equal(?n, 18), years-since(2019-04-01, ?n) or less-than-or-equal(?n, 18)."
	text = trimSpace(text)
	if text == "" then return err(badRule(line))
	constraint = constraintOf(text)
	if constraint != null then return constraint
	return SpoTriple.parse(text)
end function

constraintOf = function(text)
	"Reads a constraint call into an Equal, a NotEqual or a Comparison: null for another predicate, an error when the call is wrong."
	openAt = text.indexOf("(")
	if openAt == null then return null
	name = trimSpace(text[:openAt])
	if not isConstraint(name) then return null
	expected = "expected '" + name + "(field, field)': " + text
	inner = trimSpace(text[openAt + 1:])
	if inner.len == 0 then return err(expected)
	if inner[-1] != ")" then return err(expected)
	fields = inner[:-1].split(",")
	if fields.len != 2 then return err(expected)
	left = trimSpace(fields[0])
	right = trimSpace(fields[1])
	if left == "" or right == "" then return err(expected)
	if name == equalName then return Equal.make(termOf(left), termOf(right))
	if name == notEqualName then return NotEqual.make(termOf(left), termOf(right))
	if name == sinceName then return YearsSince.make(termOf(left), termOf(right))
	return Comparison.make(comparisonNames[name], termOf(left), termOf(right))
end function

parseBodyPart = function(text, line)
	"Reads one piece of a rule body into the conditions it stands for: a fact, a constraint, and(...) flattened, or or(...) and not(...) as one condition."
	text = trimSpace(text)
	if text == "" then return err(badRule(line))
	called = groupingOf(text)
	if called == null then
		condition = parseCondition(text, line)
		if condition isa error then return condition
		return [condition]
	end if
	inner = trimSpace(called.inner)
	if inner == "" then return err(badRule(line))
	parts = splitConditions(inner)
	if called.name == "not" then
		if parts.len != 1 then return err(badRule(line))
		body = parseBodyPart(parts[0], line)
		if body isa error then return body
		return [Not.make(body)]
	end if
	if called.name == "and" then
		conditions = []
		for part in parts
			more = parseBodyPart(part, line)
			if more isa error then return more
			conditions = conditions + more
		end for
		return conditions
	end if
	alternatives = []
	for part in parts
		alternative = parseBodyPart(part, line)
		if alternative isa error then return alternative
		alternatives.push(alternative)
	end for
	return [Or.make(alternatives)]
end function

groupingOf = function(text)
	"The {name, inner} of an and(...), or(...) or not(...) standing alone, or null when the text is not one."
	openAt = text.indexOf("(")
	if openAt == null then return null
	name = trimSpace(text[:openAt])
	if ["and", "or", "not"].indexOf(name) == null then return null
	if trimSpace(text[-1:]) != ")" then return null
	return {"name": name, "inner": text[openAt + 1:-1]}
end function

badRule = function(line)
	"One message for every malformed rule line."
	return "malformed rule: expected 'head <- condition, condition': " + line
end function

// ── Helpers ───────────────────────────────────────────────────────────────────

trimSpace = function(text)
	"Trims leading and trailing spaces and tabs."
	start = 0
	while start < text.len
		if not isSpace(text[start]) then break
		start = start + 1
	end while
	last = text.len - 1
	while last >= start
		if not isSpace(text[last]) then break
		last = last - 1
	end while
	return text[start:last + 1]
end function

isSpace = function(c)
	return c == " " or c == char(9)
end function
