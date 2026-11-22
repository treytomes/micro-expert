# The Open-Meteo API surface

Open-Meteo is not one API but a family of them. Each forecast product has its own host, the
domain APIs - marine, air quality, flood, climate, seasonal, satellite - add more, and the
geocoder is a separate service that shares the parameter style. `src/api/openmeteo.ms` holds
the layer's table of them: 23 endpoints, each with its host, path and the complete set of
query parameters it accepts. The program, `src/openmeteo.ms`, turns that table into a command
line.

This document writes the table out: the shape of a request, the shape of a reply, every
endpoint with the parameters it takes, and a reference for what each parameter means. The
per-endpoint lists name every parameter the table holds, in its order; the reference holds the
types, ranges and meanings that are the same wherever they appear.

## The request

```
GET https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.41&hourly=temperature_2m
```

- `latitude` and `longitude` are required everywhere except the two geocoding endpoints, and
  are sent as a comma-separated list for several locations at once, with as many longitudes
  as latitudes. The reply then holds a list where a single location has an object.
- A list-valued parameter - `hourly`, `daily`, `models`, `elevation` - is one comma-separated
  value. Repeating it on the command line is the same thing: the layer joins the repeats with
  commas.
- Units and formats default to the service's: `celsius`, `kmh`, `mm`, `iso8601` and the `GMT`
  time zone. `timezone=auto` resolves the zone from the coordinates instead.
- A commercial key travels as `apikey`: `--apikey` when it is given, otherwise
  `OPEN_METEO_API_KEY` from the environment or the nearest `.env`, which the program reads and
  passes with every request. `customer=1` moves the request to the
  `customer-` host, `customer-api.open-meteo.com` and the like, which is where a commercial
  account is served. `customer` is the layer's own switch, not a URL parameter.
- `format` is `json`, `csv` or `xlsx`; the geocoder takes `json` or `protobuf`. CSV and XLSX
  are not JSON, so the layer's `json` field is `null` for them and the program prints the body.
- A parameter the table does not list is passed through untouched. Open-Meteo extends its
  variables and models without notice, and the layer is not the place to drop one.

## The reply

A successful reply is JSON. The forecast family opens with where the answer is about and how
it was made:

```json
{
  "latitude": 52.512604,
  "longitude": 13.419517,
  "generationtime_ms": 0.0424,
  "utc_offset_seconds": 0,
  "timezone": "GMT",
  "timezone_abbreviation": "GMT",
  "elevation": 38.0,
  "hourly_units": {"time": "iso8601", "temperature_2m": "°C"},
  "hourly": {"time": ["2026-11-22T00:00", "2026-11-22T01:00", "…"], "temperature_2m": [4.1, 3.8, "…"]}
}
```

| Field | Meaning |
| --- | --- |
| `latitude`, `longitude` | The grid point the answer actually came from, which can differ from the one asked for. |
| `elevation` | The elevation used for downscaling, in metres. |
| `generationtime_ms` | How long the service took. |
| `timezone`, `timezone_abbreviation`, `utc_offset_seconds` | The zone the timestamps are in. |
| `hourly`, `daily`, `current`, `minutely_15`, `weekly`, `monthly` | One object per series that was asked for, with a `time` list and one list per variable. |
| `hourly_units`, `daily_units`, `current_units`, … | The unit of each variable above it, plus `iso8601` or `unixtime` for `time`. |

Only the series that was requested appear. An ensemble endpoint returns one list per member,
named `temperature_2m_member01`, `temperature_2m_member02` and so on, up to the model's member
count; the ensemble mean is `temperature_2m`. The domain APIs keep the same envelope for
their own variables, and `climate` and `flood` answer in `daily`.

The geocoder answers with a list and a timing, and nothing else:

```json
{
  "results": [
    {"id": 2950159, "name": "Berlin", "latitude": 52.52437, "longitude": 13.41053,
     "elevation": 74.0, "feature_code": "PPLC", "country_code": "DE", "timezone": "Europe/Berlin",
     "population": 3426354, "postcodes": ["10967", "13347"], "country": "Germany",
     "admin1": "State of Berlin", "admin2": "…", "admin3": "Berlin, Stadt", "admin4": "Berlin"}
  ],
  "generationtime_ms": 0.2186
}
```

A name that matches nothing has no `results` key at all, only `generationtime_ms` - not an
empty list - which is why the programs test for the key rather than for a length.
`admin2` and the lower-level names appear when the place has them; `country_id`, `admin1_id`
and the rest are given so a result can be looked up again.

`/v1/elevation` is the one reply that is nothing but its answer:

```json
{"elevation": [38.0]}
```

### Refusals

A refused request is a 4xx status with the reason beside the flag:

```json
{"reason": "Latitude must be in range of -90 to 90°. Given: 999.0.", "error": true}
```

The layer turns that into `ok: 0` and an error of `HTTP 400: Latitude must be in range of
-90 to 90°. Given: 999.0.`, and the program prints it and exits `1`. The layer catches the
ranges it knows before sending, so its own message names the parameter instead - `latitude
must be at most 90` - and no request is made.

## The reply as triples

The geocoder's reply converts to facts almost as it stands, because a result is one object with a
dozen properties. A weather reply is the same kind of thing - JSON, one object, named fields - with
one difference that decides everything below: a geocoder result is about one object, and a forecast
reply is about one place at a series of instants. The place has no id, the instants are a list
beside the values, and a fact holds exactly two fields. What follows is the vocabulary that
survives that, the rules it supports, and the parts of a reply that a triple cannot hold.

### The subject

The reply names no object. There is no OSM id and no `place_id` - only `latitude` and `longitude`,
and those are the grid cell the answer was computed on rather than the coordinate that was asked
for: the example above asked for `52.52, 13.41` and was answered from `52.512604, 13.419517`. A cell
is not an identity. Requests round onto it differently, a model's grid moves between versions, two
neighbours can share a cell, and the marine endpoints answer from the nearest *sea* point, so a
coastal coordinate can be answered from offshore.

So the place gets a name, chosen once by whatever writes the facts, and everything about the place
attaches to it:

```prolog
has-name(berlin, Berlin)
has-latitude(berlin, 52.52437)
has-longitude(berlin, 13.41053)
has-geonames-id(berlin, 2950159)
has-country-code(berlin, DE)
```

`berlin` is a choice rather than a derivation, and that is all right: a term does not have to be an
id as long as the facts about it say what it is. The geocoder's `id` is the handle worth carrying -
`2950159` is the GeoNames id, not something Open-Meteo invented - because `geocoding-lookup` takes
it back and other data names the same place by it. It sits in a fact rather than in the subject
only because a forecast reply never carries it.

A reading then needs two things at once, the place and the instant, and the object of a fact holds
neither: the object is the value. Both go in the subject, joined by `@`:

```prolog
has-temperature-2m(berlin@2026-11-22T00:00, 4.1)
```

`@`, `T` and `:` are ordinary characters in a text field, so the term is legal, and it has the
property that matters most here: every variable read at one instant shares one subject, so a rule
needs no second variable to say "the same hour". What it does not have is a way back. Nothing
splits `berlin@2026-11-22T00:00` into its two halves, so anything that has to compare or join on one
half - the same instant in another city, everything about one place - needs that half written as a
fact of its own, as `has-instant` below.

The grid point is a fact about the answer rather than about the place, so it gets its own predicates
and leaves `has-latitude` to the geocoder:

| Predicate | Comes from | Field types |
| --- | --- | --- |
| `has-name(?p, Berlin)` | geocoding `results[].name` | `text, text` |
| `has-latitude(?p, 52.52437)`, `has-longitude(?p, 13.41053)` | geocoding `latitude`, `longitude` | `text, unique(number)` |
| `has-geonames-id(?p, 2950159)` | geocoding `id` | `text, unique(number)` |
| `has-country-code(?p, DE)`, `has-country(?p, Germany)` | geocoding `country_code`, `country` | `text, unique(text)` |
| `has-population(?p, 3426354)` | geocoding `population` | `text, unique(number)` |
| `has-feature-code(?p, PPLC)` | geocoding `feature_code` | `text, text` |
| `has-grid-latitude(?p, 52.512604)`, `has-grid-longitude(?p, 13.419517)` | the reply's `latitude`, `longitude` | `text, unique(number)` |
| `has-elevation(?p, 38)` | the reply's `elevation` | `text, unique(number)` |
| `has-timezone(?p, GMT)` | the reply's `timezone`, with `timezone=auto` | `text, unique(text)` |
| `has-utc-offset(?p@instant, 3600)` | the reply's `utc_offset_seconds` | `text, unique(number)` |

Only the last line needs the instant, and only when `timezone=auto` asks for local timestamps: the
zone is a property of the place, and how far it is from UTC is a property of the place on that
date, because the offset moves twice a year.

Five of those spellings are the geocoder's, not this service's - `has-name`, `has-latitude`,
`has-longitude`, `has-country` and `has-country-code` - written here exactly as they are on its
page on purpose, and with the same field types, so a folder holding both a search result and a
forecast reads one schema line and one rule for a place rather than two with a suffix on one.
`has-geonames-id`, `has-grid-latitude`, `has-elevation`, `has-timezone` and `has-utc-offset` are
this page's own. The subject is where the two pages differ: the geocoder writes an OSM object, and
this page a name the writer chose, so the shared predicates only join two files when the writer
gives one place one term in both - the OSM object where the geocoder knows it, otherwise the chosen
name with `has-geonames-id` beside it.

### A vocabulary for one reading

Each variable becomes one predicate, named from the variable with its underscores turned into
dashes - `temperature_2m` is `has-temperature-2m` - and the object is the number that series holds
at that index:

| Predicate | Comes from | Field types |
| --- | --- | --- |
| `has-temperature-2m(?s, 4.1)` | `hourly.temperature_2m[i]` | `text, number` |
| `has-relative-humidity-2m(?s, 81)` | `hourly.relative_humidity_2m[i]` | `text, number` |
| `has-precipitation(?s, 0.2)` | `hourly.precipitation[i]` | `text, number` |
| `has-wind-speed-10m(?s, 12.4)` | `hourly.wind_speed_10m[i]` | `text, number` |
| `has-weather-code(?s, 3)` | `hourly.weather_code[i]` | `text, number` |
| `has-pm10(?s, 18.2)` | air quality `hourly.pm10[i]` | `text, number` |
| `has-wave-height(?s, 0.3)` | marine `hourly.wave_height[i]` | `text, number` |
| `has-temperature-2m-max(?s, 9.4)` | `daily.temperature_2m_max[i]` | `text, number` |
| `has-sunrise(?s, 2026-11-22T07:41)` | `daily.sunrise[i]` | `text, text` |
| `has-instant(?s, 1795305600)` | the index's `time`, with `timeformat=unixtime` | `text, unique(number)` |

A daily variable takes a date for its instant rather than a clock time, `berlin@2026-11-22`, so a
day and its first hour are separate subjects and an aggregate never collides with a reading.
`sunrise` is a timestamp rather than a number - `2026-11-22T07:41` - which fits a `text` field and
does not fit the schema's `time` type, whose one spelling is `07:41:00`.

The unit is a fact about the variable rather than about the number, so it is written once for the
folder:

```prolog
has-unit(temperature_2m, celsius)
has-unit(wind_speed_10m, kmh)
has-unit(precipitation, mm)
```

That is the request's own word rather than the reply's `°C` and `km/h`. The request names every unit
in ASCII - `celsius`, `kmh`, `mm`, `metric` - while `hourly_units` carries `°C`, `W/m²` and `µg/m³`,
so the fact holds a word a rule can already match and a schema line can list.

One reply of the example above, named, then reads:

```prolog
// The place, and the cell the answer came from.
has-name(berlin, Berlin)
has-latitude(berlin, 52.52437)
has-longitude(berlin, 13.41053)
has-elevation(berlin, 38)
has-timezone(berlin, GMT)
has-grid-latitude(berlin, 52.512604)
has-grid-longitude(berlin, 13.419517)

// The unit each variable was asked for.
has-unit(temperature_2m, celsius)

// One fact per number: the predicate is the variable, the subject is the place and the
// instant, and the object is the value that series holds at that index.
has-temperature-2m(berlin@2026-11-22T00:00, 4.1)
has-temperature-2m(berlin@2026-11-22T01:00, 3.8)
has-instant(berlin@2026-11-22T00:00, 1795305600)
has-instant(berlin@2026-11-22T01:00, 1795309200)
```

and the three files of a domain take these schema lines, one per predicate, with both field types
in the order a fact writes them:

```prolog
// The place.
has-name(text, text)
has-latitude(text, unique(number))
has-longitude(text, unique(number))
has-geonames-id(text, unique(number))
has-country(text, unique(text))
has-country-code(text, unique(text))
has-population(text, unique(number))
has-feature-code(text, text)
has-grid-latitude(text, unique(number))
has-grid-longitude(text, unique(number))
has-elevation(text, unique(number))
has-timezone(text, unique(text))
has-utc-offset(text, unique(number))
has-unit(text, unique(text))

// The readings. Nothing here needs unique(...): one place at one instant is one subject,
// so a second temperature for it is a fact about a different subject.
has-temperature-2m(text, number)
has-relative-humidity-2m(text, number)
has-precipitation(text, number)
has-wind-speed-10m(text, number)
has-weather-code(text, number)
has-pm10(text, number)
has-wave-height(text, number)
has-temperature-2m-max(text, number)
has-sunrise(text, text)
has-instant(text, unique(number))

// What the rules conclude. A derived predicate carries the value it derived from, because a
// schema line types exactly two fields.
is-warm-and-humid(text, number)
is-frosty(text, number)
is-warmer-hour-than(text, text)
is-earlier-than(text, text)
```

Every line begins `text` because the subject is a place, or a place and an instant. `has-instant`
is the one reading predicate that carries `unique(...)`, since a reading has one time; the rest are
one value by construction, which is what the composite subject buys, and it is also why none of
them can be written for a place rather than for one of its instants.

### Rules the vocabulary supports

The shared subject is the join: two variables read at one instant are two facts about one term, so
a rule comparing them needs nothing else.

```prolog
// Both readings are of the same hour, because they are of the same subject.
is-warm-and-humid(?s, ?t) => and(has-temperature-2m(?s, ?t), greater-than(?t, 25), has-relative-humidity-2m(?s, ?h), greater-than(?h, 70))

// A category, from a threshold the reply's number passes.
is-frosty(?s, ?t) => and(has-temperature-2m(?s, ?t), less-than(?t, 0))

// A warmer hour, from two numbers the body has bound.
is-warmer-hour-than(?s, ?u) => and(has-temperature-2m(?s, ?a), has-temperature-2m(?u, ?b), greater-than(?a, ?b))

// Ordering in time needs numbers: the reply's timestamps are text, and text does not compare.
is-earlier-than(?s, ?u) => and(has-instant(?s, ?a), has-instant(?u, ?b), less-than(?a, ?b))
```

`is-earlier-than` is the reason `has-instant` exists at all. The four comparisons read numbers, so
`2026-11-22T00:00` and `2026-11-22T01:00` are text and cannot be ordered against each other;
`timeformat=unixtime` asks the reply for those instants as numbers, which is also the date
arithmetic the engine will not do for you.

Every head carries two fields, like every fact, which is why `is-frosty` names the number that made
it frosty as well as the reading: a schema line types exactly two fields, so a derived predicate
with one of them could not be typed at all. A question usually wants that second field next.

What the engine cannot do is anything with the numbers but compare two of them. There is no mean,
minimum, maximum, count or sum, so "the warmest hour of the day" and "how many hours were below
freezing" are not rules: the first is a fact to compute when the reply is read,
`has-warmest-hour(berlin@2026-11-22, berlin@2026-11-22T15:00)`, and the second is an answer to count
outside the knowledge base. A daily aggregate is the exception the service hands over:
`temperature_2m_max` is already the maximum of the day's hours, so no rule has to find it.

### What a two-field fact cannot hold

A fact is exactly three terms, and text in a field may hold no top-level comma, no unbalanced
parenthesis and no `//`. Weather data strains that harder than a geocoder result does:

- **A reading has four parts** - place, variable, instant, value - and a fact holds three terms. The
  compact shape above puts place and instant in the subject and the variable in the predicate,
  which is one fact per number and makes every same-instant join free. It cannot join two places at
  one instant, because the instant is buried in the subject beside the place. The way out is to
  reify the reading and write four facts about it:

  ```prolog
  is-reading-of(berlin@2026-11-22T00:00, berlin)
  is-reading-at(berlin@2026-11-22T00:00, 2026-11-22T00:00)
  measures(berlin@2026-11-22T00:00, temperature_2m)
  has-value(berlin@2026-11-22T00:00, 4.1)
  ```

  and then the join the compact shape could not make is one rule:

  ```prolog
  warmer-than(?p, ?q) => and(is-reading-of(?s, ?p), is-reading-at(?s, ?t), measures(?s, temperature_2m), has-value(?s, ?a), is-reading-of(?u, ?q), is-reading-at(?u, ?v), equal(?t, ?v), measures(?u, temperature_2m), has-value(?u, ?b), greater-than(?a, ?b), not-equal(?p, ?q))
  ```

  `equal(?t, ?v)` is what says both readings are of one instant, since each instant was reached by
  its own fact; it is the same trick as `shares-city-with` in the geocoder's vocabulary. The cost
  is real - four facts per number instead of one, so a day of one variable goes from 24 facts to
  96 - and the variable changes spelling between the shapes: `temperature_2m` as the reply writes it
  when it stands in a field, `has-temperature-2m` when it names the predicate. Those five
  predicates need schema lines of their own in a file written this way
  (`is-reading-of(text, text)`, `is-reading-at(text, text)`, `measures(text, text)`,
  `has-value(text, number)`, `warmer-than(text, text)`); they are not part of the compact
  vocabulary.
- **A value has no unit in it.** `4.1` does not say celsius, and a `number` field cannot. The unit
  is one fact per variable, which is enough until a second fetch asks for `--temperature-unit
  fahrenheit` and lands in the same folder: nothing then compares the two values, and nothing
  converts them, so a rule over both is silently wrong rather than refused. One snapshot per unit
  set, or the unit in the predicate name, are the two ways to keep that from happening.
- **A silence is not a zero.** A variable the model does not carry, a point outside the model's
  grid, and a `null` in the middle of a series all arrive as no fact at all. Negation as failure
  cannot tell those from a value that is genuinely absent, so `not(has-snowfall(?s, ?x))` reads
  "unknown" as readily as "none", which is why the reply's own `0` - which Open-Meteo does send for
  a variable it has - is the fact worth keeping.
- **An ensemble is one dimension too many.** `temperature_2m_member01`, `_member02` and the mean are
  one variable at one instant, up to 51 times. The mean is the unsuffixed list, so it costs nothing;
  a member has to be folded into the subject (`berlin@2026-11-22T00:00/member01`) or into the
  predicate, and neither lets a rule say "the spread between them", because that is a maximum and a
  minimum over a set of facts. The subject is the better half to fold it into: the members are then
  enumerable as subjects, which is what one looks at them for.
- **A series does not fit at all.** Sixteen days of hourly data for one variable is 384 facts, and a
  reply with five variables over eight places is 15,360. A file that size reads, but nothing in the
  repository has measured what the reader and the solver do with it, which is the first thing to
  find out before a snapshot becomes a domain.
- **Nothing says where a fact came from.** The reply does not echo the model, the run,
  `cell_selection`, or the elevation that was asked for, and a fact has no fourth term for them.
  Some of it fits in a predicate name - `has-temperature-2m-from-ecmwf` is a legal name - and all of
  it fits in a folder or file name, which is the cheaper place: one snapshot folder is one model
  set, one fetch, one unit set. `generationtime_ms` is the field that would fit a fact and still
  does not belong in one: it measures the service, not the world, like the geocoder's `importance`.

### From a reply to a facts file

The reply's series are parallel lists - one `time` list and one list per variable, the same index
meaning the same instant - so the conversion is a zip rather than the property-by-property loop a
geocoder result needs: for each index, the subject is the place and that `time`, the predicate is
the variable, and the object is the value at that index. Three things decide what the file holds:

- A `null` writes nothing, so a gap in the series is a gap in the facts.
- The subject's spelling is the writer's, so it has to be chosen once and used everywhere - the same
  place name, the same `@`, the same timestamp shape - because two spellings of one instant are two
  subjects and no rule joins them.
- A predicate name has to be a name, lower case in dash-joined sections, so a variable is dashed on
  the way in. The variables this page names all survive that; the layer passes unknown parameters
  through, so a variable added later is the writer's to check rather than to assume.

`timezone` decides what a timestamp means. With the default `GMT` every reply is in one zone and two
files' instants are comparable; with `timezone=auto` or a named zone the same instant is spelled
differently in two files, so either keep the zone in the subject or ask for `GMT` and let
`has-timezone` carry the local one as a fact.

Nothing in the layer writes triples: `src/api/openmeteo.ms` hands the parsed JSON back and
`src/openmeteo.ms` prints it, exactly as the geocoder's pair do. What is missing on the way from a
reply to a domain - the writer, a place to record which fetch a file came from, and the sizes
involved - is collected in [gaps to close before these APIs are
knowledge](gaps.md).

## Endpoints

### `forecast`

Up to 16 days of forecast and 92 past days, combined from the best models.

```text
GET https://api.open-meteo.com/v1/forecast
latitude longitude elevation tilt azimuth
hourly daily current minutely_15
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
past_days forecast_days past_hours forecast_hours past_minutely_15 forecast_minutely_15
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
models cell_selection format apikey
```

`forecast_days` runs `0` to `16`. `tilt` and `azimuth` matter to `global_tilted_irradiance`
and to a solar tracker; the other variables ignore them. `models` turns this one endpoint into
the model-specific pages: `ukmo_seamless`, `meteoswiss_icon_ch1`, `knmi_harmonie_arome_europe`,
`dmi_harmonie_arome_europe`, `italia_meteo_arpae_icon_2i`, `geosphere_arome_austria`,
`chmi_aladin_cz`, and the ensemble means and `google_weathernext` presets, all as values of
`models` rather than endpoints of their own.

### `historical`

Reanalysis weather from 1940 up to a few days ago.

```text
GET https://archive-api.open-meteo.com/v1/archive
latitude longitude elevation tilt azimuth
start_date end_date hourly daily
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
models cell_selection format apikey
```

`start_date` and `end_date` are required. There is no `forecast_days` here; the interval is
the request.

### `historical-forecast`

Archived forecasts as they were issued, for a past interval.

```text
GET https://historical-forecast-api.open-meteo.com/v1/forecast
latitude longitude elevation
start_date end_date
hourly daily current minutely_15
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
models cell_selection format apikey
```

`start_date` and `end_date` are required. This is what a forecast said at the time, which is
the series to compare a forecast against when judging it after the fact.

### `previous-runs`

Earlier runs of the models, to compare a forecast with what came before it.

```text
GET https://previous-runs-api.open-meteo.com/v1/forecast
latitude longitude elevation
hourly daily current minutely_15
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
past_days forecast_days run
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
models cell_selection format apikey
```

`forecast_days` runs `0` to `16`. `run` picks the model run to read; without it the service
picks one.

### `single-runs`

One named model run.

```text
GET https://single-runs-api.open-meteo.com/v1/forecast
latitude longitude elevation run
hourly daily current minutely_15
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
models cell_selection format apikey
```

`run` is required, as `yyyy-mm-ddThh:mm`. Use `previous-runs` to find the runs that exist.

### `ensemble`

One forecast per ensemble member, up to 35 days.

```text
GET https://ensemble-api.open-meteo.com/v1/ensemble
latitude longitude elevation tilt azimuth
hourly daily
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
past_days forecast_days
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
models cell_selection format apikey
```

`models` is required - an ensemble is a model's members, so one has to be named - and
`forecast_days` runs `0` to `35`. Members come back as `variable_memberNN` lists beside the
mean.

### `seasonal`

Six-hourly seasonal forecast to seven months, with weekly and monthly summaries.

```text
GET https://seasonal-api.open-meteo.com/v1/seasonal
latitude longitude elevation
hourly daily weekly monthly
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
past_days forecast_days
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
models cell_selection format apikey
```

`forecast_days` runs `0` to `210`. `weekly` and `monthly` are the summaries; `hourly` and
`daily` are the six-hourly series at their own spacing.

### `climate`

Daily climate-model projections from 1950 to 2050.

```text
GET https://climate-api.open-meteo.com/v1/climate
latitude longitude
start_date end_date daily models
temperature_unit wind_speed_unit precipitation_unit
cell_selection format apikey
```

`start_date`, `end_date`, `daily` and `models` are all required, and the reply is daily only.
There is no time zone or `timeformat` here: a climate projection is a date, not a clock time.

### `marine`

Wave, swell, sea level, current and sea surface temperature forecasts.

```text
GET https://marine-api.open-meteo.com/v1/marine
latitude longitude
hourly daily current
temperature_unit wind_speed_unit precipitation_unit length_unit
timeformat timezone
past_days forecast_days past_hours forecast_hours
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
cell_selection format apikey
```

`forecast_days` runs `0` to `8`, and `length_unit` is the wave height unit - `metric` for
metres, `imperial` for feet. The sea point nearest the coordinate is chosen, so a coastal
coordinate can answer from offshore.

### `air-quality`

CAMS pollutants, aerosols, UV index and pollen, European or global.

```text
GET https://air-quality-api.open-meteo.com/v1/air-quality
latitude longitude
hourly current domains
timeformat timezone
past_days forecast_days past_hours forecast_hours
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
format apikey
```

`forecast_days` runs `0` to `7`. `domains` picks `auto`, `cams_europe` or `cams_global`; the
European domain is finer and covers less of the world. There are no unit parameters: the
concentrations are µg/m³ and the UV index is a number.

### `flood`

River discharge from 1984, with a seven-month ensemble forecast.

```text
GET https://flood-api.open-meteo.com/v1/flood
latitude longitude
daily
timeformat timezone
past_days forecast_days start_date end_date
ensemble cell_selection format apikey
```

`forecast_days` runs `0` to `210`, and the reply is daily. `ensemble=1` returns the members
that make the forecast's spread; without it the reply is the deterministic series.

### `elevation`

Terrain elevation from the 90-metre Copernicus DEM, up to 100 points.

```text
GET https://api.open-meteo.com/v1/elevation
latitude longitude apikey
```

The reply is `{"elevation": [...]}`, one value per coordinate pair, in metres. More than 100
pairs is refused by the service.

### `satellite`

Solar radiation from geostationary satellites, as an archive.

```text
GET https://satellite-api.open-meteo.com/v1/archive
latitude longitude
hourly tilt azimuth models temporal_resolution
start_date end_date timeformat timezone format apikey
```

`temporal_resolution` is `native`, `hourly`, or a minute interval such as `minutely_15`; the
satellite series are kept at their native step unless one is asked for.

### `geocoding`

Place names and postal codes to coordinates, time zone and population.

```text
GET https://geocoding-api.open-meteo.com/v1/search
name count format language countryCode apikey
```

`name` is required and takes a place name or a postal code, optionally with a country after a
comma - `"Berlin, Germany"`. `count` runs `1` to `100`. `format` is `json` or `protobuf`.
`countryCode` is an ISO 3166-1 alpha-2 code to filter by.

### `geocoding-lookup`

One location by the id a geocoding result gave.

```text
GET https://geocoding-api.open-meteo.com/v1/get
id format language apikey
```

`id` is required and is the `results[].id` from a `geocoding` reply. A reply is the one result
in the same shape as a search entry.

### Model hosts

Eight endpoints put one model's own forecast on the same surface as `forecast`, without the
`models` switch - the host is the model. All are on `api.open-meteo.com`, and all take the
same parameters:

```text
dwd           GET https://api.open-meteo.com/v1/dwd-icon       DWD ICON, the German model
gfs           GET https://api.open-meteo.com/v1/gfs            NOAA GFS, the American model
meteofrance   GET https://api.open-meteo.com/v1/meteofrance    Meteo-France AROME and ARPEGE
ecmwf         GET https://api.open-meteo.com/v1/ecmwf          ECMWF IFS and AIFS
jma           GET https://api.open-meteo.com/v1/jma            JMA, the Japanese model
gem           GET https://api.open-meteo.com/v1/gem            GEM, the Canadian model
cma           GET https://api.open-meteo.com/v1/cma            CMA, the Chinese model
metno         GET https://api.open-meteo.com/v1/metno          MET Norway, the Nordic model
```

Each accepts:

```text
latitude longitude elevation
hourly daily current minutely_15
temperature_unit wind_speed_unit precipitation_unit timeformat timezone
past_days forecast_days past_hours forecast_hours past_minutely_15 forecast_minutely_15
start_date end_date start_hour end_hour start_minutely_15 end_minutely_15
format apikey
```

`forecast_days` runs `0` to `16`. `models` is absent by design: naming a model on a
model-specific host is what the host already does. The other model presets - UKMO,
MeteoSwiss, KNMI, DMI, ItaliaMeteo, GeoSphere, CHMI, the ensemble means and Google
WeatherNext - have no host of their own and are `models=` values on `forecast`.

## Parameter reference

The types are the layer's: `coordinates` is one number or a comma-separated list, `csv` a
comma-separated list of names, `date` is `yyyy-mm-dd`, `datetime` is `yyyy-mm-ddThh:mm`, and
`bool` takes `true`/`false`, `1`/`0` or `yes`/`no`.

| Parameter | Type and limits | Meaning |
| --- | --- | --- |
| `latitude` | coordinates, -90 to 90, required | WGS84 latitude; a list asks for several locations. |
| `longitude` | coordinates, -180 to 180, required | WGS84 longitude, as many values as there are latitudes. |
| `elevation` | coordinates, -1000 to 9000, `nan` allowed | Elevation used for downscaling; `nan` disables downscaling. One value per location. |
| `tilt` | number, 0 to 90, `nan` allowed | Panel tilt for `global_tilted_irradiance`; `nan` for a tracker. |
| `azimuth` | number, -180 to 180, `nan` allowed | Panel azimuth, `0` south and negative east. |
| `hourly` | csv | Hourly variables. |
| `daily` | csv | Daily variables; required on `climate`. |
| `current` | csv | Variables to report as current conditions. |
| `minutely_15` | csv | 15-minutely variables. |
| `weekly` | csv | Weekly seasonal variables. |
| `monthly` | csv | Monthly seasonal variables. |
| `temperature_unit` | `celsius` \| `fahrenheit` | Temperature unit; default `celsius`. |
| `wind_speed_unit` | `kmh` \| `ms` \| `mph` \| `kn` | Wind speed unit; default `kmh`. |
| `precipitation_unit` | `mm` \| `inch` | Precipitation unit; default `mm`. |
| `length_unit` | `metric` \| `imperial` | Wave height unit, marine only. |
| `timeformat` | `iso8601` \| `unixtime` | Timestamp format; default `iso8601`. |
| `timezone` | text | Zone name, or `auto` to resolve it from the coordinates; default `GMT`. |
| `past_days` | int, at least 0 | Days before today to include. |
| `forecast_days` | int, 0 to the endpoint's maximum | Days from today to include; the maximum is 7, 8, 16, 35 or 210 by endpoint. |
| `past_hours` | int, at least 1 | Hours before now to include. |
| `forecast_hours` | int, at least 1 | Hours from now to include. |
| `past_minutely_15` | int, at least 1 | 15-minute steps before now to include. |
| `forecast_minutely_15` | int, at least 1 | 15-minute steps from now to include. |
| `start_date` | date | First day of the interval; required where the endpoint has no `forecast_days`. |
| `end_date` | date | Last day of the interval; required with `start_date`. |
| `start_hour` | datetime | First hour of the interval. |
| `end_hour` | datetime | Last hour of the interval. |
| `start_minutely_15` | datetime | First 15-minute step. |
| `end_minutely_15` | datetime | Last 15-minute step. |
| `models` | csv | Model names; `auto` combines the best. Required on `ensemble` and `climate`. |
| `cell_selection` | `land` \| `sea` \| `nearest` | Which grid cell to prefer when the coordinate falls between them. |
| `temporal_resolution` | text | `native`, `hourly`, or a minute interval such as `minutely_15`; satellite only. |
| `ensemble` | bool | Return every forecast ensemble member; flood only. |
| `domains` | `auto` \| `cams_europe` \| `cams_global` | Air quality domain. |
| `run` | datetime | Model run to read; required on `single-runs`. |
| `format` | `json` \| `csv` \| `xlsx` | Reply format; the geocoder takes `json` \| `protobuf` instead. |
| `apikey` | text | Commercial key; also read from `OPEN_METEO_API_KEY`. |
| `name` | text, required | Place name or postal code for the geocoder, optionally with a country after a comma. |
| `count` | int, 1 to 100 | Number of geocoding results. |
| `language` | text | Language for the geocoder's results, e.g. `en`, `de`, `fr`. |
| `countryCode` | text | ISO 3166-1 alpha-2 code to filter geocoding results by. |
| `id` | int, required | A location id from a geocoding result. |

## How the program maps to all this

`src/openmeteo.ms` takes an endpoint name as its first word and every parameter above as a
`--name`:

```
miniscript src/openmeteo.ms forecast --latitude 52.52 --longitude 13.41 --hourly temperature_2m
miniscript src/openmeteo.ms forecast --place Berlin --daily temperature_2m_max --forecast-days 3
miniscript src/openmeteo.ms air-quality --latitude 52.52 --longitude 13.41 --hourly pm10
miniscript src/openmeteo.ms geocoding --name Berlin --count 3
miniscript src/openmeteo.ms endpoints
miniscript src/openmeteo.ms help forecast
```

`--place` resolves a name through the `geocoding` endpoint and sends the coordinates it
answers with, so a city works wherever a coordinate pair does; it is resolved before the
request and never sent as a parameter. Underscores and dashes are the same in a name, a
parameter given twice becomes a comma-separated list, and a boolean is `--name`,
`--name false` or `--no-name`. The reply is printed as JSON - `--compact` on one line,
`--url` with the request that was made and any key replaced.

The command line is declared with the repo's cli library, one declaration per endpoint taken
from the same table this page describes. `--help` after the endpoint is therefore that
endpoint's parameter list, with what each one takes and what it is for, and `--help` before
it lists the endpoints; `--version` prints the version line. A parameter the endpoint does
not take is refused by name, and a value outside the table's range, or not among the values
it gives, is reported before the request is made.
