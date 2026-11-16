// rules.ms — the rules this program uses: what follows from the facts in facts.ms.
//
// The rules are built on request rather than at load time, because they have to come
// from the host's copy of triples.ms: a module that imports triples.ms gets a copy of
// its own, and the solver only recognizes the copy it holds. main.ms hands its copy
// in, and gets the array back:
//
//   import "rules"
//   rules = globals["rules"].build(triples)
//
// The shorthands inside build() are local for a related reason: this interpreter
// cannot call a function it only holds in a variable, but a closure over the passed-in
// module can. The Rule class itself lives in rule.ms.

import "rule"

build = function(triples)
	// The class, so a rule is built with Rule.make below. It is aliased here rather
	// than at the top of the file because a nested function sees the enclosing
	// function's locals and the imported modules, not this module's own globals.
	Rule = rule.Rule
	fact = function(subject, predicate, object)
		"Builds one triple of a rule."
		return triples.SpoTriple.make(subject, predicate, object)
	end function
	rule = function(head, body)
		"Defines a rule: head is the then-part, body a list of conditions."
		return Rule.make(head, body)
	end function
	var = function(name)
		"Builds a logic variable, e.g. var(""x"") for ?x."
		return triples.Var.make(name)
	end function
	notEqual = function(left, right)
		"Builds a 'these two terms must differ' constraint."
		return triples.NotEqual.make(left, right)
	end function

	// (<- (child-of ?x ?y) (parent-of ?y ?x)): if y is a parent of x, x is the child
	// of y.
	childOf = rule(
		fact(var("x"), "child-of", var("y")),
		[fact(var("y"), "parent-of", var("x"))])

	// (<- (married-to ?y ?x) (married-to ?x ?y)): marriage is a two-way street, so
	// one fact per couple can answer from either side.
	marriedBothWays = rule(
		fact(var("y"), "married-to", var("x")),
		[fact(var("x"), "married-to", var("y"))])

	// (<- (sibling-of ?x ?y) (parent-of ?p ?x) (parent-of ?p ?y) (?x != ?y)): two
	// people are siblings when they share at least one parent, so half-siblings
	// count too, and nobody is their own sibling.
	siblingOf = rule(
		fact(var("x"), "sibling-of", var("y")),
		[
			fact(var("p"), "parent-of", var("x")),
			fact(var("p"), "parent-of", var("y")),
			notEqual(var("x"), var("y")),
		])

	// (<- (brother-of ?x ?y) (sibling-of ?x ?y) (has-gender ?x male)): ?x is a brother
	// of ?y when ?x is a male sibling, so the gender is asked of ?x rather than of ?y.
	brotherOf = rule(
		fact(var("x"), "brother-of", var("y")),
		[
			fact(var("x"), "sibling-of", var("y")),
			fact(var("x"), "has-gender", "male"),
		])

	// (<- (sister-of ?x ?y) (sibling-of ?x ?y) (has-gender ?x female)): ?x is a sister
	// of ?y when ?x is a female sibling.
	sisterOf = rule(
		fact(var("x"), "sister-of", var("y")),
		[
			fact(var("x"), "sibling-of", var("y")),
			fact(var("x"), "has-gender", "female"),
		])

	// (<- (uncle-of ?x ?y) (parent-of ?p ?y) (sibling-of ?x ?p) (has-gender ?x male)):
	// ?x is an uncle of ?y when ?x is a male sibling of one of ?y's parents.
	uncleOf = rule(
		fact(var("x"), "uncle-of", var("y")),
		[fact(var("p"), "parent-of", var("y")), fact(var("x"), "sibling-of", var("p")),
			fact(var("x"), "has-gender", "male")])

	// (<- (aunt-of ?x ?y) (parent-of ?p ?y) (sibling-of ?x ?p) (has-gender ?x female)):
	// ?x is an aunt of ?y when ?x is a female sibling of one of ?y's parents.
	auntOf = rule(
		fact(var("x"), "aunt-of", var("y")),
		[fact(var("p"), "parent-of", var("y")), fact(var("x"), "sibling-of", var("p")),
			fact(var("x"), "has-gender", "female")])

	// (<- (grandpa-of ?x ?y) (parent-of ?p ?y) (parent-of ?x ?p) (has-gender ?x male)):
	// ?x is a grandpa of ?y when ?x is a male parent of one of ?y's parents.
	grandpaOf = rule(
		fact(var("x"), "grandpa-of", var("y")),
		[fact(var("p"), "parent-of", var("y")), fact(var("x"), "parent-of", var("p")),
			fact(var("x"), "has-gender", "male")])

	// (<- (grandma-of ?x ?y) (parent-of ?p ?y) (parent-of ?x ?p) (has-gender ?x female)):
	// ?x is a grandma of ?y when ?x is a female parent of one of ?y's parents.
	grandmaOf = rule(
		fact(var("x"), "grandma-of", var("y")),
		[fact(var("p"), "parent-of", var("y")), fact(var("x"), "parent-of", var("p")),
			fact(var("x"), "has-gender", "female")])

	return [childOf, marriedBothWays, siblingOf, brotherOf, sisterOf, uncleOf, auntOf, grandpaOf, grandmaOf]
end function
