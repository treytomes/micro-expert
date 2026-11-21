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

	// ── Dates, times and datetimes ───────────────────────────────────────────

	dated = parser.parseSchema([
		"founded-on(text, date)",
		"opens-at(text, time)",
		"seen-at(text, datetime)",
		"born-on(text, unique(date))",
	])
	h.check("date, time and datetime are field types", dated["opens-at"][1] == "time")
	h.check("a calendar date fits",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "2019-04-01")) == null)
	h.check("a date is not a value list",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "date")) ==
			"the object should be a date")
	h.check("a day the calendar does not have is refused",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "2019-02-30")) ==
			"the object should be a date")
	h.check("a date written another way is refused",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "3/15/2019")) ==
			"the object should be a date")
	h.check("a clock time fits",
		parser.schemaMisfit(dated, spo("acme", "opens-at", "09:30:00")) == null)
	h.check("a clock time may leave the seconds off",
		parser.schemaMisfit(dated, spo("acme", "opens-at", "09:30")) == null)
	h.check("there is no minute 60",
		parser.schemaMisfit(dated, spo("acme", "opens-at", "09:60")) ==
			"the object should be a time")
	h.check("a date and a time together fit a datetime",
		parser.schemaMisfit(dated, spo("acme", "seen-at", "2019-04-01 09:30:00")) == null)
	h.check("a date alone is not a datetime",
		parser.schemaMisfit(dated, spo("acme", "seen-at", "2019-04-01")) ==
			"the object should be a date and time")
	h.check("unique(...) wraps a date as it wraps any type",
		parser.schemaMisfit(dated, spo("acme", "born-on", "2019-04-01")) == null)

	// The text is what a fact stores; the Temporal is what it means. One object reads all
	// three types, so a value can be formatted, moved and ordered without going back to text.
	when = parser.receive("2019-04-01 09:30:00")
	h.check("a fitting text is read into a Temporal", when isa parser.Temporal)
	h.check("it keeps its shape and its parts",
		when.kind == "datetime" and when.year == 2019 and when.month == 4 and
			when.day == 1 and when.hour == 9 and when.minute == 30 and when.second == 0)
	h.check("it formats itself in the type's form", when.str == "2019-04-01 09:30:00")
	h.check("and in any format asked for", when.str("HH:mm") == "09:30")
	h.check("it moves by seconds", when.addSeconds(90).str == "2019-04-01 09:31:30")
	h.check("a time moves around midnight",
		parser.receive("23:59:30").addSeconds(60).str == "00:00:30")
	h.check("it orders against its own kind",
		when.compare(parser.receive("2019-04-01 10:00:00")) == -1 and
			when.compare(parser.receive("2019-04-01 09:30:00")) == 0)
	h.check("a bare time has no date",
		parser.receive("09:30:00").year == null and parser.receive("09:30:00").day == null)
	h.check("a datetime is written with a space, not a T",
		parser.receive("2019-04-01T09:30:00") isa error)
	h.check("another kind is not compared", when.compare(parser.receive("09:30:00")) isa error)
	h.check("the kind is read off the text",
		parser.receive("2019-04-01").kind == "date" and
			parser.receive("09:30").kind == "time" and parser.receive("09:30").str == "09:30:00")
	h.check("a text of no kind is refused", parser.receive("nonsense") isa error)
	h.check("the schema module reads a value into the same kind of object",
		schemaLoader.receive("2019-04-01") isa schemaLoader.Temporal)

	// ── The file the program ships ───────────────────────────────────────────

	shipped = schemaLoader.build()
	h.check("data/schema.kb loads", not (shipped isa error))
	if shipped isa error then return
	h.check("data/schema.kb names sixteen predicates", shipped.len == 16)
	h.check("an age's object is a number, and one per person",
		shipped["has-age"][1] == "unique(number)")
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
