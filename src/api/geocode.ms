// geocode.ms — geocode.maps.co's surface: its three GET endpoints, every parameter each
// accepts, the classes its replies come back as, and the request that turns an options map
// into one call.
//
// The shared transport is handed in rather than imported, because this interpreter discards
// the imports of an imported module: a program imports api/client and this file, and calls
// fetch(api, ...) and surface(api) with that module's map. Nothing here touches
// the network by itself, and nothing here knows about a command line.
//
// fetch answers the transport's map with one field of its own: reply. It is a SearchReply,
// a ReverseReply or a LookupReply - the parsed JSON read as Place objects - or null when the
// request failed or the service sent no JSON. The parsed JSON stays beside it, untouched,
// for a program that wants to print the service's own answer; a program that renders the
// results reads the classes instead of picking fields out of a map.
//
// The key travels as the api_key parameter, which the service accepts. The Authorization
// header its documentation also names answers 401, so there is no header path to fall back to.


keyName = "GEOCODE_MAPS_API_KEY"
base = "https://geocode.maps.co"
formats = ["json", "jsonv2", "xml", "geojson", "geocodejson"]

endpoints = {
	"search": {
		"path": "/search",
		"doc": "An address, or a set of structured fields, to coordinates and a display name.",
		"params": [
			{"name": "q", "type": "text", "doc": "Free-form query, e.g. ""Eiffel Tower""."},
			{"name": "amenity", "type": "text", "doc": "Place of interest, attraction or business name."},
			{"name": "street", "type": "text", "doc": "House number and street."},
			{"name": "city", "type": "text", "doc": "City name."},
			{"name": "county", "type": "text", "doc": "County or district."},
			{"name": "state", "type": "text", "doc": "State or region."},
			{"name": "country", "type": "text", "doc": "Country name."},
			{"name": "postalcode", "type": "text", "doc": "Postal code."},
			{"name": "addressdetails", "type": "bool", "default": 1, "doc": "Include a structured address."},
			{"name": "extratags", "type": "bool", "default": 1, "doc": "Include the extra OSM tags."},
			{"name": "namedetails", "type": "bool", "default": 1, "doc": "Include name variants."},
			{"name": "limit", "type": "int", "min": 0, "max": 40, "default": 10, "doc": "Most results to return, 0 to 40."},
			{"name": "countrycodes", "type": "text", "doc": "Restrict to these country codes."},
			{"name": "viewbox", "type": "text", "doc": "Bias the search with this bounding box."},
			{"name": "bounded", "type": "bool", "default": 0, "doc": "Restrict the results to the viewbox."},
			{"name": "dedupe", "type": "bool", "default": 1, "doc": "Drop duplicate OSM results."},
			{"name": "format", "type": "enum", "values": formats, "default": "json", "doc": "Reply format."},
			{"name": "accept-language", "type": "text", "doc": "Language the names come back in, e.g. en or fr."},
		],
	},
	"reverse": {
		"path": "/reverse",
		"doc": "A coordinate to the nearest address, as one result.",
		"params": [
			{"name": "lat", "type": "number", "min": -90, "max": 90, "required": 1, "doc": "Latitude."},
			{"name": "lon", "type": "number", "min": -180, "max": 180, "required": 1, "doc": "Longitude."},
			{"name": "addressdetails", "type": "bool", "default": 1, "doc": "Include a structured address."},
			{"name": "extratags", "type": "bool", "default": 1, "doc": "Include the extra OSM tags."},
			{"name": "namedetails", "type": "bool", "default": 1, "doc": "Include name variants."},
			{"name": "zoom", "type": "int", "min": 3, "max": 18, "doc": "Detail level, 3 to 18."},
			{"name": "format", "type": "enum", "values": formats, "default": "json", "doc": "Reply format."},
			{"name": "accept-language", "type": "text", "doc": "Language the names come back in."},
		],
	},
	"lookup": {
		"path": "/lookup",
		"doc": "The details of objects named by OSM ID.",
		"params": [
			{"name": "osm_ids", "type": "csv", "required": 1, "doc": "Comma-separated IDs with a type prefix, e.g. R253832,W175905."},
			{"name": "addressdetails", "type": "bool", "default": 1, "doc": "Include a structured address."},
			{"name": "extratags", "type": "bool", "default": 1, "doc": "Include the extra OSM tags."},
			{"name": "namedetails", "type": "bool", "default": 1, "doc": "Include name variants."},
			{"name": "polygon_geojson", "type": "bool", "default": 0, "doc": "Include the polygon as GeoJSON."},
			{"name": "polygon_kml", "type": "bool", "default": 0, "doc": "Include the polygon as KML."},
			{"name": "polygon_svg", "type": "bool", "default": 0, "doc": "Include the polygon as SVG."},
			{"name": "polygon_text", "type": "bool", "default": 0, "doc": "Include the polygon as text."},
			{"name": "format", "type": "enum", "values": formats, "default": "json", "doc": "Reply format."},
			{"name": "accept-language", "type": "text", "doc": "Language the names come back in."},
		],
	},
}


specFor = function(endpointName)
	"The endpoint's spec, or null when the table has no such endpoint."
	if not endpoints.hasIndex(endpointName) then return null
	return endpoints[endpointName]
end function


surface = function(api)
	"One parameter list holding the three endpoints' parameters, for the program's --help."
	return api.unionSpec([endpoints["search"], endpoints["reverse"], endpoints["lookup"]])
end function


flags = function(spec, params)
	"The service spells a boolean 1 or 0, and ignores the word false."
	for paramSpec in spec.params
		if paramSpec.type == "bool" then
			if params.hasIndex(paramSpec.name) then
				value = str(params[paramSpec.name]).lower
				if value == "true" then params[paramSpec.name] = 1
				if value == "false" then params[paramSpec.name] = 0
			end if
		end if
	end for
	return params
end function


// ── The reply as classes ─────────────────────────────────────────────────────
// The three endpoints answer in two shapes - /search and /lookup with a list of results,
// /reverse with one object - and a result carries the same fields whichever endpoint sent it,
// so one Place reads them all: the API layer's shared one, built with the three names an OSM
// result may carry. The reply classes hold those and know what the answer says about itself.
// reply() turns the parsed JSON into them, and fetch puts one on the result it returns. A
// refusal, or a shape no endpoint documents, is one of the same classes with ok 0 and error
// set: there is nothing to render, only something to report.
//
// Nothing here prints. The classes answer values and words, and the program lays them out.


Reply = {"ok": 1, "error": null}


Reply.count = function
	"How many results the reply holds."
	return self.places.len
end function


Reply.isEmpty = function
	"True when it holds no results."
	return self.places.len == 0
end function


Reply.numbered = function
	"True when the results are a list to number."
	return 1
end function


Reply.emptyMessage = function
	"What to say when nothing matched."
	return "No matches."
end function


SearchReply = new Reply
SearchReply.query = ""


SearchReply.heading = function
	"The count, and the query that asked for it."
	text = self.count + " result" + "s" * (self.count != 1)
	if self.query != "" then text = text + " for " + char(34) + self.query + char(34)
	return text + ":"
end function


SearchReply.emptyMessage = function
	"What to say when a search matched nothing."
	if self.query != "" then return "No matches for " + char(34) + self.query + char(34) + "."
	return "No matches."
end function


LookupReply = new Reply
LookupReply.ids = ""


LookupReply.heading = function
	"The count, and the ids that asked for them."
	text = self.count + " result" + "s" * (self.count != 1)
	if self.ids != "" then text = text + " for " + self.ids
	return text + ":"
end function


ReverseReply = new Reply


ReverseReply.heading = function
	"One place rather than a list: there is no line to put above it."
	return ""
end function


ReverseReply.numbered = function
	"Nor a number in front of it."
	return 0
end function


replyClass = function(endpointName)
	"The class this endpoint's reply comes back as."
	if endpointName == "reverse" then return ReverseReply
	if endpointName == "lookup" then return LookupReply
	return SearchReply
end function


refusalMessage = function(value)
	"The service's error field as one line: a word, or the message inside its object."
	if value isa string then return value
	if value isa map then
		if value.hasIndex("message") then
			if value.message isa string then return value.message
		end if
	end if
	return str(value)
end function


refusedReply = function(message)
	"The reply a refusal, or a shape no endpoint documents, answers with."
	answer = new Reply
	answer.ok = 0
	answer.error = message
	answer.places = []
	return answer
end function


reply = function(api, endpointName, json, asked={})
	"The parsed JSON as one of the reply classes; null when there is no JSON to read."
	if json == null then return null
	if json isa map then
		if json.hasIndex("error") then
			return refusedReply("The API refused the request: " + refusalMessage(json.error))
		end if
	end if

	items = json
	if json isa map then
		// /reverse answers with one object rather than a list of matches.
		items = [json]
	else if not (json isa list) then
		return refusedReply("The API returned an unexpected reply.")
	end if

	proto = replyClass(endpointName)
	answer = new proto
	answer.places = []
	for item in items
		// A result is one object; an entry that is not one is not a result to show.
		if item isa map then answer.places.push api.Place.build(item, ["display_name", "name", "localname"])
	end for

	// The question is part of what the reply says about itself.
	if answer isa SearchReply then
		if asked.hasIndex("q") then answer.query = str(asked.q)
	end if
	if answer isa LookupReply then
		if asked.hasIndex("osm_ids") then
			ids = asked.osm_ids
			if ids isa list then ids = ids.join(",")
			answer.ids = str(ids)
		end if
	end if
	return answer
end function


fetch = function(api, endpointName, options={})
	"One request to a geocoding endpoint, with the key added and hidden from the url."
	spec = specFor(endpointName)
	if spec == null then
		return api.failure("Unknown endpoint " + api.quote(endpointName) + ".")
	end if
	checked = api.validate(spec, options)
	if not checked.ok then
		return api.failure("Invalid " + endpointName + " request: " + checked.problems.join("; "))
	end if

	params = flags(spec, checked.params)
	key = api.keyIn(options)

	if key != null then params.api_key = key

	url = api.urlFor(base + spec.path, params)
	result = api.get(url)
	result.url = api.redactUrl(url, ["api_key"])
	// The reply read as classes, so a program renders objects rather than fields.
	result.reply = null
	if result.ok then result.reply = reply(api, endpointName, result.json, options)
	return result
end function
