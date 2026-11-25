// Cases for src/services/openmeteo_map.ms, Open-Meteo's endpoints as the writer reads them:
// one canned forecast written as docs/api/open-meteo.md's vocabulary with the hour and the
// probability on each fact, the other shapes a reply can answer with, and the request half
// beside the map's own request half.
//
// No request leaves the program: a client stand-in answers get with the JSON below, and the
// expected lines are the reference page's vocabulary with the two annotations the map adds -
// '@' the hour a reading covers, and '~' the service's chance of precipitation.

run = function(declared, openmeteoMap, apiClient, triples, uid, schemaLoader, h)
	decl = openmeteoMap.build()

	// Three hours, five variables, and the missing temperature at the third.
	forecast = {
		"latitude": 52.512604,
		"longitude": 13.419517,
		"generationtime_ms": 0.0424,
		"utc_offset_seconds": 0,
		"timezone": "GMT",
		"timezone_abbreviation": "GMT",
		"elevation": 38.0,
		"hourly_units": {"time": "iso8601", "temperature_2m": "°C",
			"relative_humidity_2m": "%", "precipitation": "mm", "wind_speed_10m": "km/h",
			"weather_code": "wmo code", "precipitation_probability": "%"},
		"hourly": {
			"time": ["2026-11-22T00:00", "2026-11-22T01:00", "2026-11-22T02:00"],
			"temperature_2m": [4.1, 3.8, null],
			"relative_humidity_2m": [81, 83, 85],
			"precipitation": [0.2, 0.0, 0.1],
			"precipitation_probability": [40, 35, 55],
			"wind_speed_10m": [12.4, 11.9, 10.2],
			"weather_code": [3, 3, 61],
		},
	}

	// One reply with only one of the five variables, to show the rest left out.
	sparse = {
		"latitude": 52.512604,
		"longitude": 13.419517,
		"hourly": {
			"time": ["2026-11-22T00:00", "2026-11-22T01:00", "2026-11-22T02:00"],
			"temperature_2m": [4.1, 3.8, 2.9],
		},
	}

	// A series with no time list is not a series to read.
	noTime = {"latitude": 52.512604, "longitude": 13.419517,
		"hourly": {"temperature_2m": [4.1, 3.8]}}

	refused = {"error": true, "reason": "Latitude must be in range of -90 to 90°. Given: 999.0."}

	// The reply as docs/api/open-meteo.md writes it: each reading covers the hour that starts
	// at its instant, the last hour keeps the moment alone, and only precipitation carries the
	// service's probability.
	expected = [
		"has-temperature-2m(berlin, 4.1) @ [2026-11-22 00:00, 2026-11-22 01:00]",
		"has-relative-humidity-2m(berlin, 81) @ [2026-11-22 00:00, 2026-11-22 01:00]",
		"has-precipitation(berlin, 0.2) @ [2026-11-22 00:00, 2026-11-22 01:00] ~ 40%",
		"has-wind-speed-10m(berlin, 12.4) @ [2026-11-22 00:00, 2026-11-22 01:00]",
		"has-weather-code(berlin, 3) @ [2026-11-22 00:00, 2026-11-22 01:00]",
		"has-temperature-2m(berlin, 3.8) @ [2026-11-22 01:00, 2026-11-22 02:00]",
		"has-relative-humidity-2m(berlin, 83) @ [2026-11-22 01:00, 2026-11-22 02:00]",
		"has-precipitation(berlin, 0) @ [2026-11-22 01:00, 2026-11-22 02:00] ~ 35%",
		"has-wind-speed-10m(berlin, 11.9) @ [2026-11-22 01:00, 2026-11-22 02:00]",
		"has-weather-code(berlin, 3) @ [2026-11-22 01:00, 2026-11-22 02:00]",
		"has-relative-humidity-2m(berlin, 85) @ 2026-11-22 02:00",
		"has-precipitation(berlin, 0.1) @ 2026-11-22 02:00 ~ 55%",
				"has-wind-speed-10m(berlin, 10.2) @ 2026-11-22 02:00",
		"has-weather-code(berlin, 61) @ 2026-11-22 02:00",
		// The units table, as facts about the variables: the reply's °C and km/h are the
		// request's celsius and kmh, and weather_code's "wmo code" is no unit at all.
		"has-unit(temperature_2m, celsius)",
		"has-unit(relative_humidity_2m, percent)",
		"has-unit(precipitation, mm)",
		"has-unit(wind_speed_10m, kmh)",
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

	// ── One reply, beside the documented vocabulary ─────────────────────

	reading = declared.read(triples, uid, decl, "forecast", forecast, {"place": "berlin"})
	h.check("a declared forecast is ok", reading.ok)
	h.check("and writes the fourteen lines the page names, and a unit for each variable that has one",
		reading.facts.len == 18 and linesOf(reading.facts) == expected)
	h.check("the subject is the place the caller named, once per place",
		reading.subject == "berlin" and reading.subjects.join(",") == "berlin")
	unread = 0
	for fact in reading.facts
		back = triples.SpoTriple.parse(fact.text)
		if back isa error or back.text != fact.text or back.at != fact.at or
			back.confidence != fact.confidence then unread = unread + 1
	end for
	h.check("every annotated fact reads back as the line it printed", unread == 0)
	types = schemaLoader.build()
	unfit = 0
	for fact in reading.facts
		if schemaLoader.misfit(types, fact) != null then unfit = unfit + 1
	end for
	h.check("and every one fits data/schema.kb", unfit == 0)

	// ── The two annotations ─────────────────────────────────────────────

	h.check("an hour is the span from its instant to the next",
		reading.facts[0].at == "[2026-11-22 00:00, 2026-11-22 01:00]")
	h.check("and the reply's last hour keeps the moment alone",
		reading.facts[10].at == "2026-11-22 02:00")
	spanned = 0
	moments = 0
	for fact in reading.facts
		if fact.at == null then continue
		if fact.at[:1] == "[" then
			spanned = spanned + 1
		else
			moments = moments + 1
		end if
	end for
	h.check("ten facts cover an hour and four carry a moment",
		spanned == 10 and moments == 4)
	h.check("a temperature the reply did not carry writes no fact, and the skip is named",
		reading.skipped.len == 1 and
			reading.skipped[0].indexOf("has-temperature-2m") != null)

	// A 40% chance is 40% confidence that the rain fact holds, and only that fact is unsure.
	h.check("only precipitation carries a confidence, from precipitation_probability",
		reading.facts[2].confidence == 40 and reading.facts[7].confidence == 35 and
			reading.facts[11].confidence == 55)
	others = 0
	for fact in reading.facts
		if fact.predicate != "has-precipitation" and fact.confidence != 100 then
			others = others + 1
		end if
	end for
	h.check("and no other fact is less than fully confident", others == 0)

	// The unit is the fact a number cannot carry: one per variable, in the request's own word,
	// and none for a symbol that is not a unit.
	units = []
	for fact in reading.facts
		if fact.predicate == "has-unit" then units.push fact.text
	end for
	h.check("a unit is one fact per variable, in the word the request parameters use",
		units.len == 4 and units[0] == "has-unit(temperature_2m, celsius)" and
			units[1] == "has-unit(relative_humidity_2m, percent)")
	h.check("and a variable whose unit is not one - the weather code - gets no unit fact",
		factAbout(reading.facts, "has-unit") != null and
			units.join("\n").indexOf("weather_code") == null)
	h.check("a unit fact is about the variable, so it carries no hour",
		reading.facts[14].subject == "temperature_2m" and reading.facts[14].at == null)

	// ── The other shapes a forecast answers with ────────────────────────

	sparseReading = declared.read(triples, uid, decl, "forecast", sparse, {"place": "berlin"})
	h.check("a reply with one variable writes three facts and names the rest",
		sparseReading.ok and sparseReading.facts.len == 3 and sparseReading.skipped.len == 12)
	h.check("and claims no confidence it was not given",
		sparseReading.facts[0].confidence == 100)

	noPlace = declared.read(triples, uid, decl, "forecast", forecast, {})
	h.check("a forecast with no place named has no subject",
		not noPlace.ok and noPlace.facts.len == 0)
	h.check("and says which request field it needed",
		noPlace.error == "the request named no place")

	noTimeReading = declared.read(triples, uid, decl, "forecast", noTime, {"place": "berlin"})
	h.check("a series with no time list is not a series to read",
		not noTimeReading.ok and noTimeReading.facts.len == 0 and
			noTimeReading.error == "the service did not answer with a list")

	refusal = declared.read(triples, uid, decl, "forecast", refused, {"place": "berlin"})
	h.check("a refused forecast is not ok", not refusal.ok and refusal.facts.len == 0)
	h.check("and carries the service's own reason",
		refusal.error ==
			"the service refused the request: Latitude must be in range of -90 to 90°. Given: 999.0.")

	// ── The request half ────────────────────────────────────────────────

	spec = decl.endpoints.forecast
	h.check("the map names the service's own host and path",
		spec.base == "https://api.open-meteo.com" and spec.path == "/v1/forecast")
	names = []
	for paramSpec in spec.params
		names.push paramSpec.name
	end for
	h.check("and declares the coordinate pair every reading needs",
		names.indexOf("latitude") != null and names.indexOf("longitude") != null and
			names.indexOf("hourly") != null and names.indexOf("daily") != null)
	hosted = 0
	for name in decl.endpoints.indexes
		if decl.endpoints[name].hasIndex("base") and decl.endpoints[name].hasIndex("path") then
			hosted = hosted + 1
		end if
	end for
	h.check("every endpoint names its own host and path", hosted == decl.endpoints.len)

	options = {"latitude": 52.52, "longitude": 13.41,
		"hourly": ["temperature_2m", "relative_humidity_2m"], "timezone": "auto",
		"apikey": "test-key"}
	newResult = declared.fetch(stubFor(forecast), decl, "forecast", options, 10)
	h.check("the declared fetch puts every option in the url",
		newResult.url.indexOf("https://api.open-meteo.com/v1/forecast?") == 0 and
			newResult.url.indexOf("latitude=52.52") != null and
			newResult.url.indexOf("timezone=auto") != null and
			newResult.url.indexOf("temperature_2m") != null)
	h.check("and hides the key",
		newResult.url.indexOf("test-key") == null and
			newResult.url.indexOf("apikey=REDACTED") != null)

	// ── The other hosts and reply shapes ────────────────────────────────

	// The archive answers with an hourly and a daily table in one reply.
	history = {"latitude": 52.5, "longitude": 13.4,
		"hourly": {"time": ["2026-11-20T00:00", "2026-11-20T01:00"],
			"temperature_2m": [4.1, 3.9]},
		"daily": {"time": ["2026-11-20"], "temperature_2m_max": [8.2],
			"sunrise": ["2026-11-20T07:20"]}}
	historyRead = declared.read(triples, uid, decl, "historical", history,
		{"place": "berlin", "variables": {"hourly": ["temperature_2m"],
			"daily": ["temperature_2m_max", "sunrise"]}})
	h.check("the archive reads both its tables",
		historyRead.ok and historyRead.facts.len == 4)
	h.check("and a daily fact takes the date rather than an hour",
		factAbout(historyRead.facts, "has-temperature-2m-max").at == "2026-11-20")

	// A table the map has no documented list for still reads every variable it carries.
	sea = {"latitude": 56.0, "longitude": 3.0,
		"hourly": {"time": ["2026-11-24T00:00", "2026-11-24T01:00"],
			"wave_height": [1.12, 1.1]}}
	seaRead = declared.read(triples, uid, decl, "marine", sea,
		{"place": "north-sea", "variables": {"hourly": ["wave_height"]}})
	h.check("a table with no documented list reads its own variables",
		seaRead.ok and seaRead.facts.len == 2 and
			seaRead.facts[0].predicate == "has-wave-height")

	climate = {"latitude": 52.5, "longitude": 13.4,
		"daily": {"time": ["2026-01-01"], "temperature_2m_max": [7.3]}}
	climateRead = declared.read(triples, uid, decl, "climate", climate,
		{"place": "berlin", "variables": {"daily": ["temperature_2m_max"]}})
	h.check("a daily-only host reads its one table",
		climateRead.ok and climateRead.facts.len == 1 and
			climateRead.facts[0].text == "has-temperature-2m-max(berlin, 7.3) @ 2026-01-01")

	// The geocoder answers with places, and the lookup with one place.
	places = {"results": [
		{"id": 1, "name": "Berlin", "latitude": 52.52, "longitude": 13.41,
			"country": "Germany", "country_code": "DE", "timezone": "Europe/Berlin"},
		{"id": 2, "name": "Berlin", "latitude": 44.0, "longitude": -71.0}]}
	geocoded = declared.read(triples, uid, decl, "geocoding", places, {"name": "Berlin"})
	h.check("the geocoder writes one place per result",
		geocoded.ok and geocoded.subjects.join(",") == "Berlin,Berlin" and
			factAbout(geocoded.facts, "has-country").object == "Germany")
	h.check("and records the name that asked",
		factAbout(geocoded.facts, "was-answer-to").object == "Berlin")

	// The geocoder's first result is the one count=1 asked for, so it has to be the place the
	// session holds: its name - which for a place asked about by its city is the city's - and
	// its country are the reply's own words for it.
	heldPlace = [triples.SpoTriple.make("place-1", "has-city", "Berlin"),
		triples.SpoTriple.make("place-1", "has-country", "Germany")]
	h.check("a geocoder result whose name and country are the place's own is read",
		declared.read(triples, uid, decl, "geocoding", places, {"name": "Berlin"},
			heldPlace).ok == 1)
	namesakePlace = {"results": [{"id": 9, "name": "Springfield", "latitude": 39.7984,
		"longitude": -89.6440, "country": "Germany"}]}
	namesakeReading = declared.read(triples, uid, decl, "geocoding", namesakePlace,
		{"name": "Berlin"}, heldPlace)
	h.check("a first result that is another name is refused, naming both",
		namesakeReading.ok == 0 and namesakeReading.error ==
			"the first result is not the place asked about: its name is Springfield, not Berlin")
	h.check("and another country is refused by its own name",
		declared.read(triples, uid, decl, "geocoding", {"results": [{"id": 10,
			"name": "Berlin", "latitude": 52.5, "longitude": 13.4, "country": "Canada"}]},
			{"name": "Berlin"}, heldPlace).error ==
			"the first result is not the place asked about: its country is Canada, not Germany")
	h.check("while a place the session holds neither name nor country for is read as it comes",
		declared.read(triples, uid, decl, "geocoding", namesakePlace, {"name": "Springfield"},
			[]).ok == 1)

	// The geocoder names a place its own way, and a city typed short is the same place: a result
	// named "New York" confirms a place whose city the session typed "New York City".
	cityShort = {"results": [{"id": 11, "name": "New York", "latitude": 40.7143,
		"longitude": -74.0060, "country": "United States"}]}
	h.check("a result named shorter than the city asked about is the same place",
		declared.read(triples, uid, decl, "geocoding", cityShort, {"name": "New York City"},
			[triples.SpoTriple.make("place-1", "has-city", "New York City")]).ok == 1)
	h.check("while a result named another town is still another town",
		declared.read(triples, uid, decl, "geocoding", {"results": [{"id": 12,
			"name": "Newark", "latitude": 40.7357, "longitude": -74.1724,
			"country": "United States"}]}, {"name": "New York City"},
			[triples.SpoTriple.make("place-1", "has-city", "New York City")]).ok == 0)

	looked = declared.read(triples, uid, decl, "geocoding-lookup", places.results[0], {"id": 1})
	h.check("the lookup reads the one place it answers with",
		looked.ok and looked.facts.len == 6 and looked.subject == "Berlin")

	heights = {"elevation": [38.0]}
	elevated = declared.read(triples, uid, decl, "elevation", heights, {"place": "berlin"})
	h.check("elevation reads its heights as values, not objects",
		elevated.ok and elevated.facts.len == 1 and
			elevated.facts[0].text == "has-elevation(berlin, 38)")

	h.check("each endpoint names its own host",
		decl.endpoints.marine.base == "https://marine-api.open-meteo.com" and
			decl.endpoints.geocoding.base == "https://geocoding-api.open-meteo.com")

	refusedSea = declared.read(triples, uid, decl, "marine", refused, {"place": "north-sea"})
	h.check("a refusal on another host is the service's own reason",
		not refusedSea.ok and refusedSea.error.indexOf("Latitude must be in range") != null)
end function
