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
		"is-child-of(?x, ?y) <- is-parent-of(?y, ?x)",
		"married-to(?y, ?x) <- married-to(?x, ?y)",
		"is-sibling-of(?x, ?y) <- is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y)",
		"is-brother-of(?x, ?y) <- is-sibling-of(?x, ?y), has-gender(?x, male)",
		"is-sister-of(?x, ?y) <- is-sibling-of(?x, ?y), has-gender(?x, female)",
		"is-uncle-of(?x, ?y) <- is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)",
		"is-aunt-of(?x, ?y) <- is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, female)",
		"is-grandpa-of(?x, ?y) <- is-parent-of(?p, ?y), is-parent-of(?x, ?p), has-gender(?x, male)",
		"is-grandma-of(?x, ?y) <- is-parent-of(?p, ?y), is-parent-of(?x, ?p), has-gender(?x, female)",
		"is-in-law-of(?x, ?y) <- or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))",
		"is-only-child-of(?x, ?y) <- is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q))",
		"has-age(?x, ?n) <- has-birthdate(?x, ?b), years-since(?b, ?n)",
		"belongs-to-age-group(?x, child) <- has-age(?x, ?n), less-than-or-equal(?n, 18)",
		"belongs-to-age-group(?x, adult) <- has-age(?x, ?n), not(belongs-to-age-group(?x, child))",
		"shares-age-group-with(?x, ?y) <- belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h), not-equal(?x, ?y)",
		"is-a(?x, location) <- has-latitude(?x, ?y), has-longitude(?x, ?z)",
	]
	texts = []
	for rule in loadedRules
		texts.push(rule.text)
	end for
	h.check("data/rules.kb holds sixteen rules", loadedRules.len == 16)
	h.check("the rules load in order", texts.join("|") == expected.join("|"))

	loadedFacts = factsLoader.build(t)
	h.check("data/facts.kb loads through facts.ms", not (loadedFacts isa error))
	if loadedFacts isa error then return
	h.check("data/facts.kb holds 54 facts", loadedFacts.len == 54)
	if loadedFacts.len == 54 then
		h.check("the first fact is the first line", loadedFacts[0].text == "has-gender(walter, male)")
		h.check("the last fact is the last line", loadedFacts[53].text == "has-birthdate(oliver, 2019-01-25)")
		h.check("a birthdate loads as the text it was written as", loadedFacts[1].object == "1948-03-14")
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
	// failing run says which facts did. One line each, since a string literal's \n is not
	// a newline in this interpreter.
	for problem in misfits
		print "      " + problem
	end for

	undeclared = []
	if not (types isa error) then
		for predicate in used.indexes
			if types.hasIndex(predicate) == 0 then undeclared.push(predicate)
		end for
	end if
	h.check("every predicate the facts use is declared in data/schema.kb",
		not (types isa error) and undeclared.len == 0)
	if undeclared.len > 0 then print "      " + undeclared.join(", ")

	// A rule names predicates too, in its head and in every condition under it, and what it
	// writes has to fit what the schema says. A predicate it never types would leave the
	// prompt accepting anything for it; a type that contradicts the rule would refuse the
	// very fact the rule asks for. The walk follows or(...) alternatives and not(...)
	// bodies, since a condition can sit under either.
	triplesOf = function(conditions, found)
		"Adds every triple the conditions name to the list."
		for condition in conditions
			if condition isa t.SpoTriple then
				found.push(condition)
			else if condition isa t.Or then
				for alternative in condition.alternatives
					triplesOf(alternative, found)
				end for
			else if condition isa t.Not then
				triplesOf(condition.body, found)
			end if
		end for
	end function
	written = []
	for rule in loadedRules
		written.push(rule.head)
		triplesOf(rule.body, written)
	end for
	named = {}
	for triple in written
		if triple.predicate isa string then named[triple.predicate] = 1
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

	// The constants a rule writes are checked the way a typed fact is: a variable is not a
	// value yet and fits anything, so this reads the words and numbers - has-gender's male
	// and female, and the two words belongs-to-age-group concludes. A rule that asks for a word its
	// predicate does not allow fails here instead of quietly proving nothing.
	mismatched = []
	if not (types isa error) then
		for triple in written
			problem = schemaLoader.misfit(types, triple)
			if problem != null then mismatched.push(triple.text + " - " + problem)
		end for
	end if
	h.check("every constant the rules write fits data/schema.kb",
		not (types isa error) and mismatched.len == 0)
	for problem in mismatched
		print "      " + problem
	end for

	// A unique(...) field is enforced where a fact is added, and a fact a rule concludes is
	// never added, so the shipped schema may not put one on a derived predicate: the file
	// would read as a promise the program cannot keep.
	unenforceable = null
	if not (types isa error) then unenforceable = schemaLoader.derivedUniques(types, loadedRules)
	h.check("data/schema.kb marks no derived predicate unique",
		not (types isa error) and unenforceable == null)
	if unenforceable isa error then print "      " + unenforceable.message

	// ── A file named instead of the shipped one ─────────────────────────────
	// --facts, --rules and --schema hand each loader a path, so a loader given one has to
	// read that file rather than the data folder's. The schema is the exception: it has no
	// default to fall back to, and its build takes the path as its only argument.

	temp = "."
	if env.hasIndex("TEMP") then temp = env["TEMP"]
	if env.hasIndex("TMP") then temp = env["TMP"]
	scratch = function(name)
		"Where a case's file goes: the temp folder, under a name only this suite uses."
		return file.child(temp, "micro-expert-loader-" + name)
	end function
	writeFile = function(path, lines)
		handle = file.open(path, "w")
		if handle isa error then return handle
		for line in lines
			handle.writeLine(line)
		end for
		handle.close
		return null
	end function

	factsPath = scratch("facts.kb")
	writeFile(factsPath, ["has-gender(walter, male)", "has-age(walter, 78)"])
	namedFacts = factsLoader.build(t, factsPath)
	file.delete(factsPath)
	h.check("a loader reads the facts file it is named", not (namedFacts isa error) and
		namedFacts.len == 2 and namedFacts[1].object == 78)
	missingFacts = factsLoader.build(t, scratch("absent.kb"))
	h.check("a missing facts file is an error naming it",
		missingFacts isa error and missingFacts.message.indexOf("could not read") != null)

	rulesPath = scratch("rules.kb")
	writeFile(rulesPath, ["grandparent(?x, ?y) => is-parent-of(?x, ?p), is-parent-of(?p, ?y)"])
	namedRules = rulesLoader.build(t, rulesPath)
	file.delete(rulesPath)
	h.check("a loader reads the rules file it is named", not (namedRules isa error) and
		namedRules.len == 1 and
		namedRules[0].text == "grandparent(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)")

	schemaPath = scratch("schema.kb")
	writeFile(schemaPath, ["has-age(text, number)"])
	namedSchema = schemaLoader.build(schemaPath)
	file.delete(schemaPath)
	h.check("a loader reads the schema file it is named", not (namedSchema isa error) and
		namedSchema.hasIndex("has-age") == 1)

	// A unique(...) field limits the pair, not the value, so the facts loader is handed the
	// types and reads the whole file: two lines that each fit can still be one too many.
	uniqueTypes = {"has-age": ["text", "unique(number)"]}
	repeatedPath = scratch("repeated.kb")
	writeFile(repeatedPath, ["has-age(zed, 24)", "has-age(zed, 17)"])
	repeated = factsLoader.build(t, repeatedPath, uniqueTypes)
	file.delete(repeatedPath)
	refusedIt = repeated isa error and
		repeated.message.indexOf("has-age(zed, 17): the object is already taken: has-age(zed, 24)") != null
	h.check("a facts file that gives one pair two values is refused", refusedIt)
	// Printed only when the refusal came back as something else, so a passing run says nothing
	// between its own lines and a failing one shows what the reader actually answered.
	if not refusedIt and repeated isa error then print "      " + repeated.message
	pairPath = scratch("pair.kb")
	writeFile(pairPath, ["has-age(zed, 24)", "has-age(tim, 17)"])
	oneEach = factsLoader.build(t, pairPath, uniqueTypes)
	file.delete(pairPath)
	h.check("one value each is what the field asks for",
		not (oneEach isa error) and oneEach.len == 2)
end function
