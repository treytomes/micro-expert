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
//   capabilities = providers.fittingTo(registry, triples, triple)
//   answer = providers.answer(capability, triples)
//
// forGoal names the first service that says it can answer a fact; fittingTo names every one that
// does, in the order the maps were given. A session asks them in that order and stops at the one
// that answers, so two maps declaring one fact - both geocoders declare a place's coordinates -
// is a second chance rather than a silent choice by registry order.
//
// A capability is one fact one endpoint can answer:
//
//   "provides": [
//       {"fact": ["has-location", "session", "?place"], "request": {}, "timeout": 10},
//   ]
//
// "fact" is the shape the endpoint answers, in the same three parts a fact has. A part that is a
// variable matches only a fact still unknown there, which is what the reply fills; a literal part
// matches only that term, so ipwho.is's lookup answers has-location(session, ?p) and not
// has-location(tim, ?p) or the already-ground has-location(session, Dallas), which no reply can be
// counted on to prove. "request" is what the endpoint is
// asked for - the options declared.fetch takes - and "timeout" the seconds it may take; both are
// optional, the timeout falling back to the one below. One endpoint may declare one capability or
// a list of them, and an endpoint that says nothing provides none, so a map can describe a whole
// service and still answer only the facts it is good for.
//
// A declaration may also say what its request is asked with, when the reply is read back onto the
// place the question names rather than onto an identity of the service's own:
//
//   "provides": [
//       {"fact": ["has-latitude", "?place", "?lat"], "about": "?place",
//        "from": {"q": ["has-name", "has-city"]}, "request": {"limit": 1}},
//   ]
//
// "about" names the declared part the reply's facts are read onto: a question may name that part
// - has-latitude(place-1, ?lat) - and each fact the reply writes is then about the place the
// question named. "from" fills the request's fields from facts the session already holds about
// that place, here the first of its has-name and has-city, so a service that needs an address or
// a coordinate before it can answer is asked with the one the question already settled. A field
// with no fact to fill it leaves the capability unusable for that question, and the session asks
// the reader instead.
//
// A request the session cannot fill is not sent: requestFor answers null. unfilledFor names the
// fields it could not fill, each with the predicates that would fill it, so the session can ask
// another service for one of those facts first - the geocoder's search answers a named place's
// coordinates, and the forecast is asked with them - and then come round to this request with
// what it was missing. Nothing here decides that: the fields are named, and src/session.ms does
// the asking.
//
// "about" also tells the reading which place it was asked about. A reply such as a forecast's
// names the place by nothing but the coordinates the request carried, and its reading wants the
// place as its subject, so the part the declaration reads onto - "?place" - is bound to that
// place for the reading, under the part's own name. It is given to the reading rather than
// sent, so the request holds only the fields the declaration fills and names, and the service is
// never asked a field it has no use for.
//
// The reading is the map's own: declared.read turns the reply into facts, the same lines the
// reply always writes, so a provider answers with the facts the service declares rather than
// with a second description of them. The session's facts about the place go with the reading, so
// a declaration can confirm the reply is that place - a search takes its first result, and
// another Fort Worth would otherwise be read as this one - and a reply that disagrees is a
// warning like any other failure, so the next declaration is asked. What a provider's facts are worth - whether the session
// holds them, and whether it asks again - is the session's business, in src/session.ms.
//
// Every fact a service answers carries "# <service>/<endpoint> <day>" in its own line: which
// service and endpoint gave it, and the day they were asked. A session - or a facts file it
// saves, since the line is what a file writes - can therefore tell a provider's fact from a
// typed one, and see how stale it is. The day is the search's own, from triples.dayToday, so a
// caller that pins today (the suite does) gets the day it pinned.
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
		"about": option(spec, "about", null),
		"from": option(spec, "from", {}),
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
	"The first capability that says it can answer this fact, or null when none does."
	found = fittingTo(registry, triples, triple)
	if found.len == 0 then return null
	return found[0]
end function


fittingTo = function(registry, triples, triple)
	"Every capability whose declared shape is this fact's, in the order the maps were given - two services may declare one fact, and a session asks each in turn."
	found = []
	for capability in registry
		if fits(capability, triples, triple) then found.push capability
	end for
	return found
end function


fits = function(capability, triples, triple)
	"Says whether a declared fact's shape is this fact's: a variable part only while the fact is unknown there, a literal part only itself."
	pattern = capability.fact
	if not (pattern isa list) then return false
	if pattern.len < 3 then return false
	if pattern[0] != triple.predicate then return false
	return answers(triples, pattern[1], triple.subject, capability.about) and
		answers(triples, pattern[2], triple.object, null)
end function


answers = function(triples, part, term, about)
	"One declared part against one of a fact's terms: a variable part is a term still unknown, which the reply fills, or the part the declaration reads its reply onto; a literal part only itself."
	if part isa string and part[:1] == "?" then
		if triples.isVar(term) then return true
		return about != null and about == part
	end if
	return triples.termText(term) == part
end function


heldFrom = function(triples, facts, subject, wanted, freshOnly=0)
	"One field's value: the first of these predicates the session holds a fact for about this subject, today's reading before an earlier day's, or null when it holds none - or holds only earlier readings and freshOnly asks for today's."
	for predicate in wanted
		value = heldTerm(triples, facts, subject, predicate, freshOnly)
		if value != null then return value
	end for
	return null
end function


requestFor = function(capability, triples, facts, subject, freshOnly=0)
	"The request to send, its fields filled from facts the session holds about the subject - today's readings first, since a request sent now should not be computed from a day-old one - or null when one of them has no fact to fill it, or freshOnly asks for a newer reading than the session holds."
	request = capability.request + {}
	for name in capability.from.indexes
		wanted = capability.from[name]
		if not (wanted isa list) then wanted = [wanted]
		value = heldFrom(triples, facts, subject, wanted, freshOnly)
		if value == null then return null
		request[name] = value
	end for
	return request
end function


unfilledFor = function(capability, triples, facts, subject, freshOnly=0)
	"One request's fields no held fact answers - or, when freshOnly asks for today's reading, only earlier days' answers - each with the predicates that would fill it, in field-name order: the facts another service may be asked for."
	unfilled = []
	for name in capability.from.indexes
		wanted = capability.from[name]
		if not (wanted isa list) then wanted = [wanted]
		if heldFrom(triples, facts, subject, wanted, freshOnly) == null then
			unfilled.push({"field": name, "predicates": wanted})
		end if
	end for
	unfilled.sort "field"
	return unfilled
end function


heldTerm = function(triples, facts, subject, predicate, freshOnly=0)
	"The value a held fact gives this subject under this predicate - a typed fact or today's reading first, an earlier day's only when no newer one is asked for - or null when it gives none."
	today = triples.dayText(triples.dayToday())
	older = null
	for fact in facts
		if fact.predicate != predicate then continue
		if triples.termText(fact.subject) != triples.termText(subject) then continue
		if triples.isVar(fact.object) then continue
		// A typed fact is the session's own and never stale; a reading is fresh the day it was
		// fetched, and stands in only for want of a newer one.
		if fact.source == null or fact.fetched == today then return fact.object
		if older == null then older = fact.object
	end for
	if freshOnly then return null
	return older
end function


requestText = function(request)
	"One request's fields as text, so the session's one-attempt memory tells two places apart."
	names = request.indexes
	names.sort
	parts = []
	for name in names
		parts.push name + "=" + str(request[name])
	end for
	return parts.join("&")
end function


askedFor = function(capability, request, subject)
	"One request as its reply is read: a declaration that reads its reply onto the question's part also binds that part to the place the question named, for a reply that names the place by nothing else."
	asked = request + {}
	if capability.about == null or subject == null then return asked
	name = capability.about[1:]
	if not asked.hasIndex(name) then asked[name] = subject
	return asked
end function


answer = function(capability, triples, request=null, subject=null, facts=null)
	"One provider's answer, as the facts its endpoint maps: ok with them, or ok 0 and the reason there are none. The facts the session holds let a declaration confirm the reply is about the place it was asked about."
	declared = capability.declared
	api = capability.api
	if request == null then request = capability.request
	result = declared.fetch(api, capability.decl, capability.endpoint, request, capability.timeout)
	if not result.ok then
		return {"ok": 0, "facts": [], "error": result.error}
	end if
	if result.json == null then
		return {"ok": 0, "facts": [], "error": "the service did not answer with JSON"}
	end if
	// What the session already holds about the place goes with the reply, filtered to that
	// subject: a declaration that names the fields making a reply the place asked about checks
	// them against these, so the first result of a search is refused when it is another place.
	held = []
	if facts != null and subject != null then
		for fact in facts
			if triples.termText(fact.subject) == triples.termText(subject) then held.push fact
		end for
	end if
	reading = declared.read(triples, capability.uid, capability.decl, capability.endpoint,
		result.json, askedFor(capability, request, subject), held)
	if not reading.ok then
		return {"ok": 0, "facts": [], "error": reading.error}
	end if
	// A declaration that says which part its reply is about reads the reply onto the place the
	// question named, so the facts prove that question rather than one about an identity the
	// service made up.
	facts = reading.facts
	if capability.about != null and subject != null then
		moved = []
		for fact in facts
			moved.push triples.SpoTriple.make(subject, fact.predicate, fact.object, fact.at,
				fact.confidence)
		end for
		facts = moved
	end if
	// Who answered, and when: the fact says it in its own line, so a saved file keeps it, and a
	// question that reads the fact back knows where it came from.
	source = capability.service + "/" + capability.endpoint
	fetched = triples.dayText(triples.dayToday())
	for fact in facts
		fact.source = source
		fact.fetched = fetched
	end for
	return {"ok": 1, "facts": facts, "error": null}
end function
