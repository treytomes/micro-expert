// providers.ms — the services a session can ask for a fact it needs.
//
// A service is a map (src/spike/ipwhois_map.ms and its neighbours), and an endpoint that can
// answer a fact says so in its own "provides" block. This module collects those declarations
// into one registry and runs the one that can supply a fact the facts and rules did not. Nothing
// here knows a service by name: a capability exists because a map declares it.
//
//   import "providers"
//
//   registry = providers.registry(api, declared, uid,
//       [globals["spike/ipwhois_map"].build()])
//   capability = providers.forGoal(registry, triples, triple)
//   answer = providers.answer(capability, triples)
//
// A capability is one fact one endpoint can answer:
//
//   "provides": [
//       {"fact": ["has-location", "session", "?place"], "request": {}, "timeout": 10},
//   ]
//
// "fact" is the shape the endpoint answers, in the same three parts a fact has. A part that is a
// variable matches anything; a literal part matches only that term, so ipwho.is's lookup answers
// has-location(session, ?p) and not has-location(tim, ?p). "request" is what the endpoint is
// asked for - the options declared.fetch takes - and "timeout" the seconds it may take; both are
// optional, the timeout falling back to the one below. One endpoint may declare one capability or
// a list of them, and an endpoint that says nothing provides none, so a map can describe a whole
// service and still answer only the facts it is good for.
//
// The reading is the map's own: declared.read turns the reply into facts, the same lines the
// reply always writes, so a provider answers with the facts the service declares rather than
// with a second description of them. What a provider's facts are worth - whether the session
// holds them, and whether it asks again - is the session's business, in src/session.ms.
//
// api, declared and uid are handed in rather than imported: a map cannot import, and the caller
// already loads the three the way the rest of the program does.

// The seconds a service may take when its declaration names no deadline. A lookup now stands
// between a question and its answer rather than before the first one, so it is short enough to
// give up on a network that is not there.
defaultTimeout = 10


serviceOf = function(decl)
	"One service's own name, for the messages that say which service answered."
	if not decl.hasIndex("service") then return "the service"
	return decl.service
end function


option = function(spec, name, fallback)
	"One optional part of a declaration, or the value to use when the map leaves it out."
	if not spec.hasIndex(name) then return fallback
	if spec[name] == null then return fallback
	return spec[name]
end function


capabilityOf = function(decl, name, spec, api, declared, uid)
	"One declared capability, with everything it needs to run."
	return {
		"service": serviceOf(decl),
		"endpoint": name,
		"fact": spec.fact,
		"request": option(spec, "request", {}),
		"timeout": option(spec, "timeout", defaultTimeout),
		"decl": decl,
		"api": api,
		"declared": declared,
		"uid": uid,
	}
end function


registry = function(api, declared, uid, maps)
	"Every fact the service maps declare an endpoint can answer, as one list."
	found = []
	for decl in maps
		for name in decl.endpoints.indexes
			endpoint = decl.endpoints[name]
			if not endpoint.hasIndex("provides") then continue
			// One endpoint may name one capability or a list of them.
			specs = endpoint.provides
			if not (specs isa list) then specs = [specs]
			for spec in specs
				if not (spec isa map) then continue
				if not spec.hasIndex("fact") then continue
				found.push capabilityOf(decl, name, spec, api, declared, uid)
			end for
		end for
	end for
	return found
end function


forGoal = function(registry, triples, triple)
	"The capability that says it can answer this fact, or null when none does."
	for capability in registry
		if fits(capability.fact, triples, triple) then return capability
	end for
	return null
end function


fits = function(pattern, triples, triple)
	"Says whether a declared fact's shape is this fact's: a variable part matches anything, a literal part only itself."
	if not (pattern isa list) then return false
	if pattern.len < 3 then return false
	if pattern[0] != triple.predicate then return false
	return sameTerm(triples, pattern[1], triple.subject) and
		sameTerm(triples, pattern[2], triple.object)
end function


sameTerm = function(triples, part, term)
	"One declared part against one of a fact's terms: a variable part is anything, a literal part only itself."
	if part isa string and part[:1] == "?" then return true
	return triples.termText(term) == part
end function


answer = function(capability, triples)
	"One provider's answer, as the facts its endpoint maps: ok with them, or ok 0 and the reason there are none."
	declared = capability.declared
	api = capability.api
	result = declared.fetch(api, capability.decl, capability.endpoint,
		capability.request, capability.timeout)
	if not result.ok then
		return {"ok": 0, "facts": [], "error": result.error}
	end if
	if result.json == null then
		return {"ok": 0, "facts": [], "error": "the service did not answer with JSON"}
	end if
	reading = declared.read(triples, capability.uid, capability.decl, capability.endpoint,
		result.json, capability.request)
	if not reading.ok then
		return {"ok": 0, "facts": [], "error": reading.error}
	end if
	return {"ok": 1, "facts": reading.facts, "error": null}
end function
