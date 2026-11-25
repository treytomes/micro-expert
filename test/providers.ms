// Cases for src/providers.ms: the registry the service maps declare, and a question the session
// answers by asking a service rather than the reader. geocode.maps.co's two declarations are here
// too - a search asked by a place's own name and a reverse asked by its coordinates - both read
// back onto the place the question named rather than onto the OSM object the reply identifies,
// and Open-Meteo's forecast, asked with a place's coordinates for the next hour's weather.
//
// No request leaves the program: a client stand-in answers get with the canned Fort Worth reply,
// the way test/location.ms and test/declared.ms do, and counts what it was asked.

run = function(providers, declared, apiClient, triples, uid, ipwhoisMap, geocodeMap, openmeteoMap,
	sessionModule, rules, engineModule, cliLibrary, optionsModule, h)
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

	// A one-fact answer is one change like any other, and it remembers its request the same way:
	// taken back, the reverse is asked again rather than the address being left to the reader.
	sparseReply = {"osm_type": "way", "osm_id": 77, "address": {"road": "Main Street"}}
	sparse = stubFor(sparseReply)
	sparseSession = {"triples": triples, "Rule": rules.Rule, "facts": [namedLat, namedLon],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": null, "providers": providers.registry(sparse, declared, uid, [geoDecl]),
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
	// is asked with the coordinates the session already holds for it. One request carries the
	// five documented hourly variables, so the first weather fact a question needs brings the
	// rest with it and the session does not ask twice.
	weatherDecl = openmeteoMap.build()
	weatherReply = {"latitude": 32.7555, "longitude": -97.3308, "timezone": "America/Chicago",
		"hourly": {"time": ["2026-11-25T09:00"], "temperature_2m": [18.4],
			"relative_humidity_2m": [62], "precipitation": [0], "wind_speed_10m": [9.7],
			"weather_code": [1], "precipitation_probability": [10]}}
	located = uid.of("place", ["Fort Worth weather"])
	locatedLat = triples.SpoTriple.make(located, "has-latitude", 32.7555)
	locatedLon = triples.SpoTriple.make(located, "has-longitude", -97.3308)
	needTemperature = triples.SpoTriple.make(located, "has-temperature-2m", triples.var("t"))

	weatherRegistry = providers.registry(stubFor(weatherReply), declared, uid, [weatherDecl])
	h.check("the forecast declares a fact per documented hourly variable",
		weatherRegistry.len == 5)
	weatherCap = providers.forGoal(weatherRegistry, triples, needTemperature)
	h.check("a question needing a located place's temperature finds the forecast",
		weatherCap != null and weatherCap.endpoint == "forecast")
	h.check("a place with no coordinates is no forecast's to ask",
		providers.requestFor(weatherCap, triples, [], located) == null)
	weatherRequest = providers.requestFor(weatherCap, triples, [locatedLat, locatedLon], located)
	h.check("the forecast is asked with the coordinates that place's facts hold",
		weatherRequest != null and weatherRequest.latitude == 32.7555 and
			weatherRequest.longitude == -97.3308)
	h.check("and for the next hour's five variables, which is one request",
		weatherRequest != null and weatherRequest.forecast_hours == 1 and
			weatherRequest.hourly.len == 5 and weatherRequest.hourly[0] == "temperature_2m")

	forecastStub = stubFor(weatherReply)
	forecastAnswer = providers.answer(
		providers.forGoal(providers.registry(forecastStub, declared, uid, [weatherDecl]), triples,
			needTemperature),
		triples, providers.requestFor(weatherCap, triples, [locatedLat, locatedLon], located),
		located)
	h.check("the forecast's answer is one reading per variable, about the place the question named",
		forecastAnswer.ok and forecastAnswer.facts.len == 5 and
			forecastAnswer.facts[0].predicate == "has-temperature-2m" and
			triples.termText(forecastAnswer.facts[0].subject) == located)
	h.check("with the hour the reply covers kept as the fact's span",
		forecastAnswer.facts.len == 5 and forecastAnswer.facts[0].at != null)
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
		"knowledge": null, "providers": providers.registry(forecasting, declared, uid, [weatherDecl]),
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
			weatherSession.changes[0].steps.len == 5)
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
		countOf(weatherSaid, "took back 5 facts open-meteo answered") == 1 and
			not holds(weatherSaid, "took back has-temperature-2m("))
	// The request went with the answer: a session that no longer holds what the forecast said
	// asks it again rather than the reader.
	h.check("and /undo forgets the request that answer made",
		weatherSession.providerCalls.len == 0)
	changed = sessionModule.provideMissing(weatherSession,
		triples.needsFor(needTemperature, weatherSession.facts, [], 8))
	h.check("so the question asks the forecast again rather than the reader",
		changed and forecasting.calls == 2)

	// A forecast that cannot answer leaves the fact to the reader, and the place's next weather
	// fact reads the same failed attempt rather than making a second request.
	offlineForecast = stubFor(null, 1, "Could not run curl: no such host")
	weatherUnmet = []
	unmetSession = {"triples": triples, "Rule": rules.Rule, "facts": [locatedLat, locatedLon],
		"rules": [], "depth": 8, "verbose": 0, "nlp": 0, "style": null, "paths": {},
		"knowledge": null,
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
	h.check("and one place's failed weather request is not asked again for its next fact",
		offlineForecast.calls == 1 and not changed)

	// ── A session given no registry asks nothing ────────────────────────────

	plain = startSession(null, ["has-location(session, ?p)", "Fort Worth", "quit"])
	h.check("a session with no registry prompts for the fact, as it always did",
		holds(plain.answers.asked, "  ?p = ") and
			holds(plain.answers.lines, "  added has-location(session, Fort Worth)"))
	h.check("and the registry it was not given is not made up for it",
		plain.session.providers == null)
end function
