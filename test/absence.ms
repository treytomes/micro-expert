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
		spo("bill", "is-parent-of", "tim"),
		spo("susan", "is-parent-of", "tim"),
		spo("bill", "has-gender", "male"),
	]
	asked = spo(v("?p"), "is-parent-of", "susan")

	// ── Nothing but a new fact would answer it ───────────────────────────────

	lines = t.neededFactLines(asked, family, [], 8)
	h.check("a missing answer is explained", lines.len == 2)
	h.check("the report names the needed fact",
		lines[0] == "  A solution would need one of these:")
	h.check("the needed fact keeps the query's variables",
		lines[1] == "    a fact like is-parent-of(?p, susan)")

	// A goal with no variables asks for exactly that fact.
	h.check("a ground goal asks for itself",
		t.neededFactLines(spo("doris", "is-parent-of", "susan"), family, [], 0)[1] ==
			"    a fact like is-parent-of(doris, susan)")

	// ── A rule path names what its body still needs ─────────────────────────

	lineage = [
		spo("bill", "is-parent-of", "tim"),
		spo("tim", "is-parent-of", "anna"),
	]
	grandparent = rule(spo(v("x"), "is-grandparent-of", v("y")),
		[spo(v("x"), "is-parent-of", v("p")), spo(v("p"), "is-parent-of", v("y"))])

	viaRule = t.neededFactLines(spo(v("x"), "is-grandparent-of", "nobody"), lineage, [grandparent], 8)
	h.check("the rule path is reported", viaRule.len == 4)
	h.check("the rule itself is named",
		viaRule[2] == "    through rule is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)")
	h.check("the body condition that is missing is named",
		viaRule[3] == "      is-parent-of(?p, nobody)")

	// Once a fact is missing, a later condition it would bind is reported as one to
	// check rather than one to add.
	uncle = rule(spo(v("x"), "uncle", v("y")),
		[spo(v("p"), "is-parent-of", v("y")), spo(v("x"), "is-sibling-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	viaUncle = t.neededFactLines(spo("bill", "uncle", "nobody"), family, [uncle], 8)
	h.check("conditions behind the gap are listed", viaUncle.len == 5)
	h.check("the first missing fact",
		viaUncle[3] == "      is-parent-of(?p, nobody)")
	h.check("the condition that fact would settle is marked, not asked for",
		viaUncle[4] == "      is-sibling-of(bill, ?p)  (checked once the facts above exist)")
	// The gender condition is ground and known, so it is not asked for.

	// Every condition of a body can be provable on its own and still never hold
	// together: "a" is nobody's uncle here, though a parent of ?p exists, a sibling of
	// "a" exists, and "a" is male. The report must still name the rule, and say which
	// facts its body would need as one set, instead of claiming no rule can conclude it.
	tangle = [
		spo("a", "is-parent-of", "b"),
		spo("c", "is-parent-of", "a"),
		spo("d", "is-parent-of", "a"),
		spo("c", "is-parent-of", "e"),
		spo("a", "is-sibling-of", "e"),
		spo("a", "has-gender", "male"),
	]
	tangled = t.neededFactLines(spo("a", "uncle", v("p")), tangle, [uncle], 8)
	h.check("a body whose conditions only hold apart still names its rule", tangled.len == 6)
	h.check("the facts it would need are reported as one set",
		tangled[3] == "      is-parent-of(?p', ?p)")
	h.check("the condition those facts would settle is tagged",
		tangled[4] == "      is-sibling-of(a, ?p')  (checked once the facts above exist)")

	// ── Depth still bounds the report ──────────────────────────────────────

	shallow = t.neededFactLines(spo("bill", "uncle", "nobody"), family, [uncle], 0)
	h.check("depth 0 reports facts only", shallow.len == 2)

	// ── A rule behind a rule is expanded, not named as a fact ──────────────

	kin = rule(spo(v("x"), "kin", v("y")), [spo(v("x"), "is-grandparent-of", v("y"))])
	nested = t.neededFactLines(spo("nobody", "kin", "bill"), lineage, [kin, grandparent], 8)
	h.check("both readings of the nested goal are offered", nested.len == 7)
	h.check("the nested rule's own condition is named as one to check",
		nested[6] == "      is-parent-of(?p, bill)  (checked once the facts above exist)")

	// ── A rule's variable that would read like the query's ─────────────────

	grandpa = rule(spo(v("x"), "grandpa", v("y")),
		[spo(v("p"), "is-parent-of", v("y")), spo(v("x"), "is-parent-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	viaGrandpa = t.neededFactLines(spo(v("p"), "grandpa", "nobody"), family, [grandpa], 8)

	h.check("a rule variable that would read the same shows primed",
		viaGrandpa[4] == "      is-parent-of(?p, ?p')")
	h.check("the primed name is explained once, at the end",
		viaGrandpa[viaGrandpa.len - 1] ==
			"    (a name ending in ' is the rule's own variable, not one you asked about)")
	h.check("a condition the listed facts would bind is marked",
		viaGrandpa[5] == "      has-gender(?p, male)  (checked once the facts above exist)")

	// ── A body that offers a choice ────────────────────────────────────────

	// Each alternative is a way to answer, so each is reported with the facts its
	// own body would need.
	either = rule(spo(v("x"), "close", v("y")),
		[t.Or.make([[spo(v("x"), "is-sibling-of", v("y"))], [spo(v("x"), "married-to", v("y"))]])])
	choices = t.neededFactLines(spo("bill", "close", "nobody"), family, [either], 8)
	h.check("both alternatives are offered", choices.len == 6)
	h.check("the query's own shape is offered too", choices[1] == "    a fact like close(bill, nobody)")
	h.check("the rule is named once per alternative",
		choices[2] == choices[4] and choices[2].indexOf("or(") != null)
	h.check("the first alternative names its fact",
		choices[3] == "      is-sibling-of(bill, nobody)")
	h.check("the second alternative names its fact",
		choices[5] == "      married-to(bill, nobody)")

	// ── A negation is checked, never asked for ─────────────────────────────

	// Nothing added to the graph can make an absence true, so not(...) is judged
	// against what is known: met, it adds nothing to the report; failed, it rules
	// that way through the rule out entirely.
	only = rule(spo(v("x"), "is-only-child-of", v("y")),
		[spo(v("y"), "is-parent-of", v("x")), t.Not.make([spo(v("x"), "is-sibling-of", v("q"))])])
	unmet = t.neededFactLines(spo("tim", "is-only-child-of", "nobody"), family, [only], 8)
	h.check("a negation that holds asks for no fact", unmet.len == 4)
	h.check("the fact the body still needs is the one before it",
		unmet[3] == "      is-parent-of(nobody, tim)")
	h.check("the rule line prints the negation it checks",
		unmet[2] == "    through rule is-only-child-of(?x, ?y) <- is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q))")

	// Bill has a brother, so no fact would make him an only child: the rule is not
	// offered at all, and the query's own shape is all that is left.
	sibs = [spo("walter", "is-parent-of", "bill"), spo("walter", "is-parent-of", "george"),
		spo("doris", "is-parent-of", "bill"), spo("doris", "is-parent-of", "george")]
	siblingOf = rule(spo(v("x"), "is-sibling-of", v("y")),
		[spo(v("p"), "is-parent-of", v("x")), spo(v("p"), "is-parent-of", v("y")),
			t.NotEqual.make(v("x"), v("y"))])
	ruledOut = t.neededFactLines(spo("bill", "is-only-child-of", "walter"), sibs,
		[siblingOf, only], 8)
	h.check("a body its negation rules out is not offered", ruledOut.len == 2)
	h.check("only the query's own shape is left",
		ruledOut[1] == "    a fact like is-only-child-of(bill, walter)")

	// ── Painting is opt-in: no style, no escape codes ──────────────────────

	h.check("an unpainted report stays plain text", lines[1].indexOf(char(27)) == null)

	// The engine only ever places the caller's own strings, so a style of markers
	// shows exactly which pieces got painted where.
	mark = {"header": "<h>", "warning": "<w>", "fact": "<f>", "rule": "<r>",
		"var": "<v>", "normal": "</>"}
	painted = t.neededFactLines(asked, family, [], 8, mark)
	h.check("a painted header opens and closes its line",
		painted[0] == "<h>  A solution would need one of these:</>")
	h.check("a painted fact dims each variable inside it",
		painted[1] == "    a fact like <f>is-parent-of(<v>?p</><f>, susan)</>")

	paintedRule = t.neededFactLines(spo(v("x"), "is-grandparent-of", "nobody"), lineage,
		[grandparent], 8, mark)
	h.check("a painted rule path opens with its rule",
		paintedRule[2] ==
			"<r>    through rule is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)</>")
	h.check("a painted rule path paints the facts under it",
		paintedRule[3] == "      <f>is-parent-of(<v>?p</><f>, nobody)</>")
end function
