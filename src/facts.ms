// facts.ms — the family the program reasons about.
//
// A fact is one SPO triple: subject, predicate, object. Nothing here is derived;
// rules.ms says what follows from these, and main.ms assembles both and asks the
// query at the bottom of it.
//
// The facts are built on request rather than at load time, because they have to come
// from the host's copy of triples.ms: a module that imports triples.ms gets a copy of
// its own, and the solver only recognizes triples from the copy it holds. So main.ms
// hands its copy in, and the fact() below builds with it:
//
//   import "facts"
//   facts = globals["facts"].build(triples)
//
// The shorthand is local rather than passed in because this interpreter cannot call a
// function it only holds in a variable - only named functions and map members - so a
// local closure over the passed-in module is how it has to be done.

build = function(triples)
	fact = function(subject, predicate, object)
		"Builds one fact: a Subject-Predicate-Object triple."
		return triples.SpoTriple.make(subject, predicate, object)
	end function

	return [
		// Walter and Doris.
		fact("walter", "has-gender", "male"),
		fact("walter", "has-age", 78),
		fact("doris", "has-gender", "female"),
		fact("doris", "has-age", 76),
		fact("walter", "married-to", "doris"),

		// Their three sons.
		fact("walter", "parent-of", "bill"),
		fact("doris", "parent-of", "bill"),
		fact("walter", "parent-of", "george"),
		fact("doris", "parent-of", "george"),
		fact("walter", "parent-of", "henry"),
		fact("doris", "parent-of", "henry"),
		fact("bill", "has-gender", "male"),
		fact("bill", "has-age", 54),
		fact("george", "has-gender", "male"),
		fact("george", "has-age", 51),
		fact("henry", "has-gender", "male"),
		fact("henry", "has-age", 47),

		// Bill and Susan, with one son.
		fact("bill", "married-to", "susan"),
		fact("susan", "has-gender", "female"),
		fact("susan", "has-age", 52),
		fact("bill", "parent-of", "tim"),
		fact("susan", "parent-of", "tim"),
		fact("tim", "has-gender", "male"),
		fact("tim", "has-age", 24),

		// George and Diane, with a daughter and a son.
		fact("george", "married-to", "diane"),
		fact("diane", "has-gender", "female"),
		fact("diane", "has-age", 49),
		fact("george", "parent-of", "anna"),
		fact("diane", "parent-of", "anna"),
		fact("george", "parent-of", "mark"),
		fact("diane", "parent-of", "mark"),
		fact("anna", "has-gender", "female"),
		fact("anna", "has-age", 21),
		fact("mark", "has-gender", "male"),
		fact("mark", "has-age", 18),

		// Henry and Rachel, with two daughters and two sons.
		fact("henry", "married-to", "rachel"),
		fact("rachel", "has-gender", "female"),
		fact("rachel", "has-age", 45),
		fact("henry", "parent-of", "clara"),
		fact("rachel", "parent-of", "clara"),
		fact("henry", "parent-of", "jack"),
		fact("rachel", "parent-of", "jack"),
		fact("henry", "parent-of", "nina"),
		fact("rachel", "parent-of", "nina"),
		fact("henry", "parent-of", "oliver"),
		fact("rachel", "parent-of", "oliver"),
		fact("clara", "has-gender", "female"),
		fact("clara", "has-age", 15),
		fact("jack", "has-gender", "male"),
		fact("jack", "has-age", 13),
		fact("nina", "has-gender", "female"),
		fact("nina", "has-age", 10),
		fact("oliver", "has-gender", "male"),
		fact("oliver", "has-age", 7),
	]
end function
