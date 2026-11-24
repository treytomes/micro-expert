// spike-ipwhois-declared.ms — the declared writer against the canned Fort Worth reply.
//
//   ./3rd-party/miniscript-linux/miniscript src/spike-ipwhois-declared.ms
//
// No request leaves the program: the client is a stand-in whose get answers the JSON below, so
// the old path (ipwhois.fetch -> LocationReply -> location.getCurrentLocation ->
// location.generateLocationFacts) and the new one (spike/declared reading the map in
// src/spike/ipwhois_map.ms) are fed the same reply. Each case prints both fact lists and counts
// a difference; the last line says how many there were.
//
// The runner sits in src/ rather than beside its modules because triples.ms imports temporal,
// and an import resolves against the entry script's folder: from src/spike that import looks
// for src/spike/temporal.ms and stops. The writer and the map stay in src/spike.

import "api/client"
import "api/ipwhois"
import "triples"
import "uid"
import "location"
import "spike/declared"
import "spike/ipwhois_map"

api = globals["api/client"]
ipwhois = globals["api/ipwhois"]
triples = globals["triples"]
uid = globals["uid"]
location = globals["location"]
declared = globals["spike/declared"]
decl = globals["spike/ipwhois_map"].build()


// ── The reply, as ipwho.is answers this machine ─────────────────────────────

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

cases = [
	{"name": "full Fort Worth", "json": fortWorth},
	{"name": "no region", "json": noRegion},
	{"name": "region null", "json": nullRegion},
	{"name": "region blank", "json": blankRegion},
	{"name": "no city", "json": noCity},
	{"name": "no coordinates", "json": noCoordinates},
	{"name": "city blank", "json": blankCity},
	{"name": "refused lookup", "json": refused},
	{"name": "narrowed to city and country", "json": narrowed},
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


textOf = function(value)
	"One value for a line, with null said rather than printed."
	if value == null then return "(none)"
	return str(value)
end function


pad = function(text, width)
	"text, then spaces to width; the text itself when it is already that wide."
	padding = width - text.len
	if padding <= 0 then return text
	return text + " " * padding
end function


sameFacts = function(a, b)
	"Whether two fact lists are the same lines in the same order."
	if a.len != b.len then return false
	for i in a.indexes
		if a[i].text != b[i].text then return false
	end for
	return true
end function


showFacts = function(name, oldFacts, newFacts)
	"Both lists, one line each, the old on the left."
	width = 0
	for fact in oldFacts
		if fact.text.len > width then width = fact.text.len
	end for
	width = width + 2
	print ""
	print "== " + name
	print "   old (location.ms): " + str(oldFacts.len) + "    new (spike/ipwhois_map): " + str(newFacts.len)
	if oldFacts.len == 0 and newFacts.len == 0 then
		print "   (no facts either way)"
		return
	end if
	rows = oldFacts.len
	if newFacts.len > rows then rows = newFacts.len
	for i in range(0, rows - 1)
		left = ""
		right = ""
		if i < oldFacts.len then left = oldFacts[i].text
		if i < newFacts.len then right = newFacts[i].text
		print "   " + pad(left, width) + right
	end for
end function


// ── Every case, both paths ──────────────────────────────────────────────────

failures = 0

for c in cases
	json = c.json
	stub = stubFor(json)
	here = location.getCurrentLocation(stub, ipwhois)
	oldFacts = []
	if here.ok then oldFacts = location.generateLocationFacts(triples, uid, here)
	reading = declared.read(triples, uid, decl, "lookup", json)
	newFacts = reading.facts

	showFacts(c.name, oldFacts, newFacts)
	for note in reading.skipped
		print "   left out: " + note
	end for
	oldError = null
	if here.hasIndex("error") then oldError = here.error
	if here.ok != reading.ok then
		print "   (the old path is ok " + str(here.ok) + ", the new one " + str(reading.ok) + ")"
	end if
	if oldError != null or reading.error != null then
		print "   old error: " + textOf(oldError)
		print "   new error: " + textOf(reading.error)
	end if
	if not sameFacts(oldFacts, newFacts) then
		print "   DIFF: the facts differ"
		failures = failures + 1
	end if
	// Every fact has to read back as the line it printed, as test/location.ms checks.
	unread = 0
	for fact in newFacts
		back = triples.SpoTriple.parse(fact.text)
		if back isa error or back.text != fact.text then unread = unread + 1
	end for
	if unread > 0 then
		print "   DIFF: " + str(unread) + " fact(s) do not read back"
		failures = failures + 1
	end if
end for


// ── The request half ────────────────────────────────────────────────────────
// The map carries the endpoint's params too, so the same checks and the same url come out of
// the declared fetch as out of ipwhois.fetch.

print ""
print "== the request"
oldStub = stubFor(fortWorth)
oldResult = ipwhois.fetch(oldStub, "lookup", {"fields": ["city", "country"]}, 10)
newStub = stubFor(fortWorth)
newResult = declared.fetch(newStub, decl, "lookup", {"fields": ["city", "country"]}, 10)
print "   ipwhois.fetch   " + oldResult.url
print "   declared.fetch  " + newResult.url
if oldResult.url != newResult.url then
	print "   DIFF: the urls differ"
	failures = failures + 1
end if
if oldStub.seenTimeout != newStub.seenTimeout then
	print "   DIFF: the timeouts differ"
	failures = failures + 1
end if
print "   the startup deadline reached the transport: " + textOf(newStub.seenTimeout)


// ── What the reply is known by ──────────────────────────────────────────────
// LocationReply's label and coordinates were the two members that needed a class; the map
// names the fields instead.

print ""
print "== what the reply is known by"
oldReply = ipwhois.reply(api, fortWorth)
oldLabel = oldReply.label
newLabel = declared.label(decl, "lookup", fortWorth)
oldCoordinates = oldReply.coordinates
newCoordinates = declared.coordinates(decl, "lookup", fortWorth)
print "   old label:       " + oldLabel
print "   new label:       " + newLabel
print "   old coordinates: " + oldCoordinates
print "   new coordinates: " + newCoordinates
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
	print "RESULT: 0 differences across " + str(cases.len) + " cases."
else
	print "RESULT: " + str(failures) + " difference(s) across " + str(cases.len) + " cases."
	exit 1
end if
