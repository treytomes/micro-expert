// spike-geocode-declared.ms — the declared writer against geocode.maps.co's canned Eiffel reply.
//
//   ./3rd-party/miniscript-linux/miniscript src/spike-geocode-declared.ms
//
// No request leaves the program. The expected facts are the vocabulary in
// docs/api/geocode-maps-co.md, written out; the declared column is what
// src/spike/geocode_map.ms makes of the same JSON. The class column is what
// src/api/geocode.ms reads from it, compared on the two members a Place answers - its label
// and its coordinates - since geocode has no fact writer to compare against.
//
// The runner sits in src/ for the same reason the ipwho.is one does: triples.ms imports
// temporal, and an import resolves against the entry script's folder.

import "api/client"
import "api/geocode"
import "triples"
import "uid"
import "spike/declared"
import "spike/geocode_map"

api = globals["api/client"]
geo = globals["api/geocode"]
triples = globals["triples"]
uid = globals["uid"]
declared = globals["spike/declared"]
decl = globals["spike/geocode_map"].build()


// ── The reply, as geocode.maps.co answers a search ──────────────────────────

eiffel = {
	"place_id": 119141919,
	"licence": "Data © OpenStreetMap contributors, ODbL 1.0.",
	"osm_type": "way",
	"osm_id": 5013364,
	"boundingbox": ["48.8574", "48.8590", "2.2933", "2.2956"],
	"lat": "48.8582599",
	"lon": "2.2945006",
	"display_name": "Tour Eiffel, 5, Avenue Anatole France, 75007, France",
	"class": "man_made",
	"type": "tower",
	"place_rank": 30,
	"importance": 0.6199831475570641,
	"addresstype": "man_made",
	"name": "Tour Eiffel",
	"localname": "Tour Eiffel",
	"address": {"house_number": "5", "road": "Avenue Anatole France", "city": "Paris",
		"country": "France", "country_code": "fr", "postcode": "75007"},
	"extratags": {"wikidata": "Q243", "wikipedia": "fr:Tour Eiffel", "fee": "10-25€"},
	"namedetails": {"name:fr": "Tour Eiffel"},
}

berlin = {
	"place_id": 240109189,
	"osm_type": "relation",
	"osm_id": 62422,
	"boundingbox": ["52.3382", "52.6755", "13.0883", "13.7611"],
	"lat": "52.5170365",
	"lon": "13.3888599",
	"display_name": "Berlin, Deutschland",
	"class": "boundary",
	"type": "administrative",
	"place_rank": 4,
	"importance": 0.8268,
	"addresstype": "city",
	"name": "Berlin",
	"localname": "Berlin",
	"address": {"house_number": "1", "road": "Unter den Linden", "city": "Berlin",
		"country": "Deutschland", "country_code": "de", "postcode": "10117"},
	"extratags": {"wikidata": "Q64", "wikipedia": "de:Berlin", "fee": "no"},
	"namedetails": {"name:fr": "Berlin"},
}

missingId = {
	"place_id": 1, "osm_type": "way", "lat": "48.8582599", "lon": "2.2945006",
	"name": "Nowhere", "display_name": "Nowhere",
}

badLatitude = {
	"place_id": 119141919, "osm_type": "way", "osm_id": 5013364,
	"boundingbox": ["48.8574", "48.8590", "2.2933", "2.2956"],
	"lat": "north", "lon": "2.2945006",
	"display_name": "Tour Eiffel", "class": "man_made", "type": "tower", "place_rank": 30,
	"importance": 0.6199831475570641, "name": "Tour Eiffel",
	"address": {"house_number": "5", "road": "Avenue Anatole France", "city": "Paris",
		"country": "France", "country_code": "fr"},
	"extratags": {"wikidata": "Q243", "wikipedia": "fr:Tour Eiffel", "fee": "10-25€"},
	"namedetails": {"name:fr": "Tour Eiffel"},
}

refused = {"error": {"code": 400, "message": "Parameter 'lon' missing."}}

// One result, as docs/api/geocode-maps-co.md writes it. The numbers are the text the reply
// sent, read as numbers and printed by the engine, which keeps six decimals.
expected = [
	"has-name(way/5013364, Tour Eiffel)",
	"has-name-in-fr(way/5013364, Tour Eiffel)",
	"has-latitude(way/5013364, 48.85826)",
	"has-longitude(way/5013364, 2.294501)",
	"has-south-latitude(way/5013364, 48.8574)",
	"has-north-latitude(way/5013364, 48.859)",
	"has-west-longitude(way/5013364, 2.2933)",
	"has-east-longitude(way/5013364, 2.2956)",
	"has-osm-class(way/5013364, man_made)",
	"has-osm-type(way/5013364, tower)",
	"has-place-rank(way/5013364, 30)",
	"has-importance(way/5013364, 0.619983)",
	"has-place-id(way/5013364, 119141919)",
	"has-house-number(way/5013364, ""5"")",
	"has-road(way/5013364, Avenue Anatole France)",
	"has-city(way/5013364, Paris)",
	"has-country(way/5013364, France)",
	"has-country-code(way/5013364, fr)",
	"has-wikidata(way/5013364, Q243)",
	"has-wikipedia(way/5013364, fr:Tour Eiffel)",
	"has-fee(way/5013364, 10-25€)",
	"was-answer-to(way/5013364, Eiffel Tower)",
]


// ── The client stand-in, and the printing ───────────────────────────────────

stubFor = function(json)
	"A client whose checks are the real ones and whose get answers canned JSON."
	fake = {}
	for name in api.indexes
		fake[name] = api[name]
	end for
	fake.canned = json
	fake.seenTimeout = null
	fake.get = function(url, timeout=null)
		self.seenTimeout = timeout
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


linesOf = function(facts)
	"One line per fact, as a .kb file would write it."
	lines = []
	for fact in facts
		lines.push fact.text
	end for
	return lines
end function


sameLines = function(a, b)
	"Whether two lists are the same lines in the same order."
	if a.len != b.len then return false
	for i in a.indexes
		if a[i] != b[i] then return false
	end for
	return true
end function


failures = 0


// ── One result, beside the documented vocabulary ────────────────────────────

reading = declared.read(triples, uid, decl, "search", [eiffel], {"q": "Eiffel Tower"})
actual = linesOf(reading.facts)

width = 0
for line in expected
	if line.len > width then width = line.len
end for
print ""
print "== one /search result"
print "   expected (docs/api/geocode-maps-co.md): " + str(expected.len) + "    declared (spike/geocode_map): " + str(actual.len)
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
if not sameLines(expected, actual) then
	print "   DIFF: the facts are not the documented ones"
	failures = failures + 1
end if
unread = 0
for fact in reading.facts
	back = triples.SpoTriple.parse(fact.text)
	if back isa error or back.text != fact.text then unread = unread + 1
end for
if unread > 0 then
	print "   DIFF: " + str(unread) + " fact(s) do not read back"
	failures = failures + 1
end if


// ── The other shapes a search can answer with ───────────────────────────────

report = function(name, reading, factCount, subjectCount, skipCount)
	"One case's counts, and a difference when they are not what it says."
	print ""
	print "== " + name
	print "   ok " + str(reading.ok) + "    facts " + str(reading.facts.len) +
		"    subjects " + str(reading.subjects.len) + "    skipped " + str(reading.skipped.len)
	if reading.error != null then print "   error: " + reading.error
	for note in reading.skipped
		print "   left out: " + note
	end for
	if reading.facts.len != factCount or reading.subjects.len != subjectCount or
		reading.skipped.len != skipCount then
		print "   DIFF: expected " + str(factCount) + " facts, " + str(subjectCount) +
			" subjects, " + str(skipCount) + " skipped"
		globals.failures = globals.failures + 1
	end if
end function

two = declared.read(triples, uid, decl, "search", [eiffel, berlin], {"q": "Paris"})
report("two results", two, 44, 2, 0)
print "   subjects: " + two.subjects.join(", ")

empty = declared.read(triples, uid, decl, "search", [], {"q": "Nowhere"})
report("a search that matched nothing", empty, 0, 0, 0)

partial = declared.read(triples, uid, decl, "search", [eiffel, missingId], {"q": "Paris"})
report("one result without an OSM id", partial, 22, 1, 1)

unfit = declared.read(triples, uid, decl, "search", [badLatitude], {"q": "Eiffel Tower"})
report("a latitude that is not a number", unfit, 21, 1, 1)

refusal = declared.read(triples, uid, decl, "search", refused, {})
report("a refused search", refusal, 0, 0, 0)

noQuery = declared.read(triples, uid, decl, "search", [eiffel], {})
report("a result with no query to record", noQuery, 21, 1, 1)


// ── The request half ────────────────────────────────────────────────────────
// The map carries the key and the boolean spelling too, so the url and the redaction come out
// the same as geocode.fetch's.

print ""
print "== the request"
options = {"q": "Eiffel Tower", "limit": 1, "addressdetails": true, "api_key": "test-key"}
oldResult = geo.fetch(stubFor([eiffel]), "search", options)
newResult = declared.fetch(stubFor([eiffel]), decl, "search", options, 10)
print "   geocode.fetch   " + oldResult.url
print "   declared.fetch  " + newResult.url
if oldResult.url != newResult.url then
	print "   DIFF: the urls differ"
	failures = failures + 1
end if
if newResult.url.indexOf("test-key") != null then
	print "   DIFF: the key is still in the url the result keeps"
	failures = failures + 1
end if


// ── What the result is known by ─────────────────────────────────────────────

print ""
print "== what the result is known by"
place = geo.reply(api, "search", [eiffel]).places[0]
oldLabel = place.label
newLabel = declared.label(decl, "search", eiffel)
oldCoordinates = place.coordinates
newCoordinates = declared.coordinates(decl, "search", eiffel)
print "   geocode Place label:       " + oldLabel
print "   declared label:            " + newLabel
print "   geocode Place coordinates: " + oldCoordinates
print "   declared coordinates:      " + newCoordinates
if oldLabel != newLabel then
	print "   DIFF: the labels differ"
	failures = failures + 1
end if
if oldCoordinates != newCoordinates then
	print "   DIFF: the coordinates differ"
	failures = failures + 1
end if


print ""
if failures == 0 then
	print "RESULT: 0 differences."
else
	print "RESULT: " + str(failures) + " difference(s)."
	exit 1
end if