// Cases for a query with no answer: the report on what facts would allow one.

run = function(t, rules, h)
	"Checks the missing-fact report, against the shared copies in t and rules."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	v = function(name)
		return t.var(name)
	end function
	rule = function(head, body)
		return rules.Rule.make(head, body)
	end function

	// Susan has a son but no parent of her own here, which is the query the
	// program asks: ?p is the parent of susan.
	family = [
		spo("bill", "parent-of", "tim"),
		spo("susan", "parent-of", "tim"),
		spo("bill", "has-gender", "male"),
	]
	asked = spo(v("?p"), "parent-of", "susan")

	// ── Nothing but a new fact would answer it ───────────────────────────────

	lines = t.neededFactLines(asked, family, [], 8)
	h.check("a missing answer is explained", lines.len == 2)
	h.check("the report names the needed fact",
		lines[0] == "  A solution would need one of these:")
	h.check("the needed fact keeps the query's variables",
		lines[1] == "    a fact like parent-of(?p, susan)")

	// A goal with no variables asks for exactly that fact.
	h.check("a ground goal asks for itself",
		t.neededFactLines(spo("doris", "parent-of", "susan"), family, [], 0)[1] ==
			"    a fact like parent-of(doris, susan)")

	// ── A rule path names what its body still needs ─────────────────────────

	lineage = [
		spo("bill", "parent-of", "tim"),
		spo("tim", "parent-of", "anna"),
	]
	grandparent = rule(spo(v("x"), "grandparent", v("y")),
		[spo(v("x"), "parent-of", v("p")), spo(v("p"), "parent-of", v("y"))])

	viaRule = t.neededFactLines(spo(v("x"), "grandparent", "nobody"), lineage, [grandparent], 8)
	h.check("the rule path is reported", viaRule.len == 4)
	h.check("the rule itself is named",
		viaRule[2] == "    through rule grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)")
	h.check("the body condition that is missing is named",
		viaRule[3] == "      parent-of(?p, nobody)")

	// Once a fact is missing, later conditions it would bind are listed too rather
	// than judged against the facts that are already known.
	uncle = rule(spo(v("x"), "uncle", v("y")),
		[spo(v("p"), "parent-of", v("y")), spo(v("x"), "sibling-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	viaUncle = t.neededFactLines(spo("bill", "uncle", "nobody"), family, [uncle], 8)
	h.check("conditions behind the gap are listed", viaUncle.len == 5)
	h.check("the first missing fact",
		viaUncle[3] == "      parent-of(?p, nobody)")
	h.check("the condition it would bind",
		viaUncle[4] == "      sibling-of(bill, ?p)")
	// The gender condition is ground and known, so it is not asked for.

	// ── Depth still bounds the report ──────────────────────────────────────

	shallow = t.neededFactLines(spo("bill", "uncle", "nobody"), family, [uncle], 0)
	h.check("depth 0 reports facts only", shallow.len == 2)

	// ── A rule behind a rule is expanded, not named as a fact ──────────────

	kin = rule(spo(v("x"), "kin", v("y")), [spo(v("x"), "grandparent", v("y"))])
	nested = t.neededFactLines(spo("nobody", "kin", "bill"), lineage, [kin, grandparent], 8)
	h.check("both readings of the nested goal are offered", nested.len == 7)
	h.check("the nested rule's own conditions are named",
		nested[6] == "      parent-of(?p, bill)")

	// ── Painting is opt-in: no style, no escape codes ──────────────────────

	plainLine = t.neededFactLines(asked, family, [], 8)[1]
	h.check("an unpainted report stays plain text", plainLine.indexOf(char(27)) == null)

	// The engine only ever places the caller's own strings, so a style of markers
	// shows exactly which pieces got painted where.
	mark = {"header": "<h>", "warning": "<w>", "fact": "<f>", "rule": "<r>",
		"var": "<v>", "normal": "</>"}
	painted = t.neededFactLines(asked, family, [], 8, mark)
	h.check("a painted header opens and closes its line",
		painted[0] == "<h>  A solution would need one of these:</>")
	h.check("a painted fact dims each variable inside it",
		painted[1] == "    a fact like <f>parent-of(<v>?p</><f>, susan)</>")

	paintedRule = t.neededFactLines(spo(v("x"), "grandparent", "nobody"), lineage,
		[grandparent], 8, mark)
	h.check("a painted rule path opens with its rule",
		paintedRule[2] ==
			"<r>    through rule grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)</>")
	h.check("a painted rule path paints the facts under it",
		paintedRule[3] == "      <f>parent-of(<v>?p</><f>, nobody)</>")
end function
