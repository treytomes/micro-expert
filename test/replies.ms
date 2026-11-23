// Cases for the geocode reply classes: one Place per result, held by the reply class its
// endpoint answers with.
//
// The JSON here is hand-written from docs/api/geocode-maps-co.md rather than fetched, so a
// failure says what a class made of a field, and the suite needs no key and no network.

run = function(geo, h)
	// One /search result, trimmed to the fields these cases read.
	eiffel = {
		"place_id": 119141919,
		"osm_type": "way",
		"osm_id": 5013364,
		"lat": "48.8582599",
		"lon": "2.2945006",
		"type": "tower",
		"name": "Tour Eiffel",
		"display_name": "Tour Eiffel, 5, Avenue Anatole France, 75007, France",
		"address": {"house_number": "5", "city": "Paris", "country": "France"},
		"extratags": {"wikidata": "Q243"},
	}

	quote = char(34)

	search = function(items, asked={})
		"One /search reply, as the layer reads it."
		return geo.reply("search", items, asked)
	end function

	// ── One result ──────────────────────────────────────────────────────────

	one = search([eiffel], {"q": "Eiffel Tower"})
	h.check("a result is a Place", one.places[0] isa geo.Place)
	h.check("its fields stay as the service sent them", one.places[0].raw.lat == "48.8582599")
	h.check("a result is known by its display name", one.places[0].label == eiffel.display_name)
	h.check("or by its own name when there is no display name",
		search([{"name": "Berlin"}]).places[0].label == "Berlin")
	h.check("or by its local name",
		search([{"localname": "Köln"}]).places[0].label == "Köln")
	h.check("a result with none of the three has no label", search([{}]).places[0].label == "")
	h.check("its coordinates are the lat and lon it carried",
		one.places[0].coordinates == "48.8582599, 2.2945006")
	h.check("a result with no coordinates has none", search([{}]).places[0].coordinates == "")
	h.check("its type is the OSM type it was classified as", one.places[0].typeName == "tower")
	h.check("a result without a type has none", search([{}]).places[0].typeName == "")

	// ── The search reply ────────────────────────────────────────────────────

	three = search([eiffel, eiffel, eiffel], {"q": "Paris"})
	h.check("a search reply holds one Place per result", three.count == 3)
	h.check("each of them a Place", search([eiffel, {}], {}).places[1] isa geo.Place)
	h.check("its heading counts the results and names the query",
		one.heading == "1 result for " + quote + "Eiffel Tower" + quote + ":")
	h.check("and says results when there are more than one",
		three.heading == "3 results for " + quote + "Paris" + quote + ":")
	h.check("a structured search has no query to name",
		search([eiffel], {"city": "Paris"}).heading == "1 result:")
	h.check("a search that matched nothing is empty", search([], {"q": "Nowhere"}).isEmpty)
	h.check("and says what was searched for",
		search([], {"q": "Nowhere"}).emptyMessage == "No matches for " + quote + "Nowhere" + quote + ".")
	h.check("a structured search that matched nothing says only that",
		search([], {"city": "Nowhere"}).emptyMessage == "No matches.")
	h.check("a search reply numbers its results", one.numbered)

	// ── The reverse reply ───────────────────────────────────────────────────

	reverse = geo.reply("reverse", eiffel, {"lat": 48.8583, "lon": 2.2945})
	h.check("a reverse reply is a ReverseReply", reverse isa geo.ReverseReply)
	h.check("it holds the one object it was sent", reverse.count == 1)
	h.check("and that result reads like any other", reverse.places[0].label == eiffel.display_name)
	h.check("there is no heading above a single answer", reverse.heading == "")
	h.check("nor a number in front of it", not reverse.numbered)

	// ── The lookup reply ────────────────────────────────────────────────────

	// A lookup result may carry a GeoJSON point instead of lat and lon.
	tower = {"osm_type": "relation", "osm_id": 253832, "centroid": {"coordinates": [2.2945, 48.8584]},
		"localname": "Tour Eiffel"}
	lookup = geo.reply("lookup", [tower], {"osm_ids": ["R253832", "W175905"]})
	h.check("a lookup reply is a LookupReply", lookup isa geo.LookupReply)
	h.check("a centroid point is stored longitude first and shown latitude first",
		lookup.places[0].coordinates == "48.8584, 2.2945")
	h.check("its heading names the ids that were asked for",
		lookup.heading == "1 result for R253832,W175905:")
	h.check("one id given as text is named as it came",
		geo.reply("lookup", [tower], {"osm_ids": "R253832"}).heading == "1 result for R253832:")
	h.check("a lookup with no ids to name says none",
		geo.reply("lookup", [tower], {}).heading == "1 result:")
	h.check("an id the service did not find is simply absent",
		geo.reply("lookup", [], {"osm_ids": "R253832"}).isEmpty)

	// ── Refusals and other shapes ───────────────────────────────────────────

	refused = geo.reply("search", {"error": {"code": 400, "message": "Parameter 'lon' missing."}}, {})
	h.check("a refused request is not ok", not refused.ok)
	h.check("and carries the service's own message",
		refused.error == "The API refused the request: Parameter 'lon' missing.")
	h.check("an error sent as a word is kept as it came",
		geo.reply("search", {"error": "ERROR 400: bad format"}, {}).error == "The API refused the request: ERROR 400: bad format")
	h.check("a reply that is neither an object nor a list is refused",
		geo.reply("search", "not json", {}).error == "The API returned an unexpected reply.")
	h.check("nothing to read is no reply at all", geo.reply("search", null, {}) == null)
	h.check("an entry that is not a result object is skipped",
		geo.reply("search", [eiffel, "junk", 7], {}).count == 1)
end function
