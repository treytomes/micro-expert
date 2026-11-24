// Cases for src/providers.ms: the registry the service maps declare, and a question the session
// answers by asking a service rather than the reader. geocode.maps.co's two declarations are here
// too - a search asked by a place's own name and a reverse asked by its coordinates - both read
// back onto the place the question named rather than onto the OSM object the reply identifies.
//
// No request leaves the program: a client stand-in answers get with the canned Fort Worth reply,
// the way test/location.ms and test/declared.ms do, and counts what it was asked.

run = function(providers, declared, apiClient, triples, uid, ipwhoisMap, geocodeMap, sessionModule, rules,
	engineModule, cliLibrary, optionsModule, h)
	decl = ipwhoisMap.build()

	// The arguments a run parses, so the session below is built the way a program builds its
	// own rather than from a hand-made table of values.
	parsed = function(arguments)
		cmd = cliLibrary.newCommand("micro-expert-providers", "0.2.0", "the suite")
		optionsModule.declare(cliLibrary, cmd)
		return cliLibrary.parse(cmd, ["providers.ms"] + arguments)
	end function

	fortWorth = {"success": true, "continent": "North America", "country": "United States",
		"region": "Texas", "city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}

	// The client's own checks, with get answering canned JSON or the failure a network that is
	// not there gives: nothing leaves the program, and the count says how often it was asked.
	stubFor = function(json, fails=0, why=null)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.canned = json
		fake.calls = 0
		fake.fails = fails
		fake.why = why
		fake.seenTimeout = null
		fake.seenUrl = null
		fake.get = function(url, timeout=null)
			self.calls = self.calls + 1
			self.seenUrl = url
			self.seenTimeout = timeout
			if self.fails then
				return {"ok": 0, "status": null, "body": "", "json": null, "url": url,
					"error": self.why}
			end if
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url,
				"error": null}
		end function
		return fake
	end function

	// A session over a script of typed lines, recording what it printed and asked, as the
	// prompt's own cases do.
	startSession = function(registry, script)
		answers = {"lines": [], "asked": [], "at": 0}
		reader = function(question)
			answers.asked.push(question)
			if answers.at >= script.len then return null
			answers.at = answers.at + 1
			return script[answers.at - 1]
		end function
		writer = function(line)
			answers.lines.push(line)
		end function
		// No schema and no types, as a session handed neither reads: the facts a service answers
		// with are held as they come, which is what these cases are about.
		session = {"triples": triples, "Rule": rules.Rule, "facts": [], "rules": [],
			"depth": 8, "verbose": 0, "nlp": 0, "style": null,
			"paths": {}, "knowledge": null, "providers": registry,
			"io": {"read": @reader, "say": @writer}}
		sessionModule.run(session)
		return {"session": session, "answers": answers}
	end function

	printed = function(lines, text)
		"Whether a transcript holds this line exactly."
		return lines.indexOf(text) != null
	end function

	holds = function(lines, piece)
		"Whether any transcript line holds this piece of text."
		for line in lines
			if line.indexOf(piece) != null then return true
		end for
		return false
	end function

	countOf = function(lines, piece)
		"How many transcript lines hold this piece of text."
		found = 0
		for line in lines
			if line.indexOf(piece) != null then found = found + 1
		end for
		return found
	end function

	countWhere = function(items, name, value)
		"How many of these maps name this value under this field."
		found = 0
		for item in items
			if item[name] == value then found = found + 1
		end for
		return found
	end function

	place = uid.of("place", ["Fort Worth", "Texas", "United States"])
	sessionPlace = triples.SpoTriple.make("session", "has-location", triples.var("p"))

	// ── The registry is what the maps declare ───────────────────────────────

	client = stubFor(fortWorth)
	registry = providers.registry(client, declared, uid, [decl])
	h.check("the map's declared fact is the registry's one capability", registry.len == 1)
	h.check("named for the service and the endpoint that answers it",
		registry.len == 1 and registry[0].service == "ipwho.is" and
			registry[0].endpoint == "lookup")
	h.check("and it declares the fact the session's place is",
		registry.len == 1 and registry[0].fact[0] == "has-location")

	// A service that declares nothing answers nothing, however many endpoints it has.
	quiet = {"service": "quiet.example", "base": "https://quiet.example",
		"endpoints": {"one": {"method": "GET", "path": "/", "params": []}}}
	h.check("an endpoint that declares nothing adds no capability",
		providers.registry(client, declared, uid, [quiet]).len == 0)
	h.check("and the registry reads every map it is given",
		providers.registry(client, declared, uid, [quiet, decl]).len == 1)

	// ── Which fact a service says it answers ────────────────────────────────

	capability = providers.forGoal(registry, triples, sessionPlace)
	h.check("a goal needing the declared fact finds its service",
		capability != null and capability.endpoint == "lookup")
	h.check("a fact about another subject is not that service's",
		providers.forGoal(registry, triples,
			triples.SpoTriple.make("tim", "has-location", triples.var("p"))) == null)
	h.check("nor is a fact it does not declare",
		providers.forGoal(registry, triples,
			triples.SpoTriple.make(triples.var("p"), "has-city", "Fort Worth")) == null)
	h.check("a need already ground where the reply would answer is not that service's",
		providers.forGoal(registry, triples,
			triples.SpoTriple.make("session", "has-location", "Fort Worth")) == null)
	h.check("while a need still unknown there is",
		providers.forGoal(registry, triples,
			triples.SpoTriple.make("session", "has-location", triples.var("p"))) != null)

	// ── What the service answers ────────────────────────────────────────────

	answered = providers.answer(capability, triples)
	h.check("the answer is the reply's facts", answered.ok and answered.facts.len == 7)
	h.check("with the place the reply identifies under the session subject",
		answered.ok and answered.facts[0].text == "has-location(session, " + place + ")")
	h.check("and the declaration's deadline reaching the transport",
		client.seenTimeout == providers.defaultTimeout)

	// ── A service that cannot answer ────────────────────────────────────────

	failing = stubFor(null, 1, "Could not run curl: no such host")
	failed = providers.answer(providers.forGoal(providers.registry(failing, declared, uid, [decl]),
		triples, sessionPlace), triples)
	h.check("a service that cannot answer says why",
		not failed.ok and failed.facts.len == 0 and failed.error != null)

	// ── A question the session asks a service ───────────────────────────────

	answering = stubFor(fortWorth)
	asked = startSession(providers.registry(answering, declared, uid, [decl]),
		["has-location(session, ?p)", "quit"])
	lines = asked.answers.lines
	h.check("a question a service can answer asks it", answering.calls == 1)
	h.check("the facts it answers with are added to the session",
		holds(lines, "  added has-location(session, " + place + ")"))
	h.check("so the question is answered without a value being asked for",
		not holds(asked.answers.asked, "  ?p = "))
	h.check("and the answer is the fact the service gave",
		printed(lines, "  has-location(session, " + place + ")"))

	// ── A service that cannot answer leaves the fact to the reader ──────────

	unreachable = stubFor(null, 1, "Could not run curl: no such host")
	unanswered = startSession(providers.registry(unreachable, declared, uid, [decl]),
		["has-location(session, ?p)", "Fort Worth", "quit"])
	lines = unanswered.answers.lines
	h.check("a service that cannot answer is a warning, not a failed question",
		holds(lines, "ipwho.is could not answer has-location(session, ?p)"))
	h.check("and says why once", countOf(lines, "ipwho.is could not answer") == 1)
	h.check("the fact falls through to the prompt",
		holds(unanswered.answers.asked, "  ?p = "))
	h.check("which adds it as a typed fact is added",
		holds(lines, "  added has-location(session, Fort Worth)"))
	h.check("and the question is answered from it",
		printed(lines, "  has-location(session, Fort Worth)"))

	// ── A need already ground is not a service's to answer ──────────────────

	// The reply can only fill the parts the declaration leaves a variable, so a need that
	// names the place itself would make a request whose answer could never prove it. The
	// service is not asked at all, and the fact goes to the reader as one no service answers.
	quietStub = stubFor(fortWorth)
	quietSaid = []
	grounded = {"triples": triples, "Rule": rules.Rule, "facts": [], "rules": [], "depth": 8,
		"verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": null,
		"providers": providers.registry(quietStub, declared, uid, [decl]),
		"io": {"read": null, "say": function(line)
			quietSaid.push(line)
		end function}}
	groundNeed = triples.SpoTriple.make("session", "has-location", "Fort Worth")
	changed = sessionModule.provideMissing(grounded,
		triples.needsFor(groundNeed, [], [], 8))
	h.check("a need already ground is not asked of the service",
		quietStub.calls == 0 and not changed)
	h.check("and nothing is said or added for it",
		quietSaid.len == 0 and grounded.facts.len == 0)

	// ── A service is asked once, however many passes need it ────────────────

	// The session's own two passes over one question, called directly: the second reads
	// what the first attempt said rather than making the request again.
	said = []
	probe = {"triples": triples, "Rule": rules.Rule, "facts": [], "rules": [], "depth": 8,
		"verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": null,
		"providers": providers.registry(unreachable, declared, uid, [decl]),
		"io": {"read": null, "say": function(line)
			said.push(line)
		end function}}
	options = triples.needsFor(sessionPlace, [], [], 8)
	before = unreachable.calls
	sessionModule.provideMissing(probe, options)
	sessionModule.provideMissing(probe, options)
	h.check("a service is asked once per endpoint, however many passes need it",
		unreachable.calls - before == 1)
	h.check("and the pass that reads the attempt says nothing new",
		said.len == 1 and probe.facts.len == 0)

	// ── A geocoder asked about a place the session names ────────────────────

	// geocode.maps.co's request fields are the place's own: a search is asked by its name or
	// city, a reverse by its coordinates, and both replies are read back onto the place the
	// question named rather than onto the OSM object they identify.
	geoDecl = geocodeMap.build()
	named = uid.of("place", ["Fort Worth", "Texas", "United States"])
	namedLat = triples.SpoTriple.make(named, "has-latitude", 32.7254134)
	namedLon = triples.SpoTriple.make(named, "has-longitude", -97.3208492)
	namedCity = triples.SpoTriple.make(named, "has-city", "Fort Worth")

	searchReply = [{"osm_type": "relation", "osm_id": 12345, "lat": "32.7555",
		"lon": "-97.3308", "name": "Fort Worth", "class": "place", "type": "city",
		"place_rank": 16, "importance": 0.7, "place_id": 1,
		"address": {"city": "Fort Worth", "country": "United States", "country_code": "us"}}]
	reverseReply = {"osm_type": "way", "osm_id": 5013364, "lat": "32.7254",
		"lon": "-97.3208", "name": "Main Street",
		"address": {"house_number": "500", "road": "Main Street", "city": "Fort Worth",
			"country": "United States", "country_code": "us"}}

	geoRegistry = providers.registry(stubFor(searchReply), declared, uid, [geoDecl])
	h.check("the geocode map declares a fact per answer it can give", geoRegistry.len == 4)
	h.check("two of them the search's coordinates",
		countWhere(geoRegistry, "endpoint", "search") == 2)
	h.check("and two the reverse's address",
		countWhere(geoRegistry, "endpoint", "reverse") == 2)

	needCoords = triples.SpoTriple.make(named, "has-latitude", triples.var("lat"))
	needRoad = triples.SpoTriple.make(named, "has-road", triples.var("road"))
	searchCap = providers.forGoal(geoRegistry, triples, needCoords)
	reverseCap = providers.forGoal(geoRegistry, triples, needRoad)
	h.check("a question needing a named place's coordinates finds the search",
		searchCap != null and searchCap.endpoint == "search")
	h.check("and one needing its address finds the reverse",
		reverseCap != null and reverseCap.endpoint == "reverse")
	h.check("the query the search is asked by is the place's own city",
		providers.requestFor(searchCap, triples, [namedCity], named).q == "Fort Worth")
	namedName = triples.SpoTriple.make(named, "has-name", "Cowtown")
	h.check("a name is asked with before a city",
		providers.requestFor(searchCap, triples, [namedCity, namedName], named).q == "Cowtown")
	h.check("a place with neither is no search's to ask",
		providers.requestFor(searchCap, triples, [], named) == null)
	reverseRequest = providers.requestFor(reverseCap, triples, [namedLat, namedLon], named)
	h.check("the reverse is asked by the place's own coordinates",
		reverseRequest != null and reverseRequest.lat == 32.7254134 and
			reverseRequest.lon == -97.3208492)
	h.check("and a place with none is no reverse's to ask",
		providers.requestFor(reverseCap, triples, [namedCity], named) == null)

	searching = stubFor(searchReply)
	searchAnswer = providers.answer(
		providers.forGoal(providers.registry(searching, declared, uid, [geoDecl]), triples, needCoords),
		triples, providers.requestFor(searchCap, triples, [namedCity], named), named)
	answeredLat = null
	for fact in searchAnswer.facts
		if fact.predicate == "has-latitude" then answeredLat = fact
	end for
	h.check("the search's answer is about the place the question named",
		searchAnswer.ok and answeredLat != null and
			triples.termText(answeredLat.subject) == named)
	h.check("with the coordinates the reply carried",
		answeredLat != null and answeredLat.object == 32.7555)
	h.check("and the request sent with the query and the one result",
		searching.seenUrl != null and searching.seenUrl.indexOf("Fort") != null and
			searching.seenUrl.indexOf("limit=1") != null)

	// A session needing the coordinates of the place it names asks the search, and holds what
	// it answered under that place.
	asking = stubFor(searchReply)
	coordSaid = []
	coordSession = {"triples": triples, "Rule": rules.Rule, "facts": [namedCity], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": null,
		"providers": providers.registry(asking, declared, uid, [geoDecl]),
		"io": {"read": null, "say": function(line)
			coordSaid.push(line)
		end function}}
	changed = sessionModule.provideMissing(coordSession,
		triples.needsFor(needCoords, coordSession.facts, [], 8))
	h.check("a session needing a named place's coordinates asks the search once",
		asking.calls == 1 and changed)
	h.check("and holds the coordinates it answered as that place's",
		holds(coordSaid, "added has-latitude(" + named + ", 32.7555)"))

	// The reverse takes the coordinates the place already has, and answers its address.
	addressed = stubFor(reverseReply)
	addressSaid = []
	addressSession = {"triples": triples, "Rule": rules.Rule,
		"facts": [namedLat, namedLon, namedCity], "rules": [], "depth": 8, "verbose": 0,
		"nlp": 0, "style": null, "paths": {}, "knowledge": null,
		"providers": providers.registry(addressed, declared, uid, [geoDecl]),
		"io": {"read": null, "say": function(line)
			addressSaid.push(line)
		end function}}
	roadOptions = triples.needsFor(needRoad, addressSession.facts, [], 8)
	changed = sessionModule.provideMissing(addressSession, roadOptions)
	road = null
	for fact in addressSession.facts
		if fact.predicate == "has-road" then road = fact
	end for
	h.check("a session needing the address at a named place asks the reverse once",
		addressed.calls == 1 and changed)
	h.check("and holds the road it answered as that place's",
		road != null and triples.termText(road.subject) == named and road.object == "Main Street")
	// The transport writes a number to seven significant digits, which is what the service reads.
	h.check("asked with the coordinates that place's facts hold",
		addressed.seenUrl != null and addressed.seenUrl.indexOf("lat=32.725413&") != null and
			addressed.seenUrl.indexOf("lon=-97.320849") != null)
	h.check("and a second pass over that need reads the first attempt",
		sessionModule.provideMissing(addressSession, roadOptions) == false and addressed.calls == 1)

	// A place with nothing to ask by is left to the reader, not asked about.
	unasked = stubFor(reverseReply)
	noCoords = {"triples": triples, "Rule": rules.Rule, "facts": [namedCity], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": null,
		"providers": providers.registry(unasked, declared, uid, [geoDecl]),
		"io": {"read": null, "say": function(line)
		end function}}
	changed = sessionModule.provideMissing(noCoords, triples.needsFor(needRoad, noCoords.facts, [], 8))
	h.check("a place with no coordinates is never asked about",
		unasked.calls == 0 and not changed)

	// ── The shipped domain holds what a service answers ─────────────────────

	// Every session above is handed no schema and no types, so a service's facts are held as
	// they come. engine.build reads data/schema.kb, which is what a run holds them against:
	// the search's has-latitude is a number there, so the coordinate is added through the same
	// addFact a typed line goes through rather than refused, and the place learns it.
	shipped = engineModule.build(triples, rules.Rule, parsed(["--domain", "data"]), null)
	h.check("the shipped domain builds for a provider's answer", not (shipped isa error))
	if not (shipped isa error) then
		shippedSaid = []
		shipped.providers = providers.registry(stubFor(searchReply), declared, uid, [geoDecl])
		shipped.io = {"read": null, "say": function(line)
			shippedSaid.push(line)
		end function}
		sessionModule.addFact(shipped, triples.SpoTriple.make(named, "has-city", "Fort Worth"))
		changed = sessionModule.provideMissing(shipped,
			triples.needsFor(needCoords, shipped.facts, [], 8))
		heldLat = null
		for fact in shipped.facts
			if fact.predicate == "has-latitude" and triples.termText(fact.subject) == named then
				heldLat = fact
			end if
		end for
		h.check("data/schema.kb adds the latitude a geocoder answers",
			changed and heldLat != null and heldLat.object == 32.7555)
		h.check("and refuses none of the facts the answer carried",
			not holds(shippedSaid, "refused") and not holds(shippedSaid, "could not answer"))
	end if

	// ── A session given no registry asks nothing ────────────────────────────

	plain = startSession(null, ["has-location(session, ?p)", "Fort Worth", "quit"])
	h.check("a session with no registry prompts for the fact, as it always did",
		holds(plain.answers.asked, "  ?p = ") and
			holds(plain.answers.lines, "  added has-location(session, Fort Worth)"))
	h.check("and the registry it was not given is not made up for it",
		plain.session.providers == null)
end function
