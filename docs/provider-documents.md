# Provider documents that can name a group

Status: built where it can be checked. `src/services/document.ms` reads a document, resolves it into
the map `declared.ms` reads, and writes one back; `test/document.ms` resolves the geocode document on
this page against the map `geocode.grfon` resolves to, does the same for Open-Meteo's two generated
blocks, takes all three service maps out to a document and back, and checks every refusal below. All
three services are documents now - `ipwhois.grfon`, `geocode.grfon`, `openmeteo.grfon` - in
`services/`, where `src/services/loader.ms` reads every `.grfon` it finds, so `main.ms`,
`notebook.ms` and `where.ms` build their declarations from files.

## Where this starts

A declaration is a map of plain data, and GRFON can carry one: ipwho.is went through
`toGRFON`/`parse` unchanged once four of GRFON's silent rules were handled (they are collected at
the end of this page). The ipwho.is map was 60 lines of literal, and a document was enough for it:
`ipwhois.grfon` is 51.

The other two maps were not literals either. They were short programs that emitted a map, and each
now reads the document beside it instead - `geocode.grfon`, `openmeteo.grfon`. What they computed:

- the geocoder's map - one `placeFacts()` of 21 lines and one `replyShape()` produced all three
  endpoints' replies; the three param lists shared two groups of records and one `details` trio.
- the forecast's map - one `weather()` helper composed 24 endpoints out of shared parameter records
  (`location + [elevation] + variables + units + time + window + dates + output`), `forecastDays(16)`
  wrote a bound into its own doc string, `weatherProvides` was built in a loop, and
  `forecast.reply.once` was assigned after the endpoint was made.

Written as plain documents with no fragment to name, those became repetition: geocode's 21 fact lines
three times over, `openmeteo`'s `latitude` in twenty-two of its endpoints, and about two thousand
lines for Open-Meteo. The format needed one thing - a fragment that can be named and used again - and
with it both maps are data without a single line copied: 223 lines of MiniScript became a 169-line
document, and 392 became 490.

## The additions

Four, plus one optional. Nothing else about a document changes: the same keys, the same terms, the
same reply grammar.

### 1. `groups:`

A document may hold a `groups` map beside `service`, `base` and `endpoints`. Each entry names a
fragment, keyed by what it is:

```miniscript
groups: {
  details: {
    params: {
      {name: addressdetails; type: bool; default: 1; doc: Include a structured address.};
      {name: extratags; type: bool; default: 1; doc: Include the extra OSM tags.}
    }
  }
  placeReply: {
    reply: {require: {osm_type; osm_id}; subject: {name: place; from: {osm_type}; join: /}}
  }
}
```

The keys a group may hold are the ones that hold a fragment: `params`, `facts`, `once`, `series`,
`provides`, `reply`, `endpoint`. A group may hold more than one (`placeReply` above holds only
`reply`; nothing stops it holding `facts` too), and a group is used by the key that matches where
it is used - a `params` reference needs a group with `params`, a reply reference a group with
`reply`. That is the only typing in the format, and it is what makes a wrong use a message rather
than a mystery three steps into the reading.

A group may use another group - a `params` group whose list opens with `@details` - and groups are
resolved before the endpoints are, so the order they are written in is not a rule to remember.

### 2. `@name` wherever a fragment belongs

Any position that expects a fragment may hold the text `@name` instead:

```miniscript
params: { @details; {name: limit; type: int; min: 0; max: 40; default: 10} }
reply:  @placeReply
facts:  @placeFacts
```

`@` is reserved: text beginning with `@` is a reference, never a literal term. The terms a
declaration writes already own `?x` and `$.a.b`, so this is the third prefix and the last one free.

A lone `@name` as a whole list also reads as a list of one, which is what GRFON gives a one-element
collection anyway; the reading wraps it back. Where a document needs a list of one value rather than
a reference, it writes `{value;}` - the trailing semicolon is what makes a list of one (see the
GRFON rules at the end).

### 3. `use:` for a group plus changes

A group used as-is is written `@name`. A group used with something changed is a map with a `use`
key:

```miniscript
reply: {
  use: @placeReply
  each: $
  request: {q}
  facts: {@placeFacts; {was-answer-to; ?place; ?q}}
  confirm: {has-city: {address.city; name}; has-country: address.country}
}
```

The rule is **local wins, wholesale**: every key written beside `use` replaces the one the group
brought. Lists are replaced, not appended - so a reply that adds a fact line starts from
`@placeFacts` again, which costs one token and keeps the merge rule to one sentence. `use` is
reserved in a reply and in an endpoint; neither has a key of that name today.

### 4. `params` are keyed by `name`

Two entries with one `name` in an assembled param list are one parameter: the later merges over the
earlier, field by field, and keeps the earlier one's place in the list. That is how an endpoint
narrows a shared record without copying it:

```miniscript
params: {
  @output
  {name: accept-language; type: text; doc: Language the names come back in, e.g. en or fr.}
}
```

`accept-language` keeps its position and gains the search's own words; `format` is untouched. The
same rule covers the pairs the Open-Meteo map had to build beside each other -
`daily`/`dailyRequired`, `models`/`modelsRequired`, `startDate`/`startDateRequired` - which an
endpoint can narrow with `{name: daily; required: 1}` after `@variables` instead. The shipped
document names them as two groups apiece: an endpoint's list reads better as names, and the merge is
kept for a record that narrows a shared one in place, which is what the geocode search does.

This is the only place the format merges by identity rather than by key, because a request can
carry a parameter once.

### 5. `takes:` - a group with arguments (stage two)

Open-Meteo has two blocks the four rules cannot share: five `provides` entries that differ only in
the variable they ask for, and five `forecast_days` parameters that differ only in their bound. A
group may therefore take arguments:

```miniscript
groups: {
  forecastDays: {
    takes: {most}
    params: {
      {name: forecast_days; type: int; min: 0; max: <most>; doc: Forecast days, 0 to <most>.}
    }
  }
}

endpoints: {
  previous-runs: { params: {@location; @forecastDays(16); @output} }
}
```

Three rules keep this flat: an argument list is positional and one line; `<name>` is replaced in the
group's text (and a placeholder standing alone takes the argument's own type, so `max: <most>` is
the number 16 while `doc:` spells it); and a group with `takes` may not reference another group, so
there is no recursion to detect. No expressions, no conditionals.

Arguments are separated by commas, because GRFON already owns the alternatives: `;` separates a
list's entries and `:` separates a key from its value, so `@hourlyProvides(a; b)` would split the
reference in two. A part of a group that is a list is still a list, so a group holding one
parameter for a list of one value writes `{<variable>;}` - the semicolon is what makes it a list,
as it does everywhere else in a document.

Stage one was entirely enough for geocode.maps.co. Without stage two, Open-Meteo would have written
ten entries out by hand - five `provides` and five `forecast_days`; with it, two `takes:` groups
carry all of them and the endpoints only name what each one is for.

## What a reader refuses

| What a document did | What the reader answers |
| --- | --- |
| `@nope` with no such group | the document uses a group it does not define: nope |
| `@details` where a reply belongs | details holds params, and the document asked it for a reply |
| a group that reaches itself through `use` | the group placeReply uses itself |
| `@forecastDays` given no argument | forecastDays takes 1 argument, and was given 0 |
| an argument list longer than `takes` | forecastDays takes 1 argument, and was given 2 |
| `<most>` left unfilled in a text | the group forecastDays names <most> and no argument fills it |
| a reference inside a `takes` group | a group with arguments cannot use another group: forecastDays |
| a key the level does not have | an endpoint has no methd |

A refusal about one endpoint names it first, as `search: ` here, so a document with several
endpoints says which one it is.

Nothing else is checked, as before: whether a request names a parameter the endpoint takes, and
whether a reply can write a fact a `provides` entry promises, stay `api/http_client.ms`'s and the
suite's business.

## geocode.maps.co, end to end

The declaration the three endpoints now are - `services/geocode.grfon`, verbatim - with the
sharing the code had written as groups. Every comment here is the document's own; `//` runs to the end of the line.

```miniscript
// geocode.maps.co, as a provider document: three endpoints over one place and one reply shape.

service: geocode.maps.co
base: https://geocode.maps.co
// The key travels as its own parameter, and is read from this variable when the caller has none.
keyEnv: GEOCODE_MAPS_API_KEY

groups: {
  // What all three endpoints share about the request: the key, where it travels, and the fact that
  // this service spells a boolean 1 or 0. \1/0 is text - GRFON's escape is what keeps a value that
  // would otherwise read as a number as the string it is meant to be.
  keyed: {
    endpoint: {key: api_key; redact: {api_key}; boolAs: \1/0}
  }
  // The detail fields every endpoint takes.
  details: {
    params: {
      {name: addressdetails; type: bool; default: 1; doc: Include a structured address.};
      {name: extratags; type: bool; default: 1; doc: Include the extra OSM tags.};
      {name: namedetails; type: bool; default: 1; doc: Include name variants.}
    }
  }
  // The reply format and the language: the same three choices and five formats everywhere.
  output: {
    params: {
      {name: format; type: enum; values: {json; jsonv2; xml; geojson; geocodejson};
       default: json; doc: Reply format.};
      {name: accept-language; type: text; doc: Language the names come back in.}
    }
  }
  // One result's fields, in the order docs/api/geocode-maps-co.md lists them. The query is the one
  // line only a search has, so it is added there rather than here.
  placeFacts: {
    facts: {
      {has-name; ?place; $.name};
      // A term with a colon in it is escaped, or the colon would make a pair of it: see the last
      // of the GRFON rules.
      {has-name-in-fr; ?place; $.namedetails.name\:fr};
      // A /lookup result may carry a GeoJSON centroid instead of lat and lon, so the two
      // coordinate facts name both paths, the first that carries a value winning.
      {has-latitude; ?place; {$.lat as number; $.centroid.coordinates[1] as number}};
      {has-longitude; ?place; {$.lon as number; $.centroid.coordinates[0] as number}};
      {has-south-latitude; ?place; $.boundingbox[0] as number};
      {has-north-latitude; ?place; $.boundingbox[1] as number};
      {has-west-longitude; ?place; $.boundingbox[2] as number};
      {has-east-longitude; ?place; $.boundingbox[3] as number};
      {has-osm-class; ?place; $.class};
      {has-osm-type; ?place; $.type};
      {has-place-rank; ?place; $.place_rank};
      {has-importance; ?place; $.importance};
      {has-place-id; ?place; $.place_id};
      {has-house-number; ?place; $.address.house_number};
      {has-road; ?place; $.address.road};
      {has-city; ?place; $.address.city};
      {has-country; ?place; $.address.country};
      {has-country-code; ?place; $.address.country_code};
      {has-wikidata; ?place; $.extratags.wikidata};
      {has-wikipedia; ?place; $.extratags.wikipedia};
      {has-fee; ?place; $.extratags.fee}
    }
  }
  // What every reply has to say to be one, and what it becomes: an OSM object joined as
  // way/5013364 rather than hashed, with its coordinates and its own words for itself.
  placeReply: {
    reply: {
      refuse: {present: error; message: error.message}
      require: {osm_type; osm_id}
      subject: {name: place; from: {osm_type; osm_id}; join: /}
      label: {name: {display_name; name; localname}; also: {}}
      coordinates: {lat; lon}
      facts: @placeFacts
    }
  }
}

endpoints: {
  search: {
    // Everything the keyed group says about the request, and this endpoint's own method and path.
    use: @keyed
    method: GET
    path: /search
    params: {
      {name: q; type: text; doc: Free-form query, e.g. \"Eiffel Tower\".};
      {name: amenity; type: text; doc: Place of interest, attraction or business name.};
      {name: street; type: text; doc: House number and street.};
      {name: city; type: text; doc: City name.};
      {name: county; type: text; doc: County or district.};
      {name: state; type: text; doc: State or region.};
      {name: country; type: text; doc: Country name.};
      {name: postalcode; type: text; doc: Postal code.};
      @details;
      {name: limit; type: int; min: 0; max: 40; default: 10;
       doc: Most results to return, 0 to 40.};
      {name: countrycodes; type: text; doc: Restrict to these country codes.};
      {name: viewbox; type: text; doc: Bias the search with this bounding box.};
      {name: bounded; type: bool; default: 0; doc: Restrict the results to the viewbox.};
      {name: dedupe; type: bool; default: 1; doc: Drop duplicate OSM results.};
      @output;
      {name: accept-language; type: text; doc: Language the names come back in, e.g. en or fr.}
    }
    // A question needing the coordinates of a place the session already names.
    provides: {
      {fact: {has-latitude; ?place; ?lat}; about: ?place;
       from: {q: {has-name; has-city}}; request: {limit: 1}};
      {fact: {has-longitude; ?place; ?lon}; about: ?place;
       from: {q: {has-name; has-city}}; request: {limit: 1}}
    }
    // /search answers with a list, so every entry is one place - and it is asked with limit=1, so
    // the first entry is the one that answers. The reply's own city and country must be the place
    // the session holds, or another Fort Worth would be read as this one.
    reply: {
      use: @placeReply
      each: $
      request: {q}
      facts: {@placeFacts; {was-answer-to; ?place; ?q}}
      confirm: {has-city: {address.city; name}; has-country: address.country}
    }
  }

  reverse: {
    use: @keyed
    method: GET
    path: /reverse
    params: {
      {name: lat; type: number; min: -90; max: 90; required: 1; doc: Latitude.};
      {name: lon; type: number; min: -180; max: 180; required: 1; doc: Longitude.};
      @details;
      {name: zoom; type: int; min: 3; max: 18; doc: Detail level, 3 to 18.};
      @output
    }
    // A question needing the address at a place the session already names, asked by the
    // coordinates that place's facts hold.
    provides: {
      {fact: {has-road; ?place; ?road}; about: ?place;
       from: {lat: has-latitude; lon: has-longitude}};
      {fact: {has-house-number; ?place; ?number}; about: ?place;
       from: {lat: has-latitude; lon: has-longitude}}
    }
    // /reverse answers with one object rather than a list of matches, and says nothing more than
    // the place it answered for.
    reply: @placeReply
  }

  lookup: {
    use: @keyed
    method: GET
    path: /lookup
    params: {
      {name: osm_ids; type: csv; required: 1;
       doc: Comma-separated IDs with a type prefix, e.g. R253832,W175905.};
      @details;
      {name: polygon_geojson; type: bool; default: 0; doc: Include the polygon as GeoJSON.};
      {name: polygon_kml; type: bool; default: 0; doc: Include the polygon as KML.};
      {name: polygon_svg; type: bool; default: 0; doc: Include the polygon as SVG.};
      {name: polygon_text; type: bool; default: 0; doc: Include the polygon as text.};
      @output
    }
    // /lookup answers with a list, and its result may carry a centroid instead of lat and lon;
    // the two coordinate facts in @placeFacts name both paths, in order. Two of the three
    // endpoints answer with a list and /reverse does not, so `each` is written at the two rather
    // than in the group.
    reply: {
      use: @placeReply
      each: $
    }
  }
}
```

What the groups hold, against the map it replaces:

| Document | Today's map | Lines saved |
| --- | --- | --- |
| `placeFacts` (21 lines) | `placeFacts()`'s list | 42 - the search and lookup copies |
| `placeReply` | `replyShape(null, 0)` and two thirds of `replyShape("$", 1, ...)` | 2 copies of six reply clauses |
| `details`, `output` | the same records repeated in three `params` lists | 10 records |
| `keyed` | `key`/`redact`/`boolAs` on three endpoints | 6 lines |
| `{name: accept-language; ...}` | the search's own doc string for the shared parameter | - (the by-name merge) |

That was about sixty lines the map could not share with itself while it was code, in a 223-line
file; the document is 169. Against Open-Meteo it was the difference between a document and a
transcription: `latitude` and `longitude`, which the document names once, serve twenty-two of the
twenty-four endpoints (392 lines became 490, against the two thousand the transcription would
have cost);
`temperature_unit` and its neighbours seventeen; the `hourly` and `daily` variable records most of
them; and `weatherReply` would be written out once per endpoint family rather than once.

## What Open-Meteo needs on top

The endpoint groups carry what `weather()` did - everything but the path, the params and the series.
Stage two filled the two generated blocks. The excerpt leaves out the groups that are plain records -
`elevation`, `tilt`, `azimuth`, `variables`, `units`, `time`, `window`, `dates`, `models`, `cell`,
`output`, `modelSurface`, and the nine series - each of which is a record the map already declared,
moved into a group unchanged.

```miniscript
groups: {
  location: {
    params: {
      // A semicolon inside a value is escaped, the way the design's own sample learned: unescaped,
      // it ends the value and the part after it joins the line's earlier parts under a _ key.
      {name: latitude; type: coordinates; min: -90; max: 90; required: 1;
       doc: WGS84 latitude\; a comma-separated list asks for several locations.};
      {name: longitude; type: coordinates; min: -180; max: 180; required: 1;
       doc: WGS84 longitude\; as many values as there are latitudes.}
    }
  }
  weather: {
    endpoint: {key: apikey; redact: {apikey}}
  }
  weatherReply: {
    reply: {
      refuse: {when: error; is: 1; message: reason}
      require: {latitude; longitude; ?place}
      subject: {name: reading; from: {?place}}
      request: {place}
    }
  }
  forecastDays: {
    takes: {most}
    params: {
      {name: forecast_days; type: int; min: 0; max: <most>; doc: Forecast days, 0 to <most>.}
    }
  }
  hourlyProvides: {
    takes: {variable; predicate}
    provides: {
      {fact: {<predicate>; ?place; ?value}; about: ?place;
       from: {latitude: has-latitude; longitude: has-longitude};
       // Asked in the place's own zone: a reading's hour is the hour there, and has-time is the
       // clock those hours are written in.
       request: {hourly: {<variable>;}; forecast_hours: 24; timezone: auto}}
    }
  }
}

endpoints: {
  forecast: {
    use: @weather
    base: https://api.open-meteo.com
    path: /v1/forecast
    params: {
      @location; @elevation; @tilt; @azimuth; @variables; @units; @time; @window;
      @forecastDays(16); @dates; @models; @cell; @output
    }
    provides: {
      @hourlyProvides(temperature_2m, has-temperature-2m);
      @hourlyProvides(relative_humidity_2m, has-relative-humidity-2m);
      @hourlyProvides(precipitation, has-precipitation);
      @hourlyProvides(wind_speed_10m, has-wind-speed-10m);
      @hourlyProvides(weather_code, has-weather-code)
    }
    reply: {
      use: @weatherReply
      series: {@hourSeries; @daySeries; @currentSeries; @minutelySeries};
      // Said once about the place rather than read by reading: the clock the same hours are
      // written in, so a place the machine is not at can still be asked about now.
      once: {
        {has-timezone; ?place; $.timezone};
        {has-utc-offset; ?place; $.utc_offset_seconds as number}
      }
    }
  }

  // The zone facts alone: one request, and no readings the question never asked about.
  clock: {
    use: @weather
    base: https://api.open-meteo.com
    path: /v1/forecast
    params: {@location; @time; @output}
    provides: {
      {fact: {has-utc-offset; ?place; ?offset}; about: ?place;
       from: {latitude: has-latitude; longitude: has-longitude};
       request: {timezone: auto}}
    }
    reply: {
      use: @weatherReply
      series: {};
      once: {
        {has-timezone; ?place; $.timezone};
        {has-utc-offset; ?place; $.utc_offset_seconds as number}
      }
    }
  }
}
```

The eight model endpoints (`dwd`, `gfs`, `meteofrance`, `ecmwf`, `jma`, `gem`, `cma`, `metno`) are
then one `use: @weather` and one `@modelSurface` each: two lines where the two lines that share
`modelSurface` stood.

That is built: `services/openmeteo.grfon` is the whole service, not the excerpt. What it needed
beyond these blocks was mechanical - a group per parameter, the nine series as groups, the three
replies the geocoder and the elevation endpoint carry, and twenty-two endpoints written out one by
one. The excerpt's own parts are the five groups above and `forecast` and `clock`, which is the
half that took thinking.

## GRFON's own rules a document has to keep

These are the format's, not the proposal's - they were found by running the shipped ipwho.is map
through `toGRFON` and `parse`:

1. **A list of one value has no spelling.** `{city}` reads as `city`. The reading wraps a lone value
   where the format says a list belongs, and a document that needs a real list of one writes
   `{city;}` - the trailing semicolon is the list.
2. **An empty list and an empty map are both `{}`.** `also: {}` and `series: {}` above rely on the
   reading turning an empty map into the empty list a list-shaped part means.
3. **`true` and `false` are text.** GRFON reads the words as strings, deliberately, because a
   service's own parameter may be the word. A declaration writes `1` and `0`, which are what the
   language's booleans are, so `is: 0` is `is: false`.
4. **Two collections side by side read as one.** `{a; b; c}` followed on the next line by
   `{d; e; f}` merges into one line of six parts, so every entry of a list of collections ends with
   `;` - every fact line, every parameter, every capability. It is why `toGRFON`'s readable spelling
   only round trips in its compact form.
5. **A colon reads as a key and a value.** `{has-name-in-fr; ?place; $.namedetails.name:fr}` reads as
   a line of two parts and the pair `name: fr`, so a term carrying a colon is written `\:` - which
   is what `toGRFON` writes on its own. Nothing about the document makes the difference visible
   after the fact: an unescaped colon changes what the parse produces, not what the text says.
6. **A value that begins with a digit or a dot is a number.** `1/0` reads as 1 and
   `15-minutely variables.` as 15, so a text that begins with one is escaped - `\1/0` is the
   `boolAs` of the geocode document above. `%` after a number reads as a percentage, and two slashes
   begin a comment unless they follow a url's colon. `document.text` leaves all of that to
   `grfon.escape` - the escaping the bundled module already owns, `https://` and all - and adds the
   one escape GRFON has no rule for: a value that begins with a digit, a dot, `@` or a space.

## What a reader has to know that a document does not say

Resolving the geocode document above against the map it replaced came out to zero differences - but it
took three passes, and the passes are the part worth keeping.

**Which parts are lists.** GRFON cannot tell a lone value from a list of one, so something has to,
and that something is `lists` in `src/services/document.ms` - the only place these part names are
written down. The reader wraps a part it names and turns an empty map into the empty list, so
`{city}` and `{city;}` resolve alike, and `{city;}` is how a document says a list of one on purpose.
Two shape rules go with the table: a fact line is a list of parts and a fact list is a list of
lines, told apart by whether the first element is itself a list; and a group holding one parameter
collapses to that parameter - `takes: {most}` is one of those, and reads as the text `most`. Miss an
entry and the document still parses, still resolves, and means something else: `redact: {api_key}`
would resolve to the text `api_key`, `request: {q}` to `q`, and an Open-Meteo
`hourly: {temperature_2m}` would make `declared.ms` answer with the documented variables instead of
the one the question asked for - a wrong answer rather than an error.

**That a value is a value.** A colon reads as a key and a value, so `$.namedetails.name:fr` parsed
as `{"_": ["has-name-in-fr", "?place"], "name": "fr"}` in the first draft of this page's own
sample. `;`, `{`, `}` and `@` reinterpret text the same way and leave no trace of having done it;
only `\:` - which `toGRFON` writes for you - keeps a term a term.

**Three guards, and all three are in the reader:**

- a map carrying a `_` key is refused at read - GRFON's own mark for the parts before a pair, and
  never something a declaration means. This is the guard that caught this page's own Open-Meteo
  excerpt, where two doc strings had an unescaped `;`;
- a declared fact line that is not a list is refused - it is a map exactly when a colon went
  unescaped, or when two lines merged for want of a `;`;
- a key that is not one of the declaration's, a group's or an endpoint's is refused, so a typo is a
  message rather than a field nobody reads.

**The proof is still a diff.** Zero differences against `build()` is the only evidence that a
document is faithful; nothing in the format establishes it - which is why that diff is now a test
(`test/document.ms`) rather than a throwaway. It makes the code the specification and the diff the
test: enough to migrate three maps, not enough to publish a format, because a document written by
someone who has never read these maps can be wrong in ways every reader will call correct. Nothing
here checks a document against the service itself either.

Stage two was resolved the same way and came out even: `@forecastDays(16)` binds to the parameter
`build()`'s closure writes, `max` taking the number 16 and `doc:` spelling it; the five
`@hourlyProvides(variable, predicate)` calls bind to the five entries its loop writes, argument
lists, `{<variable>;}` and all; and `clock.reply`, a group used with changes, matches what
`weatherReply()` returns. What that does not prove is any Open-Meteo endpoint whole - this page's
excerpt leaves out the plain records the endpoints are made of, so the generated blocks and one
reply group are all there is to diff.

**Which kind a reference is.** A reference resolves with the part it is replacing: `params:
@location` wants a group holding `params`, `reply: @placeReply` one holding `reply`, and inside a
reply the three list parts each ask for their own name - `once: @zoneOnce` finds the group's `once`
and not a `facts` it does not have, and `series: {@hourSeries; @daySeries}` splices one group per
entry. The reader's first version flattened everything as `facts`, so no group could be used for
`once` or `series` at all; the Open-Meteo document is what found it.

## What is built, and what is not

Built:

- **`services/ipwhois.grfon`** - ipwho.is as a document: one endpoint, two params, one reply with
  five clauses and eight fact lines. 60 lines of literal became 51 of document, and the difference
  was none.
- **`services/geocode.grfon`** - geocode.maps.co as a document: three endpoints over one place
  and one reply shape, with the groups this page's sample uses and each fragment's one-line
  comment. It resolves to the map the `_map.ms` it replaced used to build in code, member for
  member - 223 lines of MiniScript became a 169-line file, and the difference was none.
- **`services/openmeteo.grfon`** - Open-Meteo as a document: twenty-four endpoints over one
  reply shape. The `weather` group carries the GET and the key every endpoint shares, `weatherReply`
  with `zoneOnce` is a reading, `placeFacts` and `searchReply`/`lookupReply` the geocoder,
  `elevationReply` the heights; nine series groups stand for the six tables and the three read-any
  variants; and `forecastDays` and `hourlyProvides` are the two blocks the map generated with a
  closure and a loop. 392 lines of MiniScript became 490 of document, and the difference was none.
- **`src/services/loader.ms`** - the three `_map.ms` wrappers became one entry point: `load` lists
  the folder it is given - by default the one it stands in, found through `knowledge.resolvePath` -
  takes every name ending in `.grfon`, and reads each through `document.read` and
  `document.resolve`. The map it returns is keyed by file name and sorted, so `main.ms`, `notebook.ms`
  and `where.ms` ask the services in one order; a file that is refused is an error beside its name
  rather than a stop, so that one service is off with a warning naming the file and the run goes on.
  A folder with no documents in it is refused outright, since that is the wrong folder rather than a
  run with no services. A document moved aside is simply not found, and nothing knows to miss it.
- **`src/services/document.ms`** - `read` (GRFON to map, refusing a `_` key), `resolve` (groups
  expanded, `use` merged, params keyed by `name`, arguments bound, the keys of a declaration, group
  and endpoint checked, a group that reaches itself refused) and `text` (a declaration written back
  as a document, every value escaped so it reads back as itself). Both tables live in that module:
  `lists` for the parts that are lists and `keys` for what each level may hold. The result is the map
  `declared.ms` already reads, so `declared.ms`, `providers.ms`, `api/http_client.ms`, `session.ms` and
  every rule in the domain are untouched.
- **`test/document.ms`** - the geocode document on this page against the map its loader reads from
  `services/geocode.grfon`; the loader's checks in `test/run.ms` - one that `./services` is scanned,
  then one per service that its document declares the service it is meant to - made before any case
  module and through `harness.require`, which a filter cannot take away, so `--file geocoder.ms`
  still fails when a document is refused, and `test/serviceLoader.ms` covers the folder a host names,
  a refused document beside its own name, and a folder that is missing or bare. A
  refused document fails there by name with the loader's reason, and a case module that needs its map
  asks `harness.documents` first, which prints the skip and counts it - unless `--file` left that
  module out, since the run was not going to name it: one bad `.grfon` costs its own cases and never
  stops the run;
  Open-Meteo's five `@hourlyProvides` entries, its `@forecastDays(16)` parameter, `clock.reply` and
  `forecast.reply.once` against the map `openmeteo.grfon` resolves to; all three service maps
  written with `text`, read with `read` and resolved back to themselves; and one check per refusal
  below. Reading the page's own samples in
  the suite is deliberate: a document that stops resolving is a page that is wrong.

What still has to stay in code:

- **The loader, and the hand-in at its call sites.** A module here cannot see its own imports -
  `document` is an unknown identifier inside a module that imports it, which is why the reader and
  the path rule arrive as arguments - and the folder a run reads is found from the entry script's
  root, which is where the loader's own path rule works. One `load` call each in `main.ms`,
  `notebook.ms` and `where.ms`, and in each host the loop that drops a refused file with a warning
  naming it.
- **Nothing of the services themselves.** What the maps *computed* - a loop over five variables, a
  closure over the endpoint's maximum, `once` assigned after the endpoint was made - is a group with
  `takes:`, a `<placeholder>`, or a `once:` line in the document.

Not built:

- **A document per API page.** `docs/api/*.md` describe each service's surface by hand. Nothing
  checks them against the documents the program actually reads.
- **A writer that keeps groups.** `text` writes a declaration expanded, so a round trip through it
  loses the grouping and the comments: what comes back is the same declaration as a single long
  line. Writing the groups back - and choosing which fragments deserve one for a map that never had
  any - is the one piece of the format still unwritten.
