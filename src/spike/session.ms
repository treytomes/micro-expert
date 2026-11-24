// session.ms — where this session is, physically.
//
// A script has no sensor to ask, so the session's public address stands in for it: ipwho.is
// reads that address to a city and a pair of coordinates. The lookup itself is the API layer's
// - api/ipwhois.ms holds the service's surface and the classes its answer comes back as, and
// api/client.ms is the transport both programs use - so this file is only the spike on top of
// them: one function answering the place, and one turning that answer into facts.
//
// Both take what they need as arguments, the way the API modules do. This file imports nothing
// and reads no globals: an imported module's imports belong to the entry script, and so does its
// globals, so the maps handed to it are the only ones it can be sure of its classes in. A host
// loads them first and passes them in, as src/where.ms does:
//
//   import "api/client"
//   import "api/ipwhois"
//   import "triples"
//   import "spike/session"
//   session = globals["spike/session"]
//   where = session.getCurrentLocation(globals["api/client"], globals["api/ipwhois"])
//   print where.city           Fort Worth
//   print where.latitude       32.7254134
//
// The answer is ok with the continent, country, region, city and the address's two coordinates,
// or ok 0 and error. Nothing here prints, and nothing here touches the network until a host calls
// it. The coordinates are the address's, so they name a city rather than a street: where the
// session reaches the network from, not which room it sits in.
//
// generateLocationFacts turns that answer into facts about the session: one line places it,
// has-location(session, fort-worth), and the rest say what that place is, one S-P-O triple per
// field. A lookup carries no id, so the place is named by what the service called it - the city in
// lower case with its spaces joined by dashes - and the session subject stays the same from one
// run to the next, so a folder of these facts can be added to rather than replaced. Each triple's
// text is one line of a `.kb` file, which is what src/where.ms prints.


getCurrentLocation = function(api, ipwhois)
	"Where this session is: ok with its names and coordinates, or ok 0 and error."
	result = ipwhois.fetch(api, "lookup")
	if not result.ok then
		return {"ok": 0, "error": "could not find this session's location: " + result.error}
	end if
	// The API layer read the JSON into classes; this reads them.
	answer = result.reply
	if answer == null then
		return {"ok": 0, "error": "the location service did not answer with JSON"}
	end if
	if not answer.ok then
		return {"ok": 0, "error": "could not find this session's location: " + answer.error}
	end if
	place = answer.place
	latitude = place.latitude
	longitude = place.longitude
	if latitude == null or longitude == null then
		return {"ok": 0, "error": "the location service gave no coordinates"}
	end if
	// The names are the service's own fields, read through the layer's shared Place.
	return {"ok": 1, "continent": place.text("continent"), "country": place.text("country"),
		"region": place.text("region"), "city": place.text("city"),
		"latitude": latitude, "longitude": longitude}
end function


generateLocationFacts = function(triples, location)
	"The session's location, then one S-P-O triple per name and coordinate about that place; empty when there is no location."
	if not location.ok then return []
	city = location.city
	if city == null then return []
	// The subject is the place itself, named the way a term is spelled: the city in lower case
	// with its spaces joined by dashes. Anything the form cannot write bare is quoted by the
	// writer, so the line still reads back as the triple it holds.
	subject = city.lower.replace(" ", "-")
	// The session is the subject that holds the place, and the place is the subject its own
	// fields hang off, so a geocoder or another session can name the same city term.
	facts = [triples.SpoTriple.make("session", "has-location", subject)]
	for field in ["continent", "country", "region", "city"]
		if location[field] != null then
			facts.push triples.SpoTriple.make(subject, "has-" + field, location[field])
		end if
	end for
	facts.push triples.SpoTriple.make(subject, "has-latitude", location.latitude)
	facts.push triples.SpoTriple.make(subject, "has-longitude", location.longitude)
	return facts
end function
