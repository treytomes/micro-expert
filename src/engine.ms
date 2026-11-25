// engine.ms — the session a run is made of, built from the options a command line parsed.
//
// The program is one session, whether it is typed at or served to a notebook, so what makes
// it lives here rather than in an entry point:
//
//   import "engine"
//
//   session = engine.build(triples, Rule, options, style)
//   session.providers = providers.registry(api, declared, uid, maps)
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
// providers is the one field a run fills in after build: the services a question may ask for a
// fact it needs, which main.ms builds from the service maps with src/providers.ms. build answers
// null, so a session nobody gave a registry - a notebook's - starts from the domain's files and
// asks nothing of the network, and this module stays clear of the API layer either way.
//
// offline is --offline, and it is build's business because it comes from the command line: a
// session that carries it asks nothing of the network even when it is handed a registry.

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
		"offline": options.values.offline,
		"style": style,
		"schema": schema,
		"types": types,
		"paths": paths,
		"knowledge": knowledge,
		"providers": null,
	}
end function
