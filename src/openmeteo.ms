// openmeteo.ms — asks Open-Meteo for data and prints the JSON it returns.
//
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms forecast --latitude 52.52 --longitude 13.41 --hourly temperature_2m
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms forecast --place Berlin --hourly temperature_2m
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms air-quality --latitude 52.52 --longitude 13.41 --hourly pm10
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms geocoding --name Berlin --count 3
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms endpoints
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms help forecast
//
// The first argument names an endpoint; every other argument is one of that endpoint's own
// URL parameters, spelled --name. Underscores and dashes are the same character here, so
// --forecast-days and --forecast_days both work, and a parameter given twice is sent as a
// comma-separated list:
//
//   ... forecast --latitude 52.52 --longitude 13.41 --hourly temperature_2m --hourly rain
//
// --place asks Open-Meteo's geocoding endpoint where a city is, and the latitude and
// longitude it answers with are sent in place of the pair, so a name works wherever
// coordinates do. It is resolved before the request and never sent as a parameter.
//
// The reply is printed as JSON, indented; --compact prints it on one line, and --url also
// prints the request that was made, with any key replaced. A refusal is reported on stdout
// with exit status 1, so a successful run is always the JSON the API sent.


import "api/client"
import "json"

client = globals["api/client"]

scriptName = "openmeteo.ms"
if shellArgs.len > 0 then scriptName = file.name(shellArgs[0])


usageText = function
	"The usage, with every endpoint and what it is for."
	lines = []
	lines.push "Usage: miniscript " + scriptName + " <endpoint> [--parameter value ...]"
	lines.push ""
	lines.push "Endpoints:"
	width = 0
	for name in client.openMeteoEndpointNames
		if name.len > width then width = name.len
	end for
	for name in client.openMeteoEndpointNames
		spec = client.openMeteoSpecFor(name)
		lines.push "  " + name + " " * (width - name.len + 2) + spec.doc
	end for
	lines.push ""
	lines.push "Parameters are the endpoint's own URL parameters, spelled --name with underscores"
	lines.push "or dashes; --name value, --name=value, and --no-name for a false flag all work,"
	lines.push "and a parameter given twice becomes a comma-separated list. --place <city> looks"
	lines.push "the city up first and sends its latitude and longitude instead. ""help <endpoint>"""
	lines.push "lists one endpoint's parameters. The reply is printed as JSON: --compact puts it"
	lines.push "on one line, and --url also shows the request."
	return lines.join(char(10))
end function


endpointText = function(name)
	"One endpoint's host, path and parameters."
	spec = client.openMeteoSpecFor(name)
	if spec == null then return "No endpoint named " + char(34) + name + char(34) + "."
	lines = []
	lines.push name + ": " + spec.doc
	lines.push "  GET https://" + spec.host + spec.path
	lines.push ""
	for paramSpec in spec.params
		note = paramSpec.type
		if paramSpec.hasIndex("values") then note = paramSpec.values.join("|")
		if paramSpec.hasIndex("min") then
			if paramSpec.hasIndex("max") then
				note = paramSpec.min + " to " + paramSpec.max
			else
				note = "at least " + paramSpec.min
			end if
		end if
		if paramSpec.hasIndex("default") then note = note + ", default " + paramSpec.default
		if paramSpec.hasIndex("required") then
			if paramSpec.required then note = "required"
		end if
		lines.push "  --" + paramSpec.name.replace("_", "-") + "  [" + note + "]"
		lines.push "      " + paramSpec.doc
	end for
	return lines.join(char(10))
end function


placeLabel = function(place)
	"A place's name, with its country when the geocoder gave one."
	label = ""
	if place.hasIndex("name") then
		if place.name isa string then label = place.name
	end if
	if label == "" then label = "(no name)"
	if place.hasIndex("country") then
		if place.country isa string then label = label + ", " + place.country
	end if
	return label
end function


resolvePlace = function(name)
	"The coordinates of a place name: {ok, latitude, longitude, label} or {ok: 0, error}."
	quoted = char(34) + name + char(34)
	found = client.openMeteoFetch("geocoding", {"name": name, "count": 1})
	if not found.ok then
		return {"ok": 0, "error": "could not look up " + quoted + ": " + found.error}
	end if
	reply = found.json
	if not (reply isa map) then
		return {"ok": 0, "error": "the geocoder's reply for " + quoted + " was not JSON"}
	end if
	// No matches comes back as an error body rather than an empty list, so both count.
	if not reply.hasIndex("results") then
		return {"ok": 0, "error": "no place named " + quoted}
	end if
	results = reply.results
	if not (results isa list) then
		return {"ok": 0, "error": "the geocoder's reply for " + quoted + " was not what the API documents"}
	end if
	if results.len == 0 then
		return {"ok": 0, "error": "no place named " + quoted}
	end if
	place = results[0]
	if not (place isa map) then
		return {"ok": 0, "error": "the geocoder's reply for " + quoted + " was not what the API documents"}
	end if
	if not place.hasIndex("latitude") or not place.hasIndex("longitude") then
		return {"ok": 0, "error": "the geocoder gave no coordinates for " + quoted}
	end if
	return {"ok": 1, "latitude": place.latitude, "longitude": place.longitude, "label": placeLabel(place)}
end function


// ── The arguments ────────────────────────────────────────────────────────────

arguments = client.programArguments

if arguments.len == 0 then
	print usageText
	exit 1
end if

endpoint = arguments[0]

if endpoint == "endpoints" then
	for name in client.openMeteoEndpointNames
		print name
	end for
	exit 0
end if

if endpoint == "help" or endpoint == "--help" or endpoint == "-h" then
	if arguments.len > 1 then
		print endpointText(arguments[1])
	else
		print usageText
	end if
	exit 0
end if

if client.openMeteoSpecFor(endpoint) == null then
	print "error: unknown endpoint " + char(34) + endpoint + char(34)
	print usageText
	exit 1
end if


// ── The parameters ───────────────────────────────────────────────────────────

rest = []
if arguments.len > 1 then rest = arguments[1:]
parsed = client.parseArguments(rest, ["url", "compact", "help"])
problems = parsed.problems
for word in parsed.words
	problems.push "unexpected argument " + char(34) + word + char(34)
end for
if problems.len > 0 then
	for problem in problems
		print "error: " + problem
	end for
	exit 1
end if
if parsed.flags.hasIndex("help") then
	print endpointText(endpoint)
	exit 0
end if

options = parsed.options
showUrl = parsed.flags.hasIndex("url")
compact = parsed.flags.hasIndex("compact")


// ── The place ────────────────────────────────────────────────────────────────

resolvedPlace = null
if options.hasIndex("place") then
	placeName = options.place
	options.remove("place")
	if client.matchParam(client.openMeteoSpecFor(endpoint), "latitude") == null then
		print "error: " + endpoint + " takes no coordinates, so --place does not apply"
		exit 1
	end if
	if options.hasIndex("latitude") or options.hasIndex("longitude") then
		print "error: give --place or --latitude and --longitude, not both"
		exit 1
	end if
	found = resolvePlace(placeName)
	if not found.ok then
		print "error: " + found.error
		exit 1
	end if
	options.latitude = found.latitude
	options.longitude = found.longitude
	resolvedPlace = found
end if


// ── The answer ───────────────────────────────────────────────────────────────

result = client.openMeteoFetch(endpoint, options)

if showUrl then
	if resolvedPlace != null then
		first = "resolved " + char(34) + resolvedPlace.label + char(34) + " to "
		print first + resolvedPlace.latitude + ", " + resolvedPlace.longitude
	end if
	if result.url != "" then print result.url
end if

if not result.ok then
	print "error: " + result.error
	exit 1
end if

if result.json != null then
	print json.toJSON(result.json, compact)
else
	print result.body
end if
