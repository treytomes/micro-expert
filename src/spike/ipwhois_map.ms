// ipwhois_map.ms — ipwho.is as one map: its request, and what its reply becomes.
//
// This is the whole of the service. src/spike/declared.ms reads it; nothing here is code.
//
//   import "spike/ipwhois_map"
//   decl = globals["spike/ipwhois_map"].build()
//
// The endpoint's params are the same spec shape src/api/client.ms validates against, so
// --help and the request checks come for free. The reply half says when the service refused,
// which fields identify the place, and one fact per line.

build = function
	"ipwho.is, as the writer reads it."
	return {
		"service": "ipwho.is",
		"base": "https://ipwho.is",
		"endpoints": {
			"lookup": {
				"method": "GET",
				"path": "/",
				"params": [
					{"name": "lang", "type": "text",
						"doc": "Language the words come back in, such as en or de."},
					{"name": "fields", "type": "csv",
						"doc": "Only these fields, comma-separated."},
				],
				"reply": {
					// A refusal is a 200 with success false, so it is read before any fact is.
					"refuse": {"when": "success", "is": false, "message": "message"},
					// Without a city and a longitude there is no place to hang facts on.
					"require": ["city", "longitude"],
					// The identity, not the label: the same three fields hash to the same term.
					"subject": {"kind": "place", "name": "place",
						"from": ["city", "region", "country"]},
					"label": {"name": ["city"], "also": ["region", "country"]},
					"coordinates": ["latitude", "longitude"],
					"facts": [
						["has-location", "session", "?place"],
						["has-continent", "?place", "$.continent"],
						["has-country", "?place", "$.country"],
						["has-region", "?place", "$.region"],
						["has-city", "?place", "$.city"],
						["has-latitude", "?place", "$.latitude"],
						["has-longitude", "?place", "$.longitude"],
					],
				},
			},
		},
	}
end function
