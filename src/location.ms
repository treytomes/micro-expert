// location.ms — where this session is, physically.
//
// A script has no sensor to ask, so the session's public address stands in for it: ipwho.is
// reads that address to a city and a pair of coordinates. The lookup itself is the API layer's
// - api/ipwhois.ms holds the service's surface and the classes its answer comes back as, and
// api/client.ms is the transport both programs use - so this file is only the part on top of
// them: one function answering the place, and one turning that answer into facts. It sits with
// the program's other modules because it reads the API layer rather than belonging to it.
//
// Both functions take what they need as arguments, the way the API modules do. This file imports
// nothing and reads no globals: an imported module's imports belong to the entry script, and so
// does its globals, so the maps handed to it are the only ones it can be sure of its classes in.
// A host loads them first and passes them in, as src/where.ms does:
//
//   import "api/client"
//   import "api/ipwhois"
//   import "triples"
//   import "uid"
//   import "location"
//   location = globals["location"]
//   here = location.getCurrentLocation(globals["api/client"], globals["api/ipwhois"])
//   print here.city           Fort Worth
//   print here.latitude       32.7254134
//
// The answer is ok with the continent, country, region, city and the address's two coordinates,
// or ok 0 and error. Nothing here prints, and nothing here touches the network until a host calls
// it. The coordinates are the address's, so they name a city rather than a street: where the
// session reaches the network from, not which room it sits in.
//
// generateLocationFacts turns that answer into facts about the session: one line places it,
// has-location(session, place-f1d6b283a52a28dc), and the rest say what the place is like, one
// S-P-O triple per field. What the place is - a location - is a rule's work rather than a fact's:
// data/rules.kb concludes is-a(?x, location) from the two coordinates, so no line spends itself on
// it. A lookup carries no id of its own, so the place gets one
// from src/uid.ms: a hash of the city, region and country it answered with, which is the same term
// on the next run and on another machine, so a folder of these facts can be added to rather than
// replaced. Each triple's text is one line of a `.kb` file, which is what src/where.ms prints.
//
// sessionFacts is the two together, because that is what a run wants: the answer, then the facts,
// or ok 0 and the reason there are none. main.ms calls it once at startup under --where, so the
// session the prompt reasons from already holds where it is.


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


fieldOf = function(location, name)
	"The field the answer carried, or null when it carried none: absent, null, empty and blank all read the same here."
	if not location.hasIndex(name) then return null
	value = location[name]
	if value == null then return null
	// A field sent as text with nothing in it says no more than a field not sent, and written as
	// a fact it would be an empty term: the answer's blanks are absences.
	if value isa string and value.replace(" ", "") == "" then return null
	return value
end function


generateLocationFacts = function(triples, uid, location)
	"The session's location, what it is, and one S-P-O triple per field of it; empty when there is no location."
	if not location.ok then return []
	city = fieldOf(location, "city")
	if city == null or fieldOf(location, "longitude") == null then return []
	// The subject is the place itself, named by the id its own fields generate: the city, region
	// and country are what says which place is meant, and the hash is what makes the term the same
	// one the next time this runs, here or on another machine. The region and country alone would
	// name a whole country's worth of places, so a lookup with no city gets no term to hang facts
	// on rather than one every town in a region would share.
	subject = uid.of("place", [city, fieldOf(location, "region"), fieldOf(location, "country")])
	if subject == "" then return []
	// The session is the subject that holds the place, and the place is the subject its own
	// fields hang off, so a geocoder or another session that reaches the same place generates the
	// same term and the facts meet.
	facts = []
	facts.push triples.SpoTriple.make("session", "has-location", subject)
	facts.push triples.SpoTriple.make(subject, "has-continent", fieldOf(location, "continent"))
	facts.push triples.SpoTriple.make(subject, "has-country", fieldOf(location, "country"))
	facts.push triples.SpoTriple.make(subject, "has-region", fieldOf(location, "region"))
	facts.push triples.SpoTriple.make(subject, "has-city", fieldOf(location, "city"))
	facts.push triples.SpoTriple.make(subject, "has-latitude", fieldOf(location, "latitude"))
	facts.push triples.SpoTriple.make(subject, "has-longitude", fieldOf(location, "longitude"))
	// A field the reply did not carry is no fact at all: one whose object is null would read back
	// as the word null, a value the service never sent.
	kept = []
	for fact in facts
		if fact.object != null then kept.push fact
	end for
	return kept
end function


sessionFacts = function(triples, uid, api, ipwhois)
	"Where this session is, as the facts it starts with: ok with them, or ok 0 and the reason there are none."
	here = getCurrentLocation(api, ipwhois)
	if not here.ok then return {"ok": 0, "facts": [], "error": here.error}
	return {"ok": 1, "facts": generateLocationFacts(triples, uid, here), "error": null}
end function
