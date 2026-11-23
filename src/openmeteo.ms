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
// The reply is read into the API layer's classes and printed from those: the grid point the
// answer came from, then one table per series - the instant, then each variable's value under
// its name and unit, with a dash for a gap. The geocoder prints a place per result and the
// elevation endpoint a height per point. --json prints the API's own JSON instead, --compact
// prints that on one line, and --url also prints the request that was made, with any key
// replaced. A refusal is reported on stdout with exit status 1.


import "cli/cli"
import "api/client"
import "api/openmeteo"
// Importing the loader puts the .env beside the runner into env.
import "dotenv"
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
	lines.push "instead. --json prints the API's own JSON rather than the summary, --compact"
	lines.push "prints that JSON on one line, and --url also shows the request."
	return lines.join(char(10))
end function


addSwitches = function(cmd)
	"The switches a run takes whatever the endpoint is."
	cli.add(cmd, {"name": "json", "aliases": ["--json"], "type": "flag",
		"description": "Print the API's own JSON instead of the summary."})
	cli.add(cmd, {"name": "url", "aliases": ["--url"], "type": "flag",
		"description": "Show the request that was made, with any key replaced."})
	cli.add(cmd, {"name": "compact", "aliases": ["--compact"], "type": "flag",
		"description": "Print the reply on one line, with --json."})
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


resolvePlace = function(name)
	"The coordinates of a place name: {ok, latitude, longitude, label} or {ok: 0, error}."
	quoted = char(34) + name + char(34)
	request = {"name": name, "count": 1}
	if apiKey != null then request.apikey = apiKey
	found = om.fetch(client, "geocoding", request)
	if not found.ok then
		return {"ok": 0, "error": "could not look up " + quoted + ": " + found.error}
	end if
	// The API layer read the geocoder's reply into its classes; this reads them.
	answer = found.reply
	if answer == null then
		return {"ok": 0, "error": "the geocoder's reply for " + quoted + " was not JSON"}
	end if
	if not answer.ok then
		return {"ok": 0, "error": "could not look up " + quoted + ": " + answer.error}
	end if
	// A name that matched nothing has no results key at all, which the classes call empty.
	if answer.isEmpty then
		return {"ok": 0, "error": "no place named " + quoted}
	end if
	place = answer.places[0]
	latitude = place.latitude
	longitude = place.longitude
	if latitude == null or longitude == null then
		return {"ok": 0, "error": "the geocoder gave no coordinates for " + quoted}
	end if
	return {"ok": 1, "latitude": latitude, "longitude": longitude, "label": place.label}
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

options = client.apiOptions(parsed.values, ["url", "compact", "place", "json"])
showUrl = parsed.values.url
compact = parsed.values.compact
// One line is still the JSON, so asking for one line asks for the JSON too.
showJson = parsed.values.json or compact

// The key comes from --apikey when it was given, otherwise the environment, where the loader
// has put the .env; either way the request reads it off the options.
apiKey = client.keyIn(options)
if apiKey == null then
	if env.hasIndex(om.keyName) then apiKey = env[om.keyName]
end if
if apiKey != null then options.apikey = apiKey


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


// ── The reply, as printed ────────────────────────────────────────────────────
// The classes say what a reply holds; these decide how it reads. A series is a table: its
// name and extent, a row naming each variable with its unit, then one row per instant with
// the values right-aligned under their names. A gap is a dash, because the service sends null
// for a reading a model does not carry.

valueText = function(value)
	"One value as the reply spelled it, or a dash for a gap in the series."
	if value isa null then return "-"
	if value isa string then return value
	return str(value)
end function


padLeft = function(text, width)
	"text at the right of a column of this width."
	if text.len >= width then return text
	return " " * (width - text.len) + text
end function


padRight = function(text, width)
	"text at the left of a column of this width."
	if text.len >= width then return text
	return text + " " * (width - text.len)
end function


showSeries = function(series)
	"Prints one table: its extent, a row of variables, then a row per instant."
	rows = series.rows
	names = series.variables
	if rows == 0 or names.len == 0 then return

	// Each column as wide as the wider of its heading and its values.
	columns = []
	for name in names
		heading = name
		unit = series.unit(name)
		// A timestamp's unit is iso8601, which the value already shows.
		if unit != "" and unit != "iso8601" then heading = heading + " " + unit
		width = heading.len
		for i in range(0, rows - 1)
			text = valueText(series.reading(name, i))
			if text.len > width then width = text.len
		end for
		columns.push {"name": name, "heading": heading, "width": width}
	end for

	instants = []
	instantWidth = 4
	for i in range(0, rows - 1)
		instant = series.instant(i)
		instants.push instant
		if instant.len > instantWidth then instantWidth = instant.len
	end for

	label = series.name
	if series.times.len > 0 then
		label = label + "  " + rows + " steps, " + instants[0] + " to " + instants[rows - 1]
	end if
	print label

	line = "  " + padRight("time", instantWidth)
	for column in columns
		line = line + "  " + padLeft(column.heading, column.width)
	end for
	print line

	for i in range(0, rows - 1)
		line = "  " + padRight(instants[i], instantWidth)
		for column in columns
			line = line + "  " + padLeft(valueText(series.reading(column.name, i)), column.width)
		end for
		print line
	end for
end function


showWeather = function(answer)
	"Prints the grid point the answer came from, then each table it holds."
	where = answer.coordinates
	if where != "" then
		line = where
		if answer.elevation != "" then line = line + "  " + answer.elevation
		if answer.timezone != "" then line = line + "  " + answer.timezone
		print line
	end if
	tables = answer.series
	for i in tables.indexes
		if i > 0 then print ""
		showSeries(tables[i])
	end for
end function


showPlaces = function(answer)
	"Prints a geocoder reply: a heading, then a name and its coordinates per place."
	if answer.isEmpty then
		print answer.emptyMessage
		return
	end if
	print answer.heading
	for i in answer.places.indexes
		place = answer.places[i]
		print "  " + (i + 1) + ". " + place.label
		where = place.coordinates
		if where != "" then print "     " + where
	end for
end function


showHeights = function(answer)
	"Prints the elevation endpoint's answer: one height per point asked about."
	heights = answer.heights
	if heights.len == 0 then
		print "The reply held no elevation."
		return
	end if
	print heights.len + " point" + "s" * (heights.len != 1) + ":"
	for i in heights.indexes
		print "  " + (i + 1) + ". " + valueText(heights[i]) + " m"
	end for
end function


showReply = function(answer)
	"Prints a reply the API layer read into classes, whichever shape it is."
	if answer isa om.MultiReply then
		for i in answer.replies.indexes
			if i > 0 then print ""
			showWeather(answer.replies[i])
		end for
	else if answer isa om.WeatherReply then
		showWeather(answer)
	else if answer isa om.GeocodingReply then
		showPlaces(answer)
	else if answer isa om.ElevationReply then
		showHeights(answer)
	end if
end function


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

if showJson then
	if result.json != null then
		print json.toJSON(result.json, compact)
	else
		print result.body
	end if
	exit 0
end if

// The API layer read the JSON into classes; this renders them. CSV, XLSX and protobuf are not
// JSON, so there is nothing to read and the body is the reply.
answer = result.reply
if answer == null then
	print result.body
	exit 0
end if
if not answer.ok then
	print "error: " + answer.error
	exit 1
end if

showReply(answer)
