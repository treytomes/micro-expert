// openmeteo_map.ms — Open-Meteo's forecast endpoint as one map, for its hourly series.
//
//   import "spike/openmeteo_map"
//   decl = globals["spike/openmeteo_map"].build()
//
// Open-Meteo answers with parallel lists: `hourly.time` holds the instants, and one list beside
// it holds each variable's value at that index. So "each" names the series rather than a list of
// objects, and a fact's path indexes the same position with [i]. The place is not in the reply
// at all - it is the caller's name for the point - so it comes from the request as ?place.
//
// Two annotations carry what the object cannot. '@' says when the fact holds: an hourly value is
// the hour that starts at its instant, so the fact spans that instant to the next one, and the
// last hour of a reply falls back to the instant alone rather than claiming an end it was not
// given. '~' carries the service's chance of precipitation, read as how confident the
// precipitation fact is: a 40% chance is 40% confidence that the hour's rain happens. It is the
// service's own probability, not a measured confidence in the amount, and a reply asked without
// `precipitation_probability` says nothing, leaving the fact fully confident.
//
// The instant lives only in '@', not in the subject: a fact is known by its whole line, so two
// hours holding the same value are two facts, told apart by the span they cover. The subject is
// the place alone, which is what a question about the place can name.
//
// Only the forecast endpoint is here: the other twenty-two hosts answer the same shape but are
// separate entries, and a commercial key moves the host to customer-api.open-meteo.com, which
// this map does not yet say.

build = function
	"Open-Meteo's forecast endpoint, as the writer reads it."
	// The hour a reading covers, and the instant alone for the reply's last one. Open-Meteo
	// writes an instant with ISO 8601's 'T', which the fact grammar does not read as a
	// datetime, so each side is spelled the way '@' reads it.
	instant = "$.hourly.time[i] as moment"
	hour = {"span": [instant, "$.hourly.time[i+1] as moment"], "or": instant}
	// Rain, and how sure the service is that it happens.
	rain = {"at": hour, "confidence": "$.hourly.precipitation_probability[i]"}
	return {
		"service": "open-meteo",
		"base": "https://api.open-meteo.com",
		"endpoints": {
			"forecast": {
				"method": "GET",
				"path": "/v1/forecast",
				"key": "apikey",
				"redact": ["apikey"],
				"params": [
					{"name": "latitude", "type": "coordinates", "min": -90, "max": 90,
						"required": 1, "doc": "WGS84 latitude; a list asks for several locations."},
					{"name": "longitude", "type": "coordinates", "min": -180, "max": 180,
						"required": 1, "doc": "WGS84 longitude; as many values as there are latitudes."},
					{"name": "elevation", "type": "coordinates", "min": -1000, "max": 9000,
						"allowNan": 1, "doc": "Elevation used for downscaling, or nan."},
					{"name": "hourly", "type": "csv", "doc": "Hourly variables, comma separated."},
					{"name": "daily", "type": "csv", "doc": "Daily variables, comma separated."},
					{"name": "current", "type": "csv",
						"doc": "Variables to report as current conditions."},
					{"name": "temperature_unit", "type": "enum",
						"values": ["celsius", "fahrenheit"], "doc": "Temperature unit."},
					{"name": "wind_speed_unit", "type": "enum",
						"values": ["kmh", "ms", "mph", "kn"], "doc": "Wind speed unit."},
					{"name": "precipitation_unit", "type": "enum", "values": ["mm", "inch"],
						"doc": "Precipitation unit."},
					{"name": "timeformat", "type": "enum", "values": ["iso8601", "unixtime"],
						"doc": "Timestamp format."},
					{"name": "timezone", "type": "text",
						"doc": "Time zone name, or auto to resolve it from the coordinates."},
					{"name": "past_days", "type": "int", "min": 0,
						"doc": "Days before today to include."},
					{"name": "forecast_days", "type": "int", "min": 0, "max": 16,
						"doc": "Forecast days, 0 to 16."},
					{"name": "start_date", "type": "date",
						"doc": "First day of the interval, yyyy-mm-dd."},
					{"name": "end_date", "type": "date",
						"doc": "Last day of the interval, yyyy-mm-dd."},
					{"name": "models", "type": "csv",
						"doc": "Model names, comma separated; auto combines the best ones."},
					{"name": "cell_selection", "type": "enum",
						"values": ["land", "sea", "nearest"], "doc": "Which grid cell to prefer."},
					{"name": "format", "type": "enum", "values": ["json", "csv", "xlsx"],
						"doc": "Reply format."},
				],
				"reply": {
					// One index of this series is one reading.
					"each": {"path": "$.hourly.time"},
					// Open-Meteo reports a refusal as error true with the reason beside it.
					"refuse": {"when": "error", "is": true, "message": "reason"},
					"require": ["latitude", "longitude", "?place"],
					// The place is the caller's, and the instant is on each fact's '@'.
					"subject": {"name": "reading", "from": ["?place"]},
					"request": ["place"],
					"facts": [
						["has-temperature-2m", "?reading", "$.hourly.temperature_2m[i]",
							{"at": hour}],
						["has-relative-humidity-2m", "?reading",
							"$.hourly.relative_humidity_2m[i]", {"at": hour}],
						["has-precipitation", "?reading", "$.hourly.precipitation[i]", rain],
						["has-wind-speed-10m", "?reading", "$.hourly.wind_speed_10m[i]",
							{"at": hour}],
						["has-weather-code", "?reading", "$.hourly.weather_code[i]",
							{"at": hour}],
					],
				},
			},
		},
	}
end function