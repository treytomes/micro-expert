// geocode.ms — geocode.maps.co's surface: its three GET endpoints, every parameter each
// accepts, and the request that turns an options map into one call.
//
// The shared transport is handed in rather than imported, because this interpreter discards
// the imports of an imported module: a program imports api/client and this file, and calls
// fetch(api, ...) and surface(api) with that module's map. Nothing here touches
// the network by itself, and nothing here knows about a command line.
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
	key = api.keyFrom(options, keyName)

	if key != null then params.api_key = key

	url = api.urlFor(base + spec.path, params)
	result = api.get(url)
	result.url = api.redactUrl(url, ["api_key"])
	return result
end function
