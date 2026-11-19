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
// A rule body is a list of goals, and it may also hold constraints: conditions
// that are checked against the bindings rather than proved by search.

NotEqual = {}

NotEqual.make = function(left, right)
	"Builds a 'these two terms must differ' constraint."
	c = new NotEqual
	c.left = left
	c.right = right
	return c
end function

NotEqual.text = function
	"Says how the constraint reads: ?x != ?y."
	return termText(self.left) + " != " + termText(self.right)
end function

holdsConstraint = function(constraint, binds)
	"Says whether a constraint holds under the current bindings."
	if constraint isa NotEqual then
		return substitute(constraint.left, binds) != substitute(constraint.right, binds)
	end if
	return false
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
	"One condition renamed: a goal as a triple, a constraint as it is."
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
	"Proves each condition in turn: a goal by search, a constraint by checking it."
	if conditions.len == 0 then return [{"binds": binds, "proofs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint either holds or the branch ends; it proves nothing, so it
		// contributes no proof to the tree.
		if not holdsConstraint(first, binds) then return []
		return proveConditions(conditions[1:], facts, rules, depth, binds, open, index)
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

reasonText = function(reason)
	"Where one derivation came from: a fact, or the rule that concluded it."
	if reason.rule == null then return "fact"
	return "rule " + reason.rule.text
end function

proofLines = function(answer, indent="")
	"Describes every derivation of an answer, with the conditions behind each."
	lines = []
	appendDerivations(answer.goal, answer.binds, answer.reasons, indent, lines)
	return lines
end function

appendDerivations = function(goal, binds, reasons, indent, lines)
	"Appends each derivation's line, then the block behind each of its conditions."
	for reason in reasons
		lines.push(indent + substitute(goal, binds).text + "  <- " + reasonText(reason))
		appendConditions(reason.conditions, indent + "  ", lines)
	end for
end function

appendConditions = function(conditions, indent, lines)
	"Appends the block behind each proved condition, in order."
	for condition in conditions
		appendDerivations(condition.goal, condition.binds, condition.reasons, indent, lines)
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
	"Every way of proving a rule body: the bindings it would leave, and the facts it would still need; newVars are the variables the facts found so far would bind."
	if conditions.len == 0 then return [{"binds": binds, "needs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint is checked here rather than proved, so it asks for no fact.
		if not holdsConstraint(first, binds) then return []
		return bodyRequirements(conditions[1:], facts, rules, depth, binds, open, newVars, reportOpen)
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
	"Turns a '?x' field into a Var, leaving every other field a plain string."
	if text[:1] == "?" then return Var.make(text)
	return text
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
	head = SpoTriple.parse(pieces[0])
	if head isa error then return err(badRule(line))
	body = trimSpace(pieces[1])
	if body == "" then return err(badRule(line))
	conditions = []
	for text in splitConditions(body)
		condition = parseCondition(text, line)
		if condition isa error then return err(badRule(line))
		conditions.push(condition)
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
	"Reads one condition of a rule body: a triple, or a '?x != ?y' constraint."
	text = trimSpace(text)
	differ = text.split("!=")
	if text == "" then return err(badRule(line))
	if differ.len == 2 then
		return NotEqual.make(termOf(trimSpace(differ[0])), termOf(trimSpace(differ[1])))
	end if
	return SpoTriple.parse(text)
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
