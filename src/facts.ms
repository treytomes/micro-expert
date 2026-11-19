// facts.ms — the fact loader: the family's facts are data, in data/facts.kb by default.
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
// data/rules.kb says what follows from these, and main.ms assembles both and starts the
// session with them.

import "knowledge"

build = function(triples, path=null)
	"Reads the facts file at path - data/facts.kb when none is named - and returns its triples, or an error."
	if path == null then path = "../data/facts.kb"
	return knowledge.loadFacts(triples, info(@build).sourceLoc, path)
end function
