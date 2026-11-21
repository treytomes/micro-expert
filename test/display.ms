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

	h.check("display", spo("bill", "parent-of", "susan").text == "parent-of(bill, susan)")
	h.check("display with variables", spo(v("x"), "child", v("y")).text == "child(?x, ?y)")
	h.check("display with a variable predicate", spo("bill", v("p"), "susan").text == "?p(bill, susan)")

	// ── A sentence ──────────────────────────────────────────────────────────

	// A predicate is named in sections joined by dashes, and the sentence is that name with
	// the dashes opened to spaces: the name is where the words are, so there is no second
	// table saying what each predicate means.
	h.check("a triple reads as a sentence",
		spo("oliver", "has-uncle", "zed").sentence == "oliver has uncle zed")
	h.check("each dash is a space",
		spo("bill", "parent-of", "susan").sentence == "bill parent of susan")
	h.check("a number field is said as it stands",
		spo("oliver", "has-age", 7).sentence == "oliver has age 7")
	h.check("a digit inside a section is said too",
		spo("oliver", "has-1-child", "true").sentence == "oliver has 1 child true")
	h.check("a variable field keeps its ?",
		spo(v("x"), "parent-of", "susan").sentence == "?x parent of susan")
	h.check("a variable predicate has no name to say, so the fact form stands",
		spo("bill", v("p"), "susan").sentence == "?p(bill, susan)")

	// ── Parsing ─────────────────────────────────────────────────────────────

	parsed = t.SpoTriple.parse("parent-of(bill, susan)")
	h.check("parses the display form", parsed.text == "parent-of(bill, susan)")
	h.check("the display form reads back", t.SpoTriple.parse(parsed.text).text == parsed.text)
	h.check("parses the pipe form", t.SpoTriple.parse("bill | parent-of | susan").text == "parent-of(bill, susan)")
	h.check("parses variables", t.SpoTriple.parse("child(?x, ?y)").text == "child(?x, ?y)")
	h.check("spaces are trimmed",
		t.SpoTriple.parse("  parent-of( bill ,  susan )  ").text == "parent-of(bill, susan)")
	h.check("rejects one argument", t.SpoTriple.parse("child(susan)") isa error)
	h.check("rejects a pipe form inside a call", t.SpoTriple.parse("oav(bill | gender | male)") isa error)
	h.check("rejects two fields", t.SpoTriple.parse("bill | parent-of") isa error)
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
end function
