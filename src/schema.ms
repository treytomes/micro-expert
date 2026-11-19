// schema.ms — the type of each predicate's fields, as data/schema.kb writes them.
//
// The file names each predicate the knowledge base uses, stored or derived by a rule, and
// the type of its two fields in the order a fact writes them:
//
//   has-age(text, number)
//
// A type is the word number, text or boolean, or a '|' list of the values allowed, such
// as male|female. knowledge.ms reads that format; this module finds the file and hands
// the map back, so the prompt can refuse a fact that does not fit before storing it:
//
//   import "schema"
//   types = globals["schema"].build()
//   problem = schema.misfit(types, triple)   // null, or "the object should be a number"
//
// A predicate the file does not name is taken as it is written, so the schema grows
// with the family rather than standing in its way.

import "knowledge"

build = function()
	"Reads the schema data and returns {predicate: [field type, field type]}, or an error."
	return knowledge.loadSchema(info(@build).sourceLoc, "../data/schema.kb")
end function

misfit = function(types, triple)
	"How the triple misses the schema it is checked against, or null when it fits."
	return knowledge.schemaMisfit(types, triple)
end function
