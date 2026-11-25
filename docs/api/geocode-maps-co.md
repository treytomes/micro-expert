# The geocode.maps.co API surface

geocode.maps.co is a small geocoder over OpenStreetMap data: an address in, coordinates and a
display name out, and the reverse. It has three GET endpoints, and `src/spike/geocode_map.ms`
holds all three with every parameter each one takes and the facts a result becomes.

This document is the remote surface written out: what a request looks like, what comes back,
and every parameter of every endpoint. Anything here that the layer checks - a range, a
required field, a list of values - is checked before the request is sent, so a request the
layer allows is one the service should also accept.

## The request

```
GET https://geocode.maps.co/search?q=Eiffel+Tower&limit=1&api_key=...
```

- Every parameter is a query parameter. The layer URL-encodes names and values, drops empty
  ones, and joins a repeated `--name` with commas, so `--countrycodes de --countrycodes fr`
  becomes `countrycodes=de%2Cfr`.
- The key is the `api_key` parameter, added to every request. The map names the variable it is
  read from (its `keyEnv`, `GEOCODE_MAPS_API_KEY`), and `src/spike/declared.ms` fills the
  parameter from the environment - which is where the `.env` beside the run puts it - unless the
  caller hands a key in itself. The map keeps the key out of any URL it builds. A run with no key
  in either place refuses the request before it goes out and says which variable to set, since a
  keyless call can only be a `401`. The service's documentation also names an `Authorization:
  Bearer` header; that path answers `401`, so the parameter is the only one used.
- A name the table does not list is passed through untouched. The service adds optional
  parameters between releases, and the layer is not the place to drop one.
- The free-form and structured fields are alternatives, not a sequence: give `q`, or give
  `street`, `city`, `country` and the rest. The service refuses a search with neither.

## The reply

The default format is JSON. `/search` and `/lookup` answer with a list of results, `/reverse`
with one result object. A search that matches nothing answers `[]`; a bad request answers an
error object (see [Refusals](#refusals)).

A result looks like this (one entry of a `/search` reply, trimmed):

```json
{
  "place_id": 119141919,
  "licence": "Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright",
  "osm_type": "way",
  "osm_id": 5013364,
  "lat": "48.8582599",
  "lon": "2.2945006",
  "class": "man_made",
  "type": "tower",
  "place_rank": 30,
  "importance": 0.6199831475570641,
  "addresstype": "man_made",
  "name": "Tour Eiffel",
  "display_name": "Tour Eiffel, 5, Avenue Anatole France, … , 75007, France",
  "address": {"house_number": "5", "road": "Avenue Anatole France", "city": "Paris", "country": "France", "country_code": "fr"},
  "extratags": {"fee": "10-25€", "wikidata": "Q243", "wikipedia": "fr:Tour Eiffel"},
  "boundingbox": ["48.8574", "48.8590", "2.2933", "2.2956"]
}
```

| Field | Meaning |
| --- | --- |
| `place_id` | The service's own id for the result. |
| `licence` | The ODbL attribution the data comes with. |
| `osm_type`, `osm_id` | The OpenStreetMap object: `node`, `way` or `relation`, and its id. |
| `lat`, `lon` | Coordinates, as strings. |
| `class`, `type` | The OSM tag pair that classified the object, e.g. `man_made` / `tower`. |
| `place_rank` | How large the object is on the administrative scale; lower is coarser. |
| `importance` | The service's ranking weight, used to order results. |
| `addresstype` | The part of the address this object stands for. |
| `name` | The object's own name, when OpenStreetMap has one. |
| `display_name` | The whole address, one line. |
| `address` | The structured address, keyed by part: `house_number`, `road`, `city`, `state`, `postcode`, `country`, `country_code` and so on, as the data has them. |
| `extratags` | The object's other OSM tags, when `extratags=1`. |
| `namedetails` | Name variants - `name:en`, `official_name`, `old_name` - when `namedetails=1`. |
| `boundingbox` | `[south, north, west, east]` as strings. |
| `geojson`, `svg`, `geokml`, `text` | The polygon in the shape asked for by the `polygon_*` parameters. |

`lat` and `lon` are strings, not numbers, which is worth knowing before doing arithmetic on
them. The layer hands the parsed JSON through as the service sent it, so they stay strings.
`src/spike/declared.ms` reads each result through the map instead: the three endpoints share one
facts list, the subject is the OSM object (`way/5013364`), and a search adds the query that asked
for it.

`format=xml`, `format=geojson` and `format=geocodejson` answer in those formats instead.
`geojson` and `geocodejson` are still JSON, so the layer's `json` field is filled;
`xml` is not, so `json` is `null` and the body is the caller's to print as it came. The result
fields above are the `json`/`jsonv2` shape; `geocodejson` moves them under
`features[].properties.geocoding`.

## The reply as triples

The knowledge base in this repository stores one statement per line, `predicate(subject, object)`,
and [the `.kb` grammar](../wiki/kb-grammar.md) is the exact format. A geocoder result is the same
shape - one object with a dozen named properties - so a reply converts to facts almost without
interpretation, and the field table above is close to the schema those facts want. What follows is
the vocabulary worth keeping, the rules that vocabulary makes possible, and the parts of a result
that a two-field fact cannot hold.

### The subject

A fact names its subject as a term, so a result needs a key. The OSM object is the one to use:
`osm_type` and `osm_id` joined into one text term, `way/5013364`. It is the identity other data
shares - the same object has a Wikidata item, a history in OpenStreetMap, and an entry in any
other geocoder - and it survives a re-query, which is what makes `/lookup --osm-ids W5013364`
the way to refresh a subject already held.

`place_id` is the service's own id and belongs in a property rather than in the key: it is
internal to geocode.maps.co, nothing outside the service refers to it, and it can change when the
index behind it is rebuilt. A name is not a key either - `Tour Eiffel`, `Eiffel Tower` and
`Tour de Fer` are one object, and two unrelated objects can share one.

The object as the subject also merges duplicate answers for free: two searches that return the
same `osm_type` and `osm_id` write facts about one subject, so `dedupe=0`, a second language and a
second query all add properties rather than copies. That is why `unique(...)` belongs on
`has-latitude`, `has-longitude` and the address parts, and not on `has-name`, where a second name
is a second fact about the same object rather than a mistake.

### A vocabulary for one result

| Predicate | Comes from | Field types |
| --- | --- | --- |
| `has-name(?p, Tour Eiffel)` | `name` | `text, text` |
| `has-name-in-fr(?p, Tour Eiffel)` | `namedetails` key `name:fr` | `text, text` |
| `has-latitude(?p, 48.8582599)` | `lat` | `text, unique(number)` |
| `has-longitude(?p, 2.2945006)` | `lon` | `text, unique(number)` |
| `has-south-latitude`, `has-north-latitude` | `boundingbox[0]`, `[1]` | `text, unique(number)` |
| `has-west-longitude`, `has-east-longitude` | `boundingbox[2]`, `[3]` | `text, unique(number)` |
| `has-osm-class(?p, man_made)` | `class` | `text, text` |
| `has-osm-type(?p, tower)` | `type` | `text, text` |
| `has-address-type(?p, man_made)` | `addresstype` | `text, text` |
| `has-place-rank(?p, 30)` | `place_rank` | `text, unique(number)` |
| `has-importance(?p, 0.6199831475570641)` | `importance` | `text, unique(number)` |
| `has-place-id(?p, 119141919)` | `place_id` | `text, unique(number)` |
| `has-house-number(?p, "5")` | `address.house_number` | `text, unique(text)` |
| `has-road`, `has-city`, `has-county`, `has-state` | `address.<part>` | `text, unique(text)` |
| `has-postcode(?p, "75007")` | `address.postcode` | `text, unique(text)` |
| `has-country(?p, France)`, `has-country-code(?p, fr)` | `address.country`, `address.country_code` | `text, unique(text)` |
| `has-wikidata(?p, Q243)` | `extratags.wikidata` | `text, unique(text)` |
| `has-wikipedia(?p, fr:Tour Eiffel)` | `extratags.wikipedia` | `text, unique(text)` |
| `has-fee(?p, 10-25€)` | `extratags.fee` | `text, text` |
| `has-extra-tag(?p, fee=10-25€)` | any other `extratags` entry | `text, text` |
| `was-answer-to(?p, Eiffel Tower)` | the query that produced the result | `text, text` |

One `/search` result - the trimmed one above - then reads:

```prolog
// One result, as facts. The subject is the OSM object, so a second search adds to it.
has-name(way/5013364, Tour Eiffel)
has-name-in-fr(way/5013364, Tour Eiffel)
has-latitude(way/5013364, 48.8582599)
has-longitude(way/5013364, 2.2945006)
has-south-latitude(way/5013364, 48.8574)
has-north-latitude(way/5013364, 48.8590)
has-west-longitude(way/5013364, 2.2933)
has-east-longitude(way/5013364, 2.2956)
has-osm-class(way/5013364, man_made)
has-osm-type(way/5013364, tower)
has-place-rank(way/5013364, 30)
has-importance(way/5013364, 0.6199831475570641)
has-place-id(way/5013364, 119141919)
has-house-number(way/5013364, "5")
has-road(way/5013364, Avenue Anatole France)
has-city(way/5013364, Paris)
has-country(way/5013364, France)
has-country-code(way/5013364, fr)
has-wikidata(way/5013364, Q243)
has-wikipedia(way/5013364, fr:Tour Eiffel)
has-fee(way/5013364, 10-25€)
was-answer-to(way/5013364, Eiffel Tower)
```

and the three files of a domain take these schema lines, one per predicate, with both field types
in the order a fact writes them:

```prolog
has-name(text, text)
has-name-in-fr(text, text)
has-latitude(text, unique(number))
has-longitude(text, unique(number))
has-south-latitude(text, unique(number))
has-north-latitude(text, unique(number))
has-west-longitude(text, unique(number))
has-east-longitude(text, unique(number))
has-osm-class(text, text)
has-osm-type(text, text)
has-place-rank(text, unique(number))
has-importance(text, unique(number))
has-place-id(text, unique(number))
has-house-number(text, unique(text))
has-road(text, unique(text))
has-city(text, unique(text))
has-country(text, unique(text))
has-country-code(text, unique(text))
has-wikidata(text, unique(text))
has-wikipedia(text, unique(text))
has-fee(text, text)
was-answer-to(text, text)

// What the rules conclude, and the table they read.
country-code-of(text, text)
is-north-of(text, text)
is-east-of(text, text)
is-coarser-than(text, text)
is-more-important-than(text, text)
shares-city-with(text, text)
shares-osm-class-with(text, text)
is-in-country(text, text)
```

Every line begins `text` because the subject is an OSM object, and the second type is the
property's. The last eight type what the rules conclude and the table they read. The shipped domain
types every predicate a rule uses, derived ones included, because that is what lets the prompt
refuse a constant no rule could match.

The address parts are the interesting typing. `5` and `75007` read as numbers wherever they
stand, and a `text` field refuses a number - `the object should be text` - so an all-digit house
number or postcode is written in quotes, `"5"`, which reads as the text `5`; the number would be refused. A house number such as `12b` is text already and needs none.

Five of these spellings also stand on the Open-Meteo page - `has-name`, `has-latitude`,
`has-longitude`, `has-country`, `has-country-code` - and that is deliberate rather than a
coincidence of two pages written separately. They mean the same thing about a place whichever
service supplied it, and both pages give them the same field types, so a domain that reads both
geocoder results and forecasts needs one schema line and one rule for a place, not two with a
suffix on one. What the two pages do not share is the subject: here it is an OSM object, there a
name the writer chose, because a forecast reply carries no id. Sharing a predicate joins nothing on
its own, so a folder holding both kinds of fact has to give one place one term in both files -
`way/5013364` where the geocoder supplied it, and otherwise the chosen name with `has-geonames-id`
beside it - or the shared `has-latitude` sits on two subjects and never meets.

### Rules the vocabulary supports

A rule joins facts the reply already wrote, and the seven built-in constraints compare them.
Ordering and sharing are what that buys:

```prolog
// Ordering, from two numbers the body has bound.
is-north-of(?x, ?y) => and(has-latitude(?x, ?a), has-latitude(?y, ?b), greater-than(?a, ?b))
is-east-of(?x, ?y) => and(has-longitude(?x, ?a), has-longitude(?y, ?b), greater-than(?a, ?b))
is-coarser-than(?x, ?y) => and(has-place-rank(?x, ?a), has-place-rank(?y, ?b), less-than(?a, ?b))
is-more-important-than(?x, ?y) => and(has-importance(?x, ?a), has-importance(?y, ?b), greater-than(?a, ?b))

// Sharing, from one text both reach: equal binds the second side to the first.
shares-city-with(?x, ?y) => and(has-city(?x, ?c), equal(?c, ?d), has-city(?y, ?d), not-equal(?x, ?y))
shares-osm-class-with(?x, ?y) => and(has-osm-class(?x, ?c), equal(?c, ?d), has-osm-class(?y, ?d), not-equal(?x, ?y))

// The code a result carries, said as the country it names, through a table of facts.
is-in-country(?x, ?c) => and(has-country-code(?x, ?k), country-code-of(?k, ?c))
```

That last one is the point of a code table as facts: `country-code-of(fr, France)` is one more
line in the facts file, and a result that arrived with only `fr` can then be asked for the name.
Nothing stores a mapping in code, which is the same reason the shipped domain's family is only
data.

The comparisons and `years-since` are all the arithmetic the engine has, and none of them adds,
subtracts or multiplies. A rule can therefore order places - north, east, finer rank, greater
importance - but it cannot measure the distance between two of them, keep those within a radius,
or work out the area of a bounding box. Those have to be facts computed when the reply is read,
`has-distance-to(way/5013364, 128)`, or answers given outside the knowledge base.

Two limits are about what a missing property means. The search is negation as failure, so
`not(has-city(?p, ?c))` holds for a place whose address came back without a city exactly as it
holds for one in open country; read an absent property as unknown and ask for it positively.
Text is compared exactly, so `Paris` and `paris` are two cities and so are `Paris` and
`Paris, France`, which is why the reply's own `city` field is the one to keep rather than a split
of `display_name`. And a longitude comparison has the dateline in the middle: 179 and -179 are
neighbours on the globe and opposite ends of the range here.

### What a two-field fact cannot hold

A fact is exactly three terms, and text in a field may hold no top-level comma, no unbalanced
parenthesis, and no `//`. That rules out some of the reply outright:

- `display_name` is one line with commas in it, and a comma at the top level is what separates
  fields, so the whole address cannot be one. The structured `address` gives the same parts in a
  form that fits, which is the reason to keep it.
- `licence` holds both commas and `http://`, and `//` starts a comment wherever it stands, so the
  attribution cannot sit in any field at all. It belongs with the data file - a line in the
  host that wrote it, or beside the folder - rather than inside the facts.
- `boundingbox` is a list of four numbers. Four predicates keep it comparable, as above; one text
  field such as `48.8574 48.8590 2.2933 2.2956` reads back but never compares, since a comparison
  needs numbers.
- `extratags` and `namedetails` are maps whose keys are not predicate names: `addr:street` has a
  colon, `name:en` has one too, and a name section is letters and digits only. There are three
  ways out. A predicate per key you mean to query, with the varying part as a section -
  `has-wikidata`, `has-name-in-fr` - which is the readable one and only scales to the keys you
  care about. A catch-all `has-extra-tag(?p, fee=10-25€)`, which keeps every pair but makes the
  key unqueryable: it can list a place's tags, not find the places whose key is `fee`. Or nothing,
  and the tag stays in the reply.
- The polygons - `geojson`, `svg`, `geokml`, `text` - are nested, full of commas and parentheses,
  and never fit a field. A fact naming where the polygon was written, `has-polygon-in(way/5013364,
  polygons/eiffel.geojson)`, is as far as a triple goes.
- Time and provenance have nowhere to sit. A fact uses all three terms, so "when this was read"
  and "which service said so" have no fourth place. The options are a domain folder per snapshot,
  or the date in the predicate name - `has-latitude-as-of-2026-11-22` is a legal name, since
  sections after the first may hold digits - which reads badly under `--nlp` and doubles the
  vocabulary for every property.
- `place_rank` and `importance` are not properties of the place. The first is how coarse its level
  in the administrative scale is and the second is the service's own ordering weight, so a rule
  over them orders results as the geocoder would, which is useful and is not a claim about the
  world.

### From a reply to a facts file

The map writes triples: `src/spike/geocode_map.ms` says one fact per property, subject from
`osm_type` and `osm_id`, `val` on the two coordinates because the reply writes them as strings,
and no fact at all for a field that is absent; `src/spike/declared.ms` turns those facts into
`.kb` text. Keeping `was-answer-to` makes a file's join reversible: it says which query produced
it, and a second run of the same query can be compared rather than merged.

The seams that remain - a place to record which fetch a file came from, and the engine's own -
are collected in [gaps to close before these APIs are knowledge](gaps.md).

## Endpoints

### `/search`

```
GET https://geocode.maps.co/search
```

An address, or a set of structured fields, to coordinates and a display name.

| Parameter | Type | Notes |
| --- | --- | --- |
| `q` | text | Free-form query, e.g. `"Eiffel Tower"`. |
| `amenity` | text | Place of interest, attraction or business name. |
| `street` | text | House number and street. |
| `city` | text | City name. |
| `county` | text | County or district. |
| `state` | text | State or region. |
| `country` | text | Country name. |
| `postalcode` | text | Postal code. |
| `addressdetails` | bool | Include the structured `address` object; default `1`. |
| `extratags` | bool | Include `extratags`; default `1`. |
| `namedetails` | bool | Include `namedetails`; default `1`. |
| `limit` | int | Most results to return, `0` to `40`; default `10`. |
| `countrycodes` | text | Restrict to these ISO 3166-1 alpha-2 codes, comma separated. |
| `viewbox` | text | Bias the search with a bounding box, `left,top,right,bottom`. |
| `bounded` | bool | Restrict results to the viewbox; default `0`. The service only honours it with a `viewbox`. |
| `dedupe` | bool | Drop duplicate OSM results; default `1`. |
| `format` | enum | `json`, `jsonv2`, `xml`, `geojson`, `geocodejson`; default `json`. |
| `accept-language` | text | Language the names come back in, e.g. `en` or `fr`. |

One of `q` or the structured fields is needed; the layer cannot tell which combination the
service will accept, so "Nothing to search for." comes back from the service rather than from
the layer.

### `/reverse`

```
GET https://geocode.maps.co/reverse
```

A coordinate to the nearest address, as one result.

| Parameter | Type | Notes |
| --- | --- | --- |
| `lat` | number | Latitude, `-90` to `90`. Required. |
| `lon` | number | Longitude, `-180` to `180`. Required. |
| `addressdetails` | bool | Include the structured `address` object; default `1`. |
| `extratags` | bool | Include `extratags`; default `1`. |
| `namedetails` | bool | Include `namedetails`; default `1`. |
| `zoom` | int | Detail level, `3` to `18`. The default is the service's. |
| `format` | enum | `json`, `jsonv2`, `xml`, `geojson`, `geocodejson`; default `json`. |
| `accept-language` | text | Language the names come back in. |

The reply is a single result object rather than a list. A point with no address near it is
still answered as an object; the service's own fields say how much it found.

### `/lookup`

```
GET https://geocode.maps.co/lookup
```

The details of objects named by OSM id, for when a result's `osm_type` and `osm_id` are
already known.

| Parameter | Type | Notes |
| --- | --- | --- |
| `osm_ids` | csv | Comma-separated ids with a type prefix, e.g. `R253832,W175905`. Required. |
| `addressdetails` | bool | Include the structured `address` object; default `1`. |
| `extratags` | bool | Include `extratags`; default `1`. |
| `namedetails` | bool | Include `namedetails`; default `1`. |
| `polygon_geojson` | bool | Include the polygon as GeoJSON; default `0`. |
| `polygon_kml` | bool | Include the polygon as KML; default `0`. |
| `polygon_svg` | bool | Include the polygon as SVG; default `0`. |
| `polygon_text` | bool | Include the polygon as text; default `0`. |
| `format` | enum | `json`, `jsonv2`, `xml`, `geojson`, `geocodejson`; default `json`. |
| `accept-language` | text | Language the names come back in. |

The prefix is the OSM object type: `N` for a node, `W` for a way, `R` for a relation. Ids
without one are refused by the service. The reply is a list, and an id the service cannot
find is simply absent from it.

## Refusals

A refused request comes back with a 4xx status and an error object:

```json
{"error": {"code": 400, "message": "Parameter 'lon' missing."}}
```

Some checks answer in plain text instead:

```text
ERROR 400: Parameter 'format' must be one of: xml, geojson, geocodejson, json, jsonv2
```

The layer turns either into `ok: 0` with an `error` such as `HTTP 400: …`. Because the JSON
error's message is nested under `error` rather than beside it, the status and the body are
what that message carries; the error carries the body it was given, not a field pulled out of
it.

A missing or wrong key answers `401`, which is the reason the layer does not send the
`Authorization` header the service's documentation mentions. The parameter is the working
path; a key the environment does not hold is refused before the call, so a `401` from here is a
key that was sent and rejected.

## How the map reads a result

`src/spike/geocode_map.ms` declares the three endpoints and one facts list: a result's name,
coordinates and bounding box, its OSM class and type, its address and its extra tags. The subject
is `osm_type`/`osm_id` joined with `/`, so the same OSM object is the same term whichever endpoint
sent it; a lookup result that carries a GeoJSON centroid instead of `lat` and `lon` names both
paths, longitude first. Only a search records `was-answer-to`, because only a search has a query.

`src/spike/declared.ms` reads a list reply (`/search`, `/lookup`) one result at a time and a
single-object reply (`/reverse`) as one, and leaves out a field the reply did not carry rather
than writing an empty term.

## What a question may ask

Two of the endpoints declare what a question can ask them, in the `provides` block
`src/providers.ms` collects into the session's registry:

```text
search:  [{"fact": ["has-latitude", "?place", "?lat"], "about": "?place",
           "from": {"q": ["has-name", "has-city"]}, "request": {"limit": 1}},
          {"fact": ["has-longitude", "?place", "?lon"], "about": "?place",
           "from": {"q": ["has-name", "has-city"]}, "request": {"limit": 1}}]
reverse: [{"fact": ["has-road", "?place", "?road"], "about": "?place",
           "from": {"lat": "has-latitude", "lon": "has-longitude"}},
          {"fact": ["has-house-number", "?place", "?number"], "about": "?place",
           "from": {"lat": "has-latitude", "lon": "has-longitude"}}]
```

`about` says the reply is read onto the place the question named. geocode.maps.co hangs its facts
on the OSM object, but `has-latitude(place-f1d6…, ?lat)` is a question about the domain's place,
so each fact the reply writes is read back onto that term. `from` fills the request's fields from
facts the session already holds about that place: the first of its `has-name` and `has-city`, or
its `has-latitude` and `has-longitude`, today's reading before an earlier day's. A field with only
an earlier day's reading behind it counts as unfilled, so the map that declares it is asked for a
newer one first and the old one is used only when nothing can. A place with neither is not asked about - there is
nothing to put in the request - so the question falls through to the prompt as it would with no
registry at all.

The search is also reached from the other direction: when a question needs a place's weather and
the session holds only that place's name or city, the forecast's request has no coordinates to be
filled with, so the search is asked for them first and the weather question comes round with them.
That is the session's doing rather than either map's - `src/providers.ms` says which fields a
request could not fill, and `src/session.ms` asks for one answer per pass - and it is why the
search's two declarations matter beyond a question that names a coordinate outright. The search
is not the only map declaring them: Open-Meteo's geocoder declares the same two facts, so when
the search cannot answer, the session asks the geocoder before the reader, in the order the
registry was built.

Nothing is asked at startup and `/lookup` declares nothing, since it needs an OSM id the session
has no way to settle on its own. The search sends `limit=1`, because one place's coordinates are
the first match's and a second answer would only be a second opinion.

The first match is worth the coordinates only if it is the place that was asked about, so the
search's reply block names the fields that make it so:
`"confirm": {"has-city": "address.city", "has-country": "address.country"}`.
`src/spike/declared.ms` looks each of those predicates up among the facts the session already
holds about that place and refuses the reply when the service's own word for the field disagrees
- a service's capitals, its accents, its abbreviations and the words a name may carry are the
same naming, so a search for `Washington, D.C.` is answered by a result that says `Washington`,
and one for `New York` by `City of New York` - so a search for Fort Worth that comes back with
another Springfield is a warning naming both cities, and those coordinates are not read onto this
place. What counts as the same naming is `samePlace` in `src/spike/declared.ms`: the words of a
name once case, accents, punctuation, one-letter initials and the administrative words are set
aside, with `St.` read as `Saint` and `Ft.` as `Fort`. Only that: `Newark` is not `New York City`,
`Paso` is not `El Paso`, and a name in another script that this cannot spell is compared as it
stands. A field the
session holds no fact under, or that the reply leaves out, is nothing to disagree with: the
declaration says which fields it can check, not that every reply must carry them.
