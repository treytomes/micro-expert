// sample.ms — where this session is, physically.
//
// A script has no sensor to ask, so the session's public address stands in for it: ipwho.is
// reads that address to a city and a pair of coordinates. The lookup itself is the API layer's
// - api/ipwhois.ms holds the service's surface and the classes its answer comes back as, and
// api/client.ms is the transport both programs use - so this file is only the spike on top of
// them: one function, answering the place in the shape the rest of the program expects.
//
//   import "../api/client"                  (the host brings the layer with it)
//   import "../api/ipwhois"
//   import "sample"
//   where = globals["sample"].Location.current()
//   print where.label          Fort Worth, Texas, United States
//   print where.latitude       32.7254134
//
// The answer is ok, latitude, longitude and label, or ok 0 and error; nothing here prints. The
// coordinates are the address's, so they name a city rather than a street: where the session
// reaches the network from, not which room it sits in.
//
// The two maps are taken from globals rather than imported here, because an imported module's
// own imports belong to the entry script: the script that loads this one imports the API layer
// first, the way main.ms imports the repl library before session.ms. A host that did not is
// told so in words, since a spike should say why it has no answer.


Location = {}


Location.current = function
	"Where this session is: ok, latitude, longitude and label, or ok 0 and error."
	missing = not globals.hasIndex("../api/client") or not globals.hasIndex("../api/ipwhois")
	if missing then
		return {"ok": 0, "error": "the API layer is not loaded: import ../api/client and ../api/ipwhois first"}
	end if
	api = globals["../api/client"]
	ipwhois = globals["../api/ipwhois"]
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
	latitude = answer.place.latitude
	longitude = answer.place.longitude
	if latitude == null or longitude == null then
		return {"ok": 0, "error": "the location service gave no coordinates"}
	end if
	return {"ok": 1, "latitude": latitude, "longitude": longitude, "label": answer.label}
end function
