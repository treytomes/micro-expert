// Cases for document.ms: the documents the design page shows, resolved against the maps the program
// reads; every service map written out and read back; the three rules the two document services rely
// on, pinned on their own; and the refusals a reader owes a document.

block = function(page, marker, opening)
	"The fenced block after a marker: from just past its opening fence to its closing one."
	at = page.indexOf(marker)
	if at == null then return null
	start = page.indexOf(opening, at)
	if start == null then return null
	start = start + opening.len
	return page[start:page.indexOf("```", start)]
end function

differences = function(mine, theirs, path)
	"Every place two declarations disagree, as paths to them."
	found = []
	if (mine isa map) != (theirs isa map) or (mine isa list) != (theirs isa list) then
		found.push path + ": shape differs"
		return found
	end if
	if mine isa map then
		for key in theirs.indexes
			if not mine.hasIndex(key) then
				found.push path + "." + key + ": missing"
				continue
			end if
			found = found + differences(mine[key], theirs[key], path + "." + key)
		end for
		for key in mine.indexes
			if not theirs.hasIndex(key) then found.push path + "." + key + ": unexpected"
		end for
		return found
	end if
	if mine isa list then
		if mine.len != theirs.len then
			found.push path + ": " + mine.len + " entries, expected " + theirs.len
			return found
		end if
		for i in mine.indexes
			found = found + differences(mine[i], theirs[i], path + "[" + i + "]")
		end for
		return found
	end if
	if mine != theirs then found.push path + ": [" + mine + "] where expected [" + theirs + "]"
	return found
end function

agrees = function(h, name, mine, theirs)
	"One check: two declarations are the same one."
	found = differences(mine, theirs, "declaration")
	h.check(name, found.len == 0)
	if found.len > 0 then
		print "    " + found.len + " difference(s), the first: " + found[0]
	end if
end function

run = function(document, geocode, openmeteo, ipwhois, h)
	page = file.loadRaw("docs/provider-documents.md").utf8

	reason = function(document, text)
		"The reason this document is refused, or nothing when it is not refused at all."
		decl = document.read(text)
		if decl isa error then return decl.message
		decl = document.resolve(decl)
		if decl isa error then return decl.message
		return ""
	end function

	// ── geocode.maps.co, as the design page writes it ───────────────────────
	geo = document.resolve(document.read(block(page, "## geocode.maps.co, end to end",
		"```miniscript")))
	h.check("the page's geocode document reads as a declaration", geo isa map)
	if geocode isa map then
		agrees(h, "the geocode document resolves to the map the loader reads", geo, geocode)
	end if

	// ── The three rules the two documents rely on, pinned on their own ──────
	// A reply part resolves with its own kind: `once: @zone` wants a group holding `once`, and
	// `series: {@hours; @days}` splices one series per entry instead of passing the reference
	// through. Neither was noticed until Open-Meteo needed them, and a reader that flattens every
	// reply part as `facts` must fail here rather than in the weather document.
	pinned = document.read("groups: {zone: {once: {{has-timezone; ?place; $.timezone}}}; " +
		"hours: {series: {path: $.hourly; kind: hour}}; " +
		"days: {series: {path: $.daily; kind: day}}; " +
		"other: {facts: {{has-timezone; ?place; $.timezone}}}}; " +
		"endpoints: {e: {path: /x; reply: {once: @zone; series: {@hours; @days}; " +
			"refuse: {when: error; is: 1; message: reason}}}}")
	reply = null
	if pinned isa map then reply = document.resolve(pinned)
	if reply isa map then reply = reply.endpoints.e.reply
	h.check("once: @group takes the group's own once", reply isa map and
		reply.once == [["has-timezone", "?place", "$.timezone"]])
	h.check("series: {@group} splices a series per entry", reply isa map and
		reply.series isa list and reply.series.len == 2 and
		reply.series[0].path == "$.hourly" and reply.series[1].kind == "day")
	// A refusal's boolean is spelled 1: a document's bare true reads back as the text "true",
	// while 1 is what true is in MiniScript, so the value the reply checks stays a boolean.
	h.check("a refusal says is: 1 and it is true", reply isa map and
		reply.refuse.is == true and reply.refuse.is isa number)
	// The kind rule from both sides: a group holding something else is refused, not flattened.
	h.check("refuses a facts group where a once belongs",
		reason(document, "groups: {other: {facts: {{has-timezone; ?place; $.timezone}}}}; " +
			"endpoints: {e: {path: /x; reply: {once: @other}}}") ==
			"e: other holds facts, and a once was expected")
	h.check("refuses a once group where a series belongs",
		reason(document, "groups: {zone: {once: {{has-timezone; ?place; $.timezone}}}}; " +
			"endpoints: {e: {path: /x; reply: {series: {@zone}}}") ==
			"e: zone holds once, and a series was expected")

	// ── Open-Meteo: the two blocks a loop and a closure write, and the reply
	//    group used with changes. The page's excerpt leaves out the plain
	//    records, so each is resolved on its own against the same endpoint.
	weather = document.read(block(page, "## What Open-Meteo needs on top", "```miniscript"))
	groups = {}
	if weather isa map then groups = weather.groups
	h.check("the page's Open-Meteo excerpt has groups", groups isa map)

	// The map itself, null when the loader refused it: the comparisons below then say nothing
	// rather than read a field an error does not have.
	forecast = null
	if openmeteo isa map then forecast = openmeteo.endpoints.forecast

	// The five provides entries the loop writes, from five argument-bearing references.
	provides = document.resolve({"groups": groups, "endpoints": {"forecast": {
		"path": "/v1/forecast", "provides": [
			"@hourlyProvides(temperature_2m, has-temperature-2m)",
			"@hourlyProvides(relative_humidity_2m, has-relative-humidity-2m)",
			"@hourlyProvides(precipitation, has-precipitation)",
			"@hourlyProvides(wind_speed_10m, has-wind-speed-10m)",
			"@hourlyProvides(weather_code, has-weather-code)"]}}})
	h.check("five @hourlyProvides calls resolve", provides isa map)
	if provides isa map and forecast != null then
		agrees(h, "the five @hourlyProvides calls resolve to the loop's entries",
			provides.endpoints.forecast.provides, forecast.provides)
	end if

	// The bound the closure writes into its parameter and its doc.
	days = document.resolve({"groups": groups, "endpoints": {"forecast": {
		"path": "/v1/forecast", "params": ["@forecastDays(16)"]}}})
	built = null
	if forecast != null then
		for param in forecast.params
			if param.name == "forecast_days" then built = param
		end for
	end if
	h.check("@forecastDays(16) resolves", days isa map)
	if days isa map and forecast != null then
		agrees(h, "@forecastDays(16) resolves to the parameter the closure writes",
			days.endpoints.forecast.params[0], built)
	end if

	// A reply group used with changes: the clock's reply says less than the forecast's.
	clock = document.resolve({"groups": groups, "endpoints": {"clock": {
		"path": "/v1/forecast", "reply": {"use": "@weatherReply", "series": [],
			"once": [["has-timezone", "?place", "$.timezone"],
				["has-utc-offset", "?place", "$.utc_offset_seconds as number"]]}}}})
	h.check("clock.reply resolves", clock isa map)
	if clock isa map and openmeteo isa map then
		agrees(h, "a reply group used with changes resolves to the clock's reply",
			clock.endpoints.clock.reply, openmeteo.endpoints.clock.reply)
	end if

	// Said once about the place, after the endpoint was made.
	once = document.resolve({"groups": groups, "endpoints": {"forecast": {
		"path": "/v1/forecast", "reply": {"once": [
			["has-timezone", "?place", "$.timezone"],
			["has-utc-offset", "?place", "$.utc_offset_seconds as number"]]}}}})
	h.check("forecast.reply.once resolves", once isa map)
	if once isa map and forecast != null then
		agrees(h, "a reply's once resolves to the two lines the map assigns",
			once.endpoints.forecast.reply.once, forecast.reply.once)
	end if

	// ── Every service map out to a document and back ────────────────────────
	// The property the next phase needs: a declaration is completely a file. Nothing here
	// groups or references anything - text() writes the map expanded - so what is proved is
	// that GRFON can carry every value these three maps hold, and that resolve() rebuilds the
	// list shapes a document cannot spell.
	for pair in [["ipwho.is", ipwhois], ["geocode.maps.co", geocode],
		["open-meteo", openmeteo]]
		declaration = pair[1]
		// A refused map is already named by the loader check above, so it is not written here.
		if declaration isa map then
			written = document.text(declaration)
			again = document.read(written)
			h.check(pair[0] + ": a map written as a document reads back", again isa map)
			if again isa map then
				agrees(h, pair[0] + ": written, read back and resolved, the declaration is build()'s",
					document.resolve(again), declaration)
			end if
		end if
	end for

	// ── The schema is the reader's, and a document cannot say it ────────────
	// One part that is a list, arriving as a lone value.
	lone = document.resolve(document.read(
		"endpoints: {a: {path: /x; redact: {api_key}}}"))
	wrapped = false
	if lone isa map then wrapped = lone.endpoints.a.redact == ["api_key"]
	h.check("a list-shaped part takes a lone value: redact", wrapped)

	// ── What a reader refuses ──────────────────────────────────────────────
	h.check("refuses a group it does not define",
		reason(document, "endpoints: {a: {path: /x; params: {@nope}}}") ==
			"a: the document uses a group it does not define: nope")
	h.check("refuses a fragment of the wrong kind",
		reason(document, "groups: {details: {params: {{name: x}}}}; " +
			"endpoints: {a: {path: /x; reply: @details}}") ==
			"a: details holds params, and a reply was expected")
	h.check("refuses a group that uses itself",
		reason(document, "groups: {loop: {params: {@loop}}}; endpoints: {a: {path: /x}}") ==
			"the group loop uses itself")
	h.check("refuses a reference that gives no argument",
		reason(document, "groups: {days: {takes: {most}; params: {{name: d; max: <most>}}}}; " +
			"endpoints: {a: {path: /x; params: {@days}}}") ==
			"a: days takes 1 argument, and was given 0")
	h.check("refuses an argument list longer than takes",
		reason(document, "groups: {days: {takes: {most}; params: {{name: d; max: <most>}}}}; " +
			"endpoints: {a: {path: /x; params: {@days(16, 35)}}}") ==
			"a: days takes 1 argument, and was given 2")
	h.check("refuses a placeholder no argument fills",
		reason(document, "groups: {days: {takes: {most}; params: {{name: d; doc: 0 to <other>.}}}}; " +
			"endpoints: {a: {path: /x; params: {@days(16)}}}") ==
			"a: the group days names <other> and no argument fills it")
	h.check("refuses a group with arguments that uses another group",
		reason(document, "groups: {other: {params: {{name: x}}}; " +
			"days: {takes: {most}; params: {@other}}}; " +
			"endpoints: {a: {path: /x; params: {@days(16)}}}") ==
			"a: a group with arguments cannot use another group: days")
	h.check("refuses a key the level does not have",
		reason(document, "endpoints: {a: {path: /x; methd: GET}}") == "a: an endpoint has no methd")

	// ── Writing a document no shortcut would carry ──────────────────────────
	// Every character a reader would otherwise reinterpret: the colon, the semicolon, the
	// percent, two slashes, a leading @, a leading space, and a url that must stay readable.
	awkward = {"service": "x", "base": "https://x/y", "endpoints": {"e": {"path": "/p",
		"params": [{"name": "q", "doc": "@home; 50% // note: a:b leading space"}]}}}
	h.check("text() keeps a value that only escaping can carry",
		document.read(document.text(awkward)) == awkward)
end function
