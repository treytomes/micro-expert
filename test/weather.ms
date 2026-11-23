// Cases for the Open-Meteo reply classes: one Series per table a forecast reply holds, one
// Place per geocoder result, and the reply class each endpoint's answer comes back as.
//
// The JSON here is hand-written from docs/api/open-meteo.md rather than fetched, so a failure
// says what a class made of a field, and the suite needs no key and no network.

run = function(om, h)
	// One forecast reply, trimmed to the fields these cases read.
	berlin = {
		"latitude": 52.512604,
		"longitude": 13.419517,
		"generationtime_ms": 0.0424,
		"utc_offset_seconds": 0,
		"timezone": "GMT",
		"timezone_abbreviation": "GMT",
		"elevation": 38.0,
		"current_units": {"time": "iso8601", "interval": "seconds", "temperature_2m": "°C"},
		"current": {"time": "2026-11-22T05:30", "interval": 900, "temperature_2m": 0.9},
		"hourly_units": {"time": "iso8601", "temperature_2m": "°C", "relative_humidity_2m": "%"},
		"hourly": {"time": ["2026-11-22T00:00", "2026-11-22T01:00", "2026-11-22T02:00"],
			"temperature_2m": [4.1, 3.8, null], "relative_humidity_2m": [81, null, 84]},
	}

	quote = char(34)

	// ── One place's reply ───────────────────────────────────────────────────

	weather = om.reply("forecast", berlin, {"latitude": 52.52, "longitude": 13.41})
	h.check("a forecast reply is a WeatherReply", weather isa om.WeatherReply)
	h.check("its grid point is the one the answer came from",
		weather.coordinates == "52.512604, 13.419517")
	h.check("its elevation is in metres", weather.elevation == "38 m")
	h.check("and its time zone comes with it", weather.timezone == "GMT")
	h.check("it holds one table per series, in the order the reply wrote them",
		weather.series.len == 2 and weather.series[0].name == "current" and weather.series[1].name == "hourly")
	h.check("each table is a Series", weather.series[1] isa om.Series)

	// ── One table of it ─────────────────────────────────────────────────────

	hourly = weather.series[1]
	current = weather.series[0]
	h.check("a table's rows are its instants", hourly.rows == 3)
	h.check("and a single reading is one row", current.rows == 1)
	h.check("its variables are the fields it holds a list for",
		hourly.variables.join(",") == "temperature_2m,relative_humidity_2m")
	h.check("the seconds a current reading covers are not a variable",
		current.variables.join(",") == "temperature_2m")
	h.check("a value is read by variable and row", hourly.reading("temperature_2m", 1) == 3.8)
	h.check("a gap in the series reads as nothing", hourly.reading("temperature_2m", 2) == null)
	h.check("and so does a row past its end", hourly.reading("temperature_2m", 9) == null)
	h.check("an instant is the time at that row", hourly.instant(1) == "2026-11-22T01:00")
	h.check("a current reading is instanted by its own time",
		current.instant(0) == "2026-11-22T05:30")
	h.check("and its value needs no index to find it",
		current.reading("temperature_2m", 0) == 0.9)
	h.check("a unit comes from the map under the table",
		hourly.unit("temperature_2m") == "°C" and hourly.unit("relative_humidity_2m") == "%")
	h.check("a field the units do not name has none", hourly.unit("nope") == "")

	// ── Several places at once ──────────────────────────────────────────────

	two = om.reply("forecast", [berlin, berlin], {})
	h.check("a list of places is a MultiReply", two isa om.MultiReply)
	h.check("holding one reply per place, in the order asked for", two.replies.len == 2)
	h.check("each of them a WeatherReply", two.replies[0] isa om.WeatherReply)

	// ── The geocoder ────────────────────────────────────────────────────────

	// A search entry, trimmed to the fields these cases read.
	entry = {"id": 2950159, "name": "Berlin", "latitude": 52.52437, "longitude": 13.41053,
		"elevation": 74.0, "feature_code": "PPLC", "country": "Germany", "timezone": "Europe/Berlin"}
	found = om.reply("geocoding", {"results": [entry], "generationtime_ms": 0.2186}, {"name": "Berlin"})
	h.check("a search reply is a GeocodingReply", found isa om.GeocodingReply)
	h.check("with one Place per result", found.count == 1 and found.places[0] isa om.Place)
	h.check("a place is known by its name and country", found.places[0].label == "Berlin, Germany")
	h.check("its coordinates are the latitude and longitude the geocoder gave",
		found.places[0].coordinates == "52.52437, 13.41053")
	h.check("and the numbers themselves are there to send as parameters",
		found.places[0].latitude == 52.52437 and found.places[0].longitude == 13.41053)
	h.check("the heading counts the places and names the query", found.heading == "1 place for " + quote + "Berlin" + quote + ":")
	h.check("a place without a country is named by itself",
		om.reply("geocoding", {"results": [{"name": "Atlantis"}]}, {}).places[0].label == "Atlantis")
	h.check("a result with no name still says something",
		om.reply("geocoding", {"results": [{}]}, {}).places[0].label == "(no name)")

	missed = om.reply("geocoding", {"generationtime_ms": 0.11229515}, {"name": "Nowhere"})
	h.check("a name that matched nothing is empty", missed.isEmpty)
	h.check("and the message says what was searched for",
		missed.emptyMessage == "No place named " + quote + "Nowhere" + quote + ".")

	lookup = om.reply("geocoding-lookup", entry, {})
	h.check("a lookup is a GeocodingReply holding the one place", lookup isa om.GeocodingReply and lookup.count == 1)
	h.check("with no query, so its heading names none", lookup.heading == "1 place:")

	// ── The elevation endpoint ──────────────────────────────────────────────

	heights = om.reply("elevation", {"elevation": [38.0, 46.0]}, {})
	h.check("elevation is an ElevationReply", heights isa om.ElevationReply)
	h.check("holding one height per coordinate pair",
		heights.heights.len == 2 and heights.heights[1] == 46.0)

	// ── Refusals and other shapes ───────────────────────────────────────────

	refused = om.reply("forecast", {"reason": "Latitude must be in range of -90 to 90°. Given: 999.0.", "error": true}, {})
	h.check("a refused request is not ok", not refused.ok)
	h.check("and carries the service's own reason",
		refused.error == "The API refused the request: Latitude must be in range of -90 to 90°. Given: 999.0.")
	h.check("a reply that is neither an object nor a list is refused",
		om.reply("forecast", "not json", {}).error == "The API returned an unexpected reply.")
	h.check("nothing to read is no reply at all", om.reply("forecast", null, {}) == null)
	h.check("one place an endpoint did not document is not a place",
		om.reply("geocoding-lookup", {"generationtime_ms": 0.1}, {}).isEmpty)
end function
