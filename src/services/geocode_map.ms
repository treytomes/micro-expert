// geocode_map.ms — geocode.maps.co as one map: its three endpoints, and what one result becomes.
//
// This is the whole of the service as the writer reads it. Nothing here is code, and the only
// thing a fourth endpoint would need is another entry under "endpoints".
//
//   import "services/geocode_map"
//   decl = globals["services/geocode_map"].build()
//
// The endpoints answer in two shapes: /search and /lookup with a list of results, /reverse with
// one object, and a result carries the same fields whichever sent it, so one facts list reads
// them all. Two clauses ipwho.is did not need:
//
//   "each": "$"              a list reply, so every entry is one place
//   "join": "/"              the identity is the OSM object, way/5013364, not a hash
//
// The coordinates arrive as text ("48.8582599"), and schema.kb types has-latitude as a
// number, one per place, so the four facts that carry one say "as number"; a value that will
// not read as one is left out and named in the reading's skipped list. A /lookup result may carry a
// GeoJSON centroid instead of lat and lon, so those two fields name both, in order.
//
// Only /search records the question that asked for its result: was-answer-to is the free-form
// query, and a reverse or a lookup has none.
//
// Two endpoints declare what a question may ask them, so a session that names a place can be
// answered about that place rather than the reader: /search answers its coordinates, asked by the
// place's own name or city, and /reverse answers its address, asked by the place's own
// coordinates. "about" says the reply is read onto the place the question named - geocode.maps.co
// hangs its facts on the OSM object, which is its identity rather than the domain's - and "from"
// names the facts the request's fields are filled from.
//
// A search sends limit=1 and takes what comes back, so its reply block also names the fields
// that make a result the place asked about - the city and the country - and src/services/declared.ms
// refuses a first result whose own words disagree with the facts the session holds for that place.
//
// The service answers 401 without a key, so the map names the variable its key is read from:
// "keyEnv" is GEOCODE_MAPS_API_KEY, which src/services/declared.ms takes from the environment - the
// .env beside the run, read by src/dotenv.ms - when the caller hands no key in. A run with
// neither refuses the request and says which variable to set.

build = function
	"geocode.maps.co, as the writer reads it."
	// The fields one result carries, in the order docs/api/geocode-maps-co.md lists them. The
	// query is the one line only a search has, so it is added where it belongs.
	placeFacts = function(withQuery)
		facts = [
			["has-name", "?place", "$.name"],
			["has-name-in-fr", "?place", "$.namedetails.name:fr"],
			["has-latitude", "?place", ["$.lat as number", "$.centroid.coordinates[1] as number"]],
			["has-longitude", "?place", ["$.lon as number", "$.centroid.coordinates[0] as number"]],
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
		]
		if withQuery then facts.push(["was-answer-to", "?place", "?q"])
		return facts
	end function
	// What every endpoint's reply has to say to be one: an id, and a refusal sent as an error.
	replyShape = function(each, withQuery, confirm=null)
					reply = {
			"refuse": {"present": "error", "message": "error.message"},
			"require": ["osm_type", "osm_id"],
			"subject": {"name": "place", "from": ["osm_type", "osm_id"], "join": "/"},
			// The first of these three that carries text, as the label reads them.
			"label": {"name": ["display_name", "name", "localname"], "also": []},
			"coordinates": ["lat", "lon"],
			"facts": placeFacts(withQuery),
		}
		if each != null then reply.each = each
		if withQuery then reply.request = ["q"]
		if confirm != null then reply.confirm = confirm
		return reply
	end function
	return {
		"service": "geocode.maps.co",
		"base": "https://geocode.maps.co",
		// The service answers 401 without a key, so the map names where the key is read from:
		// src/services/declared.ms fills the request's api_key from this variable, and refuses the
		// request - saying which variable to set - when it holds nothing.
		"keyEnv": "GEOCODE_MAPS_API_KEY",
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
				// A question needing the coordinates of a place the session already names.
				"provides": [
					{"fact": ["has-latitude", "?place", "?lat"], "about": "?place",
						"from": {"q": ["has-name", "has-city"]}, "request": {"limit": 1}},
					{"fact": ["has-longitude", "?place", "?lon"], "about": "?place",
						"from": {"q": ["has-name", "has-city"]}, "request": {"limit": 1}},
				],
				// /search answers with a list, so every entry is one place - and it is asked with
				// limit=1, so the first entry is the one that answers. The reply's own city and
				// country must be the place the session holds, or another Fort Worth would be read
				// as this one and a forecast computed for it. Some results carry no city in their
				// address - Sao Paulo and Mexico City among them - so the name the result is called
				// is what confirms those, and a reply with neither says nothing to disagree with.
				"reply": replyShape("$", 1,
					{"has-city": ["address.city", "name"], "has-country": "address.country"}),
			},
			"reverse": {
				"method": "GET",
				"path": "/reverse",
				"key": "api_key",
				"redact": ["api_key"],
				"boolAs": "1/0",
				"params": [
					{"name": "lat", "type": "number", "min": -90, "max": 90, "required": 1,
						"doc": "Latitude."},
					{"name": "lon", "type": "number", "min": -180, "max": 180, "required": 1,
						"doc": "Longitude."},
					{"name": "addressdetails", "type": "bool", "default": 1,
						"doc": "Include a structured address."},
					{"name": "extratags", "type": "bool", "default": 1,
						"doc": "Include the extra OSM tags."},
					{"name": "namedetails", "type": "bool", "default": 1,
						"doc": "Include name variants."},
					{"name": "zoom", "type": "int", "min": 3, "max": 18,
						"doc": "Detail level, 3 to 18."},
					{"name": "format", "type": "enum",
						"values": ["json", "jsonv2", "xml", "geojson", "geocodejson"],
						"default": "json", "doc": "Reply format."},
					{"name": "accept-language", "type": "text",
						"doc": "Language the names come back in."},
				],
				// A question needing the address at a place the session already names, asked by the
				// coordinates that place's facts hold.
				"provides": [
					{"fact": ["has-road", "?place", "?road"], "about": "?place",
						"from": {"lat": "has-latitude", "lon": "has-longitude"}},
					{"fact": ["has-house-number", "?place", "?number"], "about": "?place",
						"from": {"lat": "has-latitude", "lon": "has-longitude"}},
				],
				// /reverse answers with one object rather than a list of matches.
				"reply": replyShape(null, 0),
			},
			"lookup": {
				"method": "GET",
				"path": "/lookup",
				"key": "api_key",
				"redact": ["api_key"],
				"boolAs": "1/0",
				"params": [
					{"name": "osm_ids", "type": "csv", "required": 1,
						"doc": "Comma-separated IDs with a type prefix, e.g. R253832,W175905."},
					{"name": "addressdetails", "type": "bool", "default": 1,
						"doc": "Include a structured address."},
					{"name": "extratags", "type": "bool", "default": 1,
						"doc": "Include the extra OSM tags."},
					{"name": "namedetails", "type": "bool", "default": 1,
						"doc": "Include name variants."},
					{"name": "polygon_geojson", "type": "bool", "default": 0,
						"doc": "Include the polygon as GeoJSON."},
					{"name": "polygon_kml", "type": "bool", "default": 0,
						"doc": "Include the polygon as KML."},
					{"name": "polygon_svg", "type": "bool", "default": 0,
						"doc": "Include the polygon as SVG."},
					{"name": "polygon_text", "type": "bool", "default": 0,
						"doc": "Include the polygon as text."},
					{"name": "format", "type": "enum",
						"values": ["json", "jsonv2", "xml", "geojson", "geocodejson"],
						"default": "json", "doc": "Reply format."},
					{"name": "accept-language", "type": "text",
						"doc": "Language the names come back in."},
				],
				// /lookup answers with a list, and its result may carry a centroid instead of
				// lat and lon; the two coordinate facts name both paths, in order.
				"reply": replyShape("$", 0),
			},
		},
	}
end function
