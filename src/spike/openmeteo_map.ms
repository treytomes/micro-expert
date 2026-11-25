// openmeteo_map.ms — Open-Meteo as one map: all twenty-three endpoints, and what one reply becomes.
//
//   import "spike/openmeteo_map"
//   decl = globals["spike/openmeteo_map"].build()
//
// Open-Meteo answers with parallel lists: `hourly.time` holds the instants, and one list beside
// it holds each variable's value at that index. A reply carries one table per period - hourly,
// daily, current, minutely_15, weekly, monthly - and each is declared as a series: "hour" is
// read a row at a time as an hour-long span, "day" as a date, "instant" as the one instant a
// current reading names. The variables are read from the table, so a variable this map has never
// heard of still becomes has-<its-name>; the documented lists name the ones a reply left out.
//
// Two annotations carry what the object cannot. '@' says when the fact holds: an hourly value is
// the hour that starts at its instant, so the fact spans that instant to the next one, and the
// last hour of a reply falls back to the instant alone rather than claiming an end it was not
// given. '~' carries the service's chance of precipitation, read as how confident the
// precipitation fact is: a 40% chance is 40% confidence that the hour's rain happens.
//
// The instant lives only in '@', not in the subject: a fact is known by its whole line, so two
// hours holding the same value are two facts, told apart by the span they cover. The subject is
// the place alone, which is what a question about the place can name.
//
// The forecast also declares what a question may ask it, so a session that holds a place's
// coordinates is answered with that place's weather rather than the reader: one fact per
// documented hourly variable, all asked in one request because the reply carries every variable
// it was asked for, and read back onto the place the question named. src/providers.ms collects
// the block; docs/api/open-meteo.md says what it means.
//
// Each endpoint names its own host, because the service spreads its surface over a dozen of
// them. The geocoder answers with a list of places rather than a table of readings, and the
// elevation endpoint with nothing but its heights, so those two carry their own reply shape.

build = function
	"Open-Meteo's twenty-three endpoints, as the writer reads them."

	// ── Parameters ──────────────────────────────────────────────────────
	latitude = {"name": "latitude", "type": "coordinates", "min": -90, "max": 90,
		"required": 1, "doc": "WGS84 latitude; a comma-separated list asks for several locations."}
	longitude = {"name": "longitude", "type": "coordinates", "min": -180, "max": 180,
		"required": 1, "doc": "WGS84 longitude; as many values as there are latitudes."}
	elevation = {"name": "elevation", "type": "coordinates", "min": -1000, "max": 9000,
		"allowNan": 1, "doc": "Elevation used for downscaling, or nan to disable downscaling."}
	tilt = {"name": "tilt", "type": "number", "min": 0, "max": 90, "allowNan": 1,
		"doc": "Panel tilt for global_tilted_irradiance, or nan for a tracker."}
	azimuth = {"name": "azimuth", "type": "number", "min": -180, "max": 180, "allowNan": 1,
		"doc": "Panel azimuth for global_tilted_irradiance, 0 south and negative east."}

	hourly = {"name": "hourly", "type": "csv", "doc": "Hourly variables, comma separated."}
	daily = {"name": "daily", "type": "csv", "doc": "Daily variables, comma separated."}
	dailyRequired = {"name": "daily", "type": "csv", "required": 1,
		"doc": "Daily variables, comma separated."}
	current = {"name": "current", "type": "csv",
		"doc": "Variables to report as current conditions."}
	minutely = {"name": "minutely_15", "type": "csv", "doc": "15-minutely variables."}
	weekly = {"name": "weekly", "type": "csv", "doc": "Weekly seasonal variables."}
	monthly = {"name": "monthly", "type": "csv", "doc": "Monthly seasonal variables."}

	temperatureUnit = {"name": "temperature_unit", "type": "enum",
		"values": ["celsius", "fahrenheit"], "doc": "Temperature unit."}
	windSpeedUnit = {"name": "wind_speed_unit", "type": "enum",
		"values": ["kmh", "ms", "mph", "kn"], "doc": "Wind speed unit."}
	precipitationUnit = {"name": "precipitation_unit", "type": "enum",
		"values": ["mm", "inch"], "doc": "Precipitation unit."}
	lengthUnit = {"name": "length_unit", "type": "enum", "values": ["metric", "imperial"],
		"doc": "Wave height unit."}

	timeformat = {"name": "timeformat", "type": "enum", "values": ["iso8601", "unixtime"],
		"doc": "Timestamp format."}
	timezone = {"name": "timezone", "type": "text",
		"doc": "Time zone name, or auto to resolve it from the coordinates."}

	pastDays = {"name": "past_days", "type": "int", "min": 0,
		"doc": "Days before today to include."}
	pastHours = {"name": "past_hours", "type": "int", "min": 1,
		"doc": "Hours before now to include."}
	forecastHours = {"name": "forecast_hours", "type": "int", "min": 1,
		"doc": "Hours from now to include."}
	pastMinutely = {"name": "past_minutely_15", "type": "int", "min": 1,
		"doc": "15-minute steps before now to include."}
	forecastMinutely = {"name": "forecast_minutely_15", "type": "int", "min": 1,
		"doc": "15-minute steps from now to include."}

	startDate = {"name": "start_date", "type": "date",
		"doc": "First day of the interval, yyyy-mm-dd."}
	endDate = {"name": "end_date", "type": "date", "doc": "Last day of the interval, yyyy-mm-dd."}
	startDateRequired = {"name": "start_date", "type": "date", "required": 1,
		"doc": "First day of the interval, yyyy-mm-dd."}
	endDateRequired = {"name": "end_date", "type": "date", "required": 1,
		"doc": "Last day of the interval, yyyy-mm-dd."}
	startHour = {"name": "start_hour", "type": "datetime",
		"doc": "First hour of the interval, yyyy-mm-ddThh:mm."}
	endHour = {"name": "end_hour", "type": "datetime",
		"doc": "Last hour of the interval, yyyy-mm-ddThh:mm."}
	startMinutely = {"name": "start_minutely_15", "type": "datetime",
		"doc": "First 15-minute step, yyyy-mm-ddThh:mm."}
	endMinutely = {"name": "end_minutely_15", "type": "datetime",
		"doc": "Last 15-minute step, yyyy-mm-ddThh:mm."}

	models = {"name": "models", "type": "csv",
		"doc": "Model names, comma separated; auto combines the best ones."}
	modelsRequired = {"name": "models", "type": "csv", "required": 1,
		"doc": "Model names, comma separated."}
	cell = {"name": "cell_selection", "type": "enum", "values": ["land", "sea", "nearest"],
		"doc": "Which grid cell to prefer."}
	temporalResolution = {"name": "temporal_resolution", "type": "text",
		"doc": "native, hourly, or a minute interval such as minutely_15."}
	ensemble = {"name": "ensemble", "type": "bool",
		"doc": "Return every forecast ensemble member."}
	domains = {"name": "domains", "type": "enum",
		"values": ["auto", "cams_europe", "cams_global"], "doc": "Air quality domain."}
	run = {"name": "run", "type": "datetime", "doc": "Model run to read, yyyy-mm-ddThh:mm."}
	runRequired = {"name": "run", "type": "datetime", "required": 1,
		"doc": "Model run to read, yyyy-mm-ddThh:mm."}

	format = {"name": "format", "type": "enum", "values": ["json", "csv", "xlsx"],
		"doc": "Reply format."}
	geocodingFormat = {"name": "format", "type": "enum", "values": ["json", "protobuf"],
		"doc": "Reply format."}
	apikey = {"name": "apikey", "type": "text",
		"doc": "Commercial API key; also read from OPEN_METEO_API_KEY."}

	placeName = {"name": "name", "type": "text", "required": 1,
		"doc": "Place name or postal code, optionally with a country after a comma."}
	count = {"name": "count", "type": "int", "min": 1, "max": 100,
		"doc": "Number of results, 1 to 100."}
	language = {"name": "language", "type": "text",
		"doc": "Language for the results, e.g. en, de, fr."}
	countryCode = {"name": "countryCode", "type": "text",
		"doc": "ISO 3166-1 alpha-2 country code to filter by."}
	locationId = {"name": "id", "type": "int", "required": 1,
		"doc": "Location id from a geocoding result."}

	forecastDays = function(maximum)
		"forecast_days, bounded by the endpoint's own maximum."
		return {"name": "forecast_days", "type": "int", "min": 0, "max": maximum,
			"doc": "Forecast days, 0 to " + maximum + "."}
	end function

	location = [latitude, longitude]
	variables = [hourly, daily, current, minutely]
	units = [temperatureUnit, windSpeedUnit, precipitationUnit]
	time = [timeformat, timezone]
	window = [pastDays, forecastDays(16), pastHours, forecastHours, pastMinutely, forecastMinutely]
	dates = [startDate, endDate, startHour, endHour, startMinutely, endMinutely]
	output = [format, apikey]
	modelSurface = location + [elevation] + variables + units + time + window + dates + output

	// ── Reply shapes ────────────────────────────────────────────────────
	// The documented variables of the forecast family; anything else the table carries is read
	// too, named from the variable itself.
	hourSeries = {"path": "$.hourly", "kind": "hour",
		"variables": ["temperature_2m", "relative_humidity_2m", "precipitation",
			"wind_speed_10m", "weather_code"]}
	daySeries = {"path": "$.daily", "kind": "day",
		"variables": ["temperature_2m_max", "sunrise"]}
	currentSeries = {"path": "$.current", "kind": "instant"}
	minutelySeries = {"path": "$.minutely_15", "kind": "minutely"}
	weekSeries = {"path": "$.weekly", "kind": "week"}
	monthSeries = {"path": "$.monthly", "kind": "month"}
	// A table of variables this map has no documented list for: read every one it carries.
	anyHour = {"path": "$.hourly", "kind": "hour"}
	anyDay = {"path": "$.daily", "kind": "day"}
	anyCurrent = {"path": "$.current", "kind": "instant"}

	weatherReply = function(series)
		return {
			"series": series,
			"refuse": {"when": "error", "is": true, "message": "reason"},
			"require": ["latitude", "longitude", "?place"],
			"subject": {"name": "reading", "from": ["?place"]},
			"request": ["place"],
		}
	end function

	weather = function(base, path, params, series)
		return {"method": "GET", "base": base, "path": path, "params": params,
			"key": "apikey", "redact": ["apikey"], "reply": weatherReply(series)}
	end function

	// A geocoder result is a place: its name is the subject, and the coordinates, country and
	// time zone are what the result says about it. The lookup answers with one such object.
	placeFacts = [
		["has-name", "?place", "$.name"],
		["has-latitude", "?place", "$.latitude as number"],
		["has-longitude", "?place", "$.longitude as number"],
		["has-elevation", "?place", "$.elevation as number"],
		["has-country-code", "?place", "$.country_code"],
		["has-country", "?place", "$.country"],
		["has-admin1", "?place", "$.admin1"],
		["has-timezone", "?place", "$.timezone"],
		["has-population", "?place", "$.population as number"],
		["has-feature-code", "?place", "$.feature_code"],
	]
	searchReply = {
		"each": "$.results",
		"refuse": {"when": "error", "is": true, "message": "reason"},
		"require": ["id", "name"],
		"subject": {"name": "place", "from": ["name"]},
		"request": ["name"],
		"facts": placeFacts + [["was-answer-to", "?place", "?name"]],
	}
	lookupReply = {
		"refuse": {"when": "error", "is": true, "message": "reason"},
		"require": ["id", "name"],
		"subject": {"name": "place", "from": ["name"]},
		"request": ["id"],
		"facts": placeFacts,
	}
	// The elevation endpoint answers with one height per point and nothing else; the point is
	// the caller's, so it comes from the request.
	elevationReply = {
		"each": "$.elevation",
		"eachMode": "array",
		"refuse": {"when": "error", "is": true, "message": "reason"},
		"require": ["?place"],
		"subject": {"name": "place", "from": ["?place"]},
		"request": ["place"],
		"facts": [["has-elevation", "?place", "$.elevation[i] as number"]],
	}

	// ── What a question may ask ─────────────────────────────────────────
	// A session holding a place's coordinates can be answered with that place's weather rather
	// than the reader. One declaration per documented hourly variable, all with the same
	// request: the reply carries every variable it was asked for, so the first weather fact a
	// question needs brings the rest, and the session's one-attempt memory reads that reply for
	// the others rather than asking again. The next hour alone is what is asked for, so each
	// variable has one reading to answer with. "about" says the reply is read onto the place the
	// question named - the reply names that place by nothing but the coordinates it was asked
	// with - and "from" names the facts those coordinates are filled from.
	weatherFacts = ["has-temperature-2m", "has-relative-humidity-2m", "has-precipitation",
		"has-wind-speed-10m", "has-weather-code"]
	weatherVariables = ["temperature_2m", "relative_humidity_2m", "precipitation",
		"wind_speed_10m", "weather_code"]
	weatherProvides = []
	for predicate in weatherFacts
		weatherProvides.push({
			"fact": [predicate, "?place", "?value"],
			"about": "?place",
			"from": {"latitude": "has-latitude", "longitude": "has-longitude"},
			"request": {"hourly": weatherVariables, "forecast_hours": 1},
		})
	end for
	forecast = weather("https://api.open-meteo.com", "/v1/forecast",
		location + [elevation, tilt, azimuth] + variables + units + time + window + dates +
			[models, cell] + output,
		[hourSeries, daySeries, currentSeries, minutelySeries])
	forecast.provides = weatherProvides

	return {
		"service": "open-meteo",
		"base": "https://api.open-meteo.com",
		"endpoints": {
			"forecast": forecast,
			"historical": weather("https://archive-api.open-meteo.com", "/v1/archive",
				location + [elevation, tilt, azimuth, startDateRequired, endDateRequired,
					hourly, daily] + units + time + [models, cell] + output,
				[hourSeries, daySeries]),
			"historical-forecast": weather("https://historical-forecast-api.open-meteo.com",
				"/v1/forecast",
				location + [elevation, startDateRequired, endDateRequired] + variables + units +
					time + [models, cell] + output,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"previous-runs": weather("https://previous-runs-api.open-meteo.com", "/v1/forecast",
				location + [elevation] + variables + units + time +
					[pastDays, forecastDays(16), run] + dates + [models, cell] + output,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"single-runs": weather("https://single-runs-api.open-meteo.com", "/v1/forecast",
				location + [elevation, runRequired] + variables + units + time +
					[models, cell] + output,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"ensemble": weather("https://ensemble-api.open-meteo.com", "/v1/ensemble",
				location + [elevation, tilt, azimuth, hourly, daily] + units + time +
					[pastDays, forecastDays(35)] + dates + [modelsRequired, cell] + output,
				[hourSeries, daySeries]),
			"seasonal": weather("https://seasonal-api.open-meteo.com", "/v1/seasonal",
				location + [elevation] + [hourly, daily, weekly, monthly] + units + time +
					[pastDays, forecastDays(210)] + dates + [models, cell] + output,
				[hourSeries, daySeries, weekSeries, monthSeries]),
			"climate": weather("https://climate-api.open-meteo.com", "/v1/climate",
				location + [startDateRequired, endDateRequired, dailyRequired, modelsRequired] +
					units + [cell] + output,
				[daySeries]),
			"marine": weather("https://marine-api.open-meteo.com", "/v1/marine",
				location + [hourly, daily, current] + [temperatureUnit, windSpeedUnit, lengthUnit] +
					time + [pastDays, forecastDays(8), pastHours, forecastHours] + dates +
					[cell] + output,
				[anyHour, anyDay, anyCurrent]),
			"air-quality": weather("https://air-quality-api.open-meteo.com", "/v1/air-quality",
				location + [hourly, current, domains] + time +
					[pastDays, forecastDays(7), pastHours, forecastHours] + dates + output,
				[anyHour, anyCurrent]),
			"flood": weather("https://flood-api.open-meteo.com", "/v1/flood",
				location + [daily] + time +
					[pastDays, forecastDays(210), startDate, endDate, ensemble, cell] + output,
				[anyDay]),
			"elevation": {"method": "GET", "base": "https://api.open-meteo.com",
				"path": "/v1/elevation", "params": location + [apikey],
				"key": "apikey", "redact": ["apikey"], "reply": elevationReply},
			"satellite": weather("https://satellite-api.open-meteo.com", "/v1/archive",
				location + [hourly, tilt, azimuth, models, temporalResolution, startDate, endDate,
					timeformat, timezone, format, apikey],
				[anyHour]),
			"geocoding": {"method": "GET", "base": "https://geocoding-api.open-meteo.com",
				"path": "/v1/search",
				"params": [placeName, count, geocodingFormat, language, countryCode, apikey],
				"key": "apikey", "redact": ["apikey"], "reply": searchReply},
			"geocoding-lookup": {"method": "GET", "base": "https://geocoding-api.open-meteo.com",
				"path": "/v1/get",
				"params": [locationId, geocodingFormat, language, apikey],
				"key": "apikey", "redact": ["apikey"], "reply": lookupReply},
			"dwd": weather("https://api.open-meteo.com", "/v1/dwd-icon", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"gfs": weather("https://api.open-meteo.com", "/v1/gfs", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"meteofrance": weather("https://api.open-meteo.com", "/v1/meteofrance", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"ecmwf": weather("https://api.open-meteo.com", "/v1/ecmwf", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"jma": weather("https://api.open-meteo.com", "/v1/jma", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"gem": weather("https://api.open-meteo.com", "/v1/gem", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"cma": weather("https://api.open-meteo.com", "/v1/cma", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
			"metno": weather("https://api.open-meteo.com", "/v1/metno", modelSurface,
				[hourSeries, daySeries, currentSeries, minutelySeries]),
		},
	}
end function
