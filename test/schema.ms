// Cases for the predicate schema: the types data/schema.kb declares, the check the prompt
// puts a typed fact through, and the file the program ships.

run = function(t, parser, schemaLoader, h)
	"Checks the schema format, the field check, and the data file itself."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function

	// ── The format ───────────────────────────────────────────────────────────

	types = parser.parseSchema([
		"has-age(name, number)",
		"has-gender(name, male|female)",
	])
	h.check("a schema document parses", not (types isa error) and types.len == 2)
	h.check("a field type is kept as written", types["has-age"][1] == "number")
	h.check("a list of values is one type", types["has-gender"][1] == "male|female")
	h.check("comments and blank lines are skipped",
		parser.parseSchema(["// a note", "", "has-age(name, number)"]).len == 1)

	broken = parser.parseSchema([
		"has-age(name, number)",
		"has-age(name)",
	])
	h.check("a line without two field types is refused", broken isa error)
	h.check("the refusal names the line",
		broken isa error and broken.message.indexOf("line 2") != null)

	// ── What a fact has to match ─────────────────────────────────────────────

	h.check("a number where a number belongs fits",
		parser.schemaMisfit(types, spo("tim", "has-age", 24)) == null)
	h.check("text where a number belongs does not",
		parser.schemaMisfit(types, spo("tim", "has-age", "twenty")) == "the object should be a number")
	h.check("the field that misses is the one named",
		parser.schemaMisfit(types, spo(24, "has-age", 24)) == "the subject should be a name")
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

	// ── The file the program ships ───────────────────────────────────────────

	shipped = schemaLoader.build()
	h.check("data/schema.kb loads", not (shipped isa error))
	if shipped isa error then return
	h.check("data/schema.kb names four predicates", shipped.len == 4)
	h.check("an age's object is a number", shipped["has-age"][1] == "number")
	h.check("a gender is one of two names", shipped["has-gender"][1] == "male|female")
	h.check("a parent is a name either way", shipped["parent-of"].join("|") == "name|name")
end function
