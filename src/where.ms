// where.ms — runs the location spike: prints where this session is, as `.kb` facts.
//
// The spike itself is src/spike/session.ms, a module that imports nothing and reads no globals, so
// the maps it works from are loaded here and passed in. That this script sits in src/ rather than
// beside the module matters for one reason: an import is resolved against the entry script's
// folder, and triples.ms imports "temporal" itself, so from src/spike that import would look for
// src/spike/temporal.ms and fail.
//
//   ./3rd-party/miniscript-linux/miniscript src/where.ms
//
// The coordinates are the address's, not a GPS fix: they name the city the session reaches the
// network from. The first line places that city under the session subject, and the rest say what
// the place is. Every line printed is a fact as a `.kb` file writes it, so the output can be
// pasted into one as it stands - has-latitude and has-longitude carry numbers because ipwho.is
// answers with numbers, where the geocoder's reply writes its two as text.


import "api/client"
import "api/ipwhois"
import "triples"
import "uid"
import "spike/session"

api = globals["api/client"]
ipwhois = globals["api/ipwhois"]
triples = globals["triples"]
uid = globals["uid"]
session = globals["spike/session"]

loc = session.getCurrentLocation(api, ipwhois)
if not loc.ok then
	print loc.error
	exit 1
end if

// Each triple's text is one line of a `.kb` file, so the output reads back as the same facts.
for fact in session.generateLocationFacts(triples, uid, loc)
	print fact.text
end for
