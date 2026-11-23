// Cases for the parameter engine: what a table accepts, what it refuses, what it passes
// through untouched, and the two helpers the programs lean on.
//
// The table is one of each type rather than a service's, so a failure names the rule that
// broke rather than an endpoint that happens to declare it that way.

run = function(client, h)
	spec = {"params": [
		{"name": "lat", "type": "number", "min": -90, "max": 90, "required": 1},
		{"name": "lon", "type": "number", "min": -180, "max": 180, "required": 1},
		{"name": "limit", "type": "int", "min": 0, "max": 40},
		{"name": "format", "type": "enum", "values": ["json", "xml"]},
		{"name": "addressdetails", "type": "bool"},
		{"name": "polygon_geojson", "type": "bool"},
		{"name": "hourly", "type": "csv"},
		{"name": "latitude", "type": "coordinates", "min": -90, "max": 90},
		{"name": "tilt", "type": "number", "allowNan": 1},
		{"name": "start_date", "type": "date"},
		{"name": "start_hour", "type": "datetime"},
	]}

	checked = function(options)
		"Validates against the table above, the way a fetch does."
		return client.validate(spec, options)
	end function

	problem = function(options)
		"The problems joined, for a case that only cares what was said."
		return checked(options).problems.join("; ")
	end function

	together = function(extra)
		"A complete coordinate pair plus whatever the case adds."
		options = {"lat": 52.52, "lon": 13.41}
		for kv in extra
			options[kv.key] = kv.value
		end for
		return options
	end function

	// ── Required fields ──────────────────────────────────────────────────────

	h.check("a required field that is absent is named",
		problem({"lat": 52.52}).indexOf("lon is required") != null)
	h.check("a complete pair is valid", checked(together({})).ok)
	h.check("a required field given as null is still absent",
		problem({"lat": 52.52, "lon": null}).indexOf("lon is required") != null)

	// ── Ranges and types ─────────────────────────────────────────────────────

	h.check("a value past the maximum is refused", problem(together({"lat": 91})) == "lat must be at most 90")
	h.check("a value before the minimum is refused", problem(together({"lon": -181})) == "lon must be at least -180")
	h.check("a whole number is enforced", problem(together({"limit": 2.5})) == "limit must be a whole number")
	h.check("a non-number is refused where a number belongs", problem(together({"lat": "abc"})) == "lat must be a number")
	h.check("a value outside an enum is refused", problem(together({"format": "yaml"})) == "format must be one of json, xml")
	h.check("every refusal is reported, not only the first",
		checked(together({"limit": 99, "format": "yaml"})).problems.len == 2)

	// ── Booleans ─────────────────────────────────────────────────────────────

	h.check("true is spelled several ways", checked(together({"addressdetails": "yes"})).params.addressdetails == "true")
	h.check("zero is false", checked(together({"addressdetails": 0})).params.addressdetails == "false")
	h.check("a word that is neither is refused",
		problem(together({"addressdetails": "maybe"})) == "addressdetails must be true or false")

	// ── Lists ────────────────────────────────────────────────────────────────

	h.check("a comma-separated value is kept as given",
		checked(together({"hourly": "temperature_2m,rain"})).params.hourly == "temperature_2m,rain")
	h.check("a repeated option is joined the same way",
		checked(together({"hourly": ["temperature_2m", "rain"]})).params.hourly == "temperature_2m,rain")
	h.check("an empty list is refused rather than sent",
		problem(together({"hourly": []})) == "hourly must not be empty")

	h.check("several coordinates in one value are read",
		checked(together({"latitude": "52.52,13.41"})).params.latitude == "52.52,13.41")
	h.check("a list of coordinates is read the same way",
		checked(together({"latitude": ["52.52", "13.41"]})).params.latitude == "52.52,13.41")
	h.check("a coordinate out of range is refused", problem(together({"latitude": "91"})) == "latitude must be at most 90")
	h.check("a coordinate that is not a number is refused",
		problem(together({"latitude": "north"})).indexOf("must be a number") != null)

	// ── Values with a spelling of their own ──────────────────────────────────

	h.check("nan is kept where the table allows it", checked(together({"tilt": "nan"})).params.tilt == "nan")
	h.check("a date is read", checked(together({"start_date": "2026-11-21"})).params.start_date == "2026-11-21")
	h.check("a date of another shape is refused",
		problem(together({"start_date": "21/11/2026"})).indexOf("must be a date") != null)
	h.check("an hour is read", checked(together({"start_hour": "2026-11-21T09:00"})).params.start_hour == "2026-11-21T09:00")
	h.check("a space works where the T goes", checked(together({"start_hour": "2026-11-21 09:00"})).ok)

	// ── What the engine leaves alone ─────────────────────────────────────────

	h.check("a name the table does not list is passed through",
		checked(together({"language": "de"})).params.language == "de")
	h.check("a key is not sent as a parameter",
		not checked(together({"apikey": "secret"})).params.hasIndex("apikey"))
	h.check("nor is the commercial switch", not checked(together({"customer": 1})).params.hasIndex("customer"))

	// ── Names ────────────────────────────────────────────────────────────────

	h.check("a name matches without dashes, underscores or case",
		client.matchParam(spec, "Polygon-GeoJSON") != null)
	h.check("an unknown name matches nothing", client.matchParam(spec, "nope") == null)

	first = {"params": [{"name": "a", "type": "text"}, {"name": "b", "type": "text"}]}
	second = {"params": [{"name": "B", "type": "text"}, {"name": "c", "type": "text"}]}
	merged = client.unionSpec([first, second])
	h.check("a union lists each name once", merged.params.len == 3)
	h.check("keeping the spelling it met first", merged.params[1].name == "b")

	// ── The two helpers the programs use ─────────────────────────────────────

	values = {"json": 0, "tag": [], "q": null, "limit": 3}
	given = client.apiOptions(values, ["json"])
	h.check("a program's switch is not a parameter", not given.hasIndex("json"))
	h.check("an empty list is not a value", not given.hasIndex("tag"))
	h.check("an absent string is not a value", not given.hasIndex("q"))
	h.check("what was given comes through", given.limit == 3)

	h.check("a key is read under any spelling",
		client.keyIn({"apiKey": "a"}) == "a" and client.keyIn({"api_key": "b"}) == "b" and client.keyIn({"apikey": "c"}) == "c")
	h.check("no key at all is null", client.keyIn({}) == null)
end function
