// openmeteo.ms — Open-Meteo's surface: its twenty-three endpoints, every parameter each one
// accepts, and the request that turns an options map into one call.
//
// The shared transport is handed in rather than imported, because this interpreter discards
// the imports of an imported module: a program imports api/client and this file, and calls
// fetch(api, ...) and surface(api) with that module's map. Nothing here touches
// the network by itself, and nothing here knows about a command line.
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
	key = api.keyFrom(options, keyName)
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
	return result
end function
