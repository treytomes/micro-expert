// Cases for src/spike/geocode_map.ms, geocode.maps.co as the writer reads it: one search result
// written as docs/api/geocode-maps-co.md's vocabulary, the other shapes a search can answer
// with, and the request half beside geocode.fetch's own.
//
// No request leaves the program: a client stand-in answers get with the JSON below, and the
// expected facts are the ones the reference page writes for the trimmed Eiffel result.

run = function(declared, geocodeMap, apiClient, triples, uid, schemaLoader, h)
	decl = geocodeMap.build()

	// One /search result, as the reference page trims it.
	eiffel = {
		"place_id": 119141919,
		"licence": "Data © OpenStreetMap contributors, ODbL 1.0.",
		"osm_type": "way",
		"osm_id": 5013364,
		"boundingbox": ["48.8574", "48.8590", "2.2933", "2.2956"],
		"lat": "48.8582599",
		"lon": "2.2945006",
		"display_name": "Tour Eiffel, 5, Avenue Anatole France, 75007, France",
		"class": "man_made",
		"type": "tower",
		"place_rank": 30,
		"importance": 0.6199831475570641,
		"addresstype": "man_made",
		"name": "Tour Eiffel",
		"localname": "Tour Eiffel",
		"address": {"house_number": "5", "road": "Avenue Anatole France", "city": "Paris",
			"country": "France", "country_code": "fr", "postcode": "75007"},
		"extratags": {"wikidata": "Q243", "wikipedia": "fr:Tour Eiffel", "fee": "10-25€"},
		"namedetails": {"name:fr": "Tour Eiffel"},
	}

	berlin = {
		"place_id": 240109189,
		"osm_type": "relation",
		"osm_id": 62422,
		"boundingbox": ["52.3382", "52.6755", "13.0883", "13.7611"],
		"lat": "52.5170365",
		"lon": "13.3888599",
		"display_name": "Berlin, Deutschland",
		"class": "boundary",
		"type": "administrative",
		"place_rank": 4,
		"importance": 0.8268,
		"addresstype": "city",
		"name": "Berlin",
		"localname": "Berlin",
		"address": {"house_number": "1", "road": "Unter den Linden", "city": "Berlin",
			"country": "Deutschland", "country_code": "de", "postcode": "10117"},
		"extratags": {"wikidata": "Q64", "wikipedia": "de:Berlin", "fee": "no"},
		"namedetails": {"name:fr": "Berlin"},
	}

	missingId = {"place_id": 1, "osm_type": "way", "lat": "48.8582599", "lon": "2.2945006",
		"name": "Nowhere", "display_name": "Nowhere"}

	badLatitude = {
		"place_id": 119141919, "osm_type": "way", "osm_id": 5013364,
		"boundingbox": ["48.8574", "48.8590", "2.2933", "2.2956"],
		"lat": "north", "lon": "2.2945006",
		"display_name": "Tour Eiffel", "class": "man_made", "type": "tower", "place_rank": 30,
		"importance": 0.6199831475570641, "name": "Tour Eiffel",
		"address": {"house_number": "5", "road": "Avenue Anatole France", "city": "Paris",
			"country": "France", "country_code": "fr"},
		"extratags": {"wikidata": "Q243", "wikipedia": "fr:Tour Eiffel", "fee": "10-25€"},
		"namedetails": {"name:fr": "Tour Eiffel"},
	}

	refused = {"error": {"code": 400, "message": "Parameter 'lon' missing."}}

	// One result, as docs/api/geocode-maps-co.md writes it. The numbers are the text the reply
	// sent, read as numbers and printed by the engine, which keeps six decimals.
	expected = [
		"has-name(way/5013364, Tour Eiffel)",
		"has-name-in-fr(way/5013364, Tour Eiffel)",
		"has-latitude(way/5013364, 48.85826)",
		"has-longitude(way/5013364, 2.294501)",
		"has-south-latitude(way/5013364, 48.8574)",
		"has-north-latitude(way/5013364, 48.859)",
		"has-west-longitude(way/5013364, 2.2933)",
		"has-east-longitude(way/5013364, 2.2956)",
		"has-osm-class(way/5013364, man_made)",
		"has-osm-type(way/5013364, tower)",
		"has-place-rank(way/5013364, 30)",
		"has-importance(way/5013364, 0.619983)",
		"has-place-id(way/5013364, 119141919)",
		"has-house-number(way/5013364, ""5"")",
		"has-road(way/5013364, Avenue Anatole France)",
		"has-city(way/5013364, Paris)",
		"has-country(way/5013364, France)",
		"has-country-code(way/5013364, fr)",
		"has-wikidata(way/5013364, Q243)",
		"has-wikipedia(way/5013364, fr:Tour Eiffel)",
		"has-fee(way/5013364, 10-25€)",
		"was-answer-to(way/5013364, Eiffel Tower)",
	]

	linesOf = function(facts)
		"One line per fact, as a .kb file would write it."
		lines = []
		for fact in facts
			lines.push fact.text
		end for
		return lines
	end function

	factAbout = function(facts, predicate)
		"The fact with this predicate, or null when the reply wrote none."
		for fact in facts
			if fact.predicate == predicate then return fact
		end for
		return null
	end function

	// The client's own checks, with get answering canned JSON: nothing leaves the program.
	stubFor = function(json)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.canned = json
		fake.get = function(url, timeout=null)
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url,
				"error": null}
		end function
		return fake
	end function

	// ── One result, beside the documented vocabulary ────────────────────

	reading = declared.read(triples, uid, decl, "search", [eiffel], {"q": "Eiffel Tower"})
	h.check("a declared search is ok", reading.ok)
	h.check("and writes the twenty-two facts the reference page names",
		reading.facts.len == 22 and linesOf(reading.facts) == expected)
	h.check("the subject is the OSM object, not a hash", reading.subject == "way/5013364")
	unread = 0
	for fact in reading.facts
		back = triples.SpoTriple.parse(fact.text)
		if back isa error or back.text != fact.text then unread = unread + 1
	end for
	h.check("every fact reads back as the line it printed", unread == 0)
	types = schemaLoader.build()
	unfit = 0
	for fact in reading.facts
		if schemaLoader.misfit(types, fact) != null then unfit = unfit + 1
	end for
	h.check("and every one fits data/schema.kb", unfit == 0)

	// ── The reverse and lookup endpoints ────────────────────────────────
	// The three endpoints answer with one result shape, so the facts are the same list; only
	// a search records the question, and a lookup may carry its coordinate as a GeoJSON point.

	reverse = declared.read(triples, uid, decl, "reverse", eiffel, {"lat": 48.8583, "lon": 2.2945})
	h.check("a declared reverse is ok and writes one result",
		reverse.ok and reverse.facts.len == 21 and reverse.subject == "way/5013364")
	h.check("and records no query, since a reverse has none",
		factAbout(reverse.facts, "was-answer-to") == null)

	tower = {"osm_type": "relation", "osm_id": 253832,
		"centroid": {"coordinates": [2.2945, 48.8584]}, "name": "Tour Eiffel",
		"display_name": "Tour Eiffel", "boundingbox": ["48.8574", "48.8590", "2.2933", "2.2956"],
		"class": "man_made", "type": "tower", "place_rank": 30, "importance": 0.62,
		"place_id": 1, "address": {"house_number": "5", "road": "Avenue Anatole France",
			"city": "Paris", "country": "France", "country_code": "fr"},
		"extratags": {"wikidata": "Q243", "wikipedia": "fr:Tour Eiffel", "fee": "10-25€"},
		"namedetails": {"name:fr": "Tour Eiffel"}}
	lookup = declared.read(triples, uid, decl, "lookup", [tower], {"osm_ids": ["R253832"]})
	h.check("a declared lookup is ok and writes one result",
		lookup.ok and lookup.facts.len == 21 and lookup.subject == "relation/253832")
	h.check("a centroid point is read longitude first and written latitude first",
		factAbout(lookup.facts, "has-latitude").object == 48.8584 and
			factAbout(lookup.facts, "has-longitude").object == 2.2945)
	h.check("and a lookup records no query either",
		factAbout(lookup.facts, "was-answer-to") == null)

	// ── The other shapes a search answers with ──────────────────────────

	two = declared.read(triples, uid, decl, "search", [eiffel, berlin], {"q": "Paris"})
	h.check("two results write a set each", two.ok and two.facts.len == 44)
	h.check("with the OSM object as each subject",
		two.subjects.join(", ") == "way/5013364, relation/62422")

	empty = declared.read(triples, uid, decl, "search", [], {"q": "Nowhere"})
	h.check("a search that matched nothing is ok with no facts",
		empty.ok and empty.facts.len == 0 and empty.subjects.len == 0)

	partial = declared.read(triples, uid, decl, "search", [eiffel, missingId], {"q": "Paris"})
	h.check("a result without an OSM id is skipped, and the rest written",
		partial.facts.len == 22 and partial.subjects.len == 1)
	h.check("and the skip is named",
		partial.skipped.len == 1 and partial.skipped[0].indexOf("osm_id") != null)

	unfitLatitude = declared.read(triples, uid, decl, "search", [badLatitude], {"q": "Eiffel Tower"})
	h.check("a latitude that is not a number writes no latitude",
		unfitLatitude.facts.len == 21 and factAbout(unfitLatitude.facts, "has-latitude") == null)
	h.check("and is named as left out",
		unfitLatitude.skipped.len == 1 and
			unfitLatitude.skipped[0].indexOf("has-latitude") != null)

	refusal = declared.read(triples, uid, decl, "search", refused, {})
	h.check("a refused search is not ok", not refusal.ok and refusal.facts.len == 0)
	h.check("and carries the service's own message",
		refusal.error == "the service refused the request: Parameter 'lon' missing.")
	h.check("a reply that is not a list is refused",
		declared.read(triples, uid, decl, "search", {"foo": 1}, {}).error ==
			"the service did not answer with a list")

	noQuery = declared.read(triples, uid, decl, "search", [eiffel], {})
	h.check("a result with no query records none",
		noQuery.facts.len == 21 and factAbout(noQuery.facts, "was-answer-to") == null)

	// ── The reply has to be the place the question named ────────────────
	// A search is asked with limit=1 and read as what came back, so the reply block names the
	// fields that make a result this place: the city and the country the session holds for it.
	held = [triples.SpoTriple.make("place-1", "has-city", "Paris"),
		triples.SpoTriple.make("place-1", "has-country", "France")]
	confirmed = declared.read(triples, uid, decl, "search", [eiffel], {"q": "Paris"}, held)
	h.check("a reply whose city and country are the place's own is read",
		confirmed.ok == 1 and confirmed.facts.len == reading.facts.len)

	// The first result is the one a limit of one asked for, so it has to be this place: another
	// Springfield would otherwise be read as the Paris asked about.
	wrongCity = {"osm_type": "node", "osm_id": 1, "lat": "39.7984", "lon": "-89.6440",
		"name": "Springfield", "address": {"city": "Springfield", "country": "France"}}
	mismatch = declared.read(triples, uid, decl, "search", [wrongCity], {"q": "Paris"}, held)
	h.check("a first result that is another city is refused",
		mismatch.ok == 0 and mismatch.facts.len == 0)
	h.check("whose message says both cities",
		mismatch.error == "the first result is not the place asked about: its city is " +
			"Springfield, not Paris")

	// The same through a reply: a search for Washington, D.C. whose result calls it Washington is
	// the place asked about, and its facts are read.
	washington = {"osm_type": "relation", "osm_id": 5396194, "lat": "38.89511",
		"lon": "-77.03637", "name": "Washington",
		"address": {"city": "Washington", "country": "United States"}}
	askedDC = [triples.SpoTriple.make("place-2", "has-city", "Washington, D.C."),
		triples.SpoTriple.make("place-2", "has-country", "United States")]
	district = declared.read(triples, uid, decl, "search", [washington], {"q": "Washington, D.C."},
		askedDC)
	h.check("a result that calls Washington, D.C. just Washington is read",
		district.ok == 1 and district.facts.len > 0)

	wrongCountry = {"osm_type": "node", "osm_id": 2, "lat": "48.8583", "lon": "2.2945",
		"name": "Paris", "address": {"city": "Paris", "country": "Canada"}}
	h.check("and another country is refused by its own name",
		declared.read(triples, uid, decl, "search", [wrongCountry], {"q": "Paris"},
			held).error == "the first result is not the place asked about: its country is " +
			"Canada, not France")

	shouted = {"osm_type": "node", "osm_id": 3, "lat": "48.8583", "lon": "2.2945",
		"name": "PARIS", "address": {"city": "PARIS", "country": "france"}}
	h.check("a name in other capitals is the same name",
		declared.read(triples, uid, decl, "search", [shouted], {"q": "Paris"}, held).ok == 1)

	// A city is often typed under a spelling its official name differs from, and the service's
	// word for it is the service's: the words are what make two namings one place.
	for pair in [["Washington, D.C.", "Washington"], ["Washington, D.C.", "Washington, D.C."],
		["New York", "City of New York"], ["New York City", "City of New York"],
		["St. Louis", "Saint Louis"], ["Ft. Worth", "Fort Worth"],
		["Sao Paulo", "São Paulo"], ["Berlin", "Berlín"],
		["Salt Lake City", "Salt Lake City"]]
		h.check(pair[0] + " is the same place as " + pair[1], declared.samePlace(pair[0], pair[1]))
	end for
	// And a loosening is only a loosening where the words are: another town stays another town.
	for pair in [["Springfield", "Fort Worth"], ["Paso", "El Paso"],
		["Kansas City", "Los Angeles"], ["Berlin", "Berne"], ["Москва", "Moscow"]]
		h.check(pair[0] + " is not the same place as " + pair[1],
			not declared.samePlace(pair[0], pair[1]))
	end for

	h.check("a place the session holds no city or country for is read as it comes",
		declared.read(triples, uid, decl, "search", [eiffel], {"q": "Eiffel Tower"}, []).ok == 1)
	noAddress = {"osm_type": "node", "osm_id": 4, "lat": "48.8583", "lon": "2.2945",
		"name": "Paris"}
	h.check("and a reply that leaves the field out says nothing to disagree with",
		declared.read(triples, uid, decl, "search", [noAddress], {"q": "Paris"}, held).ok == 1)

	// ── The request half ────────────────────────────────────────────────

	h.check("the map names the service's own base and path",
		decl.base == "https://geocode.maps.co" and decl.endpoints.search.path == "/search")
	names = []
	for paramSpec in decl.endpoints.search.params
		names.push paramSpec.name
	end for
	h.check("and the parameters a search takes",
		names.indexOf("q") != null and names.indexOf("limit") != null and
			names.indexOf("format") != null and names.indexOf("accept-language") != null)

	options = {"q": "Eiffel Tower", "limit": 1, "addressdetails": true, "api_key": "test-key"}
	newResult = declared.fetch(stubFor([eiffel]), decl, "search", options, 10)
	h.check("the declared fetch puts every option in the url",
		newResult.url.indexOf("https://geocode.maps.co/search?") == 0 and
			newResult.url.indexOf("Eiffel") != null and newResult.url.indexOf("limit=1") != null)
	h.check("and hides the key",
		newResult.url.indexOf("test-key") == null and
			newResult.url.indexOf("api_key=REDACTED") != null)

	// ── The key a declaration names in the environment ──────────────────

	// The map names the variable its key lives in, so a request with no key of its own is sent
	// with the environment's - the way src/main.ms and src/notebook.ms, having read the .env,
	// leave it - and a run with neither is refused before anything goes out.
	keyStub = function(json)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.canned = json
		fake.calls = 0
		fake.seenUrl = null
		fake.get = function(url, timeout=null)
			self.calls = self.calls + 1
			self.seenUrl = url
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url,
				"error": null}
		end function
		return fake
	end function

	kept = null
	if env.hasIndex("GEOCODE_MAPS_API_KEY") then kept = env["GEOCODE_MAPS_API_KEY"]
	env["GEOCODE_MAPS_API_KEY"] = "from-env"
	envClient = keyStub([eiffel])
	envResult = declared.fetch(envClient, decl, "search", {"q": "Eiffel Tower", "limit": 1}, 10)
	h.check("a request with no key of its own is sent with the environment's",
		envClient.calls == 1 and envClient.seenUrl.indexOf("api_key=from-env") != null)
	h.check("and the url the result keeps hides it",
		envResult.url.indexOf("from-env") == null and
			envResult.url.indexOf("api_key=REDACTED") != null)
	callerClient = keyStub([eiffel])
	declared.fetch(callerClient, decl, "search", {"q": "Eiffel Tower", "api_key": "caller"}, 10)
	h.check("a key the caller hands in wins over the environment's",
		callerClient.seenUrl.indexOf("api_key=caller") != null and
			callerClient.seenUrl.indexOf("from-env") == null)

	// A blank setting is absent, the way dotenv reads one, and a key nobody supplies is never a
	// keyless call: the request stops here, in words that name the variable to set.
	env["GEOCODE_MAPS_API_KEY"] = "  "
	blankClient = keyStub([eiffel])
	blankResult = declared.fetch(blankClient, decl, "search", {"q": "Eiffel Tower"}, 10)
	h.check("a blank setting counts as none", blankClient.calls == 0 and not blankResult.ok)
	env.remove("GEOCODE_MAPS_API_KEY")
	missingClient = keyStub([eiffel])
	missingResult = declared.fetch(missingClient, decl, "search", {"q": "Eiffel Tower"}, 10)
	h.check("a declaration whose key is missing refuses the request",
		not missingResult.ok and missingClient.calls == 0 and missingResult.json == null)
	h.check("and says which variable to set, and where",
		missingResult.error == "geocode.maps.co needs a key: set GEOCODE_MAPS_API_KEY in the environment or in the .env beside the run")
	if kept == null then
		env.remove("GEOCODE_MAPS_API_KEY")
	else
		env["GEOCODE_MAPS_API_KEY"] = kept
	end if

	// ── What the result is known by ─────────────────────────────────────

	h.check("the label reads the result's display name",
		declared.label(decl, "search", eiffel).indexOf("Tour Eiffel") != null)
	h.check("and the coordinates are the reply's",
		declared.coordinates(decl, "search", eiffel) == "48.8582599, 2.2945006")
end function