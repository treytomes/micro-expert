// Cases for the predicate schema: the types data/schema.kb declares, the check the prompt
// puts a typed fact through, and the file the program ships.

run = function(t, parser, schemaLoader, h)
	"Checks the schema format, the field check, and the data file itself."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function

	// ── The format ───────────────────────────────────────────────────────────

	types = parser.parseSchema([
		"has-age(text, number)",
		"has-gender(text, male|female)",
		"is-adult(text, boolean)",
	])
	h.check("a schema document parses", not (types isa error) and types.len == 3)
	h.check("a field type is kept as written", types["has-age"][1] == "number")
	h.check("a list of values is one type", types["has-gender"][1] == "male|female")

	// unique(...) wraps one field's type, and the type inside it is what a value meets. The
	// wrapper is kept as it was written, so the line a session saves is the line it read.
	wrapped = parser.parseSchema([
		"has-age(text, unique(number))",
		"has-gender(text, unique(male|female))",
	])
	h.check("unique(...) is kept as written", wrapped["has-age"][1] == "unique(number)")
	h.check("a wrapped value is checked against the type inside",
		parser.schemaMisfit(wrapped, spo("tim", "has-age", 24)) == null)
	h.check("and a refusal names that type, not the wrapper",
		parser.schemaMisfit(wrapped, spo("tim", "has-age", "twenty")) == "the object should be a number")
	h.check("a wrapped list is still a list",
		parser.schemaMisfit(wrapped, spo("tim", "has-gender", "boy")) ==
			"the object should be one of: male, female")

	// unique(...) wraps exactly one type: nothing nests inside it, and a comma asks for a
	// second field where a type stood. A bare unique is an ordinary word, so a domain that
	// allows the value unique still writes it as it always did.
	h.check("unique() needs a type", parser.parseSchema(["has-age(text, unique())"]) isa error)
	h.check("unique(...) wraps one type, not two",
		parser.parseSchema(["has-age(text, unique(number, number))"]) isa error)
	h.check("unique(...) does not nest",
		parser.parseSchema(["has-age(text, unique(unique(number)))"]) isa error)
	h.check("a bare unique is an ordinary value",
		not (parser.parseSchema(["has-favourite(text, unique)"]) isa error))
	h.check("comments and blank lines are skipped",
		parser.parseSchema(["// a note", "", "has-age(text, number)"]).len == 1)

	// A schema line names a predicate, so the map is held to the shape a fact's name has where
	// a schema is admitted - which is all misnamed does, with the solver handed in.
	shapedName = parser.parseSchema(["has-1-child(text, boolean)"])
	h.check("a schema may name a predicate with a digit section",
		schemaLoader.misnamed(t, shapedName) == null)
	oddName = parser.parseSchema(["Has_Age(text, number)"])
	h.check("a schema is refused when one of its names is not one",
		schemaLoader.misnamed(t, oddName) isa error)

	broken = parser.parseSchema([
		"has-age(text, number)",
		"has-age(text)",
	])
	h.check("a line without two field types is refused", broken isa error)
	h.check("the refusal names the line",
		broken isa error and broken.message.indexOf("line 2") != null)

	// ── What a fact has to match ─────────────────────────────────────────────

	h.check("a number where a number belongs fits",
		parser.schemaMisfit(types, spo("tim", "has-age", 24)) == null)
	h.check("a number is whole or fractional",
		parser.schemaMisfit(types, spo("tim", "has-age", 24.5)) == null and
			parser.schemaMisfit(types, spo("tim", "has-age", -3)) == null)
	h.check("text where a number belongs does not",
		parser.schemaMisfit(types, spo("tim", "has-age", "twenty")) == "the object should be a number")
	h.check("the field that misses is the one named",
		parser.schemaMisfit(types, spo(24, "has-age", 24)) == "the subject should be text")
	h.check("a boolean field takes either word",
		parser.schemaMisfit(types, spo("tim", "is-adult", "true")) == null and
			parser.schemaMisfit(types, spo("tim", "is-adult", "false")) == null)
	h.check("a boolean field takes nothing else",
		parser.schemaMisfit(types, spo("tim", "is-adult", "yes")) ==
			"the object should be true or false")
	h.check("a number is not a boolean",
		parser.schemaMisfit(types, spo("tim", "is-adult", 1)) ==
			"the object should be true or false")
	h.check("a listed value fits",
		parser.schemaMisfit(types, spo("tim", "has-gender", "male")) == null)
	h.check("a value that is not listed does not",
		parser.schemaMisfit(types, spo("tim", "has-gender", "boy")) ==
			"the object should be one of: male, female")
	h.check("a predicate the schema does not name fits",
		parser.schemaMisfit(types, spo("tim", "likes", 3)) == null)
	h.check("nothing to check against fits",
		parser.schemaMisfit(null, spo("tim", "has-age", "twenty")) == null)
	h.check("a variable fits any type, being no value yet",
		parser.schemaMisfit(types, spo(t.var("x"), "has-age", t.var("n"))) == null)

	// unique(...) is the one check a single term cannot answer: a value that fits its type
	// can still be the second one for that subject, so it is held against the facts.
	ages = {"has-age": ["text", "unique(number)"]}
	h.check("a second value for a unique field is a clash",
		parser.uniqueClash(ages, [spo("zed", "has-age", 24)], spo("zed", "has-age", 17)) ==
			"the object is already taken: has-age(zed, 24)")
	h.check("another subject is another pair",
		parser.uniqueClash(ages, [spo("zed", "has-age", 24)], spo("tim", "has-age", 17)) == null)
	// A unique subject limits the other direction: one subject per object, not one object
	// per subject. Which slot the wrapper sits on is what says which way round it reads.
	capitals = {"has-capital": ["unique(text)", "text"]}
	h.check("a unique subject is one per object",
		parser.uniqueClash(capitals, [spo("paris", "has-capital", "france")],
			spo("london", "has-capital", "france")) ==
			"the subject is already taken: has-capital(paris, france)")
	likes = {"likes": ["text", "text"]}
	h.check("a field that is not unique takes a second value",
		parser.uniqueClash(likes, [spo("zed", "likes", "tea")], spo("zed", "likes", "coffee")) == null)

	// The reader a date field's text goes through is datetimes.ms's, and this module hands it
	// on, so the two names it exposes have to agree about what they build; the reader's own
	// behaviour is test/datetimes.ms's.
	h.check("the schema module reads a value into the same kind of object",
		schemaLoader.receive("2019-04-01") isa schemaLoader.Temporal)

	// ── The file the program ships ───────────────────────────────────────────

	shipped = schemaLoader.build()
	h.check("data/schema.kb loads", not (shipped isa error))
	if shipped isa error then return
	h.check("data/schema.kb names seventeen predicates", shipped.len == 17)
	h.check("a birthdate is a date, and one per person",
		shipped["has-birthdate"][1] == "unique(date)")
	h.check("an age is a number the age rule works out", shipped["has-age"][1] == "number")
	h.check("a gender is one of two names, and one per person",
		shipped["has-gender"][1] == "unique(male|female)")
	h.check("a spouse is not marked unique, so the rule that reverses it can run",
		shipped["married-to"][1] == "text")
	h.check("a parent is text either way", shipped["is-parent-of"].join("|") == "text|text")
	// A derived predicate is typed by the rules that conclude it: is-sibling-of links the two
	// people is-parent-of links, and belongs-to-age-group's second field is one of the two words written.
	h.check("a derived relation is text either way", shipped["is-sibling-of"].join("|") == "text|text")
	h.check("a derived group is one of the words its rules write",
		shipped["belongs-to-age-group"][1] == "child|adult")
end function
