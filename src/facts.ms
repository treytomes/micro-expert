// facts.ms — the fact loader: the family's facts are data now, in facts.data beside
// this file.
//
// A fact is written there as one triple per line:
//
//   parent-of(walter, bill)
//   has-gender(bill, male)
//   has-age(bill, 54)
//
// knowledge.ms reads that format; this module finds the file and builds the triples
// with the caller's copy of triples.ms, because a module that imports triples.ms gets
// a copy of its own and the solver only recognizes the copy it holds:
//
//   import "facts"
//   facts = globals["facts"].build(triples)
//
// rules.data says what follows from these, and main.ms assembles both and asks the
// query at the bottom of it.

import "knowledge"

build = function(triples)
	"Reads the facts data and returns its triples, built with the caller's triples, or an error."
	return knowledge.loadFacts(triples, info(@build).sourceLoc, "facts.data")
end function
