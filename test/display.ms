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

	// ── A fact's annotations ────────────────────────────────────────────────
	// A typed line carries the two annotations a facts file does, through the one reader both
	// doors use: '@' names the moment the fact holds at and '~' how confident we are. Both
	// are optional, either may stand first, and neither is part of the fact's own form.

	untimed = t.SpoTriple.parse("wakes-up(anna, early)")
	h.check("a typed fact with no annotation is not time-bound and fully confident",
		untimed.at == null and untimed.confidence == 100)
	timed = t.SpoTriple.parse("wakes-up(anna, early) @ 2019-04-05")
	h.check("a typed fact reads the moment it holds at",
		timed.at == "2019-04-05" and timed.confidence == 100)
	h.check("the annotations stay out of the fact's own text",
		timed.text == "wakes-up(anna, early)")
	sure = t.SpoTriple.parse("wakes-up(anna, early) ~ 80%")
	h.check("a confidence reads on its own, leaving the fact untimed",
		sure.confidence == 80 and sure.at == null)
	both = t.SpoTriple.parse("wakes-up(anna, early) ~ 80% @ 2019-04-05")
	h.check("the two annotations may be typed in either order",
		both.at == "2019-04-05" and both.confidence == 80)
	h.check("a confidence may be zero",
		t.SpoTriple.parse("wakes-up(anna, early) ~ 0%").confidence == 0)
	h.check("a confidence may be a fraction",
		t.SpoTriple.parse("wakes-up(anna, early) ~ 87.5%").confidence == 87.5)

	// The moment is kept as it was typed, not as the value it stands for, so a short shape
	// stays short. A datetime's space is part of it, and a span is read between its brackets.
	h.check("a moment is kept as it was typed",
		t.SpoTriple.parse("wakes-up(anna, early) @ 2019-4").at == "2019-4")
	h.check("a datetime keeps its one space",
		t.SpoTriple.parse("wakes-up(anna, early) @ 2019-04-01 09:30").at == "2019-04-01 09:30")
	h.check("a span reads between its brackets",
		t.SpoTriple.parse("works-at(tim, school) @ [2019-04-01, 2019-04-03]").at ==
			"[2019-04-01, 2019-04-03]")

	// The pipe form is the same fact spelled the other way, so it takes the annotations too.
	piped = t.SpoTriple.parse("anna | wakes-up | early @ 2019-04-05 ~ 60%")
	h.check("the pipe form takes the annotations after its last field",
		piped.at == "2019-04-05" and piped.confidence == 60 and
			piped.text == "wakes-up(anna, early)")
	// A sign inside a quoted value is the value's, not an annotation's.
	h.check("a quoted '@' is part of the value",
		t.SpoTriple.parse("has-home-page(guid, " + inQuotes("http://a@b") + ")").at == null)

	// Everything the file refuses is refused here too, in the same words.
	h.check("a confidence past 100 is refused",
		t.SpoTriple.parse("wakes-up(anna, early) ~ 101%") isa error)
	h.check("a negative confidence is refused",
		t.SpoTriple.parse("wakes-up(anna, early) ~ -1%") isa error)
	h.check("a number with no '%' is refused",
		t.SpoTriple.parse("wakes-up(anna, early) ~ 80") isa error)
	h.check("one '@' is all a fact takes",
		t.SpoTriple.parse("wakes-up(anna, early) @ 2019-04-05 @ 2019-04-06") isa error)
	h.check("a moment no reader takes is refused",
		t.SpoTriple.parse("wakes-up(anna, early) @ 2019-02-30") isa error)

	// A rule is not a fact: its head and its conditions are written bare, so an annotation on
	// either is refused where the rule is read rather than kept as something it is not.
	h.check("an annotation on a rule's head is refused",
		t.parseRule("wakes-up(anna, early) @ 2019-04-05 <- is-parent-of(anna, ?y)") isa error)
	h.check("an annotation on a condition is refused",
		t.parseRule("wakes-up(?x, early) <- is-parent-of(?x, ?y) @ 2019-04-05") isa error)
end function
