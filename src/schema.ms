// schema.ms — the type of each predicate's fields, as data/schema.kb writes them.
//
// The file names each predicate the knowledge base uses, stored or derived by a rule, and
// the type of its two fields in the order a fact writes them:
//
//   has-birthdate(text, unique(date))
//
// A type is the word number, text, boolean, date, time or datetime, or a '|' list of the
// values allowed, such as male|female.
//
// unique(...) around one field's type says that field takes at most one value for each of
// the other: one birthdate per person rather than a list of them. It is checked against the
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
// A schema line names a predicate, and a name has a shape, so the map is held to it where a
// schema is admitted - at startup and in /load-schema - by misnamed, which is handed the
// caller's copy of the solver since the shape is the solver's to know.
//
// A predicate the file does not name is taken as it is written, so the schema grows
// with the family rather than standing in its way.

import "knowledge"
import "temporal"

build = function(path=null)
	"Reads the schema file at path - data/schema.kb when none is named - and returns {predicate: [field type, field type]}, or an error."
	if path == null then path = "../data/schema.kb"
	return knowledge.loadSchema(info(@build).sourceLoc, path)
end function

misnamed = function(triples, types)
	"Says a schema line names a predicate that is not a name, as an error naming it, or null when every name is one."
	for predicate in types.indexes
		problem = triples.predicateProblem(predicate)
		if problem != null then return err(problem + ": " + predicate)
	end for
	return null
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

uniqueTaken = function(types, facts, triple)
	"The fact the triple would take the place of, as {at, held, message}, or null when the pair is free."
	return knowledge.uniqueTaken(types, facts, triple)
end function

derivedUniques = function(types, rules)
	"Says which unique(...) sits on a predicate a rule concludes, as an error, or null when none does."
	return knowledge.derivedUniques(types, rules)
end function

// The object the three date types mean. A fact keeps its value as text, and temporal.ms's
// receive turns a fitting text into a Temporal, which formats, moves and orders it. The
// reader is handed on here so a caller holding a fact's text never needs a second import:
//
//   when = schema.receive("2019-04-01 09:30:00")
//   print when.str("HH:mm")

Temporal = temporal.Temporal

receive = function(text, kind=null)
	"Reads a date, time or datetime text into a Temporal, or says what is wrong with it."
	return temporal.receive(text, kind)
end function
