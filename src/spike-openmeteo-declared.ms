// spike-openmeteo-declared.ms — the declared writer against Open-Meteo's canned forecast reply.
//
//   ./3rd-party/miniscript-linux/miniscript src/spike-openmeteo-declared.ms
//
// The first slice of the Open-Meteo map: the hourly series, where one index is one reading and
// the variables are parallel lists. The expected lines are the vocabulary in
// docs/api/open-meteo.md with the two annotations the map adds: '@' the hour the reading covers,
// and '~' the service's chance of precipitation. The place is the caller's name for the point,
// since a forecast reply never carries one.
//
// has-instant is not mapped yet: it needs timeformat=unixtime, which turns the time list into
// numbers rather than the instants a subject is built from.

import "api/client"
import "api/openmeteo"
import "triples"
import "uid"
import "spike/declared"
import "spike/openmeteo_map"

api = globals["api/client"]
meteo = globals["api/openmeteo"]
triples = globals["triples"]
uid = globals["uid"]
declared = globals["spike/declared"]
decl = globals["spike/openmeteo_map"].build()


// ── The reply, as Open-Meteo answers the forecast endpoint ──────────────────

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

// Three hours, five variables, and the missing temperature at the third. Each reading covers
// the hour that starts at its instant; the reply's last hour has no next instant, so it keeps
// the moment alone. Only the precipitation carries a confidence, from precipitation_probability.
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


// ── The client stand-in, and the printing ───────────────────────────────────

stubFor = function(json)
	"A client whose checks are the real ones and whose get answers canned JSON."
	fake = {}
	for name in api.indexes
		fake[name] = api[name]
	end for
	fake.canned = json
	fake.get = function(url, timeout=null)
		return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url, "error": null}
	end function
	return fake
end function


pad = function(text, width)
	"text, then spaces to width; the text itself when it is already that wide."
	padding = width - text.len
	if padding <= 0 then return text
	return text + " " * padding
end function


lineOf = function(fact)
	"One fact as a facts file writes it: its own line, annotations and all."
	return fact.text
end function


linesOf = function(facts)
	"One line per fact, as a .kb file would write it."
	lines = []
	for fact in facts
		lines.push lineOf(fact)
	end for
	return lines
end function


failures = 0


// ── The hourly series, beside the documented vocabulary ─────────────────────

reading = declared.read(triples, uid, decl, "forecast", forecast, {"place": "berlin"})
actual = linesOf(reading.facts)

width = 0
for line in expected
	if line.len > width then width = line.len
end for
print ""
print "== three hours, five variables"
print "   expected (docs/api/open-meteo.md + the hour and the probability): " + str(expected.len) +
	"    declared (spike/openmeteo_map): " + str(actual.len)
rows = expected.len
if actual.len > rows then rows = actual.len
for i in range(0, rows - 1)
	left = ""
	right = ""
	if i < expected.len then left = expected[i]
	if i < actual.len then right = actual[i]
	print "   " + pad(left, width + 2) + right
end for
for note in reading.skipped
	print "   left out: " + note
end for

if not reading.ok then
	print "   DIFF: the reading is not ok: " + reading.error
	failures = failures + 1
end if
if expected != actual then
	print "   DIFF: the facts are not the documented ones"
	failures = failures + 1
end if
if reading.subjects.len != 3 then
	print "   DIFF: expected three readings' subjects, got " + str(reading.subjects.len)
	failures = failures + 1
end if

// The annotation's two forms: an hour covered by a span, and the last hour's bare moment.
spanned = 0
moments = 0
for fact in reading.facts
	if fact.at == null then
		print "   DIFF: " + fact.text + " carries no '@'"
		failures = failures + 1
	else if fact.at[:1] == "[" then
		spanned = spanned + 1
	else
		moments = moments + 1
	end if
end for
print "   hours as spans: " + str(spanned) + "    last hour as a moment: " + str(moments)
if spanned != 10 or moments != 4 then
	print "   DIFF: expected ten spans and the four facts of the last hour as moments"
	failures = failures + 1
end if
if reading.facts[0].at != "[2026-11-22 00:00, 2026-11-22 01:00]" then
	print "   DIFF: the first fact does not cover its hour: " + str(reading.facts[0].at)
	failures = failures + 1
end if

// A confidence only where the reply gave a probability, and only as far as the service is sure.
sure = 0
unsure = 0
for fact in reading.facts
	if fact.predicate == "has-precipitation" then
		unsure = unsure + 1
	else if fact.confidence != 100 then
		sure = sure + 1
	end if
end for
if unsure != 3 or sure != 0 then
	print "   DIFF: expected three precipitation facts with a confidence and no others"
	failures = failures + 1
end if
if reading.facts[2].confidence != 40 or reading.facts[7].confidence != 35 then
	print "   DIFF: the confidence is not precipitation_probability"
	failures = failures + 1
end if

// Every annotated line is a line a facts file reads back, annotations and all.
unread = 0
for fact in reading.facts
	back = triples.SpoTriple.parse(lineOf(fact))
	if back isa error then
		unread = unread + 1
	else if back.text != fact.text or back.at != fact.at or back.confidence != fact.confidence then
		unread = unread + 1
	end if
end for
if unread > 0 then
	print "   DIFF: " + str(unread) + " annotated fact(s) do not read back"
	failures = failures + 1
end if


// ── The other shapes a forecast can answer with ─────────────────────────────

report = function(name, reading, factCount, skipCount)
	"One case's counts, and a difference when they are not what it says."
	print ""
	print "== " + name
	print "   ok " + str(reading.ok) + "    facts " + str(reading.facts.len) +
		"    subjects " + str(reading.subjects.len) + "    skipped " + str(reading.skipped.len)
	if reading.error != null then print "   error: " + reading.error
	if reading.facts.len != factCount or reading.skipped.len != skipCount then
		print "   DIFF: expected " + str(factCount) + " facts and " + str(skipCount) + " skipped"
		globals.failures = globals.failures + 1
	end if
end function

// No probability in the reply, so no '~': the fact says nothing about its confidence.
sparseReading = declared.read(triples, uid, decl, "forecast", sparse, {"place": "berlin"})
report("one variable asked for", sparseReading, 3, 12)
for fact in sparseReading.facts
	if fact.confidence != 100 then
		print "   DIFF: a reply without precipitation_probability still claimed " +
			str(fact.confidence) + "%"
		failures = failures + 1
	end if
end for

noPlace = declared.read(triples, uid, decl, "forecast", forecast, {})
report("a reply with no place named", noPlace, 0, 0)

report("a series with no time list", declared.read(triples, uid, decl, "forecast", noTime,
	{"place": "berlin"}), 0, 0)

report("a refused forecast", declared.read(triples, uid, decl, "forecast", refused,
	{"place": "berlin"}), 0, 0)


// ── The request half ────────────────────────────────────────────────────────
// The map carries the key and the redaction too, so the url matches openmeteo.fetch's.

print ""
print "== the request"
options = {"latitude": 52.52, "longitude": 13.41,
	"hourly": ["temperature_2m", "relative_humidity_2m"], "timezone": "auto",
	"apikey": "test-key"}
oldResult = meteo.fetch(stubFor(forecast), "forecast", options)
newResult = declared.fetch(stubFor(forecast), decl, "forecast", options, 10)
print "   openmeteo.fetch  " + oldResult.url
print "   declared.fetch   " + newResult.url
if oldResult.url != newResult.url then
	print "   DIFF: the urls differ"
	failures = failures + 1
end if
if newResult.url.indexOf("test-key") != null then
	print "   DIFF: the key is still in the url the result keeps"
	failures = failures + 1
end if


print ""
if failures == 0 then
	print "RESULT: 0 differences."
else
	print "RESULT: " + str(failures) + " difference(s)."
	exit 1
end if