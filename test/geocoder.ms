// Cases for src/spike/geocode_map.ms, geocode.maps.co as the writer reads it: one search result
// written as docs/api/geocode-maps-co.md's vocabulary, the other shapes a search can answer
// with, and the request half beside geocode.fetch's own.
//
// No request leaves the program: a client stand-in answers get with the JSON below, and the
// expected facts are the ones the reference page writes for the trimmed Eiffel result.

run = function(declared, geocodeMap, apiClient, geocode, triples, uid, schemaLoader, h)
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

	// ── The request half ────────────────────────────────────────────────

	h.check("the map names the service's own base and path",
		decl.base == geocode.base and decl.endpoints.search.path == geocode.specFor("search").path)
	spec = geocode.specFor("search")
	names = []
	for paramSpec in decl.endpoints.search.params
		names.push paramSpec.name
	end for
	declaredNames = []
	for paramSpec in spec.params
		declaredNames.push paramSpec.name
	end for
	h.check("and the same parameters its table declares", names.join(",") == declaredNames.join(","))

	options = {"q": "Eiffel Tower", "limit": 1, "addressdetails": true, "api_key": "test-key"}
	oldResult = geocode.fetch(stubFor([eiffel]), "search", options)
	newResult = declared.fetch(stubFor([eiffel]), decl, "search", options, 10)
	h.check("the declared fetch builds the url geocode.fetch builds",
		newResult.url == oldResult.url)
	h.check("and hides the key",
		newResult.url.indexOf("test-key") == null and
			newResult.url.indexOf("api_key=REDACTED") != null)

	// ── What the result is known by ─────────────────────────────────────

	place = geocode.reply(apiClient, "search", [eiffel]).places[0]
	h.check("the label reads as Place's", declared.label(decl, "search", eiffel) == place.label)
	h.check("and so do the coordinates",
		declared.coordinates(decl, "search", eiffel) == place.coordinates)
end function