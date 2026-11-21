// rule.ms — one rule: a head triple, and a body of conditions that must all hold.
//
// Variables are Var terms from triples.ms, which is how the ?x / ?y of the Lisp form
// map onto triple fields:
//
//   (<- (is-child-of ?x ?y) (is-parent-of ?y ?x))
//
// becomes
//
//   childOf = Rule.make(
//       fact(var("x"), "is-child-of", var("y")),      // head: the then-part
//       [fact(var("y"), "is-parent-of", var("x"))])   // body: a list of conditions
//   print childOf.text    // is-child-of(?x, ?y) <- is-parent-of(?y, ?x)
//
// Head comes first and conditions after it, matching (<- head body...). The body is
// always a list, so a single condition is a list of one. A body may also hold a
// constraint such as not-equal(?x, ?y) instead of a triple - see the constraints in
// triples.ms.
//
// This module imports nothing, on purpose: a rule only stores and prints the triples
// it is given, so it needs no copy of triples.ms and works with whichever copy built
// them. rules.ms loads the rules themselves, from data/rules.kb.

Rule = {}

Rule.make = function(head, body)
	"Builds a rule from a head triple and a list of body triples."
	r = new Rule
	r.head = head
	r.body = body
	return r
end function

Rule.text = function
	"Formats the rule as 'head <- conditions', the Lisp arrow pointing left."
	conditions = []
	for condition in self.body
		conditions.push(condition.text)
	end for
	if conditions.len == 0 then
		return self.head.text + " <- (no conditions)"
	end if
	return self.head.text + " <- " + conditions.join(", ")
end function
