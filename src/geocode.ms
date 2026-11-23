// geocode.ms — asks geocode.maps.co about a place, and prints what comes back.
//
// A standalone program, not part of the session: it reads GEOCODE_MAPS_API_KEY from the
// environment or from the .env beside the runner, asks one of the service's three endpoints,
// and prints the answer.
//
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms "Eiffel Tower"
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms Paris, Texas
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms reverse 48.8584 2.2945
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms lookup R253832,W175905
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms --json --limit 3 "Paris, Texas"
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms --help
//
// A bare query searches, so the first form and "search "Eiffel Tower"" mean the same thing;
// the other two subcommands name the other two endpoints. The words after the subcommand are
// joined with spaces for a search, and are a latitude and longitude or a list of OSM IDs
// otherwise. Every parameter the endpoints document is an option, with underscores or dashes
// in its name: --limit, --countrycodes, --zoom, --polygon-geojson, and so on. --help lists
// them all - generated from the same table the request is checked against - so a parameter
// that was misspelt is named rather than sent, and a value outside the range the table gives
// never leaves the program.
//
// Without --json, the reply is read into the API layer's classes - a Place per result, held
// by a SearchReply, a ReverseReply or a LookupReply - and printed from those: a name, then
// its coordinates and type. --json prints the API's own JSON instead. Errors go to stdout
// with a non-zero exit status: a missing key, nothing to search with, an option the parser
// cannot read, a failed request, or a reply that is not what the endpoint documents. The key
// is never printed - the URL is built and handed to curl, not shown.


import "cli/cli"
import "api/client"
import "api/geocode"
import "dotenv"
import "json"

cli = globals["cli/cli"]
client = globals["api/client"]
geo = globals["api/geocode"]
dotenv = globals["dotenv"]

scriptName = "geocode.ms"
if shellArgs.len > 0 then scriptName = file.name(shellArgs[0])

version = "1.0.0"


description = function
	"The lines under the command name in --help: which words name which endpoint."
	lines = []
	lines.push "Asks geocode.maps.co about a place, a coordinate or an OSM id."
	lines.push ""
	lines.push "  " + scriptName + " <place or address>                   search"
	lines.push "  " + scriptName + " reverse <latitude> <longitude>       reverse"
	lines.push "  " + scriptName + " lookup <R253832,W175905>             lookup"
	lines.push ""
	lines.push "The words after the endpoint are joined with spaces for a search. Every"
	lines.push "parameter the endpoints document is an option; a boolean is --name,"
	lines.push "--name false or --no-name, and --json prints the API's own JSON."
	return lines.join(char(10))
end function


cmd = cli.newCommand(scriptName, version, description())


refuse = function(message)
	"Reports a mistake and stops, pointing at the generated help."
	print "error: " + message
	print "Run " + cmd.name + " --help for usage."
	exit 1
end function


cli.add(cmd, {
	"name": "json",
	"aliases": ["--json"],
	"type": "flag",
	"description": "Print the API's own JSON instead of the summary.",
})

// The three endpoints' parameters, once each: a name one endpoint takes and another does
// not is still declared, because the words decide where the request goes. Required fields
// are left to the request, since reverse alone needs --lat and --lon.
surface = geo.surface(client)
client.addParameters(cli, cmd, surface, 0)


// ── One result ───────────────────────────────────────────────────────────────

showMatch = function(place, number=0)
	"Prints one result: its name, then its coordinates and type."
	prefix = "  "
	if number > 0 then prefix = "  " + number + ". "
	label = place.label
	if label == "" then label = "(no name)"
	print prefix + label
	where = place.coordinates
	if where != "" then
		text = "     " + where
		if place.typeName != "" then text = text + "  (" + place.typeName + ")"
		print text
	end if
end function


showReply = function(answer)
	"Prints a reply the API layer read into classes: a heading, then each result."
	if answer.isEmpty then
		print answer.emptyMessage
		return
	end if
	if answer.heading != "" then print answer.heading
	for i in answer.places.indexes
		number = 0
		if answer.numbered then number = i + 1
		showMatch(answer.places[i], number)
	end for
end function


// ── The question ─────────────────────────────────────────────────────────────

if shellArgs.len <= 1 then
	print cli.helpText(cmd)
	exit 1
end if

// cli reads the options; what it leaves over is the endpoint and the words after it.
split = client.splitArguments(cli, shellArgs, cmd, surface)
parsed = cli.parse(cmd, [shellArgs[0]] + split.options)

if parsed.help then
	print cli.helpText(cmd)
	exit 0
end if
if parsed.version then
	print cli.versionLine(cmd)
	exit 0
end if
if not parsed.ok then refuse(parsed.error)

showJson = parsed.values.json
options = client.apiOptions(parsed.values, ["json"])

mode = "search"
rest = split.words
if split.words.len > 0 then
	if ["search", "reverse", "lookup"].indexOf(split.words[0]) != null then
		mode = split.words[0]
		rest = split.words[1:]
	end if
end if

if mode == "search" then
	query = rest.join(" ")
	searchable = query != "" or options.hasIndex("q")
	for field in ["amenity", "street", "city", "county", "state", "country", "postalcode"]
		if options.hasIndex(field) then searchable = 1
	end for
	if not searchable then refuse("a search needs a place or address.")
	if query != "" and not options.hasIndex("q") then options.q = query
else if mode == "reverse" then
	if rest.len >= 2 then
		options.lat = rest[0]
		options.lon = rest[1]
	end if
	if not options.hasIndex("lat") or not options.hasIndex("lon") then refuse("reverse needs a latitude and a longitude.")
else if mode == "lookup" then
	if rest.len > 0 then options.osm_ids = rest.join(",")
	if not options.hasIndex("osm_ids") then refuse("lookup needs at least one OSM ID, such as R253832.")
end if

apiKey = dotenv.find(geo.keyName, shellArgs[0])
if apiKey == null then
	print "error: no " + geo.keyName + " found."
	print "Put it in the .env beside the runner, or export it, then try again."
	exit 1
end if
options.apiKey = apiKey


// ── The reply ────────────────────────────────────────────────────────────────

result = geo.fetch(client, mode, options)
if not result.ok then
	print result.error
	exit 1
end if

if showJson then
	if result.json != null then
		print json.toJSON(result.json)
	else
		print result.body
	end if
	exit 0
end if

if result.json == null then
	print "The reply was not JSON."
	exit 1
end if

// The API layer read the JSON into classes; this renders them.
answer = result.reply
if answer == null then
	print "The API returned an unexpected reply."
	exit 1
end if
if not answer.ok then
	print answer.error
	exit 1
end if

showReply(answer)
