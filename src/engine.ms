// engine.ms — the session a run is made of, built from the options a command line parsed.
//
// The program is one session, whether it is typed at or served to a notebook, so what makes
// it lives here rather than in an entry point:
//
//   import "engine"
//
//   session = engine.build(triples, Rule, options, style)
//   engine.includePlace(session, location, uid, client, declared, decl, log)
//   replSession.run(session)
//
// build reads the domain's three files and answers the session they make, or the error
// saying which one would not read. The triples module and the Rule class are handed in for
// the reason the loaders are handed triples: a module that imports triples.ms gets a copy of
// its own, so a build has to make the classes the caller's solver already knows.
//
// io is not build's business. How a session talks belongs to the host - main.ms gives it
// input and print, notebook.ms gives it a notebook's writer - so it is set on the session
// once build has answered.
//
// includePlace stands apart because it is a network lookup with a wait: a run at the prompt
// says where it is and holds the place's facts, while a notebook starts from the domain's
// files with no request at all. It is handed the pieces that lookup reads - the location
// module, the id generator, the client, the declared writer and ipwho.is's map - so this
// module stays clear of the API layer and of the bundled libraries behind it.

import "domain"
import "facts"
import "rules"
import "schema"
import "knowledge"

build = function(triples, Rule, options, style)
	"The session a run is made of, or an error naming the file that would not read."
	paths = domain.pathsFor(options.values)

	// The schema is read first, because a unique(...) field is a property of the whole facts
	// file rather than of one line: two facts that each fit can still be one too many for a
	// pair, so the loader has to know the types to say so.
	types = schema.build(paths.schema)
	if types isa error then return types

	// The schema names predicates, so its names are held to the shape a result can say: a
	// line naming one another way is refused rather than loaded and never matched to a fact.
	misnamed = schema.misnamed(triples, types)
	if misnamed isa error then return misnamed

	// The arrays themselves, not the module maps that hold them. The facts loader is handed
	// the types, so a file that stores one pair twice is refused as the prompt would refuse it.
	loadedFacts = facts.build(triples, paths.facts, types)
	if loadedFacts isa error then return loadedFacts
	loadedRules = rules.build(triples, paths.rules)
	if loadedRules isa error then return loadedRules

	// A unique(...) field is enforced where a fact is added, and a predicate a rule concludes
	// is never added: it is derived. So a unique(...) on one is a promise the program has no
	// place to keep, and the schema is refused rather than loaded and left unenforced.
	unenforceable = knowledge.derivedUniques(types, loadedRules)
	if unenforceable isa error then return unenforceable

	return {
		"triples": triples,
		"Rule": Rule,
		"facts": loadedFacts,
		"rules": loadedRules,
		"depth": options.values.depth,
		"verbose": options.values.verbose,
		"nlp": options.values.nlp,
		"style": style,
		"schema": schema,
		"types": types,
		"paths": paths,
		"knowledge": knowledge,
	}
end function

includePlace = function(session, location, uid, client, declared, decl, log=null)
	"Adds the place the lookup answers with, or says through log why it is not there."
	here = location.sessionFacts(session.triples, uid, client, declared, decl)
	if not here.ok then
		if log != null then log.warning "{Warning}", {"Warning": here.error}
		return here
	end if
	// A domain that already holds the place's facts is not given them twice.
	held = {}
	for known in session.facts
		held[known.text] = 1
	end for
	for placeFact in here.facts
		if not held.hasIndex(placeFact.text) then
			session.facts.push(placeFact)
			held[placeFact.text] = 1
		end if
	end for
	return here
end function
