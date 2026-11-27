// where.ms — prints where this session is, as `.kb` facts.
//
// src/location.ms answers the place through services/ipwhois.grfon and the declared writer; it
// imports nothing and reads no globals, so the maps it works from are loaded here and passed in.
// This script sits in src/ so that every import resolves the same way: an import is resolved
// against the entry script's folder, and triples.ms imports "temporal" itself, so run from
// anywhere else that import would look in the wrong folder and fail.
//
//   ./3rd-party/miniscript-linux/miniscript src/where.ms
//
// The coordinates are the address's, not a GPS fix: they name the city the session reaches the
// network from. The first line places that city under the session subject, and the rest say what
// the place is. Every line printed is a fact as a `.kb` file writes it, so the output can be
// pasted into one as it stands - has-latitude and has-longitude carry numbers because ipwho.is
// answers with numbers, where the geocoder's reply writes its two as text.


import "api/http_client"
import "services/declared"
import "services/document"
import "services/loader"
import "knowledge"
import "triples"
import "uid"
import "location"

api = globals["api/http_client"]
declared = globals["services/declared"]
loaded = globals["services/loader"].load(globals["services/document"], globals["knowledge"])
if loaded isa error then
	print loaded.message
	exit 1
end if
if not loaded.hasIndex("ipwhois.grfon") then
	print "ipwhois.grfon is not in services/."
	exit 1
end if
decl = loaded["ipwhois.grfon"]
if decl isa error then
	print decl.message
	exit 1
end if
triples = globals["triples"]
uid = globals["uid"]
location = globals["location"]

here = location.sessionFacts(triples, uid, api, declared, decl)
if not here.ok then
	print here.error
	exit 1
end if

// Each triple's text is one line of a `.kb` file, so the output reads back as the same facts.
for fact in here.facts
	print fact.text
end for
