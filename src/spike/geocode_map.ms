// geocode_map.ms — geocode.maps.co's search endpoint as one map: its request, and what one
// result becomes.
//
// This is the whole of the service as the writer reads it. Nothing here is code, and the only
// thing a second endpoint needs is another entry under "endpoints".
//
//   import "spike/geocode_map"
//   decl = globals["spike/geocode_map"].build()
//
// Two clauses ipwho.is did not need:
//
//   "each": "$"              /search answers with a list, so every entry is one place
//   "join": "/"              the identity is the OSM object, way/5013364, not a hash
//
// The coordinates arrive as text ("48.8582599"), and schema.kb types has-latitude as a
// number, so the four facts that carry one say "as number"; a value that will not read as
// one is left out and named in the reading's skipped list.

build = function
	"geocode.maps.co's search endpoint, as the writer reads it."
	return {
		"service": "geocode.maps.co",
		"base": "https://geocode.maps.co",
		"endpoints": {
			"search": {
				"method": "GET",
				"path": "/search",
				// The key travels as its own parameter, and is hidden from the url a result keeps.
				"key": "api_key",
				"redact": ["api_key"],
				// The service spells a boolean 1 or 0, and ignores the word false.
				"boolAs": "1/0",
				"params": [
					{"name": "q", "type": "text",
						"doc": "Free-form query, e.g. " + char(34) + "Eiffel Tower" + char(34) + "."},
					{"name": "amenity", "type": "text",
						"doc": "Place of interest, attraction or business name."},
					{"name": "street", "type": "text", "doc": "House number and street."},
					{"name": "city", "type": "text", "doc": "City name."},
					{"name": "county", "type": "text", "doc": "County or district."},
					{"name": "state", "type": "text", "doc": "State or region."},
					{"name": "country", "type": "text", "doc": "Country name."},
					{"name": "postalcode", "type": "text", "doc": "Postal code."},
					{"name": "addressdetails", "type": "bool", "default": 1,
						"doc": "Include a structured address."},
					{"name": "extratags", "type": "bool", "default": 1,
						"doc": "Include the extra OSM tags."},
					{"name": "namedetails", "type": "bool", "default": 1,
						"doc": "Include name variants."},
					{"name": "limit", "type": "int", "min": 0, "max": 40, "default": 10,
						"doc": "Most results to return, 0 to 40."},
					{"name": "countrycodes", "type": "text",
						"doc": "Restrict to these country codes."},
					{"name": "viewbox", "type": "text",
						"doc": "Bias the search with this bounding box."},
					{"name": "bounded", "type": "bool", "default": 0,
						"doc": "Restrict the results to the viewbox."},
					{"name": "dedupe", "type": "bool", "default": 1,
						"doc": "Drop duplicate OSM results."},
					{"name": "format", "type": "enum",
						"values": ["json", "jsonv2", "xml", "geojson", "geocodejson"],
						"default": "json", "doc": "Reply format."},
					{"name": "accept-language", "type": "text",
						"doc": "Language the names come back in, e.g. en or fr."},
				],
				"reply": {
					"each": "$",
					// A refusal is an object with an error field, not a list of results.
					"refuse": {"present": "error", "message": "error.message"},
					// An id the service's own fields make, rather than a hash: the OSM object.
					"require": ["osm_type", "osm_id"],
					"subject": {"name": "place", "from": ["osm_type", "osm_id"], "join": "/"},
					// The first of these three that carries text, as Place.build reads them.
					"label": {"name": ["display_name", "name", "localname"], "also": []},
					"coordinates": ["lat", "lon"],
					// The query that asked for the result, for the one fact that records it.
					"request": ["q"],
					"facts": [
						["has-name", "?place", "$.name"],
						["has-name-in-fr", "?place", "$.namedetails.name:fr"],
						["has-latitude", "?place", "$.lat as number"],
						["has-longitude", "?place", "$.lon as number"],
						["has-south-latitude", "?place", "$.boundingbox[0] as number"],
						["has-north-latitude", "?place", "$.boundingbox[1] as number"],
						["has-west-longitude", "?place", "$.boundingbox[2] as number"],
						["has-east-longitude", "?place", "$.boundingbox[3] as number"],
						["has-osm-class", "?place", "$.class"],
						["has-osm-type", "?place", "$.type"],
						["has-place-rank", "?place", "$.place_rank"],
						["has-importance", "?place", "$.importance"],
						["has-place-id", "?place", "$.place_id"],
						["has-house-number", "?place", "$.address.house_number"],
						["has-road", "?place", "$.address.road"],
						["has-city", "?place", "$.address.city"],
						["has-country", "?place", "$.address.country"],
						["has-country-code", "?place", "$.address.country_code"],
						["has-wikidata", "?place", "$.extratags.wikidata"],
						["has-wikipedia", "?place", "$.extratags.wikipedia"],
						["has-fee", "?place", "$.extratags.fee"],
						["was-answer-to", "?place", "?q"],
					],
				},
			},
		},
	}
end function