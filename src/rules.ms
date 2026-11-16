// rules.ms — if/then rules over SPO triples.
//
// A rule has a head (the then-part, one triple) and a body (the if-part: the
// conditions that must all hold). Variables are Var terms from triples.ms, which
// is how the ?x / ?y of the Lisp form map onto triple fields:
//
//   (<- (child ?x ?y) (parent ?y ?z))
//
// becomes (spo() and var() being the triples.ms shorthands)
//
//   import "rules"
//   sibling = rules.rule(
//       spo(var("x"), "child", var("y")),   // head: the then-part
//       spo(var("y"), "parent", var("z")))  // body: the if-part
//   print sibling.text   // spo(?x | child | ?y) <- spo(?y | parent | ?z)
//
// Head comes first and conditions after it, matching (<- head body...). Pass one
// triple for a single condition, or a list for several.
//
// This module does not import triples.ms on purpose: a module that imports
// another gets its own copy of it, and rules only ever hold triples, never build
// or type-check them.

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

rule = function(head, body=null)
	"Defines a rule: head is the then-part, body one condition or a list of them."
	if body == null then return Rule.make(head, [])
	if body isa list then return Rule.make(head, body)
	return Rule.make(head, [body])
end function
