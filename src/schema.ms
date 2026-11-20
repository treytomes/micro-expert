// schema.ms — the type of each predicate's fields, as data/schema.kb writes them.
//
// The file names each predicate the knowledge base uses, stored or derived by a rule, and
// the type of its two fields in the order a fact writes them:
//
//   has-age(text, unique(number))
//
// A type is the word number, text or boolean, or a '|' list of the values allowed, such
// as male|female.
//
// unique(...) around one field's type says that field takes at most one value for each of
// the other: one age per person rather than a list of them. It is checked against the
// facts already held, since a value can fit its type and still be the second one for that
// subject, and a predicate a rule concludes cannot carry it - there is no place where a
// fact of that predicate is added to refuse. knowledge.ms reads that format; this module
// finds the file and hands
// the map back, so the prompt can refuse a fact that does not fit before storing it:
//
//   import "schema"
//   types = globals["schema"].build()
//   problem = schema.misfit(types, triple)   // null, or "the object should be a number"
//
// A predicate the file does not name is taken as it is written, so the schema grows
// with the family rather than standing in its way.

import "knowledge"

build = function(path=null)
	"Reads the schema file at path - data/schema.kb when none is named - and returns {predicate: [field type, field type]}, or an error."
	if path == null then path = "../data/schema.kb"
	return knowledge.loadSchema(info(@build).sourceLoc, path)
end function

misfit = function(types, triple)
	"How the triple misses the schema it is checked against, or null when it fits."
	return knowledge.schemaMisfit(types, triple)
end function

plainType = function(type)
	"The type a field is checked against and asked for, with a unique(...) wrapper taken off."
	return knowledge.plainType(type)
end function

uniqueClash = function(types, facts, triple)
	"How the triple would give a unique(...) field a second value, naming the fact that holds the first, or null."
	return knowledge.uniqueClash(types, facts, triple)
end function

derivedUniques = function(types, rules)
	"Says which unique(...) sits on a predicate a rule concludes, as an error, or null when none does."
	return knowledge.derivedUniques(types, rules)
end function
