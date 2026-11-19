// Cases for the loaders: the data files the program ships, read through the modules
// that load them, so the loader's path logic cannot regress silently, and the facts fit
// the schema the prompt holds typed ones against.

run = function(t, rulesLoader, factsLoader, schemaLoader, h)
	"Checks that data/rules.kb and data/facts.kb load in the order their lines hold, and that the facts fit data/schema.kb."
	loadedRules = rulesLoader.build(t)
	h.check("data/rules.kb loads through rules.ms", not (loadedRules isa error))
	if loadedRules isa error then return
	// The order search tries them, which is the order the file holds.
	expected = [
		"child-of(?x, ?y) <- parent-of(?y, ?x)",
		"married-to(?y, ?x) <- married-to(?x, ?y)",
		"sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y",
		"brother-of(?x, ?y) <- sibling-of(?x, ?y), has-gender(?x, male)",
		"sister-of(?x, ?y) <- sibling-of(?x, ?y), has-gender(?x, female)",
		"uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)",
		"aunt-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, female)",
		"grandpa-of(?x, ?y) <- parent-of(?p, ?y), parent-of(?x, ?p), has-gender(?x, male)",
		"grandma-of(?x, ?y) <- parent-of(?p, ?y), parent-of(?x, ?p), has-gender(?x, female)",
		"in-law-of(?x, ?y) <- or(and(married-to(?x, ?p), sibling-of(?p, ?y)), and(sibling-of(?x, ?p), married-to(?p, ?y)))",
		"only-child-of(?x, ?y) <- parent-of(?y, ?x), not(sibling-of(?x, ?q))",
		"age-group(?x, child) <- has-age(?x, ?n), ?n <= 18",
		"age-group(?x, adult) <- has-age(?x, ?n), not(age-group(?x, child))",
	]
	texts = []
	for rule in loadedRules
		texts.push(rule.text)
	end for
	h.check("data/rules.kb holds thirteen rules", loadedRules.len == 13)
	h.check("the rules load in order", texts.join("|") == expected.join("|"))

	loadedFacts = factsLoader.build(t)
	h.check("data/facts.kb loads through facts.ms", not (loadedFacts isa error))
	if loadedFacts isa error then return
	h.check("data/facts.kb holds 54 facts", loadedFacts.len == 54)
	if loadedFacts.len == 54 then
		h.check("the first fact is the first line", loadedFacts[0].text == "has-gender(walter, male)")
		h.check("the last fact is the last line", loadedFacts[53].text == "has-age(oliver, 7)")
		h.check("ages load as numbers", loadedFacts[1].object + 1 == 79)
	end if

	// ── The schema the shipped facts have to fit ─────────────────────────────

	// The prompt holds a typed fact against data/schema.kb, so the facts the program
	// ships have to pass the same check: a value the schema would refuse is the two
	// files drifting apart, not a fact. A predicate the schema does not name is taken
	// as written, so the second check is what stops a new predicate going unchecked.
	types = schemaLoader.build()
	misfits = []
	used = {}
	if not (types isa error) then
		for fact in loadedFacts
			used[fact.predicate] = 1
			problem = schemaLoader.misfit(types, fact)
			if problem != null then misfits.push(fact.text + " - " + problem)
		end for
	end if
	h.check("every fact in data/facts.kb fits data/schema.kb",
		not (types isa error) and misfits.len == 0)
	// Printed only when something drifted, and after the failure it explains, so a
	// failing run says which facts did.
	if misfits.len > 0 then print "      " + misfits.join("\n      ")

	undeclared = []
	if not (types isa error) then
		for predicate in used.indexes
			if types.hasIndex(predicate) == 0 then undeclared.push(predicate)
		end for
	end if
	h.check("every predicate the facts use is declared in data/schema.kb",
		not (types isa error) and undeclared.len == 0)
	if undeclared.len > 0 then print "      " + undeclared.join(", ")

	// A rule names predicates too, in its head and in every condition under it, and each
	// of them has to be typed: otherwise a new rule could quietly use a field no fact could
	// hold. The walk follows or(...) alternatives and not(...) bodies, since a predicate can
	// be needed under either.
	walkPredicates = function(conditions, names)
		"Adds each predicate the conditions name to the set."
		for condition in conditions
			if condition isa t.SpoTriple then
				if condition.predicate isa string then names[condition.predicate] = 1
			else if condition isa t.Or then
				for alternative in condition.alternatives
					walkPredicates(alternative, names)
				end for
			else if condition isa t.Not then
				walkPredicates(condition.body, names)
			end if
		end for
	end function
	named = {}
	for rule in loadedRules
		if rule.head.predicate isa string then named[rule.head.predicate] = 1
		walkPredicates(rule.body, named)
	end for
	untyped = []
	if not (types isa error) then
		for predicate in named.indexes
			if types.hasIndex(predicate) == 0 then untyped.push(predicate)
		end for
	end if
	h.check("every predicate the rules name is declared in data/schema.kb",
		not (types isa error) and untyped.len == 0)
	if untyped.len > 0 then print "      " + untyped.join(", ")
end function
