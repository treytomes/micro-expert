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
end function
