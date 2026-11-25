// Cases for src/location.ms: the facts a session starts with, read from ipwho.is's map.
//
// No request leaves the program: a client stand-in answers get with the canned Fort Worth
// reply, and src/services/declared.ms reads it through src/services/ipwhois_map.ms. Fort Worth is
// the answer throughout, because that is what ipwho.is answers this machine with, and its id
// is the one the facts carry.

run = function(location, uid, triples, apiClient, declared, ipwhoisMap, h)
	decl = ipwhoisMap.build()

	fortWorth = {"success": true, "continent": "North America", "country": "United States",
		"region": "Texas", "city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}

	// The fact with this predicate, or null when the reply wrote none.
	factAbout = function(facts, predicate)
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
		// What the client was asked to wait, so a case can see the timeout reach it.
		fake.seenTimeout = null
		fake.get = function(url, timeout=null)
			self.seenTimeout = timeout
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url,
				"error": null}
		end function
		return fake
	end function

	place = uid.of("place", ["Fort Worth", "Texas", "United States"])
	client = stubFor(fortWorth)
	looked = location.sessionFacts(triples, uid, client, declared, decl)

	// ── The place the session holds ─────────────────────────────────────────

	h.check("a session's facts come from one lookup", looked.ok and looked.facts.len == 7)
	subject = factAbout(looked.facts, "has-location").object
	h.check("the session has the place the lookup answered with", subject == place)
	h.check("named by the id its own fields generate", subject == "place-f1d6b283a52a28dc")
	h.check("and what the place is comes from the rule, not a fact",
		factAbout(looked.facts, "is-a") == null)
	others = 0
	for fact in looked.facts
		if fact.predicate != "has-location" and fact.subject != subject then others = others + 1
	end for
	h.check("every other fact hangs off the place rather than the session", others == 0)

	// ── What the place is like ──────────────────────────────────────────────

	h.check("the place is named as the answer named it",
		factAbout(looked.facts, "has-country").object == "United States" and
			factAbout(looked.facts, "has-region").object == "Texas" and
			factAbout(looked.facts, "has-city").object == "Fort Worth")
	h.check("with what it sits on", factAbout(looked.facts, "has-continent").object == "North America")
	h.check("and the coordinates the answer gave, as numbers",
		factAbout(looked.facts, "has-latitude").object == 32.7254134 and
			factAbout(looked.facts, "has-longitude").object == -97.3208492)

	// Each fact is a line of a .kb file, so it has to read back as the line it printed.
	unread = 0
	for fact in looked.facts
		read = triples.SpoTriple.parse(fact.text)
		if read isa error or read.text != fact.text then unread = unread + 1
	end for
	h.check("each fact reads back as the line it printed", unread == 0)
	h.check("and the startup lookup waits seconds rather than the client's minute",
		client.seenTimeout == location.startupTimeout and location.startupTimeout < 60)

	// ── An answer there is nothing to name ──────────────────────────────────

	refusedLookup = location.sessionFacts(triples, uid,
		stubFor({"success": false, "message": "404 not found"}), declared, decl)
	h.check("a refused lookup leaves the session without facts",
		not refusedLookup.ok and refusedLookup.facts.len == 0 and refusedLookup.error != null)

	noCity = {"success": true, "country": "United States", "longitude": -97.3208492}
	noCityLookup = location.sessionFacts(triples, uid, stubFor(noCity), declared, decl)
	h.check("a reply with no city has no place to hang facts on",
		not noCityLookup.ok and noCityLookup.facts.len == 0)

	noCoordinates = {"success": true, "country": "United States", "city": "Fort Worth"}
	noCoordinatesLookup = location.sessionFacts(triples, uid, stubFor(noCoordinates), declared, decl)
	h.check("nor does a reply with no coordinates",
		not noCoordinatesLookup.ok and noCoordinatesLookup.facts.len == 0)

	blankCity = {"success": true, "country": "United States", "city": "   ", "longitude": -97.3208492}
	blankLookup = location.sessionFacts(triples, uid, stubFor(blankCity), declared, decl)
	h.check("and a city of spaces is no city", not blankLookup.ok and blankLookup.facts.len == 0)

	noJson = location.sessionFacts(triples, uid, stubFor(null), declared, decl)
	h.check("a lookup with no JSON says so", not noJson.ok and noJson.error.indexOf("JSON") != null)
end function
