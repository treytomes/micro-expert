// location.ms — where this session is, physically.
//
// A script has no sensor to ask, so the session's public address stands in for it: ipwho.is
// reads that address to a city and a pair of coordinates. The service is a map now -
// services/ipwhois.grfon says its one endpoint and what a reply becomes - and
// src/services/declared.ms turns that reply into facts, so this file is only the part on top:
// one function answering the facts a run starts with.
//
// sessionFacts takes the writer, the map and the transport; the caller loads them. A host
// passes the client's map and the two modules, as src/where.ms does:
//
//   import "api/http_client"
//   import "services/declared"
//   import "services/loader"
//   import "triples"
//   import "uid"
//   import "location"
//   loaded = globals["services/loader"].load(globals["services/document"], globals["knowledge"])
//   here = location.sessionFacts(globals["triples"], globals["uid"], globals["api/http_client"],
//       globals["services/declared"], loaded["ipwhois.grfon"])
//   print here.facts[0].text    has-location(session, place-f1d6b283a52a28dc)
//
// The facts are the map's: has-location(session, place-...) and one line per field the reply
// carried. A refusal, a reply with no city or longitude, or a lookup that never answered is
// ok 0 with the reason and no facts. Nothing here prints, and nothing here touches the
// network until a host calls it. The coordinates are the address's, so they name a city
// rather than a street: where the session reaches the network from, not which room it sits in.

// The seconds the startup lookup may take. The client's default minute is right for a program
// whose job is the request; a run asks this before its first question, and should not wait that
// long on a network that is not there.
startupTimeout = 10


sessionFacts = function(triples, uid, api, declared, decl)
	"Where this session is, as the facts it starts with: ok with them, or ok 0 and the reason there are none."
	result = declared.fetch(api, decl, "lookup", {}, startupTimeout)
	if not result.ok then
		return {"ok": 0, "facts": [], "error": "could not find this session's location: " + result.error}
	end if
	if result.json == null then
		return {"ok": 0, "facts": [], "error": "the location service did not answer with JSON"}
	end if
	reading = declared.read(triples, uid, decl, "lookup", result.json, {})
	if not reading.ok then
		return {"ok": 0, "facts": [], "error": "could not find this session's location: " + reading.error}
	end if
	return {"ok": 1, "facts": reading.facts, "error": null}
end function
