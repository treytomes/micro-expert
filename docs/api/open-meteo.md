# The Open-Meteo API surface

Open-Meteo is not one API but a family of them. Each forecast product has its own host, the
domain APIs - marine, air quality, flood, climate, seasonal, satellite - add more, and the
geocoder is a separate service that shares the parameter style. `src/services/openmeteo_map.ms`
holds the writer's map of them: 23 endpoints, each with its host, path and the complete set of
query parameters it accepts, and the shape of the reply that comes back.

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

`src/services/openmeteo_map.ms` declares those shapes as series rather than reading them into
classes: a series names one table - hourly, daily, current and the rest - with its instants in
one list and a list per variable beside them, and the writer turns each row into a fact. The
geocoder's results and the elevation endpoint's heights are the two shapes that are not
tables, so those endpoints carry their own reply. A refusal is read as the service's reason,
so a caller reports it rather than rendering it.

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
neither: the object is the value. The subject stays the place, and the instant goes in the fact's
`@` annotation as the hour the reading covers:

```prolog
has-temperature-2m(berlin, 4.1) @ [2026-11-22 00:00, 2026-11-22 01:00]
```

A fact is known by its whole line, annotations included, so two hours holding the same value are
two facts and the annotation is what tells them apart. What the subject then lacks is a way to say
"the same hour" on its own: the span is on the fact rather than in a term, so anything that has to
compare or join on one half - the same instant in another city, everything about one place - needs
that half written as a fact of its own, as `has-instant` below.

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
| `has-utc-offset(?p, 3600) @ 2026-11-22` | the reply's `utc_offset_seconds` | `text, number` |

Only the last line needs a date, and only when `timezone=auto` asks for local timestamps: the zone
is a property of the place, and how far it is from UTC is a property of the place on that date,
because the offset moves twice a year, so the date is on the fact's `@`.

A geocoding search is asked with `count=1` and read as what comes back, so the reply block names
the fields that make the result the place asked about:
`"confirm": {"has-name": "name", "has-city": "name", "has-country": "country"}`.
`src/services/declared.ms` holds each of them against the facts the session already has about that
place, and refuses the reply when the service's own word for the field disagrees. The `name` is the
place's own word for itself, and a place asked about by its city is asked by the name that city has,
which is why `has-city` is checked against it: a session that falls through here from
`geocode.maps.co` lands on the same refusal when the geocoder finds another town, and the reader is
asked for the value rather than a forecast computed for a namesake. What counts as the same naming
is `samePlace` in `src/services/declared.ms`, the words of a name once case, accents, punctuation,
initials, abbreviations and the administrative words are set aside: this geocoder's `New York`
confirms a city typed `New York City`, and its `Newark` does not. A predicate the session holds no
fact under, and a field the reply leaves out, are nothing to disagree with.

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
at that index. In `has-temperature-2m` the `2m` is the height the number is read at: air temperature
two metres above the ground, the level a station thermometer stands at, and the same reason
`has-wind-speed-10m` is ten. It is neither a unit nor a height above sea level - that is
`elevation` - and not every digit in the vocabulary means the same thing: `has-pm10` counts
micrometres and `has-temperature-2m-max` carries an aggregate. Because the height is in the name it
is part of the predicate rather than a field, so a reading ten metres up would be
`has-temperature-10m`, a second predicate over the same subject, and no rule can compare two
heights or ask at which one a value was read.

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
| `has-instant(?s, 1795305600)` | the index's `time`, with `timeformat=unixtime` | `text, number` |

A daily variable takes a date for its instant rather than a clock time, `@ 2026-11-22`, so a day
and its first hour are separate facts and an aggregate never collides with a reading.
`sunrise` is a timestamp rather than a number - `2026-11-22T07:41` - which fits a `text` field and
does not fit the schema's `time` type, whose one spelling is `07:41:00`.

The unit is a fact about the variable rather than about the number, and the writer writes it from the
reply's own units table - `hourly_units`, `daily_units`, `weekly_units` - once per variable per
reply:

```prolog
has-unit(temperature_2m, celsius)
has-unit(wind_speed_10m, kmh)
has-unit(precipitation, mm)
```

That is the request's own word rather than the reply's `°C` and `km/h`. The request names every unit
in ASCII - `celsius`, `kmh`, `mm`, `metric` - while `hourly_units` carries `°C`, `W/m²` and `µg/m³`,
so the fact holds a word a rule can already match and a schema line can list. A symbol the writer does
not know is not a unit word at all - `weather_code`'s `wmo code` - and writes no fact rather than a
word no rule could ask for; `%` is written as `percent`.

A second unit set for one variable is the one thing these facts cannot say, and nothing in the engine
converts one unit into another, so a second one is refused wherever it arrives rather than read
beside the first: a facts file holding two units for one variable is refused as it loads, naming
both; a typed second unit is a warning that leaves the first standing; and a service's reply that
spells a variable the session already holds another way is refused whole, so its numbers are never
added beside readings in the other scale.

A rule that judges a number asks for the unit first:

```prolog
is-frosty(?p, ?t) => and(has-unit(temperature_2m, celsius), has-temperature-2m(?p, ?t), less-than(?t, 0))
```

A session that fetched `fahrenheit` proves no `is-frosty` at all rather than a wrong one, which is
the failure the engine is built around: unknown, not false.

The seasonal endpoint's weekly table is the one place where a week is the unit of time rather than an
hour or a day: one row per week, its date the day that week begins, and a mean over the week. The map
declares `has-temperature-2m-mean` and `has-precipitation-mean` for it, so a question about a located
place is answered with five weeks of them rather than asked for. The hour and the week never share a
predicate, because a mean over a week and a reading of one hour are different claims about a place.

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

// One fact per number: the predicate is the variable, the subject is the place, '@' is the
// hour the reading covers, and the object is the value that series holds at that index.
has-temperature-2m(berlin, 4.1) @ [2026-11-22 00:00, 2026-11-22 01:00]
has-temperature-2m(berlin, 3.8) @ [2026-11-22 01:00, 2026-11-22 02:00]
has-instant(berlin, 1795305600) @ [2026-11-22 00:00, 2026-11-22 01:00]
has-instant(berlin, 1795309200) @ [2026-11-22 01:00, 2026-11-22 02:00]
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
has-utc-offset(text, number)
has-unit(text, unique(text))

// The readings. Nothing here needs unique(...): the hour is on each fact's '@', so two
// hours of the same variable are two facts with different annotations.
has-temperature-2m(text, number)
has-relative-humidity-2m(text, number)
has-precipitation(text, number)
has-wind-speed-10m(text, number)
has-weather-code(text, number)
has-pm10(text, number)
has-wave-height(text, number)
has-temperature-2m-max(text, number)
has-sunrise(text, text)
has-instant(text, number)

// What the rules conclude. A derived predicate carries the value it derived from, because a
// schema line types exactly two fields.
is-warm-and-humid(text, number)
is-frosty(text, number)
is-warmer-hour-than(text, text)
is-earlier-than(text, text)
```

Every line begins `text` because the subject is a place. None of the readings carries
`unique(...)`: a place holds one value per hour, and the hour is the fact's `@` rather than part of
the subject, so two hours of the same variable sit beside each other. What the subject no longer
says is which hour a value belongs to, so a rule that has to compare two readings of one hour needs
the instant as a fact of its own, `has-instant`.

### Rules the vocabulary supports

The subject is the place, and it joins every reading of that place. The hour is on each fact's
`@`, which a rule does not read, so two readings of one hour are joined only by a fact of their own
(`has-instant`), not by a shared term.

```prolog
// Both readings are of the same place; the hour is not what joins them.
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
  compact shape above puts the place in the subject, the variable in the predicate and the instant
  in `@`, which is one fact per number. It cannot join two readings of one instant, or two places at
  one instant: the annotation is not a term a rule can bind. The way out is to reify the reading
  and write its parts as facts of their own:

  ```prolog
  is-reading-of(berlin@2026-11-22T00:00, berlin)
  is-reading-at(berlin@2026-11-22T00:00, 2026-11-22T00:00)
  measures(berlin@2026-11-22T00:00, temperature_2m)
  has-height(berlin@2026-11-22T00:00, 2)
  has-value(berlin@2026-11-22T00:00, 4.1)
  ```

  `has-height` is the fact this shape can have and the compact one cannot: there the height is in
  the predicate name, `has-temperature-2m`, and a name cannot be taken apart, so no rule can
  compare two heights or ask at which one a value was read. Here it is a field, and a `number`
  field compares. The variable's own name still ends in `2m`, so the fact repeats what the name
  says rather than adding to it - which is the price of the shape, not a mistake in it.

  and then the join the compact shape could not make is one rule:

  ```prolog
  warmer-than(?p, ?q) => and(is-reading-of(?s, ?p), is-reading-at(?s, ?t), measures(?s, temperature_2m), has-value(?s, ?a), is-reading-of(?u, ?q), is-reading-at(?u, ?v), equal(?t, ?v), measures(?u, temperature_2m), has-value(?u, ?b), greater-than(?a, ?b), not-equal(?p, ?q))
  ```

  `equal(?t, ?v)` is what says both readings are of one instant, since each instant was reached by
  its own fact; it is the same trick as `shares-city-with` in the geocoder's vocabulary. The cost
  is real - five facts per number instead of one, so a day of one variable goes from 24 facts to
  120 - and the variable changes spelling between the shapes: `temperature_2m` as the reply writes
  it when it stands in a field, `has-temperature-2m` when it names the predicate. Those six
  predicates need schema lines of their own in a file written this way
  (`is-reading-of(text, text)`, `is-reading-at(text, text)`, `measures(text, text)`,
  `has-height(text, number)`, `has-value(text, number)`, `warmer-than(text, text)`); they are not
  part of the compact vocabulary.
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

The map writes triples: `src/services/openmeteo_map.ms` names the series and the fields, and
`src/services/declared.ms` turns a reply into facts, exactly as it does for the geocoder. What is
missing on the way from a reply to a domain - a place to record which fetch a file came from,
and the sizes involved - is collected in [gaps to close before these APIs are
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

## How the map reads a reply

`src/services/openmeteo_map.ms` is the service as data: each endpoint's host, path and parameters,
and a reply that names one `series` per table - hourly as an hour-long span, daily as a date,
current as its one instant, and the seasonal weekly and monthly tables as their own periods.
`src/services/declared.ms` reads a series row by row, naming each variable's fact from the
variable itself (`wave_height` is `has-wave-height`), so a table the map has never listed still
becomes facts. The documented forecast variables are listed on the series so a reply that left
one out says which; a caller's own variable list narrows that to what was asked for.

The place is not in the reply, so it comes from the request as the subject; an hourly fact
spans the hour its instant starts, the last hour keeps the moment alone, and
`precipitation_probability` is the confidence on the precipitation fact. The geocoder answers
with a list of places and the elevation endpoint with its heights, so those two endpoints carry
their own reply shape. A refusal is read as the service's reason and returns `ok: 0` rather
than facts.

## What a question may ask

The forecast declares what a question can ask it, in the `provides` block `src/providers.ms`
collects into the session's registry. Five entries, one per documented hourly variable, each
shaped alike:

```text
{"fact": ["has-temperature-2m", "?place", "?value"], "about": "?place",
 "from": {"latitude": "has-latitude", "longitude": "has-longitude"},
 "request": {"hourly": ["temperature_2m", "relative_humidity_2m", "precipitation",
            "wind_speed_10m", "weather_code"], "forecast_hours": 1}}
```

`about` says the reply is read onto the place the question named. The reply names that place by
nothing but the coordinates it was asked with, so the reading is told the place as well, under
the same part's name, while the request itself carries only what the service uses. `from` fills
the request's coordinates from facts the session already holds about that place - today's reading
before an earlier day's, since a forecast fetched now should not be computed from yesterday's
coordinate. A place whose only coordinates were fetched on an earlier day is located again first,
by whichever map declares them, and the old coordinate is sent only when nothing can refresh it. A place the
session knows only by name or city has none of them yet, so the geocoder's search is asked for the
coordinates first and the weather question comes round with them - one answer per pass, two
answers. A place with no coordinates and nothing to search it by is not asked about at all, and
the question falls through to the prompt as it would with no registry at all.

Every entry carries the same request, so they are one request: a reply holds every variable it
was asked for, so the first weather fact a question needs brings the other four with it, and the
session's one-attempt memory answers a later weather fact about that place from the reply
rather than asking again. `forecast_hours=1` asks for the next hour alone, so each variable has
one reading to answer with, and the hour it covers stays the fact's `@`. The unit is whatever the
reply's default is - Celsius, km/h, millimetres - since the declaration names no `*_unit`.

The geocoder declares the place's coordinates as well, asked by the place's own name or city:

```text
[{"fact": ["has-latitude", "?place", "?lat"], "about": "?place",
  "from": {"name": ["has-name", "has-city"]}, "request": {"count": 1}},
 {"fact": ["has-longitude", "?place", "?lon"], "about": "?place",
  "from": {"name": ["has-name", "has-city"]}, "request": {"count": 1}}]
```

Both of `geocode.maps.co`'s search and this geocoder declare those two facts, so a question
needing a place's coordinates by name has two maps that could answer it. The session asks them
in the order the registry was built - `src/main.ms` lists the geocode map first - and a map that
cannot answer is a warning rather than the end of the question: the next declaration is asked
before the reader is.

Nothing is asked at startup, and the archive and the model-specific hosts declare nothing: they
answer about the same place but are not what a question the session cannot answer should reach
for first.
