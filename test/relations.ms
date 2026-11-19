// Cases for relations between people: a rule that runs both ways, and pairs
// that hold more than one value.

run = function(t, rules, h)
	"Checks symmetric rules and multi-valued pairs, against the shared copies in t and rules."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	v = function(name)
		return t.var(name)
	end function
	rule = function(head, body)
		return rules.Rule.make(head, body)
	end function
	answerText = function(goal, answer)
		return t.substitute(goal, answer.binds).text
	end function

	// ── A rule that runs both ways ──────────────────────────────────────────

	// One marriage fact per couple, with the rule turning it around.
	marriages = [spo("walter", "married-to", "doris")]
	marriedBothWays = rule(spo(v("y"), "married-to", v("x")), [spo(v("x"), "married-to", v("y"))])

	forward = t.proveGoals(spo("walter", "married-to", "doris"), marriages, [marriedBothWays], 4)
	h.check("the stated direction holds", forward.len == 1)
	h.check("the stated direction is a fact", forward[0].reasons[0].rule == null)

	backward = t.proveGoals(spo("doris", "married-to", "walter"), marriages, [marriedBothWays], 4)
	h.check("the reverse direction is derived", backward.len == 1)
	h.check("the reverse direction cites the rule", backward[0].reasons[0].rule.text == marriedBothWays.text)
	h.check("recursion collapses into one answer despite the depth",
		t.proveGoals(spo("doris", "married-to", "walter"), marriages, [marriedBothWays], 8).len == 1)
	h.check("unrelated people are not married",
		t.proveGoals(spo("doris", "married-to", "bill"), marriages, [marriedBothWays], 4).len == 0)
	h.check("marriage does not leak into other predicates",
		t.proveGoals(spo("doris", "parent-of", "walter"), marriages, [marriedBothWays], 4).len == 0)
	h.check("the symmetry rule derives its reversal once",
		t.proveGoals(spo("doris", "married-to", "walter"), marriages, [marriedBothWays], 8)[0].reasons.len == 1)

	// ── One subject-predicate pair, many values ─────────────────────────────

	// Nothing in the triple, in the answer list or in the solver treats a
	// subject-predicate pair as unique, so a pair can hold any number of values.
	likes = [
		spo("susan", "likes", "music"),
		spo("susan", "likes", "chess"),
		spo("susan", "likes", "music"),
	]
	liked = t.proveGoals(spo("susan", "likes", v("what")), likes, [], 0)
	h.check("both values of one pair", liked.len == 2)
	h.check("first value", answerText(spo("susan", "likes", v("what")), liked[0]) == "likes(susan, music)")
	h.check("second value", answerText(spo("susan", "likes", v("what")), liked[1]) == "likes(susan, chess)")
	h.check("a repeated value merges into one answer", liked[0].reasons.len == 2)

	// Asking the pair directly still gives one answer per value.
	pair = t.proveGoals(spo("susan", "likes", "music"), likes, [], 0)
	h.check("the pair can be asked directly", pair.len == 1)
	h.check("and it cites both listed facts", pair[0].reasons.len == 2)

	// A rule ranges over every value of the pair, not just the first one.
	fanOf = rule(spo(v("a"), "fan-of", v("b")), [spo(v("a"), "likes", v("b"))])
	fans = t.proveGoals(spo("susan", "fan-of", v("what")), likes, [fanOf], 1)
	h.check("a rule sees every value", fans.len == 2)

	// Two conditions over the same pair multiply the values out: 2 x 2 answers.
	shares = [spo("bill", "parent-of", "susan"), spo("bill", "parent-of", "tim")]
	siblingRule = rule(spo(v("x"), "sibling", v("y")),
		[spo(v("z"), "parent-of", v("x")), spo(v("z"), "parent-of", v("y"))])
	siblings = t.proveGoals(spo(v("x"), "sibling", v("y")), shares, [siblingRule], 2)
	h.check("each value pairs with each", siblings.len == 4)

	// ── Siblings share a parent ────────────────────────────────────────────

	// Bill and George share both parents; Tim shares only Walter with them.
	family = [
		spo("walter", "parent-of", "bill"),
		spo("doris", "parent-of", "bill"),
		spo("walter", "parent-of", "george"),
		spo("doris", "parent-of", "george"),
		spo("walter", "parent-of", "tim"),
	]
	siblingRule = rule(spo(v("x"), "sibling-of", v("y")),
		[spo(v("p"), "parent-of", v("x")), spo(v("p"), "parent-of", v("y")),
			t.NotEqual.make(v("x"), v("y"))])
	siblingsOf = function(a, b)
		return t.proveGoals(spo(a, "sibling-of", b), family, [siblingRule], 2)
	end function

	h.check("siblings are found", siblingsOf("bill", "george").len == 1)
	h.check("siblings are found in reverse", siblingsOf("george", "bill").len == 1)
	h.check("one shared parent is enough", siblingsOf("bill", "tim").len == 1)
	h.check("two shared parents are one answer", siblingsOf("bill", "george")[0].reasons.len == 2)
	h.check("strangers are not siblings", siblingsOf("bill", "nobody").len == 0)
	h.check("a parent is not a sibling", siblingsOf("bill", "walter").len == 0)
	// The ?x != ?y constraint in the body keeps a person from being their own
	// sibling, and a constraint adds nothing to the proof tree.
	h.check("someone is not their own sibling", siblingsOf("bill", "bill").len == 0)
	h.check("the rule prints its constraint",
		siblingRule.text == "sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y")
	h.check("a two-parent sibling still has both derivations",
		siblingsOf("bill", "george")[0].reasons.len == 2)
	openSiblings = t.proveGoals(spo(v("a"), "sibling-of", v("b")), family, [siblingRule], 2)
	h.check("no self pairs in an open query", openSiblings.len == 6)

	// ── Brothers and sisters ───────────────────────────────────────────────

	// Three brothers and a sister: Bill and George share both parents, Tim shares
	// only Walter, Clara shares both but with a different gender.
	house = [
		spo("walter", "parent-of", "bill"),
		spo("doris", "parent-of", "bill"),
		spo("walter", "parent-of", "george"),
		spo("doris", "parent-of", "george"),
		spo("walter", "parent-of", "tim"),
		spo("walter", "parent-of", "clara"),
		spo("doris", "parent-of", "clara"),
		spo("bill", "has-gender", "male"),
		spo("george", "has-gender", "male"),
		spo("tim", "has-gender", "male"),
		spo("clara", "has-gender", "female"),
	]
	houseSibling = rule(spo(v("x"), "sibling-of", v("y")),
		[spo(v("p"), "parent-of", v("x")), spo(v("p"), "parent-of", v("y")),
			t.NotEqual.make(v("x"), v("y"))])
	brotherRule = rule(spo(v("x"), "brother-of", v("y")),
		[spo(v("x"), "sibling-of", v("y")), spo(v("x"), "has-gender", "male")])
	sisterRule = rule(spo(v("x"), "sister-of", v("y")),
		[spo(v("x"), "sibling-of", v("y")), spo(v("x"), "has-gender", "female")])
	kinRules = [houseSibling, brotherRule, sisterRule]

	brothers = function(a, b)
		return t.proveGoals(spo(a, "brother-of", b), house, kinRules, 4)
	end function
	sisters = function(a, b)
		return t.proveGoals(spo(a, "sister-of", b), house, kinRules, 4)
	end function

	h.check("a brother is a male sibling", brothers("bill", "george").len == 1)
	h.check("a half-brother still counts", brothers("tim", "bill").len == 1)
	h.check("a sister is a female sibling", sisters("clara", "bill").len == 1)
	h.check("a sister is not a brother", brothers("clara", "bill").len == 0)
	h.check("a brother is not a sister", sisters("bill", "george").len == 0)
	h.check("the gender belongs to the brother", brothers("bill", "clara").len == 1)
	h.check("a parent is neither", brothers("bill", "walter").len + sisters("bill", "walter").len == 0)
	h.check("both rules are needed for an answer",
		t.proveGoals(spo("bill", "brother-of", "george"), house, kinRules, 1).len == 0)
	h.check("the brother rule prints its conditions",
		brotherRule.text == "brother-of(?x, ?y) <- sibling-of(?x, ?y), has-gender(?x, male)")

	// ── Uncles, aunts and grandparents ─────────────────────────────────────

	// Walter and Doris are Bill's, George's and Clara's parents, Walter also fathered
	// Henry by someone else, Tim is Bill's son and Jack is George's: so George and
	// Henry (Bill's half-brother) are Tim's uncles and Clara is his aunt.
	lineage = [
		spo("walter", "parent-of", "bill"),
		spo("doris", "parent-of", "bill"),
		spo("walter", "parent-of", "george"),
		spo("doris", "parent-of", "george"),
		spo("walter", "parent-of", "clara"),
		spo("doris", "parent-of", "clara"),
		spo("walter", "parent-of", "henry"),
		spo("bill", "parent-of", "tim"),
		spo("george", "parent-of", "jack"),
		spo("walter", "has-gender", "male"),
		spo("bill", "has-gender", "male"),
		spo("george", "has-gender", "male"),
		spo("tim", "has-gender", "male"),
		spo("jack", "has-gender", "male"),
		spo("henry", "has-gender", "male"),
		spo("doris", "has-gender", "female"),
		spo("clara", "has-gender", "female"),
	]
	lineageSibling = rule(spo(v("x"), "sibling-of", v("y")),
		[spo(v("p"), "parent-of", v("x")), spo(v("p"), "parent-of", v("y")),
			t.NotEqual.make(v("x"), v("y"))])
	uncleRule = rule(spo(v("x"), "uncle-of", v("y")),
		[spo(v("p"), "parent-of", v("y")), spo(v("x"), "sibling-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	auntRule = rule(spo(v("x"), "aunt-of", v("y")),
		[spo(v("p"), "parent-of", v("y")), spo(v("x"), "sibling-of", v("p")),
			spo(v("x"), "has-gender", "female")])
	grandpaRule = rule(spo(v("x"), "grandpa-of", v("y")),
		[spo(v("p"), "parent-of", v("y")), spo(v("x"), "parent-of", v("p")),
			spo(v("x"), "has-gender", "male")])
	grandmaRule = rule(spo(v("x"), "grandma-of", v("y")),
		[spo(v("p"), "parent-of", v("y")), spo(v("x"), "parent-of", v("p")),
			spo(v("x"), "has-gender", "female")])
	kinAll = [lineageSibling, uncleRule, auntRule, grandpaRule, grandmaRule]

	ask = function(predicate, a, b)
		return t.proveGoals(spo(a, predicate, b), lineage, kinAll, 4)
	end function

	h.check("an uncle is a male sibling of a parent", ask("uncle-of", "george", "tim").len == 1)
	h.check("an aunt is a female sibling of a parent", ask("aunt-of", "clara", "tim").len == 1)
	h.check("a half-sibling of a parent still counts", ask("uncle-of", "henry", "tim").len == 1)
	h.check("an aunt is not an uncle", ask("uncle-of", "clara", "tim").len == 0)
	h.check("an uncle is not an aunt", ask("aunt-of", "george", "tim").len == 0)
	h.check("a parent is neither", ask("uncle-of", "bill", "tim").len == 0)
	h.check("a grandpa is a male parent of a parent", ask("grandpa-of", "walter", "tim").len == 1)
	h.check("a grandma is a female parent of a parent", ask("grandma-of", "doris", "tim").len == 1)
	h.check("a grandmother is not a grandfather", ask("grandpa-of", "doris", "tim").len == 0)
	h.check("a parent is not a grandparent", ask("grandpa-of", "bill", "tim").len == 0)
	h.check("the uncle rule prints its conditions",
		uncleRule.text == "uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)")

	// ── A body that offers a choice ─────────────────────────────────────────

	// An in-law either married into the family or is a sibling of someone who did:
	// two bodies with nothing in common but the head, which is what or(...) is for.
	household = lineage + [
		spo("bill", "married-to", "susan"),
		spo("george", "married-to", "diane"),
		spo("henry", "married-to", "rachel"),
	]
	houseMarried = rule(spo(v("y"), "married-to", v("x")), [spo(v("x"), "married-to", v("y"))])
	inLawRule = rule(spo(v("x"), "in-law-of", v("y")),
		[t.Or.make([
			[spo(v("x"), "married-to", v("p")), spo(v("p"), "sibling-of", v("y"))],
			[spo(v("x"), "sibling-of", v("p")), spo(v("p"), "married-to", v("y"))],
		])])
	inLaw = function(a, b)
		return t.proveGoals(spo(a, "in-law-of", b), household,
			[lineageSibling, houseMarried, inLawRule], 4)
	end function

	h.check("the first alternative answers", inLaw("diane", "bill").len == 1)
	h.check("the second alternative answers", inLaw("bill", "diane").len == 1)
	h.check("a spouse is not an in-law", inLaw("bill", "susan").len == 0)
	h.check("a blood relative is not an in-law", inLaw("tim", "bill").len == 0)
	proof = t.proofLines(inLaw("bill", "diane")[0], "").join("\n")
	h.check("the proof leaves out the alternative that did not hold",
		proof.indexOf("married-to(bill, susan)") == null)
	h.check("the proof names what the alternative that held proved",
		proof.indexOf("married-to(george, diane)") != null)
	h.check("the rule prints its alternatives",
		inLawRule.text == "in-law-of(?x, ?y) <- or(and(married-to(?x, ?p), sibling-of(?p, ?y)), and(sibling-of(?x, ?p), married-to(?p, ?y)))")

	// An or(...) among other conditions: the parent condition is shared, and either
	// one of these completes the answer.
	care = [
		spo("anna", "parent-of", "tim"),
		spo("bill", "sibling-of", "anna"),
		spo("susan", "married-to", "anna"),
	]
	guardianRule = rule(spo(v("x"), "guardian-of", v("y")),
		[spo(v("p"), "parent-of", v("y")),
			t.Or.make([[spo(v("x"), "sibling-of", v("p"))], [spo(v("x"), "married-to", v("p"))]])])
	guardians = t.proveGoals(spo(v("x"), "guardian-of", "tim"), care, [guardianRule], 2)
	h.check("an or(...) among other conditions offers each alternative", guardians.len == 2)
	h.check("each alternative binds the shared condition",
		guardians[0].binds["x"] == "bill" and guardians[1].binds["x"] == "susan")
end function
