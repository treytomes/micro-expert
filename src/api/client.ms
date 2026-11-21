// client.ms — the API layer for geocode.maps.co and Open-Meteo: one HTTP request path, one
// set of parameter checks, and an endpoint table for each service.
//
// It is one file because of how imports work here: a module imported by another module has
// its imports discarded, so a layer split across files could not reach its own transport.
// The sections below are the split the layer would have had.
//
//   1. Transport      query strings, curl, the HTTP status, JSON, .env settings
//   2. Parameters     names, types, ranges, required fields, one validator
//   3. geocode.maps.co   /search, /reverse, /lookup and every parameter each accepts
//   4. Open-Meteo     23 endpoints and every parameter each accepts
//   5. Arguments      one reading of --name value, --name=value and --no-name
//
// The Open-Meteo pages for UKMO, MeteoSwiss, KNMI, DMI, ItaliaMeteo, GeoSphere Austria and
// CHMI Aladin are model presets on the forecast endpoint (models=ukmo_seamless and so on),
// not endpoints of their own; so are the Ensemble Mean and Google WeatherNext pages. They
// are reached through the models parameter, which every forecast endpoint accepts.
//
// Both services answer with JSON by default, and every request returns the same map:
//
//   {"ok": 1, "status": 200, "body": "...", "json": {...}, "url": "...", "error": null}
//
// A refused request is ok: 0 with the HTTP status and, when the service sent one, its own
// "reason". Variable and model lists are passed through untouched: those are the parts the
// services extend without notice, and the layer should not be the reason one is missing.


import "json"
import "stringUtil"


// ══ 1. Transport ════════════════════════════════════════════════════════════

defaultTimeout = 60
statusMarker = "__http_status__"
quoteMark = char(34)
newline = char(10)
whitespace = " " + char(9) + char(10) + char(13)


trimText = function(text)
	"Strips leading and trailing whitespace."
	start = 0
	finish = text.len - 1
	while start <= finish
		if not whitespace.contains(text[start]) then break
		start = start + 1
	end while
	while finish >= start
		if not whitespace.contains(text[finish]) then break
		finish = finish - 1
	end while
	return text[start:finish + 1]
end function


quote = function(text)
	"Puts a pair of double quotes around text, so a shell reads it as one word."
	return quoteMark + text + quoteMark
end function


queryString = function(params)
	"Encodes an ordered parameter map as a query string. A list joins with commas."
	parts = []
	for kv in params
		value = kv.value
		if value == null then continue
		if value isa list then
			if value.len == 0 then continue
			value = value.join(",")
		end if
		value = str(value)
		if value == "" then continue
		parts.push kv.key.urlEncode + "=" + value.urlEncode
	end for
	return parts.join("&")
end function


urlFor = function(base, params)
	"base with the parameters appended, using whichever of ? or & it already needs."
	text = queryString(params)
	if text == "" then return base
	if base.indexOf("?") == null then return base + "?" + text
	return base + "&" + text
end function


redactUrl = function(url, names=[])
	"url with the values of the named parameters replaced, so a key can be shown."
	if names.len == 0 then return url
	cut = url.indexOf("?")
	if cut == null then return url
	pairs = url[cut + 1:].split("&")
	for i in pairs.indexes
		equals = pairs[i].indexOf("=")
		if equals == null then continue
		if names.indexOf(pairs[i][:equals]) != null then
			pairs[i] = pairs[i][:equals] + "=REDACTED"
		end if
	end for
	return url[:cut + 1] + pairs.join("&")
end function


get = function(url, timeout=null)
	"Runs one curl GET and answers ok, status, body, json, url and error."
	if timeout == null then timeout = defaultTimeout
	command = "curl -sS --max-time " + timeout
	// curl writes the status after the body, marked so a body full of newlines is safe.
	command = command + " -w " + quote(newline + statusMarker + "%{http_code}") + " " + quote(url)
	reply = exec(command, timeout + 10)

	result = {"ok": 0, "status": null, "body": "", "json": null, "url": url, "error": null}
	if reply isa error then
		result.error = "Could not run curl: " + reply.message
		return result
	end if
	if reply.status != 0 then
		message = trimText(reply.errors)
		if message == "" then message = "no message from curl"
		result.error = "The request failed (curl exit " + reply.status + "): " + message
		return result
	end if

	output = reply.output
	body = output
	if output.indexOf(statusMarker) != null then
		parts = output.split(statusMarker)
		body = parts[:parts.len - 1].join(statusMarker)
		result.status = val(trimText(parts[parts.len - 1]))
	end if
	if body.len > 0 then
		if body[-1] == newline then body = body[:body.len - 1]
	end if
	result.body = body

	parsed = json.parse(body)
	if not (parsed isa error) then result.json = parsed

	if result.status == null then
		result.error = "The reply did not include an HTTP status."
		return result
	end if
	if result.status < 200 or result.status >= 300 then
		// Both services send {"error": true, "reason": "..."} for a refused request; the
		// rest of the body is a fallback for anything that is not their JSON.
		detail = ""
		if parsed isa map then
			if parsed.hasIndex("reason") then
				if parsed.reason isa string then detail = parsed.reason
			end if
			if detail == "" then
				if parsed.hasIndex("error") then
					if parsed.error isa string then detail = parsed.error
				end if
			end if
		end if
		if detail == "" then
			text = trimText(body.replace(char(13), ""))
			if text != "" then detail = text[:200]
		end if
		message = "HTTP " + result.status
		if detail != "" then message = message + ": " + detail
		result.error = message
		return result
	end if

	result.ok = 1
	return result
end function


stripQuotes = function(value)
	"Removes one pair of matching quotes from a value read out of .env."
	if value.len >= 2 then
		mark = value[0]
		if mark == char(34) then
			if value[-1] == char(34) then return value[1:value.len - 1]
		else if mark == char(39) then
			if value[-1] == char(39) then return value[1:value.len - 1]
		end if
	end if
	return value
end function


readEnvFile = function(path)
	"Reads a .env's KEY=value lines; a missing or unreadable file is an empty map."
	lines = file.readLines(path)
	if lines isa error then return {}
	values = {}
	for line in lines
		if line.len > 0 then
			if line[-1] == char(13) then line = line[0:line.len - 1]
		end if
		line = trimText(line)
		if line.len == 0 then continue
		if line[0] == "#" then continue
		parts = line.split("=", 2)
		if parts.len < 2 then continue
		settingName = trimText(parts[0])
		if settingName.len > 0 then values[settingName] = stripQuotes(trimText(parts[1]))
	end for
	return values
end function


findSetting = function(settingName)
	"A setting from the environment first, then from the nearest .env; null when absent."
	if env.hasIndex(settingName) then
		value = trimText(env[settingName])
		if value != "" then return value
	end if
	// The runner lives beside its .env, so a script named by a path finds it one level up.
	// The working folder is tried as well, for a script named from where it stands.
	paths = [".env"]
	if shellArgs.len > 0 then
		scriptPath = shellArgs[0]
		hasFolder = scriptPath.indexOf("/") != null
		if not hasFolder then hasFolder = scriptPath.indexOf(char(92)) != null
		if hasFolder then paths.push(file.child(file.parent(scriptPath), "..") + "/.env")
	end if
	paths.push("../.env")
	for path in paths
		values = readEnvFile(path)
		if values.hasIndex(settingName) then
			value = trimText(values[settingName])
			if value != "" then return value
		end if
	end for
	return null
end function


// ══ 2. Parameters ═══════════════════════════════════════════════════════════
// An endpoint is a map with "params", a list of parameter specs. A spec is a map with
// "name" and "type", and optionally "min", "max", "values", "required", "default",
// "allowNan" and "doc". The types are:
//
//   text         any string
//   int          a whole number, within min and max when given
//   number       any number, within min and max when given
//   enum         one of values
//   bool         true/false, 1/0, yes/no, on/off
//   coordinates  a number or a comma-separated list of numbers, each within min and max
//   csv          a comma-separated list, given as a string or as a list
//   date         yyyy-mm-dd
//   datetime     yyyy-mm-ddThh:mm
//
// validate() turns a caller's options map into the parameters to send, in the order the
// caller gave them, and says what is wrong with the ones it cannot use. A name the table
// does not list is passed through untouched, because both services promise to add optional
// parameters and a layer that dropped one would quietly hide it.

// Options that belong to this layer or the programs, not to the remote API.
reservedKeys = ["apikey", "customer"]


normalKey = function(key)
	"Parameter names compare without dashes, underscores or case."
	return str(key).replace("_", "").replace("-", "").lower
end function


matchParam = function(spec, key)
	"The parameter spec a caller's name refers to, or null when the table has no such name."
	normal = normalKey(key)
	for paramSpec in spec.params
		if normalKey(paramSpec.name) == normal then return paramSpec
	end for
	return null
end function


rangeProblem = function(paramSpec, number)
	"null when the number is inside the spec's range, otherwise what is wrong."
	if paramSpec.hasIndex("min") then
		if number < paramSpec.min then return "must be at least " + paramSpec.min
	end if
	if paramSpec.hasIndex("max") then
		if number > paramSpec.max then return "must be at most " + paramSpec.max
	end if
	return null
end function


isDate = function(text)
	"True for yyyy-mm-dd."
	if text.len != 10 then return false
	if text[4] != "-" or text[7] != "-" then return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9]
		if "0123456789".indexOf(text[i]) == null then return false
	end for
	return true
end function


isHour = function(text)
	"True for yyyy-mm-ddThh:mm."
	if text.len != 16 then return false
	if text[4] != "-" or text[7] != "-" then return false
	if text[10] != "T" and text[10] != " " then return false
	if text[13] != ":" then return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15]
		if "0123456789".indexOf(text[i]) == null then return false
	end for
	return true
end function


coerce = function(paramSpec, value)
	"One value checked against one spec: {ok, value} or {ok: 0, problem}."
	kind = paramSpec.type

	if kind == "bool" then
		if value isa number then
			if value == 0 then return {"ok": 1, "value": "false"}
			return {"ok": 1, "value": "true"}
		end if
		text = str(value).lower
		if ["1", "true", "yes", "on"].indexOf(text) != null then return {"ok": 1, "value": "true"}
		if ["0", "false", "no", "off"].indexOf(text) != null then return {"ok": 1, "value": "false"}
		return {"ok": 0, "problem": "must be true or false"}
	end if

	if kind == "int" or kind == "number" then
		text = trimText(str(value))
		if not text.isNumeric then
			if kind == "int" then return {"ok": 0, "problem": "must be a whole number"}
			return {"ok": 0, "problem": "must be a number"}
		end if
		number = val(text)
		if kind == "int" then
			if floor(number) != number then return {"ok": 0, "problem": "must be a whole number"}
		end if
		problem = rangeProblem(paramSpec, number)
		if problem != null then return {"ok": 0, "problem": problem}
		return {"ok": 1, "value": str(number)}
	end if

	if kind == "enum" then
		text = str(value)
		if paramSpec.values.indexOf(text) == null then
			return {"ok": 0, "problem": "must be one of " + paramSpec.values.join(", ")}
		end if
		return {"ok": 1, "value": text}
	end if

	if kind == "coordinates" or kind == "csv" then
		items = value
		if not (value isa list) then items = str(value).split(",")
		if items.len == 0 then return {"ok": 0, "problem": "must not be empty"}
		clean = []
		for item in items
			text = trimText(str(item))
			if kind == "csv" then
				if text == "" then return {"ok": 0, "problem": "must not contain an empty value"}
				clean.push text
			else
				if text.lower == "nan" and paramSpec.hasIndex("allowNan") then
					clean.push "nan"
					continue
				end if
				if not text.isNumeric then
					return {"ok": 0, "problem": "must be a number or a comma-separated list of numbers"}
				end if
				number = val(text)
				problem = rangeProblem(paramSpec, number)
				if problem != null then return {"ok": 0, "problem": problem}
				clean.push str(number)
			end if
		end for
		return {"ok": 1, "value": clean.join(",")}
	end if

	if kind == "date" then
		text = trimText(str(value))
		if not isDate(text) then return {"ok": 0, "problem": "must be a date like 2026-11-21"}
		return {"ok": 1, "value": text}
	end if

	if kind == "datetime" then
		text = trimText(str(value))
		if not isHour(text) then return {"ok": 0, "problem": "must be a date and hour like 2026-11-21T12:00"}
		return {"ok": 1, "value": text}
	end if

	// text, and any type a table names that this file does not know: sent as it came.
	text = str(value)
	if text == "" then return {"ok": 0, "problem": "must not be empty"}
	return {"ok": 1, "value": text}
end function


validate = function(spec, options={})
	"{ok, params, problems}: options checked against the endpoint's parameter specs."
	sent = {}
	problems = []
	found = {}

	for kv in options
		normal = normalKey(kv.key)
		if reservedKeys.indexOf(normal) != null then continue
		paramSpec = matchParam(spec, kv.key)
		if paramSpec == null then
			if kv.value != null then sent[kv.key] = kv.value
			continue
		end if
		if kv.value == null then continue
		// Provided, even if it turns out to be wrong: one complaint is enough.
		found[paramSpec.name] = 1
		checked = coerce(paramSpec, kv.value)
		if not checked.ok then
			problems.push paramSpec.name + " " + checked.problem
			continue
		end if
		if sent.hasIndex(paramSpec.name) then
			// The same parameter twice is how several values are given on a command line.
			sent[paramSpec.name] = str(sent[paramSpec.name]) + "," + str(checked.value)
		else
			sent[paramSpec.name] = checked.value
		end if
	end for

	for paramSpec in spec.params
		if paramSpec.hasIndex("required") then
			if paramSpec.required then
				if not found.hasIndex(paramSpec.name) then
					problems.push paramSpec.name + " is required"
				end if
			end if
		end if
	end for

	return {"ok": problems.len == 0, "params": sent, "problems": problems}
end function


// ══ 3. geocode.maps.co ══════════════════════════════════════════════════════
// Three GET endpoints, each with its own parameters; the tables are the whole surface.

geocodeKeyName = "GEOCODE_MAPS_API_KEY"
geocodeBase = "https://geocode.maps.co"
geocodeFormats = ["json", "jsonv2", "xml", "geojson", "geocodejson"]

geocodeEndpoints = {
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
			{"name": "format", "type": "enum", "values": geocodeFormats, "default": "json", "doc": "Reply format."},
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
			{"name": "format", "type": "enum", "values": geocodeFormats, "default": "json", "doc": "Reply format."},
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
			{"name": "format", "type": "enum", "values": geocodeFormats, "default": "json", "doc": "Reply format."},
			{"name": "accept-language", "type": "text", "doc": "Language the names come back in."},
		],
	},
}


geocodeEndpointNames = function
	"The geocoding endpoint names the table holds."
	return geocodeEndpoints.indexes
end function


geocodeSpecFor = function(endpointName)
	"The endpoint's spec, or null when the table has no such endpoint."
	if not geocodeEndpoints.hasIndex(endpointName) then return null
	return geocodeEndpoints[endpointName]
end function


geocodeFindKey = function
	"The key from the environment first, then from the nearest .env."
	return findSetting(geocodeKeyName)
end function


geocodeFetch = function(endpointName, options={})
	"One request to a geocoding endpoint, with the key added and hidden from the url."
	spec = geocodeSpecFor(endpointName)
	if spec == null then
		return {"ok": 0, "status": null, "body": "", "json": null, "url": "", "error": "Unknown endpoint " + quote(endpointName) + "."}
	end if
	checked = validate(spec, options)
	if not checked.ok then
		return {"ok": 0, "status": null, "body": "", "json": null, "url": "", "error": "Invalid " + endpointName + " request: " + checked.problems.join("; ")}
	end if

	params = checked.params
	key = null
	for candidate in ["apiKey", "api_key", "apikey"]
		if options.hasIndex(candidate) then
			if key == null then key = options[candidate]
		end if
	end for
	if key == null then key = geocodeFindKey

	// The key travels as the api_key parameter, which the service accepts. The
	// Authorization header its documentation also names answers 401, so there is no
	// header path here to fall back to.
	if key != null then params.api_key = key

	url = urlFor(geocodeBase + spec.path, params)
	result = get(url)
	result.url = redactUrl(url, ["api_key"])
	return result
end function


geocodeSearch = function(options={})
	return geocodeFetch("search", options)
end function

geocodeReverse = function(options={})
	return geocodeFetch("reverse", options)
end function

geocodeLookup = function(options={})
	return geocodeFetch("lookup", options)
end function


// ══ 4. Open-Meteo ═══════════════════════════════════════════════════════════
// Each API is its own host and its own parameter list; the tables below are that surface.

openMeteoKeyName = "OPEN_METEO_API_KEY"

latitudeSpec = {"name": "latitude", "type": "coordinates", "min": -90, "max": 90, "required": 1,
	"doc": "WGS84 latitude; a comma-separated list asks for several locations."}
longitudeSpec = {"name": "longitude", "type": "coordinates", "min": -180, "max": 180, "required": 1,
	"doc": "WGS84 longitude; as many values as there are latitudes."}
elevationSpec = {"name": "elevation", "type": "coordinates", "min": -1000, "max": 9000, "allowNan": 1,
	"doc": "Elevation used for downscaling, or nan to disable downscaling."}
tiltSpec = {"name": "tilt", "type": "number", "min": 0, "max": 90, "allowNan": 1,
	"doc": "Panel tilt for global_tilted_irradiance, or nan for a tracker."}
azimuthSpec = {"name": "azimuth", "type": "number", "min": -180, "max": 180, "allowNan": 1,
	"doc": "Panel azimuth for global_tilted_irradiance, 0 south and negative east."}

hourlySpec = {"name": "hourly", "type": "csv", "doc": "Hourly variables, comma separated."}
dailySpec = {"name": "daily", "type": "csv", "doc": "Daily variables, comma separated."}
dailyRequiredSpec = {"name": "daily", "type": "csv", "required": 1, "doc": "Daily variables, comma separated."}
currentSpec = {"name": "current", "type": "csv", "doc": "Variables to report as current conditions."}
minutely15Spec = {"name": "minutely_15", "type": "csv", "doc": "15-minutely variables."}
weeklySpec = {"name": "weekly", "type": "csv", "doc": "Weekly seasonal variables."}
monthlySpec = {"name": "monthly", "type": "csv", "doc": "Monthly seasonal variables."}

temperatureUnitSpec = {"name": "temperature_unit", "type": "enum", "values": ["celsius", "fahrenheit"], "doc": "Temperature unit."}
windSpeedUnitSpec = {"name": "wind_speed_unit", "type": "enum", "values": ["kmh", "ms", "mph", "kn"], "doc": "Wind speed unit."}
precipitationUnitSpec = {"name": "precipitation_unit", "type": "enum", "values": ["mm", "inch"], "doc": "Precipitation unit."}
lengthUnitSpec = {"name": "length_unit", "type": "enum", "values": ["metric", "imperial"], "doc": "Wave height unit."}

timeformatSpec = {"name": "timeformat", "type": "enum", "values": ["iso8601", "unixtime"], "doc": "Timestamp format."}
timezoneSpec = {"name": "timezone", "type": "text", "doc": "Time zone name, or auto to resolve it from the coordinates."}

pastDaysSpec = {"name": "past_days", "type": "int", "min": 0, "doc": "Days before today to include."}
pastHoursSpec = {"name": "past_hours", "type": "int", "min": 1, "doc": "Hours before now to include."}
forecastHoursSpec = {"name": "forecast_hours", "type": "int", "min": 1, "doc": "Hours from now to include."}
pastMinutely15Spec = {"name": "past_minutely_15", "type": "int", "min": 1, "doc": "15-minute steps before now to include."}
forecastMinutely15Spec = {"name": "forecast_minutely_15", "type": "int", "min": 1, "doc": "15-minute steps from now to include."}

startDateSpec = {"name": "start_date", "type": "date", "doc": "First day of the interval, yyyy-mm-dd."}
endDateSpec = {"name": "end_date", "type": "date", "doc": "Last day of the interval, yyyy-mm-dd."}
startDateRequiredSpec = {"name": "start_date", "type": "date", "required": 1, "doc": "First day of the interval, yyyy-mm-dd."}
endDateRequiredSpec = {"name": "end_date", "type": "date", "required": 1, "doc": "Last day of the interval, yyyy-mm-dd."}
startHourSpec = {"name": "start_hour", "type": "datetime", "doc": "First hour of the interval, yyyy-mm-ddThh:mm."}
endHourSpec = {"name": "end_hour", "type": "datetime", "doc": "Last hour of the interval, yyyy-mm-ddThh:mm."}
startMinutely15Spec = {"name": "start_minutely_15", "type": "datetime", "doc": "First 15-minute step, yyyy-mm-ddThh:mm."}
endMinutely15Spec = {"name": "end_minutely_15", "type": "datetime", "doc": "Last 15-minute step, yyyy-mm-ddThh:mm."}

modelsSpec = {"name": "models", "type": "csv", "doc": "Model names, comma separated; auto combines the best ones."}
modelsRequiredSpec = {"name": "models", "type": "csv", "required": 1, "doc": "Model names, comma separated."}
cellSelectionSpec = {"name": "cell_selection", "type": "enum", "values": ["land", "sea", "nearest"], "doc": "Which grid cell to prefer."}
temporalResolutionSpec = {"name": "temporal_resolution", "type": "text", "doc": "native, hourly, or a minute interval such as minutely_15."}
ensembleSpec = {"name": "ensemble", "type": "bool", "doc": "Return every forecast ensemble member."}
domainsSpec = {"name": "domains", "type": "enum", "values": ["auto", "cams_europe", "cams_global"], "doc": "Air quality domain."}
runSpec = {"name": "run", "type": "datetime", "doc": "Model run to read, yyyy-mm-ddThh:mm."}
runRequiredSpec = {"name": "run", "type": "datetime", "required": 1, "doc": "Model run to read, yyyy-mm-ddThh:mm."}

formatSpec = {"name": "format", "type": "enum", "values": ["json", "csv", "xlsx"], "doc": "Reply format."}
geocodingFormatSpec = {"name": "format", "type": "enum", "values": ["json", "protobuf"], "doc": "Reply format."}
openMeteoKeySpec = {"name": "apikey", "type": "text", "doc": "Commercial API key; also read from OPEN_METEO_API_KEY."}

placeNameSpec = {"name": "name", "type": "text", "required": 1, "doc": "Place name or postal code, optionally with a country after a comma."}
countSpec = {"name": "count", "type": "int", "min": 1, "max": 100, "doc": "Number of results, 1 to 100."}
languageSpec = {"name": "language", "type": "text", "doc": "Language for the results, e.g. en, de, fr."}
countryCodeSpec = {"name": "countryCode", "type": "text", "doc": "ISO 3166-1 alpha-2 country code to filter by."}
locationIdSpec = {"name": "id", "type": "int", "required": 1, "doc": "Location id from a geocoding result."}


forecastDaysSpec = function(maximum)
	"forecast_days, bounded by the endpoint's own maximum."
	return {"name": "forecast_days", "type": "int", "min": 0, "max": maximum, "doc": "Forecast days, 0 to " + maximum + "."}
end function


locationParameters = [latitudeSpec, longitudeSpec]
variableParameters = [hourlySpec, dailySpec, currentSpec, minutely15Spec]
unitParameters = [temperatureUnitSpec, windSpeedUnitSpec, precipitationUnitSpec]
timeParameters = [timeformatSpec, timezoneSpec]
windowParameters = [pastDaysSpec, forecastDaysSpec(16), pastHoursSpec, forecastHoursSpec, pastMinutely15Spec, forecastMinutely15Spec]
dateParameters = [startDateSpec, endDateSpec, startHourSpec, endHourSpec, startMinutely15Spec, endMinutely15Spec]
outputParameters = [formatSpec, openMeteoKeySpec]

// What the per-model forecast endpoints take: the forecast surface without the model switch,
// because the host is the model.
modelSurface = locationParameters + [elevationSpec] + variableParameters + unitParameters + timeParameters + windowParameters + dateParameters + outputParameters

openMeteoEndpoints = {
	"forecast": {
		"host": "api.open-meteo.com",
		"path": "/v1/forecast",
		"doc": "Up to 16 days of forecast and 92 past days, combined from the best models.",
		"params": locationParameters + [elevationSpec, tiltSpec, azimuthSpec] + variableParameters + unitParameters + timeParameters + windowParameters + dateParameters + [modelsSpec, cellSelectionSpec] + outputParameters,
	},
	"historical": {
		"host": "archive-api.open-meteo.com",
		"path": "/v1/archive",
		"doc": "Reanalysis weather from 1940 up to a few days ago.",
		"params": locationParameters + [elevationSpec, tiltSpec, azimuthSpec, startDateRequiredSpec, endDateRequiredSpec, hourlySpec, dailySpec] + unitParameters + timeParameters + [modelsSpec, cellSelectionSpec] + outputParameters,
	},
	"historical-forecast": {
		"host": "historical-forecast-api.open-meteo.com",
		"path": "/v1/forecast",
		"doc": "Archived forecasts as they were issued, for a past interval.",
		"params": locationParameters + [elevationSpec, startDateRequiredSpec, endDateRequiredSpec] + variableParameters + unitParameters + timeParameters + [modelsSpec, cellSelectionSpec] + outputParameters,
	},
	"previous-runs": {
		"host": "previous-runs-api.open-meteo.com",
		"path": "/v1/forecast",
		"doc": "Earlier runs of the models, to compare a forecast with what came before it.",
		"params": locationParameters + [elevationSpec] + variableParameters + unitParameters + timeParameters + [pastDaysSpec, forecastDaysSpec(16), runSpec] + dateParameters + [modelsSpec, cellSelectionSpec] + outputParameters,
	},
	"single-runs": {
		"host": "single-runs-api.open-meteo.com",
		"path": "/v1/forecast",
		"doc": "One named model run; run is required.",
		"params": locationParameters + [elevationSpec, runRequiredSpec] + variableParameters + unitParameters + timeParameters + [modelsSpec, cellSelectionSpec] + outputParameters,
	},
	"ensemble": {
		"host": "ensemble-api.open-meteo.com",
		"path": "/v1/ensemble",
		"doc": "One forecast per ensemble member for up to 35 days; models is required.",
		"params": locationParameters + [elevationSpec, tiltSpec, azimuthSpec, hourlySpec, dailySpec] + unitParameters + timeParameters + [pastDaysSpec, forecastDaysSpec(35)] + dateParameters + [modelsRequiredSpec, cellSelectionSpec] + outputParameters,
	},
	"seasonal": {
		"host": "seasonal-api.open-meteo.com",
		"path": "/v1/seasonal",
		"doc": "Six-hourly seasonal forecast to seven months, with weekly and monthly summaries.",
		"params": locationParameters + [elevationSpec] + [hourlySpec, dailySpec, weeklySpec, monthlySpec] + unitParameters + timeParameters + [pastDaysSpec, forecastDaysSpec(210)] + dateParameters + [modelsSpec, cellSelectionSpec] + outputParameters,
	},
	"climate": {
		"host": "climate-api.open-meteo.com",
		"path": "/v1/climate",
		"doc": "Daily climate-model projections from 1950 to 2050.",
		"params": locationParameters + [startDateRequiredSpec, endDateRequiredSpec, dailyRequiredSpec, modelsRequiredSpec] + unitParameters + [cellSelectionSpec] + outputParameters,
	},
	"marine": {
		"host": "marine-api.open-meteo.com",
		"path": "/v1/marine",
		"doc": "Wave, swell, sea level, current and sea surface temperature forecasts.",
		"params": locationParameters + [hourlySpec, dailySpec, currentSpec] + [temperatureUnitSpec, windSpeedUnitSpec, lengthUnitSpec] + timeParameters + [pastDaysSpec, forecastDaysSpec(8), pastHoursSpec, forecastHoursSpec] + dateParameters + [cellSelectionSpec] + outputParameters,
	},
	"air-quality": {
		"host": "air-quality-api.open-meteo.com",
		"path": "/v1/air-quality",
		"doc": "CAMS pollutants, aerosols, UV index and pollen, European or global.",
		"params": locationParameters + [hourlySpec, currentSpec, domainsSpec] + timeParameters + [pastDaysSpec, forecastDaysSpec(7), pastHoursSpec, forecastHoursSpec] + dateParameters + outputParameters,
	},
	"flood": {
		"host": "flood-api.open-meteo.com",
		"path": "/v1/flood",
		"doc": "River discharge from 1984, with a seven-month ensemble forecast.",
		"params": locationParameters + [dailySpec] + timeParameters + [pastDaysSpec, forecastDaysSpec(210), startDateSpec, endDateSpec, ensembleSpec, cellSelectionSpec] + outputParameters,
	},
	"elevation": {
		"host": "api.open-meteo.com",
		"path": "/v1/elevation",
		"doc": "Terrain elevation from the 90-metre Copernicus DEM, up to 100 points.",
		"params": locationParameters + [openMeteoKeySpec],
	},
	"satellite": {
		"host": "satellite-api.open-meteo.com",
		"path": "/v1/archive",
		"doc": "Solar radiation from geostationary satellites, as an archive.",
		"params": locationParameters + [hourlySpec, tiltSpec, azimuthSpec, modelsSpec, temporalResolutionSpec, startDateSpec, endDateSpec, timeformatSpec, timezoneSpec, formatSpec, openMeteoKeySpec],
	},
	"geocoding": {
		"host": "geocoding-api.open-meteo.com",
		"path": "/v1/search",
		"doc": "Place names and postal codes to coordinates, time zone and population.",
		"params": [placeNameSpec, countSpec, geocodingFormatSpec, languageSpec, countryCodeSpec, openMeteoKeySpec],
	},
	"geocoding-lookup": {
		"host": "geocoding-api.open-meteo.com",
		"path": "/v1/get",
		"doc": "One location by the id a geocoding result gave.",
		"params": [locationIdSpec, geocodingFormatSpec, languageSpec, openMeteoKeySpec],
	},
	"dwd": {
		"host": "api.open-meteo.com",
		"path": "/v1/dwd-icon",
		"doc": "DWD ICON, the German model, on the forecast surface.",
		"params": modelSurface,
	},
	"gfs": {
		"host": "api.open-meteo.com",
		"path": "/v1/gfs",
		"doc": "NOAA GFS, the American model, on the forecast surface.",
		"params": modelSurface,
	},
	"meteofrance": {
		"host": "api.open-meteo.com",
		"path": "/v1/meteofrance",
		"doc": "Meteo-France AROME and ARPEGE on the forecast surface.",
		"params": modelSurface,
	},
	"ecmwf": {
		"host": "api.open-meteo.com",
		"path": "/v1/ecmwf",
		"doc": "ECMWF IFS and AIFS on the forecast surface.",
		"params": modelSurface,
	},
	"jma": {
		"host": "api.open-meteo.com",
		"path": "/v1/jma",
		"doc": "JMA, the Japanese model, on the forecast surface.",
		"params": modelSurface,
	},
	"gem": {
		"host": "api.open-meteo.com",
		"path": "/v1/gem",
		"doc": "GEM, the Canadian model, on the forecast surface.",
		"params": modelSurface,
	},
	"cma": {
		"host": "api.open-meteo.com",
		"path": "/v1/cma",
		"doc": "CMA, the Chinese model, on the forecast surface.",
		"params": modelSurface,
	},
	"metno": {
		"host": "api.open-meteo.com",
		"path": "/v1/metno",
		"doc": "MET Norway, the Nordic model, on the forecast surface.",
		"params": modelSurface,
	},
}


openMeteoEndpointNames = function
	"The Open-Meteo endpoint names the table holds."
	return openMeteoEndpoints.indexes
end function


openMeteoSpecFor = function(endpointName)
	"The endpoint's spec, or null when the table has no such endpoint."
	if not openMeteoEndpoints.hasIndex(endpointName) then return null
	return openMeteoEndpoints[endpointName]
end function


openMeteoFindKey = function
	"The commercial key, when the environment or the nearest .env has one."
	return findSetting(openMeteoKeyName)
end function


openMeteoFetch = function(endpointName, options={})
	"One request to an Open-Meteo endpoint, with the key added and hidden from the url."
	spec = openMeteoSpecFor(endpointName)
	if spec == null then
		return {"ok": 0, "status": null, "body": "", "json": null, "url": "", "error": "Unknown endpoint " + quote(endpointName) + "."}
	end if
	checked = validate(spec, options)
	if not checked.ok then
		return {"ok": 0, "status": null, "body": "", "json": null, "url": "", "error": "Invalid " + endpointName + " request: " + checked.problems.join("; ")}
	end if

	params = checked.params
	key = null
	for candidate in ["apiKey", "api_key", "apikey"]
		if options.hasIndex(candidate) then
			if key == null then key = options[candidate]
		end if
	end for
	if key == null then key = openMeteoFindKey
	if key != null then params.apikey = key

	// A commercial account is served from customer-<host>.
	commercial = 0
	if options.hasIndex("customer") then
		setting = coerce({"name": "customer", "type": "bool"}, options.customer)
		if setting.ok then commercial = (setting.value == "true")
	end if
	host = spec.host
	if commercial then host = "customer-" + host

	url = urlFor("https://" + host + spec.path, params)
	result = get(url)
	result.url = redactUrl(url, ["apikey"])
	return result
end function


// ══ 5. Arguments ════════════════════════════════════════════════════════════
// Both programs read their command line the same way: --name value, --name=value, a bare
// --name meaning true, --no-name meaning false, dashes or underscores in the name, and a
// name given twice collected so queryString can join it as a list. Anything else is a
// word, which each program interprets for itself.
//
// A program's own switches are named in the flags list, which keeps them out of the
// parameters: --url and --compact are not URL parameters, and must not be sent as ones.
// parseArguments answers {options, words, flags, problems}; flags is a map whose keys are
// the switches that were given, so a caller tests with hasIndex.

programArguments = function
	"The arguments after the program name, as a list."
	arguments = []
	if shellArgs.len > 1 then
		for i in range(1, shellArgs.len - 1)
			arguments.push shellArgs[i]
		end for
	end if
	return arguments
end function


asList = function(existing, value)
	"existing with value added, as a list either way."
	if existing isa list then
		existing.push value
		return existing
	end if
	return [existing, value]
end function


parseArguments = function(arguments, flags=[])
	"{options, words, flags, problems} read from a program's arguments."
	options = {}
	words = []
	chosen = {}
	problems = []
	i = 0
	while i < arguments.len
		argument = arguments[i]
		if argument[:2] == "--" then
			body = argument[2:]
			value = null
			equals = body.indexOf("=")
			if equals != null then
				value = body[equals + 1:]
				body = body[:equals]
			else if i + 1 < arguments.len then
				following = arguments[i + 1]
				if following[:2] != "--" then
					value = following
					i = i + 1
				end if
			end if
			if body == "" then
				problems.push "-- needs a parameter name"
			else if flags.indexOf(normalKey(body)) != null then
				if value == null then value = "true"
				chosen[normalKey(body)] = value
			else
				paramName = body.replace("-", "_")
				if paramName[:3] == "no_" and value == null then
					paramName = paramName[3:]
					value = "false"
				end if
				if value == null then value = "true"
				if options.hasIndex(paramName) then
					options[paramName] = asList(options[paramName], value)
				else
					options[paramName] = value
				end if
			end if
		else if argument == "-h" then
			chosen.help = "true"
		else
			words.push argument
		end if
		i = i + 1
	end while
	return {"options": options, "words": words, "flags": chosen, "problems": problems}
end function
