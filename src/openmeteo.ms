// openmeteo.ms — asks Open-Meteo for data and prints the JSON it returns.
//
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms forecast --latitude 52.52 --longitude 13.41 --hourly temperature_2m
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms forecast --place Berlin --hourly temperature_2m
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms air-quality --latitude 52.52 --longitude 13.41 --hourly pm10
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms geocoding --name Berlin --count 3
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms endpoints
//   ./3rd-party/miniscript-linux/miniscript src/openmeteo.ms forecast --help
//
// The first word names an endpoint; every other argument is one of that endpoint's own URL
// parameters, declared from the service's table, so the command line and the request are
// checked against the same list:
//
//   ... forecast --latitude 52.52 --longitude 13.41 --hourly temperature_2m --hourly rain
//
// Underscores and dashes are the same character in a name, a boolean is --name, --name false
// or --no-name, and a parameter given twice is sent as a comma-separated list. A parameter
// the endpoint does not take is refused by name, and so is a value outside the range or not
// among the values the table gives. --help after the endpoint lists what that endpoint takes;
// before it, --help lists the endpoints.
//
// --place asks Open-Meteo's geocoding endpoint where a city is, and the latitude and
// longitude it answers with are sent in place of the pair, so a name works wherever
// coordinates do. It is resolved before the request and never sent as a parameter.
//
// The reply is printed as JSON, indented; --compact prints it on one line, and --url also
// prints the request that was made, with any key replaced. A refusal is reported on stdout
// with exit status 1, so a successful run is always the JSON the API sent.


import "cli/cli"
import "api/client"
import "api/openmeteo"
import "json"

cli = globals["cli/cli"]
client = globals["api/client"]
om = globals["api/openmeteo"]

scriptName = "openmeteo.ms"
if shellArgs.len > 0 then scriptName = file.name(shellArgs[0])

version = "1.0.0"


usageText = function
	"The endpoints there are, and how the arguments work, for a run that names none."
	lines = []
	lines.push "Usage: miniscript " + scriptName + " <endpoint> [--parameter value ...]"
	lines.push "       miniscript " + scriptName + " endpoints"
	lines.push "       miniscript " + scriptName + " <endpoint> --help"
	lines.push ""
	lines.push "Endpoints:"
	width = 0
	for name in om.names
		if name.len > width then width = name.len
	end for
	for name in om.names
		spec = om.specFor(name)
		lines.push "  " + name + " " * (width - name.len + 2) + spec.doc
	end for
	lines.push ""
	lines.push "A parameter is the endpoint's own URL parameter, spelled --name value or"
	lines.push "--name=value, with underscores or dashes in the name. A parameter given twice"
	lines.push "becomes a comma-separated list, a boolean is --name, --name false or --no-name,"
	lines.push "and a value the endpoint's table refuses is reported before the request is made."
	lines.push "--place <city> looks the city up first and sends its latitude and longitude"
	lines.push "instead. --url also shows the request, and --compact prints the reply on one line."
	return lines.join(char(10))
end function


addSwitches = function(cmd)
	"The switches a run takes whatever the endpoint is."
	cli.add(cmd, {"name": "url", "aliases": ["--url"], "type": "flag",
		"description": "Show the request that was made, with any key replaced."})
	cli.add(cmd, {"name": "compact", "aliases": ["--compact"], "type": "flag",
		"description": "Print the reply on one line."})
	cli.add(cmd, {"name": "place", "aliases": ["--place"], "type": "string",
		"description": "A place name to look up and send as its coordinates."})
	return cmd
end function


commandFor = function(endpointName)
	"One endpoint's command: its host and path, its parameters, and the switches."
	spec = om.specFor(endpointName)
	header = spec.doc + char(10) + "GET https://" + spec.host + spec.path
	cmd = cli.newCommand(scriptName + " " + endpointName, version, header)
	client.addParameters(cli, cmd, spec)
	addSwitches(cmd)
	return cmd
end function


// Every endpoint's parameters at once, to read the words before an endpoint is named. The
// merged list is built once, since both the command and the split read it.
surface = om.surface(client)


surfaceCommand = function
	"One command holding every parameter, for the command line before an endpoint is named."
	cmd = cli.newCommand(scriptName, version, "Asks Open-Meteo for data.")
	client.addParameters(cli, cmd, surface, 0)
	addSwitches(cmd)
	return cmd
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
	found = om.fetch(client, "geocoding", {"name": name, "count": 1})
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


// ── The endpoint ─────────────────────────────────────────────────────────────

if shellArgs.len <= 1 then
	print usageText
	exit 1
end if

// The words come first: the endpoint is named before its parameters can be declared.
surfaceCmd = surfaceCommand()
split = client.splitArguments(cli, shellArgs, surfaceCmd, surface)
words = split.words
argumentText = [shellArgs[0]] + split.options

if words.len == 0 then
	// Nothing names an endpoint, so there is nothing to declare but the switches.
	parsed = cli.parse(surfaceCmd, argumentText)
	if parsed.version then
		print cli.versionLine(surfaceCmd)
		exit 0
	end if
	print usageText
	if parsed.help then exit 0
	exit 1
end if

endpoint = words[0]

if endpoint == "endpoints" then
	for name in om.names
		print name
	end for
	exit 0
end if

if endpoint == "help" then
	if words.len > 1 then
		if om.specFor(words[1]) == null then
			print "error: unknown endpoint " + char(34) + words[1] + char(34)
			exit 1
		end if
		print cli.helpText(commandFor(words[1]))
	else
		print usageText
	end if
	exit 0
end if

if om.specFor(endpoint) == null then
	print "error: unknown endpoint " + char(34) + endpoint + char(34)
	print usageText
	exit 1
end if


// ── The parameters ───────────────────────────────────────────────────────────

cmd = commandFor(endpoint)
parsed = cli.parse(cmd, argumentText)

if parsed.version then
	print cli.versionLine(cmd)
	exit 0
end if
if parsed.help then
	print cli.helpText(cmd)
	exit 0
end if
if not parsed.ok then
	print "error: " + parsed.error
	print "Run " + cmd.name + " --help for usage."
	exit 1
end if
// The library has read every option; a second word is one with nothing to belong to.
if words.len > 1 then
	print "error: unexpected argument " + char(34) + words[1] + char(34)
	print "Run " + cmd.name + " --help for usage."
	exit 1
end if

options = client.apiOptions(parsed.values, ["url", "compact", "place"])
showUrl = parsed.values.url
compact = parsed.values.compact


// ── The place ────────────────────────────────────────────────────────────────

resolvedPlace = null
if parsed.values.place != null then
	placeName = parsed.values.place
	if client.matchParam(om.specFor(endpoint), "latitude") == null then
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

result = om.fetch(client, endpoint, options)

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
