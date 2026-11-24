// openmeteo.ms — Open-Meteo's surface: its twenty-three endpoints, every parameter each one
// accepts, and the request that turns an options map into one call.
//
// The shared transport is handed in rather than imported, because this interpreter discards
// the imports of an imported module: a program imports api/client and this file, and calls
// fetch(api, ...) and surface(api) with that module's map. Nothing here touches the network by
// itself, and nothing here knows about a command line: what a reply says is read into the
// classes below, and the program lays them out.
//
// Each API is its own host and its own parameter list; the table below is that surface. The
// Open-Meteo pages for UKMO, MeteoSwiss, KNMI, DMI, ItaliaMeteo, GeoSphere Austria and CHMI
// Aladin are model presets on the forecast endpoint (models=ukmo_seamless and so on), not
// endpoints of their own; so are the Ensemble Mean and Google WeatherNext pages. They are
// reached through the models parameter, which every forecast endpoint accepts.


keyName = "OPEN_METEO_API_KEY"

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
accessKeySpec = {"name": "apikey", "type": "text", "doc": "Commercial API key; also read from OPEN_METEO_API_KEY."}

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
outputParameters = [formatSpec, accessKeySpec]

// What the per-model forecast endpoints take: the forecast surface without the model switch,
// because the host is the model.
modelSurface = locationParameters + [elevationSpec] + variableParameters + unitParameters + timeParameters + windowParameters + dateParameters + outputParameters

endpoints = {
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
		"params": locationParameters + [accessKeySpec],
	},
	"satellite": {
		"host": "satellite-api.open-meteo.com",
		"path": "/v1/archive",
		"doc": "Solar radiation from geostationary satellites, as an archive.",
		"params": locationParameters + [hourlySpec, tiltSpec, azimuthSpec, modelsSpec, temporalResolutionSpec, startDateSpec, endDateSpec, timeformatSpec, timezoneSpec, formatSpec, accessKeySpec],
	},
	"geocoding": {
		"host": "geocoding-api.open-meteo.com",
		"path": "/v1/search",
		"doc": "Place names and postal codes to coordinates, time zone and population.",
		"params": [placeNameSpec, countSpec, geocodingFormatSpec, languageSpec, countryCodeSpec, accessKeySpec],
	},
	"geocoding-lookup": {
		"host": "geocoding-api.open-meteo.com",
		"path": "/v1/get",
		"doc": "One location by the id a geocoding result gave.",
		"params": [locationIdSpec, geocodingFormatSpec, languageSpec, accessKeySpec],
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


// The endpoint names the table holds, in the order the table was written.
names = endpoints.indexes


specFor = function(endpointName)
	"The endpoint's spec, or null when the table has no such endpoint."
	if not endpoints.hasIndex(endpointName) then return null
	return endpoints[endpointName]
end function


surface = function(api)
	"Every endpoint's parameters, once each, for a command line read before one is named."
	specs = []
	for name in names
		specs.push endpoints[name]
	end for
	return api.unionSpec(specs)
end function


// ── The reply as classes ─────────────────────────────────────────────────────
// A reply comes in one of four shapes, and each has a class here. The forecast family - the
// forecast endpoint, the model hosts, marine, air quality, flood, climate, seasonal, satellite
// - answers with one place's metadata beside a table per period: hourly, daily, current,
// minutely_15, weekly, monthly. Several coordinates in one request make that a list of such
// replies. The geocoder answers with a list of places, or the one place a lookup asks for, and
// the elevation endpoint with nothing but its heights.
//
// A Series is one of those tables: a name list and one list per variable, the same index
// meaning the same instant, plus the units that came under it. A Place is one geocoder
// result. The reply classes hold them and answer what the reply says about itself. reply()
// turns the parsed JSON into them, and fetch puts one on the result it returns.
//
// Nothing here prints. The classes answer values and words, and the program lays them out.

// A geocoder result is the API layer's shared Place, built with the name it goes by and the
// country after it, so there is no class of its own to keep here.


Series = {}


Series.build = function(name, raw, units={})
	"One table of the reply: its name, its fields, and the unit of each field."
	series = new Series
	series.name = name
	series.raw = raw
	series.units = units
	return series
end function


Series.value = function(field)
	"The field the reply carried, or null when it carried none."
	if not self.raw.hasIndex(field) then return null
	return self.raw[field]
end function


Series.times = function
	"The instants it runs through, one per row; empty for a table of a single reading."
	times = self.value("time")
	if not (times isa list) then return []
	return times
end function


Series.variables = function
	"The names it holds a list for, in the order the reply wrote them."
	fields = []
	for field in self.raw.indexes
		if field == "time" then continue
		// current also carries the seconds it is read over, which is not a variable.
		if field == "interval" then continue
		fields.push field
	end for
	return fields
end function


Series.unit = function(field)
	"The unit the reply gave that field, empty when it gave none."
	if not self.units.hasIndex(field) then return ""
	return str(self.units[field])
end function


Series.rows = function
	"How many rows it has: one per instant, or one for a single reading."
	times = self.times
	if times.len > 0 then return times.len
	if self.variables.len > 0 then return 1
	return 0
end function


Series.instant = function(index)
	"The instant at one row: the time list's entry, or a single reading's own time."
	times = self.times
	if times.len > 0 then return str(times[index])
	value = self.value("time")
	if value isa string then return value
	return ""
end function


Series.reading = function(field, index)
	"One variable's value at one row, or null for a gap in the series."
	values = self.value(field)
	if values isa list then
		if index >= values.len then return null
		return values[index]
	end if
	// A current reading holds its values once rather than as a list.
	if index == 0 then return values
	return null
end function


Reply = {"ok": 1, "error": null}


WeatherReply = new Reply


WeatherReply.value = function(field)
	"The field the reply carried, or null when it carried none."
	if not self.raw.hasIndex(field) then return null
	return self.raw[field]
end function


WeatherReply.unitsFor = function(name)
	"The unit map that came under a table, when the reply sent one."
	units = self.value(name + "_units")
	if not (units isa map) then return {}
	return units
end function


WeatherReply.series = function
	"The tables it holds, in the order the reply wrote them."
	tables = []
	for field in self.raw.indexes
		if field.len > 6 then
			if field[field.len - 6:] == "_units" then continue
		end if
		value = self.raw[field]
		if not (value isa map) then continue
		tables.push Series.build(field, value, self.unitsFor(field))
	end for
	return tables
end function


WeatherReply.coordinates = function
	"The grid point the answer came from, which can differ from the one asked for."
	lat = self.value("latitude")
	lon = self.value("longitude")
	if lat == null or lon == null then return ""
	return str(lat) + ", " + str(lon)
end function


WeatherReply.elevation = function
	"The elevation used for downscaling in metres, empty when the reply gave none."
	value = self.value("elevation")
	if value == null then return ""
	return str(value) + " m"
end function


WeatherReply.timezone = function
	"The zone its timestamps are in, empty when the reply gave none."
	value = self.value("timezone")
	if not (value isa string) then return ""
	return value
end function


GeocodingReply = new Reply
GeocodingReply.query = ""


GeocodingReply.count = function
	"How many places the reply holds."
	return self.places.len
end function


GeocodingReply.isEmpty = function
	"True when it holds no places."
	return self.places.len == 0
end function


GeocodingReply.heading = function
	"The count, and the name that asked for it."
	text = self.count + " place" + "s" * (self.count != 1)
	if self.query != "" then text = text + " for " + char(34) + self.query + char(34)
	return text + ":"
end function


GeocodingReply.emptyMessage = function
	"What to say when no place matched."
	if self.query != "" then return "No place named " + char(34) + self.query + char(34) + "."
	return "No places."
end function


ElevationReply = new Reply


MultiReply = new Reply


reasonOf = function(json)
	"The refusal's reason as the word the service sent, or a stand-in when it sent none."
	if json.hasIndex("reason") then
		if json.reason isa string then return json.reason
	end if
	return "no reason given."
end function


refusedReply = function(message)
	"The reply a refusal, or a shape no endpoint documents, answers with."
	answer = new Reply
	answer.ok = 0
	answer.error = message
	return answer
end function


weatherReply = function(raw)
	"One place's series reply, as it came."
	answer = new WeatherReply
	answer.raw = raw
	return answer
end function


placeReply = function(places, asked={})
	"One reply holding the places it was given."
	answer = new GeocodingReply
	answer.places = places
	if asked.hasIndex("name") then answer.query = str(asked.name)
	return answer
end function


geocodingReply = function(api, raw, asked={})
	"A search's list of places; a name that matched nothing has no results key at all."
	places = []
	if raw.hasIndex("results") then
		if raw.results isa list then
			for item in raw.results
				if item isa map then places.push api.Place.build(item, ["name"], ["country"])
			end for
		end if
	end if
	return placeReply(places, asked)
end function


lookupReply = function(api, raw)
	"A lookup answers with the one place, in the same shape a search entry has."
	if not raw.hasIndex("latitude") then return placeReply([])
	return placeReply([api.Place.build(raw, ["name"], ["country"])])
end function


elevationReply = function(raw)
	"The elevation endpoint's bare list of heights, one per coordinate pair."
	answer = new ElevationReply
	answer.heights = []
	if raw.hasIndex("elevation") then
		if raw.elevation isa list then answer.heights = raw.elevation[:]
	end if
	return answer
end function


reply = function(api, endpointName, json, asked={})
	"The parsed JSON as one of the reply classes; null when there is no JSON to read."
	if json == null then return null

	if json isa list then
		// Several coordinates in one request: one series reply per location, in that order.
		answer = new MultiReply
		answer.replies = []
		for item in json
			if item isa map then answer.replies.push weatherReply(item)
		end for
		return answer
	end if
	if not (json isa map) then return refusedReply("The API returned an unexpected reply.")

	// A refusal is {reason, error: true}; client already reports the 4xx status it came with.
	if json.hasIndex("error") then
		if json.error then return refusedReply("The API refused the request: " + reasonOf(json))
	end if

	if endpointName == "geocoding" then return geocodingReply(api, json, asked)
	if endpointName == "geocoding-lookup" then return lookupReply(api, json)
	if endpointName == "elevation" then return elevationReply(json)
	return weatherReply(json)
end function


fetch = function(api, endpointName, options={})
	"One request to an Open-Meteo endpoint, with the key added and hidden from the url."
	spec = specFor(endpointName)
	if spec == null then
		return api.failure("Unknown endpoint " + api.quote(endpointName) + ".")
	end if
	checked = api.validate(spec, options)
	if not checked.ok then
		return api.failure("Invalid " + endpointName + " request: " + checked.problems.join("; "))
	end if

	params = checked.params
	key = api.keyIn(options)
	if key != null then params.apikey = key

	// A commercial account is served from customer-<host>.
	commercial = 0
	if options.hasIndex("customer") then
		setting = api.coerce({"name": "customer", "type": "bool"}, options.customer)
		if setting.ok then commercial = (setting.value == "true")
	end if
	host = spec.host
	if commercial then host = "customer-" + host

	url = api.urlFor("https://" + host + spec.path, params)
	result = api.get(url)
	result.url = api.redactUrl(url, ["apikey"])
	// The parsed JSON as the classes that describe it; null for CSV, XLSX and a failed request.
	result.reply = null
	if result.ok then result.reply = reply(api, endpointName, result.json, options)
	return result
end function
