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
//   print triples.SpoTriple.make(triples.var("x"), "child", "?y").text
//   // child(?x, ?y)
//   print triples.unify(triples.SpoTriple.parse("child(?x, ?y)"),
//       triples.SpoTriple.parse("child(susan, bill)"))   // {"x": "susan", "y": "bill"}

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

unify = function(pattern, fact, binds=null)
	"Unifies a pattern against a fact: a bindings map (may be empty) or null."
	// Work on a copy: a match that fails partway must not leave its partial
	// bindings behind in the caller's map.
	working = {}
	if binds != null then
		for name in binds.indexes
			working[name] = binds[name]
		end for
	end if
	matches = null
	if pattern isa SpoTriple then
		if not (fact isa SpoTriple) then return null
		matches = unifyParts(pattern, fact, working)
	else
		matches = unifyTerms(pattern, fact, working)
	end if
	if matches == null then return null
	return resolveBindings(matches)
end function

unifyParts = function(pattern, fact, binds)
	"Unifies the three fields of two triples of the same shape."
	for i in range(0, 2)
		binds = unifyTerms(pattern.parts[i], fact.parts[i], binds)
		if binds == null then return null
	end for
	return binds
end function

unifyTerms = function(left, right, binds)
	"Adds whatever binding makes two terms equal, or null when they cannot agree."
	left = deref(left, binds)
	right = deref(right, binds)
	if left == right then return binds
	if left isa Var then
		binds[left.name] = right
		return binds
	end if
	if right isa Var then
		binds[right.name] = left
		return binds
	end if
	return null
end function

deref = function(term, binds)
	"Follows bindings until a non-variable or an unbound variable."
	while term isa Var
		if not binds.hasIndex(term.name) then return term
		term = binds[term.name]
	end while
	return term
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
	body = []
	for condition in candidate.body
		if condition isa SpoTriple then
			body.push(renameTriple(condition, suffix))
		else
			body.push(renameConstraint(condition, suffix))
		end if
	end for
	return {"head": renameTriple(candidate.head, suffix), "body": body}
end function

canonicalText = function(triple)
	"Renders a triple with its variables numbered by first appearance, so goals that differ only in variable names render the same."
	names = {}
	texts = []
	for part in triple.parts
		if part isa Var then
			if names.hasIndex(part.name) == 0 then names[part.name] = "?" + (names.len + 1)
			texts.push(names[part.name])
		else
			texts.push(part)
		end if
	end for
	return texts[0] + "|" + texts[1] + "|" + texts[2]
end function

goalKey = function(goal, binds)
	"Identifies a goal as it stands under the current bindings, for loop detection."
	grounded = substitute(goal, binds)
	if grounded isa SpoTriple then return canonicalText(grounded)
	return str(termText(grounded))
end function

proveGoals = function(goal, facts, rules, depth, binds=null, open=null)
	"Every answer to goal, at most depth rules deep, each with all its derivations; open is the chain of goals being proved, so a loop stops that branch."
	if open == null then open = {}
	key = goalKey(goal, binds)
	if open.hasIndex(key) then return []
	// Copy, so one branch's ancestors do not prune its siblings.
	path = {}
	for name in open.indexes
		path[name] = open[name]
	end for
	path[key] = 1

	answers = []
	byText = {}
	for fact in facts
		matched = unify(goal, fact, binds)
		if matched != null then
			mergeAnswer(answers, byText, goal, matched, {"rule": null, "conditions": []})
		end if
	end for
	if depth <= 0 then return answers
	for candidate in rules
		fresh = standardizeApart(candidate)
		matched = unify(fresh.head, goal, binds)
		if matched != null then
			for proved in proveConditions(fresh.body, facts, rules, depth - 1, matched, path)
				mergeAnswer(answers, byText, goal, proved.binds, {"rule": candidate, "conditions": proved.proofs})
			end for
		end if
	end for
	return answers
end function

proveConditions = function(conditions, facts, rules, depth, binds, open=null)
	"Proves each condition in turn: a goal by search, a constraint by checking it."
	if conditions.len == 0 then return [{"binds": binds, "proofs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint either holds or the branch ends; it proves nothing, so it
		// contributes no proof to the tree.
		if not holdsConstraint(first, binds) then return []
		return proveConditions(conditions[1:], facts, rules, depth, binds, open)
	end if
	results = []
	for proved in proveGoals(first, facts, rules, depth, binds, open)
		for rest in proveConditions(conditions[1:], facts, rules, depth, proved.binds, open)
			results.push({"binds": rest.binds, "proofs": [proved] + rest.proofs})
		end for
	end for
	return results
end function

mergeAnswer = function(answers, byText, goal, binds, reason)
	"One entry per answer, holding every way that answer was proved."
	key = substitute(goal, binds).text
	if byText.hasIndex(key) == 0 then
		byText[key] = {"goal": goal, "binds": binds, "reasons": []}
		answers.push(byText[key])
	end if
	byText[key].reasons.push(reason)
end function

reasonText = function(reason)
	"Where one derivation came from: a fact, or the rule that concluded it."
	if reason.rule == null then return "fact"
	return "rule " + reason.rule.text
end function

proofLines = function(goal, answer, indent="")
	"Describes every derivation of an answer, with the conditions behind each."
	lines = []
	for reason in answer.reasons
		lines = lines + derivationLines(goal, answer.binds, reason, indent)
	end for
	return lines
end function

derivationLines = function(goal, binds, reason, indent)
	"One derivation: the answer, where it came from, then its conditions."
	lines = [indent + substitute(goal, binds).text + "  <- " + reasonText(reason)]
	for condition in reason.conditions
		lines = lines + proofLines(condition.goal, condition, indent + "  ")
	end for
	return lines
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

	fields = text.split("|")
	if fields.len != 3 then return err(badLine(line))

	for i in range(0, 2)
		fields[i] = trimSpace(fields[i])
		if fields[i] == "" then return err("malformed spo: empty field: " + line)
		fields[i] = termOf(fields[i])
	end for
	return fields
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
