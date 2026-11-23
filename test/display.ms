// Cases for how a triple renders and reads back.

run = function(t, h)
	"Checks the display form and the parser, against the shared copy in t."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	v = function(name)
		return t.var(name)
	end function

	// ── Display ─────────────────────────────────────────────────────────────

	h.check("display", spo("bill", "is-parent-of", "susan").text == "is-parent-of(bill, susan)")
	h.check("display with variables", spo(v("x"), "child", v("y")).text == "child(?x, ?y)")
	h.check("display with a variable predicate", spo("bill", v("p"), "susan").text == "?p(bill, susan)")

	// ── A sentence ──────────────────────────────────────────────────────────

	// A predicate is named in sections joined by dashes, and the sentence is that name with
	// the dashes opened to spaces: the name is where the words are, so there is no second
	// table saying what each predicate means.
	h.check("a triple reads as a sentence",
		spo("oliver", "has-uncle", "zed").sentence == "oliver has uncle zed")
	h.check("each dash is a space",
		spo("bill", "is-parent-of", "susan").sentence == "bill is parent of susan")
	h.check("a number field is said as it stands",
		spo("oliver", "has-age", 7).sentence == "oliver has age 7")
	h.check("a digit inside a section is said too",
		spo("oliver", "has-1-child", "true").sentence == "oliver has 1 child true")
	h.check("a variable predicate has no name to say, so the fact form stands",
		spo("bill", v("p"), "susan").sentence == "?p(bill, susan)")

	// ── Parsing ─────────────────────────────────────────────────────────────

	parsed = t.SpoTriple.parse("is-parent-of(bill, susan)")
	h.check("parses the display form", parsed.text == "is-parent-of(bill, susan)")
	h.check("the display form reads back", t.SpoTriple.parse(parsed.text).text == parsed.text)
	h.check("parses the pipe form", t.SpoTriple.parse("bill | is-parent-of | susan").text == "is-parent-of(bill, susan)")
	h.check("parses variables", t.SpoTriple.parse("child(?x, ?y)").text == "child(?x, ?y)")
	h.check("spaces are trimmed",
		t.SpoTriple.parse("  is-parent-of( bill ,  susan )  ").text == "is-parent-of(bill, susan)")
	h.check("rejects one argument", t.SpoTriple.parse("child(susan)") isa error)
	h.check("rejects a pipe form inside a call", t.SpoTriple.parse("oav(bill | gender | male)") isa error)
	h.check("rejects two fields", t.SpoTriple.parse("bill | is-parent-of") isa error)
	h.check("rejects an empty field", t.SpoTriple.parse("bill |  | susan") isa error)

	// A predicate is lower case, its sections joined by '-', each section letters and digits
	// and the first starting with a letter. A line that names one another way is refused
	// where it is read, so the knowledge base holds only names a result can say.
	h.check("a predicate may hold a digit in a later section",
		not (t.SpoTriple.parse("has-1-child(oliver, true)") isa error))
	h.check("a predicate in capitals is refused",
		t.SpoTriple.parse("Parent-Of(bill, susan)") isa error)
	h.check("a predicate that opens with a digit is refused",
		t.SpoTriple.parse("2nd-child(bill, susan)") isa error)
	h.check("a predicate with an empty section is refused",
		t.SpoTriple.parse("parent--of(bill, susan)") isa error)
	h.check("a predicate with anything but letters and digits is refused",
		t.SpoTriple.parse("parent_of(bill, susan)") isa error)

	// A number is read as a number here as it is in the data files, so a question typed
	// with one in it meets the fact that was loaded with one in it.
	numberField = t.SpoTriple.parse("has-age(oliver, 7)")
	h.check("a number field reads as a number", numberField.object isa number and
		numberField.object == 7)
	h.check("a number field displays as it was written", numberField.text == "has-age(oliver, 7)")
	h.check("a number field meets a stored number",
		t.unify(t.SpoTriple.parse("has-age(?p, 54)"), spo("bill", "has-age", 54)) != null)
	h.check("a number field does not meet the same digits as text",
		t.unify(t.SpoTriple.parse("has-age(?p, 54)"), spo("bill", "has-age", "54")) == null)

	// An exponent is part of the number, so 1e3 is a thousand rather than the text
	// '1e3'. val alone cannot tell: it stops reading at the 'e' and keeps the one.
	exponentField = t.SpoTriple.parse("has-age(oliver, 1e3)")
	h.check("an exponent field reads as a number", exponentField.object isa number and
		exponentField.object == 1000)
	h.check("a signed exponent reads too",
		t.SpoTriple.parse("has-age(oliver, 1.5e-3)").object == 0.0015 and
			t.SpoTriple.parse("has-age(oliver, 1E+3)").object == 1000)
	h.check("an exponent displays as the number it is", exponentField.text == "has-age(oliver, 1000)")
	// The digits on each side are checked, so the readings val gives these leniently
	// stay text rather than becoming the numbers they look a little like.
	h.check("an exponent needs digits on both sides",
		t.SpoTriple.parse("has-age(oliver, 1e)").object == "1e" and
			t.SpoTriple.parse("has-age(oliver, e3)").object == "e3")
	h.check("an exponent is not a second decimal",
		t.SpoTriple.parse("has-age(oliver, 1e3.5)").object == "1e3.5")
	// A small number prints in scientific notation, so the form it prints has to read
	// back as the number it printed from.
	scientific = t.SpoTriple.parse("has-age(oliver, 0.0000001)")
	h.check("a number that prints in scientific notation reads back",
		scientific.text == "has-age(oliver, 1E-07)" and
			t.SpoTriple.parse(scientific.text).object == 0.0000001)

	// ── Quoted values ───────────────────────────────────────────────────────
	// A field may be written in double quotes, so a value holds what the form would
	// otherwise read itself: a comma, a bracket, the '//' that opens a comment. The quotes
	// are syntax, not part of the value - what they hold is read as the same text bare
	// would be - and they appear again whenever the bare spelling would read back as
	// something else, so what a triple displays as is a line that reads back as itself.

	quote = char(34)
	inQuotes = function(text)
		return quote + text + quote
	end function

	town = t.SpoTriple.parse("has-home-town(guid, " + inQuotes("Dallas, TX") + ")")
	h.check("a quoted comma stays in one field", not (town isa error) and
		town.object == "Dallas, TX")
	h.check("a quoted value displays in quotes, so it reads back",
		town.text == "has-home-town(guid, " + inQuotes("Dallas, TX") + ")" and
			t.SpoTriple.parse(town.text).text == town.text)

	// Quotes promise text: a quoted value is the text bare would be when bare is text too,
	// and a quoted number stays text where the unquoted one is the number. That is what lets
	// an all-digit value sit in a `text` field, and what makes a number's own spelling the
	// only one a `number` field takes.
	bare = t.SpoTriple.parse("has-home-town(guid, Dallas)")
	h.check("a quoted value is the value its bare spelling is",
		t.SpoTriple.parse("has-home-town(guid, " + inQuotes("Dallas") + ")").text ==
			bare.text)
	h.check("and it meets the bare one",
		t.unify(t.SpoTriple.parse("has-home-town(guid, " + inQuotes("Dallas") + ")"),
			bare) != null)
	h.check("a value that needs no quotes is shown without them",
		bare.text == "has-home-town(guid, Dallas)")
	quotedNumber = t.SpoTriple.parse("has-house-number(way/1, " + inQuotes("7") + ")")
	h.check("a quoted number is text, not the number",
		quotedNumber.object == "7" and not (quotedNumber.object isa number))
	h.check("it keeps its quotes when it displays, so a file reads it as text",
		quotedNumber.text == "has-house-number(way/1, " + inQuotes("7") + ")")
	h.check("and a number is written bare",
		t.SpoTriple.parse("has-age(oliver, 7)").object == 7)

	bracketed = t.SpoTriple.parse("born-in(oliver, " + inQuotes("Round Rock (north)") + ")")
	h.check("a quoted bracket stays in one field",
		bracketed.object == "Round Rock (north)")
	h.check("and it displays so it reads back",
		t.SpoTriple.parse(bracketed.text).object == "Round Rock (north)")

	// A subject is a value like any other, so it takes quotes the same way.
	place = t.SpoTriple.parse(inQuotes("Dallas, TX") + " | has-resident | guid")
	h.check("a quoted subject parses", not (place isa error) and
		place.subject == "Dallas, TX")
	h.check("and it displays in the call form, quoted",
		place.text == "has-resident(" + inQuotes("Dallas, TX") + ", guid)" and
			t.SpoTriple.parse(place.text).subject == "Dallas, TX")

	// The pipe form reads a comma with no quotes at all, and the call form it displays as
	// writes that value in quotes: this is the line a session that took the one can save.
	unquoted = t.SpoTriple.parse("guid | has-home-town | Dallas, TX")
	h.check("the pipe form takes a comma bare", not (unquoted isa error) and
		unquoted.object == "Dallas, TX")
	h.check("the line it displays as reads back",
		t.SpoTriple.parse(unquoted.text).object == "Dallas, TX")

	page = t.SpoTriple.parse("has-home-page(guid, " + inQuotes("http://example.com/x") + ")")
	h.check("a quoted '//' is part of the value", page.object == "http://example.com/x")
	h.check("and it displays in quotes, so a data file reads it as the value",
		page.text == "has-home-page(guid, " + inQuotes("http://example.com/x") + ")")

	// A quote that is never closed would swallow the rest of the line, so the line is
	// refused where it is read rather than stored as a misreading.
	h.check("an unclosed quote is refused", t.SpoTriple.parse("has-home-town(guid, " +
		quote + "Dallas)") isa error)
	equal = t.constraintOf("equal(?x, " + inQuotes("Dallas, TX") + ")")
	h.check("a constraint reads a quoted field too", not (equal isa error) and
		equal != null and equal.right == "Dallas, TX")
end function
