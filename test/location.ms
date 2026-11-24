// Cases for src/location.ms: the place a bare lookup answers with, turned into facts about
// the session and named by the id its own fields generate.
//
// The lookup is not run here, and no request leaves the program: generateLocationFacts takes the
// answer a lookup would return, so these cases hand it maps. Fort Worth is the answer throughout,
// because that is what ipwho.is answers this machine with, and its id is the one the facts carry.

run = function(location, uid, triples, apiClient, ipwhois, h)
	fortWorth = {"ok": 1, "continent": "North America", "country": "United States",
		"region": "Texas", "city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}

	// The fact with this predicate, or null when the answer carried no field for it.
	factAbout = function(facts, predicate)
		for fact in facts
			if fact.predicate == predicate then return fact
		end for
		return null
	end function

	place = uid.of("place", ["Fort Worth", "Texas", "United States"])
	facts = location.generateLocationFacts(triples, uid, fortWorth)

	// ── The place the session holds ─────────────────────────────────────────

	h.check("a location is seven facts", facts.len == 7)
	subject = factAbout(facts, "has-location").object
	h.check("the session has the place the lookup answered with", subject == place)
	h.check("named by the id its own fields generate", subject == "place-f1d6b283a52a28dc")
	h.check("and what the place is comes from the rule, not a fact", factAbout(facts, "is-a") == null)
	others = 0
	for fact in facts
		if fact.predicate != "has-location" and fact.subject != subject then others = others + 1
	end for
	h.check("every other fact hangs off the place rather than the session", others == 0)

	// ── What the place is like ──────────────────────────────────────────────

	h.check("the place is named as the answer named it",
		factAbout(facts, "has-country").object == "United States" and
			factAbout(facts, "has-region").object == "Texas" and
			factAbout(facts, "has-city").object == "Fort Worth")
	h.check("with what it sits on", factAbout(facts, "has-continent").object == "North America")
	h.check("and the coordinates the answer gave, as numbers",
		factAbout(facts, "has-latitude").object == 32.7254134 and
			factAbout(facts, "has-longitude").object == -97.3208492)

	// Each fact is a line of a .kb file, so it has to read back as the line it printed.
	unread = 0
	for fact in facts
		read = triples.SpoTriple.parse(fact.text)
		if read isa error or read.text != fact.text then unread = unread + 1
	end for
	h.check("each fact reads back as the line it printed", unread == 0)

	// ── A field the answer did not carry ────────────────────────────────────
	// The reply is the identity: a lookup that names no region names the same city under another
	// id, since region is one of the three fields the term is built from.

	narrow = {"ok": 1, "continent": "North America", "country": "United States",
		"city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}
	narrowFacts = location.generateLocationFacts(triples, uid, narrow)
	h.check("a reply with no region writes no region fact", factAbout(narrowFacts, "has-region") == null)
	h.check("and still writes the rest, one fact fewer", narrowFacts.len == 6)
	h.check("still naming the place by what it carried",
		factAbout(narrowFacts, "has-location").object == uid.of("place", ["Fort Worth", "United States"]))

	// A field sent as null is the same as one not sent at all.
	nullRegion = {"ok": 1, "continent": "North America", "country": "United States", "region": null,
		"city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}
	nullFacts = location.generateLocationFacts(triples, uid, nullRegion)
	h.check("a null field is dropped exactly as an absent one",
		nullFacts.len == 6 and factAbout(nullFacts, "has-region") == null)
	blankRegion = {"ok": 1, "country": "United States", "region": "  ", "city": "Fort Worth",
		"longitude": -97.3208492}
	blankFacts = location.generateLocationFacts(triples, uid, blankRegion)
	h.check("a field sent as spaces is no field either",
		blankFacts.len == 4 and factAbout(blankFacts, "has-region") == null)
	nullObjects = 0
	for fact in facts + narrowFacts + nullFacts
		if fact.object == null then nullObjects = nullObjects + 1
	end for
	h.check("and no fact carries null as a value", nullObjects == 0)

	// ── An answer there is nothing to name ──────────────────────────────────
	// The region and country alone name a whole country's worth of places, so neither a reply
	// without a city nor one whose city is only spaces gets a term to hang facts on.

	noCity = {"ok": 1, "continent": "North America", "country": "United States", "region": "Texas",
		"latitude": 32.7254134, "longitude": -97.3208492}
	h.check("a reply with no city has no place to hang facts on",
		location.generateLocationFacts(triples, uid, noCity).len == 0)
	noCoordinates = {"ok": 1, "continent": "North America", "country": "United States",
		"region": "Texas", "city": "Fort Worth"}
	h.check("nor does a reply with no coordinates",
		location.generateLocationFacts(triples, uid, noCoordinates).len == 0)
	blankCity = {"ok": 1, "country": "United States", "city": "   ", "longitude": -97.3208492}
	h.check("and a city of spaces is no city",
		location.generateLocationFacts(triples, uid, blankCity).len == 0)
	h.check("a lookup that failed writes no facts",
		location.generateLocationFacts(triples, uid, {"ok": 0, "error": "no location"}).len == 0)

	// ── The facts a run starts with ─────────────────────────────────────────
	// sessionFacts is what --where calls at startup, so the path from a lookup to the facts a
	// session holds is walked here through a client stand-in, with no request leaving the program.
	// The stand-in copies the client's own checks by name, since reading one out of an iteration
	// pair calls it, and answers get with canned JSON.

	stubFor = function(json)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.canned = json
		fake.get = function(url, timeout=null)
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url, "error": null}
		end function
		return fake
	end function

	looked = location.sessionFacts(triples, uid, stubFor({"success": 1, "continent": "North America",
		"country": "United States", "region": "Texas", "city": "Fort Worth",
		"latitude": 32.7254134, "longitude": -97.3208492}), ipwhois)
	h.check("a session's facts come from one lookup", looked.ok and looked.facts.len == 7 and
		looked.facts[0].text == "has-location(session, place-f1d6b283a52a28dc)")
	refusedLookup = location.sessionFacts(triples, uid, stubFor({"success": 0, "message": "404 not found"}), ipwhois)
	h.check("a refused lookup leaves the session without facts",
		not refusedLookup.ok and refusedLookup.facts.len == 0 and refusedLookup.error != null)
end function
