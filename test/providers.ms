// Cases for src/providers.ms: the registry the service maps declare, and a question the session
// answers by asking a service rather than the reader. geocode.maps.co's two declarations are here
// too - a search asked by a place's own name and a reverse asked by its coordinates - both read
// back onto the place the question named rather than onto the OSM object the reply identifies,
// and Open-Meteo's forecast, asked with a place's coordinates for the next day of one variable.
//
// No request leaves the program: a client stand-in answers get with the canned Fort Worth reply,
// the way test/location.ms and test/declared.ms do, and counts what it was asked.

run = function(providers, declared, apiClient, triples, uid, ipwhoisMap, geocodeMap, openmeteoMap,
	sessionModule, rules, engineModule, cliLibrary, optionsModule, knowledge, h)
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

	// A client that answers by host, so one session can be asked of two services: the geocoder for
	// the coordinates, then the forecast for the weather. Nothing leaves the program, and the
	// urls say which service was asked, in what order.
	splitStub = function(routes)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.routes = routes
		fake.calls = []
		fake.get = function(url, timeout=null)
			self.calls.push url
			for route in self.routes
				if url.indexOf(route.host) != null then
					if route.hasIndex("fails") and route.fails then
						return {"ok": 0, "status": null, "body": "", "json": null, "url": url,
							"error": route.why}
					end if
					return {"ok": 1, "status": 200, "body": "", "json": route.json, "url": url,
						"error": null}
				end if
			end for
			return {"ok": 0, "status": null, "body": "", "json": null, "url": url,
				"error": "no service at this host"}
		end function
		return fake
	end function

	// A session over a script of typed lines, recording what it printed and asked, as the
	// prompt's own cases do.
	startSession = function(registry, script, facts=[], ruleList=[])
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
		session = {"triples": triples, "Rule": rules.Rule, "facts": facts + [], "rules": ruleList,
			"depth": 8, "verbose": 0, "nlp": 0, "style": null,
			"paths": {}, "knowledge": knowledge, "providers": registry,
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
	// The line also says which service answered it and when, so the fact is read by its parts.
	h.check("with the place the reply identifies under the session subject",
		answered.ok and triples.termText(answered.facts[0].subject) == "session" and
			answered.facts[0].predicate == "has-location" and
			triples.termText(answered.facts[0].object) == place and
			answered.facts[0].text.indexOf("has-location(session, " + place + ")") == 0)
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
	// The answer is the line the service gave, annotations and all: an answer from a service
	// says which one and the day it was read, so it can be written back to a facts file as it
	// stands. The day is the one the run's clock says, read the same way the writer read it.
	today = triples.dayText(triples.dayToday())
	h.check("and the answer is the fact the service gave, with where it came from",
		printed(lines, "  has-location(session, " + place + ") # ipwho.is/lookup " + today))

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
		"verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
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
		"verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
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
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
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

	// ── A body joins two facts, and the far one is asked of a service ───────

	// The session knows where it is and the place's city, but not its coordinates. The body's
	// first condition settles the place, so the second is a need with that place for its
	// subject - the fact the geocoder's search declares - and the answer is both facts.
	placed = triples.SpoTriple.make("session", "has-location", named)
	joinedClient = stubFor(searchReply)
	joinedSession = startSession(providers.registry(joinedClient, declared, uid, [geoDecl]),
		["and(has-location(session, ?loc), has-latitude(?loc, ?lat))"], [placed, namedCity])
	h.check("a body's second condition asks the service for the place the first located",
		joinedClient.calls == 1 and joinedClient.seenUrl.indexOf("q=Fort") != null)
	h.check("and the answer is both facts the body settled, the read one with where it came from",
		printed(joinedSession.answers.lines, "  has-location(session, " + named + ")") and
			printed(joinedSession.answers.lines, "  has-latitude(" + named + ", 32.7555) # geocode.maps.co/search " +
				today))
	h.check("with no value asked for any of it",
		not holds(joinedSession.answers.asked, "  ?loc = "))

	// The reverse takes the coordinates the place already has, and answers its address.
	addressed = stubFor(reverseReply)
	addressSaid = []
	addressSession = {"triples": triples, "Rule": rules.Rule,
		"facts": [namedLat, namedLon, namedCity], "rules": [], "depth": 8, "verbose": 0,
		"nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
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

	// A one-fact answer is one change like any other, and it remembers its request the same way:
	// taken back, the reverse is asked again rather than the address being left to the reader.
	sparseReply = {"osm_type": "way", "osm_id": 77, "address": {"road": "Main Street"}}
	sparse = stubFor(sparseReply)
	sparseSession = {"triples": triples, "Rule": rules.Rule, "facts": [namedLat, namedLon],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge, "providers": providers.registry(sparse, declared, uid, [geoDecl]),
		"io": {"read": null, "say": function(line)
		end function}}
	sparseOptions = triples.needsFor(needRoad, sparseSession.facts, [], 8)
	changed = sessionModule.provideMissing(sparseSession, sparseOptions)
	h.check("a one-fact answer is one change that remembers its request",
		changed and sparseSession.changes.len == 1 and
			sparseSession.changes[0].kind == "add" and sparseSession.changes[0].attempt != null)
	takenBack = sessionModule.undo(sparseSession)
	h.check("/undo forgets a one-fact answer's request too",
		takenBack and sparseSession.facts.len == 2 and sparseSession.providerCalls.len == 0)
	changed = sessionModule.provideMissing(sparseSession, sparseOptions)
	h.check("so the reverse is asked again rather than prompting",
		changed and sparse.calls == 2)

	// A place with nothing any service can ask by is left to the reader: the reverse wants
	// coordinates and the search wants a name or city, and this place has neither.
	unasked = stubFor(reverseReply)
	noCoords = {"triples": triples, "Rule": rules.Rule,
		"facts": [triples.SpoTriple.make(named, "has-fee", "no")], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
		"providers": providers.registry(unasked, declared, uid, [geoDecl]),
		"io": {"read": null, "say": function(line)
		end function}}
	changed = sessionModule.provideMissing(noCoords, triples.needsFor(needRoad, noCoords.facts, [], 8))
	h.check("a place with nothing any service can ask by is never asked about",
		unasked.calls == 0 and not changed)

	// ── The shipped domain holds what a service answers ─────────────────────

	// Every session above is handed no schema and no types, so a service's facts are held as
	// they come. engine.build reads data/schema.kb, which is what a run holds them against:
	// the search's has-latitude is one number per place there, so the coordinate is added
	// through the same addFact a typed line goes through rather than refused, and a place that
	// already had one is corrected rather than left holding two.
	shipped = engineModule.build(triples, rules.Rule, parsed(["--domain", "data"]), null)
	h.check("the shipped domain builds for a provider's answer", not (shipped isa error))
	if not (shipped isa error) then
		shippedSaid = []
		shipped.providers = providers.registry(stubFor(searchReply), declared, uid, [geoDecl])
		shipped.io = {"read": null, "say": function(line)
			shippedSaid.push(line)
		end function}
		sessionModule.addFact(shipped, triples.SpoTriple.make(named, "has-city", "Fort Worth"))
		// What the place already held: a lookup's coordinate, which a search's answer corrects.
		stale = triples.SpoTriple.make(named, "has-latitude", 32.7254134)
		sessionModule.addFact(shipped, stale)
		needLon = triples.SpoTriple.make(named, "has-longitude", triples.var("lon"))
		changed = sessionModule.provideMissing(shipped,
			triples.needsFor(needLon, shipped.facts, [], 8))
		heldLats = []
		stillStale = false
		for fact in shipped.facts
			if fact.predicate == "has-latitude" and triples.termText(fact.subject) == named then
				heldLats.push(fact)
				if fact.text == stale.text then stillStale = true
			end if
		end for
		h.check("data/schema.kb adds the latitude a geocoder answers",
			changed and heldLats.len == 1 and heldLats[0].object == 32.7555)
		h.check("and the coordinate the place already held is replaced, not kept beside it",
			not stillStale and heldLats.len == 1)
		h.check("and refuses none of the facts the answer carried",
			not holds(shippedSaid, "refused") and not holds(shippedSaid, "could not answer"))
		// The answer replaced the place's latitude as well as adding its longitude, and both
		// changes belong to the one answer: /undo puts the corrected latitude back where it
		// stood rather than leaving the answer half taken back.
		lastChange = shipped.changes[shipped.changes.len - 1]
		takenBack = sessionModule.undo(shipped)
		restored = 0
		backToStale = false
		for fact in shipped.facts
			if fact.predicate == "has-latitude" and triples.termText(fact.subject) == named then
				restored = restored + 1
				if fact.text == stale.text then backToStale = true
			end if
		end for
		h.check("/undo takes that answer back whole, the corrected latitude with it",
			takenBack and lastChange.kind == "batch" and restored == 1 and backToStale)
	end if

	// ── A weather service asked about a place the session locates ───────────

	// Open-Meteo's forecast answers a reading per hour about the place the question names, and
	// is asked with the coordinates the session already holds for it. Each of the five
	// documented hourly variables has a request of its own, for the next day's hours of that
	// variable: a reply is read as one fact per hour, so a question answers with a day of them.
	weatherDecl = openmeteoMap.build()
	weatherReply = {"latitude": 32.7555, "longitude": -97.3308, "timezone": "America/Chicago",
		"utc_offset_seconds": -21600,
		"hourly_units": {"time": "iso8601", "temperature_2m": "°C",
			"relative_humidity_2m": "%", "precipitation": "mm", "wind_speed_10m": "km/h",
			"weather_code": "wmo code"},
		"hourly": {"time": ["2026-11-25T09:00"], "temperature_2m": [18.4],
			"relative_humidity_2m": [62], "precipitation": [0], "wind_speed_10m": [9.7],
			"weather_code": [1], "precipitation_probability": [10]}}
	located = uid.of("place", ["Fort Worth weather"])
	locatedLat = triples.SpoTriple.make(located, "has-latitude", 32.7555)
	locatedLon = triples.SpoTriple.make(located, "has-longitude", -97.3308)
	needTemperature = triples.SpoTriple.make(located, "has-temperature-2m", triples.var("t"))

	weatherRegistry = providers.registry(stubFor(weatherReply), declared, uid, [weatherDecl])
	h.check("the forecast declares a fact per documented hourly variable",
		countWhere(weatherRegistry, "endpoint", "forecast") == 5)
	h.check("and the geocoder declares the place's coordinates, as the other map does",
		countWhere(weatherRegistry, "endpoint", "geocoding") == 2)
	weatherCap = providers.forGoal(weatherRegistry, triples, needTemperature)
	h.check("a question needing a located place's temperature finds the forecast",
		weatherCap != null and weatherCap.endpoint == "forecast")
	h.check("a place with no coordinates is no forecast's to ask",
		providers.requestFor(weatherCap, triples, [], located) == null)
	weatherRequest = providers.requestFor(weatherCap, triples, [locatedLat, locatedLon], located)
	h.check("the forecast is asked with the coordinates that place's facts hold",
		weatherRequest != null and weatherRequest.latitude == 32.7555 and
			weatherRequest.longitude == -97.3308)
	h.check("and for the next day's hours of the one variable it was asked about",
		weatherRequest != null and weatherRequest.forecast_hours == 24 and
			weatherRequest.hourly.len == 1 and weatherRequest.hourly[0] == "temperature_2m")

	forecastStub = stubFor(weatherReply)
	forecastAnswer = providers.answer(
		providers.forGoal(providers.registry(forecastStub, declared, uid, [weatherDecl]), triples,
			needTemperature),
		triples, providers.requestFor(weatherCap, triples, [locatedLat, locatedLon], located),
		located)
	h.check("the forecast's answer is the reading the question named, about the place it named",
		forecastAnswer.ok and forecastAnswer.facts.len == 4 and
			forecastAnswer.facts[0].predicate == "has-temperature-2m" and
			triples.termText(forecastAnswer.facts[0].subject) == located)
	h.check("with the hour the reply covers kept as the fact's span",
		forecastAnswer.facts.len == 4 and forecastAnswer.facts[0].at != null)
	h.check("and the unit the reply gave, as a fact about the variable it asked for",
		forecastAnswer.facts[1].predicate == "has-unit" and
			triples.termText(forecastAnswer.facts[1].subject) == "temperature_2m" and
			triples.termText(forecastAnswer.facts[1].object) == "celsius")
	// The place is the reading's subject, not a query parameter: the service is asked for what
	// it can use, and a session's place is named by the coordinates it already held.
	h.check("and the request carrying the coordinates rather than a place name of its own",
		forecastStub.seenUrl != null and
			forecastStub.seenUrl.indexOf("latitude=32.7555") != null and
			forecastStub.seenUrl.indexOf("hourly=temperature_2m") != null and
			forecastStub.seenUrl.indexOf("place=") == null)

	// A session that holds the place's coordinates asks once, and keeps the readings as that
	// place's.
	forecasting = stubFor(weatherReply)
	weatherSaid = []
	weatherSession = {"triples": triples, "Rule": rules.Rule, "facts": [locatedLat, locatedLon],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge, "providers": providers.registry(forecasting, declared, uid, [weatherDecl]),
		"io": {"read": null, "say": function(line)
			weatherSaid.push(line)
		end function}}
	changed = sessionModule.provideMissing(weatherSession,
		triples.needsFor(needTemperature, weatherSession.facts, [], 8))
	heldTemperature = null
	for fact in weatherSession.facts
		if fact.predicate == "has-temperature-2m" then heldTemperature = fact
	end for
	h.check("a session needing a located place's weather asks the forecast once",
		forecasting.calls == 1 and changed)
	h.check("and holds the reading it answered as that place's",
		heldTemperature != null and triples.termText(heldTemperature.subject) == located and
			heldTemperature.object == 18.4)

	// Five facts from one reply are one change, so /undo takes the answer back whole rather
	// than leaving four of its readings behind - and says so once rather than five times.
	h.check("a service's answer is one change the session records",
		weatherSession.changes.len == 1 and weatherSession.changes[0].kind == "batch" and
			weatherSession.changes[0].steps.len == 4)
	takenBack = sessionModule.undo(weatherSession)
	coordinates = 0
	for fact in weatherSession.facts
		if fact.predicate == "has-latitude" or fact.predicate == "has-longitude" then
			coordinates = coordinates + 1
		end if
	end for
	h.check("/undo takes the whole answer back in one step",
		takenBack and weatherSession.facts.len == 2 and coordinates == 2 and
			weatherSession.changes.len == 0)
	h.check("saying it once, with the service that answered",
		countOf(weatherSaid, "took back 4 facts open-meteo answered") == 1 and
			not holds(weatherSaid, "took back has-temperature-2m("))
	// The request went with the answer: a session that no longer holds what the forecast said
	// asks it again rather than the reader.
	h.check("and /undo forgets the request that answer made",
		weatherSession.providerCalls.len == 0)
	changed = sessionModule.provideMissing(weatherSession,
		triples.needsFor(needTemperature, weatherSession.facts, [], 8))
	h.check("so the question asks the forecast again rather than the reader",
		changed and forecasting.calls == 2)

	// An offset ages like a reading: yesterday's answer to where the place's clock stands from
	// UTC is not a clock to move one by, so the session holds none until the forecast is asked
	// again - and the reply it answers with today is the one the clock is read from.
	savedClockDay = triples.today
	triples.today = "2026-11-25"
	clockStale = triples.SpoTriple.make(located, "has-utc-offset", -18000, null, 100,
		"open-meteo/forecast", "2026-11-21")
	clocking = stubFor(weatherReply)
	clockSession = {"triples": triples, "Rule": rules.Rule, "facts": [locatedLat, locatedLon, clockStale],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge, "providers": providers.registry(clocking, declared, uid, [weatherDecl]),
		"io": {"read": null, "say": function(line)
			end function}}
	sessionModule.placeClocks(clockSession)
	h.check("a day-old offset is not a clock to read the place by",
		triples.machineOffset == null and triples.placeOffsets.len == 0)
	changed = sessionModule.provideMissing(clockSession,
		triples.needsFor(needTemperature, clockSession.facts, [], 8))
	sessionModule.placeClocks(clockSession)
	offsets = triples.placeOffsets
	h.check("and the forecast asked again says how far the place's clock stands today",
		changed and clocking.calls == 1 and offsets.len == 1 and
			offsets[offsets.indexes[0]] == -21600)
	triples.today = savedClockDay
	// A question that asks only what time it is at a place has no reading in it to fetch, so the
	// fact the session is missing is that place's offset: the clock endpoint is asked for today's,
	// and the clock is read rather than the question failing on yesterday's answer. The reply is
	// read for what it says once about the place, so the question adds no readings it never asked.
	clockReply = {"latitude": 52.52, "longitude": 13.404, "timezone": "Europe/Berlin",
		"utc_offset_seconds": 3600}
	clocking = stubFor(clockReply)
	savedOnlyDay = triples.today
	savedOnlyClock = triples.clock
	triples.today = "2026-11-25"
	triples.clock = "2026-11-25 17:45:00"
	clockLines = []
	clockOnly = {"triples": triples, "Rule": rules.Rule, "facts": [
		triples.SpoTriple.make("session", "has-location", "home"),
		triples.SpoTriple.make("home", "has-utc-offset", -21600),
		triples.SpoTriple.make("berlin", "has-latitude", 52.52),
		triples.SpoTriple.make("berlin", "has-longitude", 13.404),
		triples.SpoTriple.make("berlin", "has-utc-offset", 7200, null, 100,
			"open-meteo/forecast", "2026-11-21")],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge, "providers": providers.registry(clocking, declared, uid, [weatherDecl]),
		"io": {"read": null, "say": function(line)
			clockLines.push(line)
		end function}}
	sessionModule.askGoal(clockOnly, triples.SpoTriple.make("berlin", "has-time", triples.var("now")))
	clockOffset = null
	for fact in clockOnly.facts
		if fact.predicate == "has-utc-offset" and triples.termText(fact.subject) == "berlin" and
				fact.fetched == "2026-11-25" then clockOffset = fact.object
	end for
	h.check("a question that asks only the clock asks a service for today's offset",
		clocking.calls == 1 and clockOffset == 3600)
	h.check("and the clock it could not read from yesterday's is read from that reply",
		holds(clockLines, "2026-11-26 00:45:00"))
	h.check("and the reply adds the zone rather than readings the question never asked for",
		clockLines.len > 0 and clockOnly.facts.len == 7)
	triples.clock = savedOnlyClock
	triples.today = savedOnlyDay
	// A forecast that cannot answer leaves the fact to the reader. One attempt is one request,
	// and each variable has a request of its own now, so another variable is a second attempt
	// rather than the same failed one; the request already made is not made twice.
	offlineForecast = stubFor(null, 1, "Could not run curl: no such host")
	weatherUnmet = []
	unmetSession = {"triples": triples, "Rule": rules.Rule, "facts": [locatedLat, locatedLon],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge,
		"providers": providers.registry(offlineForecast, declared, uid, [weatherDecl]),
		"io": {"read": null, "say": function(line)
			weatherUnmet.push(line)
		end function}}
	changed = sessionModule.provideMissing(unmetSession,
		triples.needsFor(needTemperature, unmetSession.facts, [], 8))
	h.check("a forecast that cannot answer is a warning, and nothing is added",
		not changed and holds(weatherUnmet, "open-meteo could not answer has-temperature-2m("))
	needRain = triples.SpoTriple.make(located, "has-precipitation", triples.var("v"))
	changed = sessionModule.provideMissing(unmetSession,
		triples.needsFor(needRain, unmetSession.facts, [], 8))
	h.check("and another variable's request is a request of its own, so it is tried",
		offlineForecast.calls == 2 and not changed)
	h.check("while the request that already failed is not made twice",
		not sessionModule.provideMissing(unmetSession,
			triples.needsFor(needTemperature, unmetSession.facts, [], 8)) and
			offlineForecast.calls == 2)

	// Nothing converts one unit into another, so a reply that spells a variable in another unit
	// than the session holds is refused whole rather than added beside the held readings: two
	// scales in one knowledge base is the silent mixing the unit facts exist to prevent.
	fahrenheitReply = weatherReply + {}
	fahrenheitReply.hourly_units = {"time": "iso8601", "temperature_2m": "°F",
		"relative_humidity_2m": "%", "precipitation": "mm", "wind_speed_10m": "km/h",
		"weather_code": "wmo code"}
	heldCelsius = triples.SpoTriple.make("temperature_2m", "has-unit", "celsius")
	mixedSaid = []
	mixedSession = {"triples": triples, "Rule": rules.Rule,
		"facts": [locatedLat, locatedLon, heldCelsius],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge,
		"providers": providers.registry(stubFor(fahrenheitReply), declared, uid, [weatherDecl]),
		"io": {"read": null, "say": function(line)
			mixedSaid.push(line)
		end function}}
	changed = sessionModule.provideMissing(mixedSession,
		triples.needsFor(needTemperature, mixedSession.facts, [], 8))
	h.check("a reply in another unit is refused rather than mixed with the held one",
		not changed and holds(mixedSaid, "could not answer") and
			holds(mixedSaid, "temperature_2m is celsius and fahrenheit"))
	h.check("and the session keeps its one unit and gains no readings",
		mixedSession.facts.len == 3 and not holds(mixedSaid, "added has-temperature-2m("))

	// ── A place known only by name is located before it is asked about ──────

	// The forecast's request needs coordinates the session does not hold. The geocoder's search
	// declares a place's coordinates from its own name or city, so it is asked first and the
	// question comes round with them. One pass asks one service, so the two hops are two answers
	// and each is one change to take back.
	both = splitStub([
		{"host": "geocode.maps.co", "json": searchReply},
		{"host": "api.open-meteo.com", "json": weatherReply},
	])
	byName = uid.of("place", ["Fort Worth by name"])
	byNameCity = triples.SpoTriple.make(byName, "has-city", "Fort Worth")
	needWeather = triples.SpoTriple.make(byName, "has-temperature-2m", triples.var("t"))
	chainSaid = []
	chainSession = {"triples": triples, "Rule": rules.Rule, "facts": [byNameCity],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge,
		"providers": providers.registry(both, declared, uid, [geoDecl, weatherDecl]),
		"io": {"read": null, "say": function(line)
			chainSaid.push(line)
		end function}}
	chainCap = providers.forGoal(chainSession.providers, triples, needWeather)
	h.check("a place with only a name has no weather request yet",
		chainCap != null and providers.requestFor(chainCap, triples, chainSession.facts, byName) == null)
	changed = sessionModule.provideMissing(chainSession,
		triples.needsFor(needWeather, chainSession.facts, [], 8))
	h.check("the geocoder is asked first, for the coordinates the forecast needs",
		changed and both.calls.len == 1 and both.calls[0].indexOf("geocode.maps.co") != null and
			both.calls[0].indexOf("q=Fort") != null)
	chainedLat = null
	for fact in chainSession.facts
		if fact.predicate == "has-latitude" then chainedLat = fact
	end for
	h.check("and the place holds the coordinates it answered as its own",
		chainedLat != null and triples.termText(chainedLat.subject) == byName and
			chainedLat.object == 32.7555)
	changed = sessionModule.provideMissing(chainSession,
		triples.needsFor(needWeather, chainSession.facts, [], 8))
	h.check("the next pass asks the forecast with those coordinates",
		changed and both.calls.len == 2 and
			both.calls[1].indexOf("api.open-meteo.com") != null and
			both.calls[1].indexOf("latitude=32.7555") != null)
	chainedWeather = null
	for fact in chainSession.facts
		if fact.predicate == "has-temperature-2m" then chainedWeather = fact
	end for
	h.check("so the weather fact is answered from the service, about that place",
		chainedWeather != null and triples.termText(chainedWeather.subject) == byName and
			chainedWeather.object == 18.4)
	h.check("as two changes, one per answer",
		chainSession.changes.len == 2 and chainSession.changes[0].kind == "batch" and
			chainSession.changes[1].kind == "batch")

	// A place with nothing to search by is not located, and its weather question is left to the
	// reader as it was before there was anything to chain.
	nowhere = uid.of("place", ["Fort Worth nowhere"])
	nowhereSession = {"triples": triples, "Rule": rules.Rule,
		"facts": [triples.SpoTriple.make(nowhere, "has-road", "Main Street")],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge,
		"providers": providers.registry(both, declared, uid, [geoDecl, weatherDecl]),
		"io": {"read": null, "say": function(line)
		end function}}
	changed = sessionModule.provideMissing(nowhereSession,
		triples.needsFor(triples.SpoTriple.make(nowhere, "has-temperature-2m", triples.var("t")),
			nowhereSession.facts, [], 8))
	h.check("a place with neither name nor city is not located, and nothing is asked",
		not changed and both.calls.len == 2 and nowhereSession.facts.len == 1)

	// Both hops are changes, so /undo reaches back through them and forgets both requests.
	sessionModule.undo(chainSession)
	sessionModule.undo(chainSession)
	h.check("undoing both answers forgets both requests, so the chain can start over",
		chainSession.providerCalls.len == 0 and chainSession.facts.len == 1)

	// ── A service that cannot answer leaves the next to try ────────────────

	// Both maps declare a place's coordinates: geocode.maps.co's search and Open-Meteo's
	// geocoder. The first is asked first, and when it cannot answer the second is asked before
	// the reader - registry order decides who goes first, not who gets the only chance.
	geocoderReply = {"results": [{"id": 3394344, "name": "Fort Worth", "latitude": 32.7555,
		"longitude": -97.3308, "country": "United States", "country_code": "US",
		"admin1": "Texas", "timezone": "America/Chicago"}]}
	secondChance = splitStub([
		{"host": "geocode.maps.co", "fails": 1, "why": "Could not run curl: no such host"},
		{"host": "geocoding-api.open-meteo.com", "json": geocoderReply},
	])
	nextPlace = uid.of("place", ["Fort Worth next"])
	nextCity = triples.SpoTriple.make(nextPlace, "has-city", "Fort Worth")
	needNextLat = triples.SpoTriple.make(nextPlace, "has-latitude", triples.var("lat"))
	nextSaid = []
	nextSession = {"triples": triples, "Rule": rules.Rule, "facts": [nextCity], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
		"providers": providers.registry(secondChance, declared, uid, [geoDecl, weatherDecl]),
		"io": {"read": null, "say": function(line)
			nextSaid.push(line)
		end function}}
	changed = sessionModule.provideMissing(nextSession,
		triples.needsFor(needNextLat, nextSession.facts, [], 8))
	h.check("one map that cannot answer is a warning, and the other is asked",
		changed and secondChance.calls.len == 2 and
			secondChance.calls[0].indexOf("geocode.maps.co") != null and
			secondChance.calls[1].indexOf("geocoding-api.open-meteo.com") != null and
			holds(nextSaid, "geocode.maps.co could not answer"))
	nextLatitude = null
	for readFact in nextSession.facts
		if readFact.predicate == "has-latitude" then nextLatitude = readFact
	end for
	h.check("so the coordinate is the one the second map gave",
		nextLatitude != null and nextLatitude.object == 32.7555 and
			nextLatitude.source == "open-meteo/geocoding")

	// Which one goes first is registry order, and the first answer is enough: the second map is
	// not asked once the session holds the fact.
	secondIdle = splitStub([
		{"host": "geocode.maps.co", "json": searchReply},
		{"host": "geocoding-api.open-meteo.com", "json": geocoderReply},
	])
	idlePlace = uid.of("place", ["Fort Worth first"])
	idleSession = {"triples": triples, "Rule": rules.Rule,
		"facts": [triples.SpoTriple.make(idlePlace, "has-city", "Fort Worth")], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
		"providers": providers.registry(secondIdle, declared, uid, [geoDecl, weatherDecl]),
		"io": {"read": null, "say": function(line)
		end function}}
	changed = sessionModule.provideMissing(idleSession,
		triples.needsFor(triples.SpoTriple.make(idlePlace, "has-latitude", triples.var("lat")),
			idleSession.facts, [], 8))
	h.check("and a map that can answer leaves the other unasked",
		changed and secondIdle.calls.len == 1 and
			secondIdle.calls[0].indexOf("geocode.maps.co") != null)

	// A key the environment does not hold is the same shape of failure, and the same fall-
	// through: the map that wanted the key says so in the session and the next declaration is
	// asked, so a notebook cell shows the refusal and still gets its answer. The stub would have
	// answered, which is what makes "nothing was sent" worth pinning.
	keylessPlace = uid.of("place", ["Fort Worth keyless"])
	keyless = splitStub([
		{"host": "geocode.maps.co", "json": searchReply},
		{"host": "geocoding-api.open-meteo.com", "json": geocoderReply},
	])
	keptKey = null
	if env.hasIndex("GEOCODE_MAPS_API_KEY") then keptKey = env["GEOCODE_MAPS_API_KEY"]
	env.remove("GEOCODE_MAPS_API_KEY")
	keylessSession = startSession(providers.registry(keyless, declared, uid, [geoDecl, weatherDecl]),
		["has-latitude(" + keylessPlace + ", ?lat)"],
		[triples.SpoTriple.make(keylessPlace, "has-city", "Fort Worth")])
	if keptKey == null then
		env.remove("GEOCODE_MAPS_API_KEY")
	else
		env["GEOCODE_MAPS_API_KEY"] = keptKey
	end if
	keylessLines = keylessSession.answers.lines
	h.check("a key the environment does not hold is said in the session, naming the variable",
		printed(keylessLines, "  geocode.maps.co could not answer has-latitude(" +
			keylessPlace + ", ?lat): geocode.maps.co needs a key: set GEOCODE_MAPS_API_KEY " +
			"in the environment or in the .env beside the run"))
	keylessAsked = 0
	for url in keyless.calls
		if url.indexOf("geocode.maps.co") != null then keylessAsked = keylessAsked + 1
	end for
	h.check("with no request built for the map that wanted it", keylessAsked == 0 and
		keyless.calls.len == 1 and keyless.calls[0].indexOf("geocoding-api.open-meteo.com") != null)
	keylessLatitude = null
	for readFact in keylessSession.session.facts
		if readFact.predicate == "has-latitude" then keylessLatitude = readFact
	end for
	h.check("so the next declaration answers, and the question is answered from it",
		printed(keylessLines, "  has-latitude(" + keylessPlace + ", 32.7555) # open-meteo/geocoding " +
			today) and
			keylessLatitude != null and keylessLatitude.source == "open-meteo/geocoding" and
			not holds(keylessSession.answers.asked, "  ?lat = "))

	// A reply that is not the place the question named is the same shape of failure once more:
	// the search takes the first result limit=1 offers, so the declaration checks its city and
	// country against the place's own facts and refuses another Fort Worth - and the next
	// declaration is asked, so a cell that would otherwise show a clean forecast for the wrong
	// town shows the refusal and the answer it did reach.
	namesake = splitStub([
		{"host": "geocode.maps.co", "json": [{"osm_type": "relation", "osm_id": 999,
			"lat": "32.7555", "lon": "-97.3308", "name": "Fort Worth",
			"address": {"city": "Springfield", "country": "United States"}}]},
		{"host": "geocoding-api.open-meteo.com", "json": geocoderReply},
	])
	namesakePlace = uid.of("place", ["Fort Worth namesake"])
	namesakeSession = startSession(
		providers.registry(namesake, declared, uid, [geoDecl, weatherDecl]),
		["has-latitude(" + namesakePlace + ", ?lat)"],
		[triples.SpoTriple.make(namesakePlace, "has-city", "Fort Worth")])
	namesakeLines = namesakeSession.answers.lines
	h.check("a first result that is not the place asked about is refused, naming both",
		printed(namesakeLines, "  geocode.maps.co could not answer has-latitude(" +
			namesakePlace + ", ?lat): the first result is not the place asked about: its city " +
			"is Springfield, not Fort Worth"))
	h.check("after the search that would have answered was asked",
		namesake.calls.len == 2 and namesake.calls[0].indexOf("geocode.maps.co") != null)
	namesakeLatitude = null
	for readFact in namesakeSession.session.facts
		if readFact.predicate == "has-latitude" then namesakeLatitude = readFact
	end for
	h.check("so the next declaration answers, and nothing of the wrong place is read",
		printed(namesakeLines, "  has-latitude(" + namesakePlace + ", 32.7555) # open-meteo/geocoding " +
			today) and
			namesakeLatitude != null and namesakeLatitude.source == "open-meteo/geocoding" and
			not holds(namesakeSession.answers.asked, "  ?lat = "))

	// The map a session falls through to takes its first result the same way, so it says the
	// same thing about it: when both geocoders find another town, both are warnings and the value
	// is asked for, rather than the second map's namesake passing where the first map's failed.
	bothNamesakes = splitStub([
		{"host": "geocode.maps.co", "json": [{"osm_type": "relation", "osm_id": 998,
			"lat": "32.7555", "lon": "-97.3308", "name": "Fort Worth",
			"address": {"city": "Springfield", "country": "United States"}}]},
		{"host": "geocoding-api.open-meteo.com", "json": {"results": [{"id": 7,
			"name": "Springfield", "latitude": 39.7984, "longitude": -89.6440,
			"country": "United States"}]}},
	])
	bothPlace = uid.of("place", ["Fort Worth both namesakes"])
	bothSession = startSession(
		providers.registry(bothNamesakes, declared, uid, [geoDecl, weatherDecl]),
		["has-latitude(" + bothPlace + ", ?lat)"],
		[triples.SpoTriple.make(bothPlace, "has-city", "Fort Worth")])
	bothLines = bothSession.answers.lines
	h.check("the map a search falls through to refuses a namesake of its own, naming both",
		printed(bothLines, "  open-meteo could not answer has-latitude(" + bothPlace +
			", ?lat): the first result is not the place asked about: its name is Springfield, " +
			"not Fort Worth"))
	h.check("after both geocoders were asked", bothNamesakes.calls.len == 2)
	bothLatitude = null
	for readFact in bothSession.session.facts
		if readFact.predicate == "has-latitude" then bothLatitude = readFact
	end for
	h.check("so neither reading is held and the value is asked for instead",
		bothLatitude == null and holds(bothSession.answers.asked, "  ?lat = "))

	// A reply with no city in its address is the shape Sao Paulo and Mexico City come back in,
	// and the name it is called confirms it: the session answers from the search with nothing said,
	// where a namesake in the same shape is the warning above.
	cityless = splitStub([
		{"host": "geocode.maps.co", "json": [{"osm_type": "relation", "osm_id": 298285,
			"lat": "-23.55065", "lon": "-46.63338", "name": "São Paulo",
			"address": {"country": "Brasil"}}]},
		{"host": "geocoding-api.open-meteo.com", "json": geocoderReply},
	])
	citylessPlace = uid.of("place", ["Sao Paulo by city"])
	citylessSession = startSession(
		providers.registry(cityless, declared, uid, [geoDecl, weatherDecl]),
		["has-latitude(" + citylessPlace + ", ?lat)"],
		[triples.SpoTriple.make(citylessPlace, "has-city", "Sao Paulo")])
	citylessLines = citylessSession.answers.lines
	citylessLatitude = null
	for readFact in citylessSession.session.facts
		if readFact.predicate == "has-latitude" then citylessLatitude = readFact
	end for
	h.check("a search reply with a name and no city is confirmed by that name",
		citylessLatitude != null and citylessLatitude.source == "geocode.maps.co/search" and
			printed(citylessLines, "  has-latitude(" + citylessPlace + ", -23.55065) # geocode.maps.co/search " +
				today))
	h.check("with nothing said against it",
		not holds(citylessLines, "could not answer") and
			not holds(citylessSession.answers.asked, "  ?lat = "))
	h.check("and the map that declares the fact again is not asked",
		cityless.calls.len == 1 and cityless.calls[0].indexOf("geocode.maps.co") != null)

	// ── A weather question answered through the prompt ──────────────────

	// The whole loop rather than one pass: a question about a place the session knows only by
	// city is answered from the geocoder's coordinates and then the forecast's reading, and the
	// value prompt is never reached.
	prompted = splitStub([
		{"host": "geocode.maps.co", "json": searchReply},
		{"host": "api.open-meteo.com", "json": weatherReply},
	])
	byCity = uid.of("place", ["Fort Worth by city"])
	askedWeather = startSession(
		providers.registry(prompted, declared, uid, [geoDecl, weatherDecl]),
		["has-temperature-2m(" + byCity + ", ?t)", "quit"],
		[triples.SpoTriple.make(byCity, "has-city", "Fort Worth")])
	h.check("a weather question asks the geocoder and then the forecast",
		prompted.calls.len == 2 and prompted.calls[0].indexOf("geocode.maps.co") != null and
			prompted.calls[1].indexOf("api.open-meteo.com") != null)
	h.check("and asks the reader for no value",
		not holds(askedWeather.answers.asked, "  ?t = "))
	h.check("so the question is answered from the reading the forecast gave",
		holds(askedWeather.answers.lines, "has-temperature-2m(" + byCity + ", 18.4)") and
			not holds(askedWeather.answers.lines, "no solution found"))

	// ── A reading from an earlier day is due again ──────────────────────────

	// The day is the host's, so the suite pins one, as the provenance cases do.
	savedStaleDay = triples.today
	triples.today = {"year": 2026, "month": 11, "day": 21}
	// Yesterday's coordinate says where the place was yesterday. A question needing it asks the
	// service again and is answered from today's reading, which takes the earlier line's place.
	newerReply = [{"osm_type": "relation", "osm_id": 12345, "lat": "32.7600",
		"lon": "-97.3400", "name": "Fort Worth", "class": "place", "type": "city",
		"place_rank": 16, "importance": 0.7, "place_id": 1,
		"address": {"city": "Fort Worth", "country": "United States", "country_code": "us"}}]
	newerStub = stubFor(newerReply)
	duePlace = uid.of("place", ["Fort Worth yesterday"])
	dueCity = triples.SpoTriple.make(duePlace, "has-city", "Fort Worth")
	dueLat = triples.SpoTriple.make(duePlace, "has-latitude", 32.7555)
	dueLat.source = "geocode.maps.co/search"
	dueLat.fetched = "2026-11-20"
	dueAsked = startSession(providers.registry(newerStub, declared, uid, [geoDecl]),
		["has-latitude(" + duePlace + ", ?lat)", "quit"], [dueCity, dueLat])
	h.check("a reading fetched on an earlier day is asked for again", newerStub.calls == 1)
	dueLatHeld = null
	for readFact in dueAsked.session.facts
		if readFact.predicate == "has-latitude" then dueLatHeld = readFact
	end for
	h.check("and the answer is today's reading, on the line the earlier one stood on",
		dueLatHeld != null and dueLatHeld.object == 32.76 and
			dueLatHeld.fetched == "2026-11-21" and holds(dueAsked.answers.lines,
			"has-latitude(" + duePlace + ", 32.76)"))
	h.check("so a reading fetched again is no stale reading to own up to",
		not holds(dueAsked.answers.lines, "from an earlier reading"))

	// A reading fetched today is today's already, and a typed fact was never a service's to
	// fetch: neither asks anything.
	todayStub = stubFor(newerReply)
	todayLat = triples.SpoTriple.make(duePlace, "has-latitude", 32.7555)
	todayLat.source = "geocode.maps.co/search"
	todayLat.fetched = "2026-11-21"
	todayAsked = startSession(providers.registry(todayStub, declared, uid, [geoDecl]),
		["has-latitude(" + duePlace + ", ?lat)", "quit"], [dueCity, todayLat])
	h.check("a reading fetched today is answered from without a call",
		todayStub.calls == 0 and holds(todayAsked.answers.lines,
			"has-latitude(" + duePlace + ", 32.7555)"))
	typedStub = stubFor(newerReply)
	typedAsked = startSession(providers.registry(typedStub, declared, uid, [geoDecl]),
		["has-latitude(" + duePlace + ", ?lat)", "quit"],
		[dueCity, triples.SpoTriple.make(duePlace, "has-latitude", 32.7555)])
	h.check("and a typed fact was never a service's to fetch again", typedStub.calls == 0)

	// Nothing in the registry declares the reading, so there is no newer one to fetch: the fact
	// the session holds answers, and the reader is not asked for what it already knows.
	lonelyPlace = uid.of("place", ["Fort Worth uncovered"])
	lonelyTemp = triples.SpoTriple.make(lonelyPlace, "has-temperature-2m", 18.4)
	lonelyTemp.source = "open-meteo/forecast"
	lonelyTemp.fetched = "2026-11-20"
	lonelyStub = stubFor(searchReply)
	lonelyAsked = startSession(providers.registry(lonelyStub, declared, uid, [geoDecl]),
		["has-temperature-2m(" + lonelyPlace + ", ?t)", "quit"], [lonelyTemp])
	h.check("a reading nothing can fetch again still answers, rather than the reader",
		lonelyStub.calls == 0 and not holds(lonelyAsked.answers.asked, "  ?t = ") and
			holds(lonelyAsked.answers.lines,
				"has-temperature-2m(" + lonelyPlace + ", 18.4)"))
	// Answering from it silently would be the worst of both, so the transcript says which day
	// the reading is from - the line a facts file would hold, its annotation included - and
	// says it before the answer it stands behind.
	noteAt = null
	answerAt = null
	for lineAt in lonelyAsked.answers.lines.indexes
		line = lonelyAsked.answers.lines[lineAt]
		if noteAt == null and line.indexOf("from an earlier reading") != null then noteAt = lineAt
		if line.indexOf("has-temperature-2m(" + lonelyPlace + ", 18.4)") != null then
			answerAt = lineAt
		end if
	end for
	h.check("and an answer from an old reading says which day it is from, before it answers",
		noteAt != null and answerAt != null and noteAt < answerAt and
			lonelyAsked.answers.lines[noteAt].indexOf("fetched 2026-11-20") != null and
			lonelyAsked.answers.lines[noteAt].indexOf("# open-meteo/forecast 2026-11-20") != null)
	// A request sent now is not computed from yesterday's coordinates. The forecast's fields want
	// today's readings, so the map that declares a stale one is asked for a newer reading first,
	// and the forecast goes out with what that map answered.
	coordStub = splitStub([
		{"host": "geocode.maps.co", "json": newerReply},
		{"host": "api.open-meteo.com", "json": weatherReply},
	])
	coordPlace = uid.of("place", ["Fort Worth old coords"])
	oldLat = triples.SpoTriple.make(coordPlace, "has-latitude", 32.7555)
	oldLat.source = "geocode.maps.co/search"
	oldLat.fetched = "2026-11-20"
	oldLon = triples.SpoTriple.make(coordPlace, "has-longitude", -97.3308)
	oldLon.source = "geocode.maps.co/search"
	oldLon.fetched = "2026-11-20"
	coordAsked = startSession(
		providers.registry(coordStub, declared, uid, [geoDecl, weatherDecl]),
		["has-temperature-2m(" + coordPlace + ", ?t)", "quit"],
		[triples.SpoTriple.make(coordPlace, "has-city", "Fort Worth"), oldLat, oldLon])
	h.check("a forecast is not sent with yesterday's coordinates",
		coordStub.calls.len == 2 and coordStub.calls[0].indexOf("geocode.maps.co") != null and
			coordStub.calls[1].indexOf("latitude=32.76") != null and
			coordStub.calls[1].indexOf("32.7555") == null)
	h.check("and the reading it answers with is the forecast's",
		holds(coordAsked.answers.lines, "has-temperature-2m(" + coordPlace + ", 18.4)"))

	// With no map declaring the coordinate, the reading the session holds is what the request
	// goes with: an old coordinate still answers where nothing can refresh it.
	lonelyCoord = stubFor(weatherReply)
	lonelyCoords = startSession(providers.registry(lonelyCoord, declared, uid, [weatherDecl]),
		["has-temperature-2m(" + coordPlace + ", ?t)", "quit"], [oldLat, oldLon])
	h.check("a coordinate nothing can refresh is sent as it stands, and answered",
		lonelyCoord.calls == 1 and lonelyCoord.seenUrl.indexOf("latitude=32.7555") != null and
			holds(lonelyCoords.answers.lines, "has-temperature-2m(" + coordPlace + ", 18.4)"))

	// When the session holds both, today's reading is the one the request is computed from.
	bothCoordStub = stubFor(weatherReply)
	todayLat = triples.SpoTriple.make(coordPlace, "has-latitude", 32.76)
	todayLat.source = "geocode.maps.co/search"
	todayLat.fetched = "2026-11-21"
	todayLon = triples.SpoTriple.make(coordPlace, "has-longitude", -97.34)
	todayLon.source = "geocode.maps.co/search"
	todayLon.fetched = "2026-11-21"
	startSession(providers.registry(bothCoordStub, declared, uid, [geoDecl, weatherDecl]),
		["has-temperature-2m(" + coordPlace + ", ?t)", "quit"],
		[oldLat, oldLon, todayLat, todayLon])
	h.check("today's reading is preferred to the earlier one, without asking for another",
		bothCoordStub.calls == 1 and bothCoordStub.seenUrl.indexOf("latitude=32.76") != null and
			bothCoordStub.seenUrl.indexOf("32.7555") == null)

	// A reading the question never needed is not announced. A rule's other derivation wants
	// yesterday's temperature, which proves nothing - 18.4 is not 10 or less - so the answer
	// comes from the latitude alone, and the note names only that reading.
	warmer = triples.SpoTriple.make(duePlace, "has-temperature-2m", 18.4)
	warmer.source = "open-meteo/forecast"
	warmer.fetched = "2026-11-20"
	hereByLatitude = triples.parseRule("is-here(?p, yes) => has-latitude(?p, ?lat)")
	hereByWeather = triples.parseRule(
		"is-here(?p, yes) => has-temperature-2m(?p, ?t), less-than-or-equal(?t, 10)")
	hereRules = [rules.Rule.make(hereByLatitude.head, hereByLatitude.body),
		rules.Rule.make(hereByWeather.head, hereByWeather.body)]
	quietAsked = startSession([], ["is-here(" + duePlace + ", ?v)", "quit"],
		[dueCity, dueLat, warmer], hereRules)
	h.check("a reading the answer never stood on is not announced",
		holds(quietAsked.answers.lines, "from an earlier reading, fetched 2026-11-20: " +
			"has-latitude(" + duePlace + ", 32.7555)") and
			not holds(quietAsked.answers.lines, "18.4") and
			holds(quietAsked.answers.lines, "is-here(" + duePlace + ", yes)"))

	// Nor is one announced for a question that ends up unanswered: the reading could fill the
	// gap of a derivation, but no derivation is reached, so there is no answer to stand on it.
	cozyRule = triples.parseRule(
		"is-cozy(?p, yes) => has-temperature-2m(?p, ?t), less-than-or-equal(?t, 10)")
	cozyAsked = startSession([], ["is-cozy(?p, yes)", "quit"], [warmer],
		[rules.Rule.make(cozyRule.head, cozyRule.body)])
	h.check("and a question that stays unanswered announces none",
		not holds(cozyAsked.answers.lines, "from an earlier reading") and
			holds(cozyAsked.answers.lines, "no solution found"))
	triples.today = savedStaleDay

	// ── A provider's fact says who answered it, and when ────────────────────

	// The day is the host's, so the suite pins one, as the age cases do.
	savedToday = triples.today
	triples.today = {"year": 2026, "month": 11, "day": 21}
	answeredBy = providers.answer(
		providers.forGoal(providers.registry(stubFor(fortWorth), declared, uid, [decl]), triples,
			sessionPlace),
		triples)
	h.check("a fact a service answered names the service and endpoint that gave it",
		answeredBy.ok and answeredBy.facts[0].source == "ipwho.is/lookup")
	h.check("and the day it was read", answeredBy.facts[0].fetched == "2026-11-21")
	h.check("which the fact's own line carries, so a saved file keeps it",
		answeredBy.facts[0].text.indexOf(" # ipwho.is/lookup 2026-11-21") != null)
	readBack = triples.SpoTriple.parse(answeredBy.facts[0].text)
	h.check("and reads back as the fact it is",
		not (readBack isa error) and readBack.text == answeredBy.facts[0].text and
			readBack.source == "ipwho.is/lookup" and readBack.fetched == "2026-11-21")
	h.check("while a typed fact names no service",
		triples.SpoTriple.make("tim", "has-age", 17).text == "has-age(tim, 17)")
	stampedWeather = providers.answer(
		providers.forGoal(providers.registry(stubFor(weatherReply), declared, uid, [weatherDecl]),
			triples, needTemperature),
		triples, providers.requestFor(weatherCap, triples, [locatedLat, locatedLon], located),
		located)
	forecastStamps = 0
	for fact in stampedWeather.facts
		if fact.source == "open-meteo/forecast" and fact.fetched == "2026-11-21" then
			forecastStamps = forecastStamps + 1
		end if
	end for
	h.check("and every fact a forecast answered names that endpoint too",
		stampedWeather.ok and forecastStamps == 4)
	triples.today = savedToday

	// ── The same fact, answered again ───────────────────────────────────────

	// A reading fetched on another day is the same claim, so the later answer takes the line
	// the earlier one stood on rather than sitting beside it - and /undo puts the earlier back.
	refetched = uid.of("place", ["Fort Worth refetched"])
	firstRead = triples.SpoTriple.make(refetched, "has-latitude", 32.7555)
	firstRead.source = "geocode.maps.co/search"
	firstRead.fetched = "2026-11-20"
	secondRead = triples.SpoTriple.make(refetched, "has-latitude", 32.7555)
	secondRead.source = "geocode.maps.co/search"
	secondRead.fetched = "2026-11-21"
	readingSession = {"triples": triples, "Rule": rules.Rule, "facts": [firstRead], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
		"providers": null, "io": {"read": null, "say": function(line)
		end function}}
	changed = sessionModule.addFact(readingSession, secondRead)
	h.check("a fact answered again replaces the line it was read on before",
		changed and readingSession.facts.len == 1 and
			readingSession.facts[0].fetched == "2026-11-21" and
			readingSession.changes.len == 1 and readingSession.changes[0].kind == "replace")
	changed = sessionModule.undo(readingSession)
	h.check("and /undo puts the earlier answer back",
		changed and readingSession.facts.len == 1 and
			readingSession.facts[0].fetched == "2026-11-20")

	// A typed fact that says the same thing is not written over by an answer: the claim is
	// already known, so the service's line is not a second copy of it.
	typedRead = triples.SpoTriple.make(refetched, "has-latitude", 32.7555)
	typedSaid = []
	typedSession = {"triples": triples, "Rule": rules.Rule, "facts": [typedRead], "rules": [],
		"depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {}, "knowledge": knowledge,
		"providers": null, "io": {"read": null, "say": function(line)
			typedSaid.push(line)
		end function}}
	changed = sessionModule.addFact(typedSession, secondRead)
	h.check("a typed fact saying the same thing is not written over by an answer",
		not changed and typedSession.facts.len == 1 and typedSession.facts[0].source == null and
			holds(typedSaid, "already known"))

	// ── --offline is the run's own switch ──────────────────────────────────

	// It is read from the command line into the session, and a session carrying it asks nothing
	// of any service it was handed: the question goes the way it did before there were any.
	offlineRun = engineModule.build(triples, rules.Rule,
		parsed(["--domain", "data", "--offline"]), null)
	onlineRun = engineModule.build(triples, rules.Rule, parsed(["--domain", "data"]), null)
	h.check("--offline is the run's own switch, off unless asked for",
		not (offlineRun isa error) and offlineRun.offline == 1 and
			not (onlineRun isa error) and onlineRun.offline == 0)
	offlineStub = stubFor(weatherReply)
	offlineSession = {"triples": triples, "Rule": rules.Rule, "facts": [locatedLat, locatedLon],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": knowledge, "offline": 1,
		"providers": providers.registry(offlineStub, declared, uid, [weatherDecl]),
		"io": {"read": null, "say": function(line)
		end function}}
	changed = sessionModule.provideMissing(offlineSession,
		triples.needsFor(needTemperature, offlineSession.facts, [], 8))
	h.check("and refuses a call the session could otherwise make",
		not changed and offlineStub.calls == 0)

	// ── A session given no registry asks nothing ────────────────────────────

	plain = startSession(null, ["has-location(session, ?p)", "Fort Worth", "quit"])
	h.check("a session with no registry prompts for the fact, as it always did",
		holds(plain.answers.asked, "  ?p = ") and
			holds(plain.answers.lines, "  added has-location(session, Fort Worth)"))
	h.check("and the registry it was not given is not made up for it",
		plain.session.providers == null)
end function
