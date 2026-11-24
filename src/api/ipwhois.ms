// ipwhois.ms — ipwho.is's surface: its lookup, the parameters it accepts, the classes its
// reply comes back as, and the request that turns an options map into one call.
//
// The shared transport is handed in rather than imported, because this interpreter discards
// the imports of an imported module: a program imports api/client and this file, and calls
// fetch(api, ...) with that module's map, declaring the parameters it takes with
// api.addParameters(cli, cmd, specFor("lookup")). Nothing here touches the network by itself,
// and nothing here knows about a command line.
//
//   lookup    GET https://ipwho.is/          the caller's own address
//
// It takes no key: the free service is rate-limited by address rather than by key, and the
// keyed parts of it - /bulk, the security fields - are left out rather than half-answered. Its
// two query parameters are lang and fields. `fields` narrows the reply, so a class reads only
// what it was sent and answers null for the rest.
//
// fetch answers the transport's map with one field of its own: reply. It is a LocationReply -
// the parsed JSON read as the classes below - or null when the request failed or the service
// sent no JSON. The parsed JSON stays beside it, untouched, for a program that wants to print
// the service's own answer.
//
// ipwho.is reports a refused lookup as a 200 with success false and a message, not as an HTTP
// error, so that refusal is a reply with ok 0 rather than a failed request. The transport's
// string methods come from stringUtil, which this file imports for trim.


import "stringUtil"

base = "https://ipwho.is"

endpoints = {
	"lookup": {
		"path": "/",
		"doc": "The caller's own address: where this session reaches the network from.",
		"params": [
			{"name": "lang", "type": "text", "doc": "Language the words come back in, such as en or de."},
			{"name": "fields", "type": "csv", "doc": "Only these fields, comma-separated."},
		],
	},
}


specFor = function(endpointName)
	"The endpoint's spec, or null when the table has no such endpoint."
	if not endpoints.hasIndex(endpointName) then return null
	return endpoints[endpointName]
end function


// ── The reply as classes ─────────────────────────────────────────────────────
// The answer is one object of place fields with three objects inside it - the flag, the
// network and the clock. All four are the API layer's: the place is its shared Place, built
// with the city and the region and country around it, and the three parts are its Fields, read
// by the name the service gave each field. What is here is only what holds them together,
// which is the complete answer: the address it is about, what it is called, where it is, and
// every field the service sent, described a line at a time.
//
// Nothing here prints. The classes answer values and lines, and the program lays them out.

Reply = {"ok": 1, "error": null}


LocationReply = new Reply
LocationReply.place = null
LocationReply.connection = null
LocationReply.timezone = null
LocationReply.flag = null


LocationReply.ip = function
	"The address the answer is about; empty when the reply named none."
	if self.place == null then return ""
	text = self.place.text("ip")
	if text == null then return ""
	return text
end function


LocationReply.label = function
	"What the address is known by, as its place names it."
	if self.place == null then return ""
	return self.place.label
end function


LocationReply.coordinates = function
	"Where it is, as latitude and longitude; empty when the reply gave none."
	if self.place == null then return ""
	return self.place.coordinates
end function


LocationReply.isEmpty = function
	"True when the reply holds no address to describe."
	return self.place == null
end function


LocationReply.describe = function
	"The whole answer as lines: what it is and where, then every field the service sent."
	if self.place == null then return []
	lines = [self.label, self.coordinates]
	lines.push ""
	for line in self.place.describe
		lines.push line
	end for
	return lines
end function


refusalMessage = function(json)
	"The service's own message for a refused lookup, or a stand-in when it sent none."
	if json.hasIndex("message") then
		if json.message isa string then
			message = json.message.trim
			if message != "" then return message
		end if
	end if
	return "no message given."
end function


partOf = function(api, raw, field)
	"One of the objects inside the answer, as the layer's Fields; null when it sent none."
	if not raw.hasIndex(field) then return null
	if not (raw[field] isa map) then return null
	return api.Fields.build(raw[field])
end function


refusedReply = function(message)
	"The reply a refusal, or a shape the service does not document, answers with."
	answer = new LocationReply
	answer.ok = 0
	answer.error = message
	return answer
end function


locationReply = function(api, raw)
	"The one answer the service gave, read as the classes above."
	answer = new LocationReply
	answer.place = api.Place.build(raw, ["city"], ["region", "country"])
	answer.connection = partOf(api, raw, "connection")
	answer.timezone = partOf(api, raw, "timezone")
	answer.flag = partOf(api, raw, "flag")
	return answer
end function


reply = function(api, json)
	"The parsed JSON as a LocationReply; null when there is no JSON to read."
	if json == null then return null
	if not (json isa map) then
		return refusedReply("The API returned an unexpected reply.")
	end if
	// A refused lookup is a 200 with success false, not an HTTP error.
	if json.hasIndex("success") then
		if not json.success then
			return refusedReply("The API refused the lookup: " + refusalMessage(json))
		end if
	end if
	return locationReply(api, json)
end function


fetch = function(api, endpointName, options={}, timeout=null)
	"One lookup at ipwho.is: the caller's own address, as the service reads it; timeout is the seconds the request may take, the client's own when none is given."
	spec = specFor(endpointName)
	if spec == null then
		return api.failure("Unknown endpoint " + api.quote(endpointName) + ".")
	end if
	checked = api.validate(spec, options)
	if not checked.ok then
		return api.failure("Invalid " + endpointName + " request: " + checked.problems.join("; "))
	end if

	url = api.urlFor(base + spec.path, checked.params)
	result = api.get(url, timeout)
	// The reply read as classes, so a program renders objects rather than fields.
	result.reply = null
	if result.ok then result.reply = reply(api, result.json)
	return result
end function
