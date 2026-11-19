// Cases for the loaders: the data files the program ships, read through the modules
// that load them, so the loader's path logic cannot regress silently.

run = function(t, rulesLoader, factsLoader, h)
	"Checks that rules.data and facts.data load, in the order their lines hold."
	loadedRules = rulesLoader.build(t)
	h.check("rules.data loads through rules.ms", not (loadedRules isa error))
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
	]
	texts = []
	for rule in loadedRules
		texts.push(rule.text)
	end for
	h.check("rules.data holds nine rules", loadedRules.len == 9)
	h.check("the rules load in order", texts.join("|") == expected.join("|"))

	loadedFacts = factsLoader.build(t)
	h.check("facts.data loads through facts.ms", not (loadedFacts isa error))
	if loadedFacts isa error then return
	h.check("facts.data holds 54 facts", loadedFacts.len == 54)
	if loadedFacts.len == 54 then
		h.check("the first fact is the first line", loadedFacts[0].text == "has-gender(walter, male)")
		h.check("the last fact is the last line", loadedFacts[53].text == "has-age(oliver, 7)")
		h.check("ages load as numbers", loadedFacts[1].object + 1 == 79)
	end if
end function
