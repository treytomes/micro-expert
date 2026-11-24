// Cases for src/spike/declared.ms, the shared writer, and src/spike/ipwhois_map.ms, ipwho.is as
// the map it reads: the canned Fort Worth reply as the writer reads it.
//
// No request leaves the program: a client stand-in answers get with the JSON below.

run = function(declared, ipwhoisMap, apiClient, triples, uid, h)
	decl = ipwhoisMap.build()

	// One answer, as ipwho.is answers this machine.
	fortWorth = {
		"ip": "2607:fb91:4080:a72e:6fb9:c94a:f32a:7f70",
		"success": true,
		"type": "IPv6",
		"continent": "North America",
		"continent_code": "NA",
		"country": "United States",
		"country_code": "US",
		"region": "Texas",
		"region_code": "TX",
		"city": "Fort Worth",
		"latitude": 32.7254134,
		"longitude": -97.3208492,
		"is_eu": 0,
		"postal": "76127",
		"calling_code": "1",
		"capital": "Washington D.C.",
		"borders": "CA,MX",
		"flag": {"img": "https://cdn.ipwhois.io/flags/us.svg", "emoji": "🇺🇸",
			"emoji_unicode": "U+1F1FA U+1F1F8"},
		"connection": {"asn": 21928, "org": "T-Mobile USA, Inc.", "isp": "T-Mobile USA, Inc.",
			"domain": "t-mobile.com"},
		"timezone": {"id": "America/Chicago", "abbr": "CST", "is_dst": 0, "offset": -21600,
			"utc": "-06:00"},
	}

	// The replies the service can send when a field is missing or it says no.
	noRegion = {"success": true, "continent": "North America", "country": "United States",
		"city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}
	nullRegion = {"success": true, "continent": "North America", "country": "United States",
		"region": null, "city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}
	blankRegion = {"success": true, "country": "United States", "region": "  ",
		"city": "Fort Worth", "latitude": 32.7254134, "longitude": -97.3208492}
	noCity = {"success": true, "continent": "North America", "country": "United States",
		"region": "Texas", "latitude": 32.7254134, "longitude": -97.3208492}
	noCoordinates = {"success": true, "continent": "North America", "country": "United States",
		"region": "Texas", "city": "Fort Worth"}
	blankCity = {"success": true, "country": "United States", "city": "   ",
		"longitude": -97.3208492}
	refused = {"success": false, "message": "404 not found"}
	narrowed = {"success": true, "city": "Fort Worth", "country": "United States"}

	// A fact with this predicate, or null when the reply wrote none.
	factAbout = function(facts, predicate)
		for fact in facts
			if fact.predicate == predicate then return fact
		end for
		return null
	end function

	// Whether two fact lists are the same lines in the same order.
	sameFacts = function(a, b)
		if a.len != b.len then return false
		for i in a.indexes
			if a[i].text != b[i].text then return false
		end for
		return true
	end function

	// The client's own checks, with get answering canned JSON: nothing leaves the program.
	stubFor = function(json)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.canned = json
		fake.seenTimeout = null
		fake.get = function(url, timeout=null)
			self.seenTimeout = timeout
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url,
				"error": null}
		end function
		return fake
	end function

	// ── The full reply, both ways ───────────────────────────────────────

	reading = declared.read(triples, uid, decl, "lookup", fortWorth)
	h.check("a declared lookup is ok", reading.ok)
	h.check("and writes the seven facts the reply supports", reading.facts.len == 7)
	h.check("the place is named by the id its fields generate",
		reading.subject == "place-f1d6b283a52a28dc")
	h.check("has-location puts the place under the session",
		reading.facts[0].text == "has-location(session, place-f1d6b283a52a28dc)")
	others = 0
	for fact in reading.facts
		if fact.predicate != "has-location" and fact.subject != reading.subject then
			others = others + 1
		end if
	end for
	h.check("and every other fact hangs off the place", others == 0)
	h.check("the coordinates stay numbers, as the reply sent them",
		factAbout(reading.facts, "has-latitude").object isa number)
	unread = 0
	for fact in reading.facts
		back = triples.SpoTriple.parse(fact.text)
		if back isa error or back.text != fact.text then unread = unread + 1
	end for
	h.check("every fact reads back as the line it printed", unread == 0)

	// ── A field the reply did not carry ─────────────────────────────────

	noRegionReading = declared.read(triples, uid, decl, "lookup", noRegion)
	h.check("a reply with no region writes one fact fewer",
		noRegionReading.facts.len == 6 and factAbout(noRegionReading.facts, "has-region") == null)
	h.check("and says which fact it left out",
		noRegionReading.skipped.len == 1 and
			noRegionReading.skipped[0].indexOf("has-region") != null)
	h.check("and writes the six facts the reply supports",
		noRegionReading.facts.len == 6 and factAbout(noRegionReading.facts, "has-city") != null)
	nullRegionReading = declared.read(triples, uid, decl, "lookup", nullRegion)
	h.check("a null region is dropped exactly as an absent one",
		sameFacts(noRegionReading.facts, nullRegionReading.facts))
	blankRegionReading = declared.read(triples, uid, decl, "lookup", blankRegion)
	h.check("a region of spaces is no region either",
		blankRegionReading.facts.len == 5 and factAbout(blankRegionReading.facts, "has-region") == null)
	h.check("and writes the five facts the reply supports",
		blankRegionReading.facts.len == 5 and factAbout(blankRegionReading.facts, "has-city") != null)

	// ── An answer there is nothing to name ──────────────────────────────

	noCityReading = declared.read(triples, uid, decl, "lookup", noCity)
	h.check("a reply with no city has no place to hang facts on",
		not noCityReading.ok and noCityReading.facts.len == 0)
	h.check("and says which field it needed", noCityReading.error == "the reply named no city")
	noCoordinatesReading = declared.read(triples, uid, decl, "lookup", noCoordinates)
	h.check("nor does a reply with no coordinates",
		not noCoordinatesReading.ok and noCoordinatesReading.facts.len == 0)
	blankCityReading = declared.read(triples, uid, decl, "lookup", blankCity)
	h.check("and a city of spaces is no city",
		not blankCityReading.ok and blankCityReading.facts.len == 0)

	// ── A refused lookup ────────────────────────────────────────────────

	refusedReading = declared.read(triples, uid, decl, "lookup", refused)
	h.check("a refusal is read before any fact is",
		not refusedReading.ok and refusedReading.facts.len == 0)
	h.check("and carries the service's own message",
		refusedReading.error == "the service refused the request: 404 not found")
	h.check("a body that is not an object is refused",
		declared.read(triples, uid, decl, "lookup", "not json").error ==
			"the service did not answer with an object")
	narrowedReading = declared.read(triples, uid, decl, "lookup", narrowed)
	h.check("a reply narrowed to city and country writes no place",
		not narrowedReading.ok and narrowedReading.facts.len == 0)

	// ── The request half ────────────────────────────────────────────────

	h.check("the map names the service's own base", decl.base == "https://ipwho.is")
	h.check("and the same two parameters its table declares",
		decl.endpoints.lookup.params.len == 2 and
			decl.endpoints.lookup.params[0].name == "lang" and
			decl.endpoints.lookup.params[1].name == "fields")

	newStub = stubFor(fortWorth)
	newResult = declared.fetch(newStub, decl, "lookup", {"fields": ["city", "country"]}, 10)
	h.check("the declared fetch builds the url the service's table says",
		newResult.url == "https://ipwho.is/?fields=city%2Ccountry")
	h.check("and hands the transport the deadline it was given", newStub.seenTimeout == 10)
	h.check("an endpoint the map does not name is refused by name",
		declared.fetch(newStub, decl, "bulk").error ==
			"Unknown endpoint " + apiClient.quote("bulk") + ".")
	badResult = declared.fetch(stubFor(fortWorth), decl, "lookup", {"fields": ""})
	h.check("and a parameter the table refuses never leaves the program",
		not badResult.ok and badResult.url == "" and badResult.error.indexOf("fields") != null)

	// ── What the reply is known by ──────────────────────────────────────

	h.check("the label names the city",
		declared.label(decl, "lookup", fortWorth).indexOf("Fort Worth") != null)
	h.check("and the coordinates are the reply's",
		declared.coordinates(decl, "lookup", fortWorth) == "32.725413, -97.320849")
end function