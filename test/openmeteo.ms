// Cases for src/spike/openmeteo_map.ms, Open-Meteo's forecast endpoint as the writer reads it:
// one canned forecast written as docs/api/open-meteo.md's vocabulary with the hour and the
// probability on each fact, the other shapes a reply can answer with, and the request half
// beside openmeteo.fetch's own.
//
// No request leaves the program: a client stand-in answers get with the JSON below, and the
// expected lines are the reference page's vocabulary with the two annotations the map adds -
// '@' the hour a reading covers, and '~' the service's chance of precipitation.

run = function(declared, openmeteoMap, apiClient, meteo, triples, uid, schemaLoader, h)
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
	h.check("and writes the fourteen lines the page names",
		reading.facts.len == 14 and linesOf(reading.facts) == expected)
	h.check("the subject is the place the caller named, once per reading",
		reading.subject == "berlin" and reading.subjects.join(",") == "berlin,berlin,berlin")
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

	spec = meteo.specFor("forecast")
	h.check("the map names the service's own host and path",
		decl.base == "https://" + spec.host and decl.endpoints.forecast.path == spec.path)
	missing = []
	for paramSpec in decl.endpoints.forecast.params
		found = false
		for known in spec.params
			if known.name == paramSpec.name then found = true
		end for
		if not found then missing.push paramSpec.name
	end for
	h.check("and every parameter it declares is one the service's table has", missing.len == 0)

	options = {"latitude": 52.52, "longitude": 13.41,
		"hourly": ["temperature_2m", "relative_humidity_2m"], "timezone": "auto",
		"apikey": "test-key"}
	oldResult = meteo.fetch(stubFor(forecast), "forecast", options)
	newResult = declared.fetch(stubFor(forecast), decl, "forecast", options, 10)
	h.check("the declared fetch builds the url openmeteo.fetch builds",
		newResult.url == oldResult.url)
	h.check("and hides the key",
		newResult.url.indexOf("test-key") == null and
			newResult.url.indexOf("apikey=REDACTED") != null)
end function
