# The geocode.maps.co API surface

geocode.maps.co is a small geocoder over OpenStreetMap data: an address in, coordinates and a
display name out, and the reverse. It has three GET endpoints, and `src/api/geocode.ms` holds
all three with every parameter each one takes. `src/geocode.ms` is the program built on that
table.

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
- The key is the `api_key` parameter, added to every request. The program reads
  `GEOCODE_MAPS_API_KEY` from the environment or the nearest `.env` and hands it to the layer,
  which sends it and keeps it out of any URL it prints. The service's documentation also names
  an `Authorization: Bearer` header; that path answers `401`, so the parameter is the only one
  used.
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

`format=xml`, `format=geojson` and `format=geocodejson` answer in those formats instead.
`geojson` and `geocodejson` are still JSON, so the layer's `json` field is filled;
`xml` is not, so `json` is `null` and the program prints the body as it came. The result
fields above are the `json`/`jsonv2` shape; `geocodejson` moves them under
`features[].properties.geocoding`.

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
what that message carries; the program prints the body it was given, not a field pulled out of
it.

A missing or wrong key answers `401`, which is the reason the layer does not send the
`Authorization` header the service's documentation mentions. The parameter is the working
path.

## How the program maps to all this

`src/geocode.ms` takes the endpoint as a word - `search`, `reverse`, `lookup` - or as nothing
for a bare query, and every parameter above as a `--name`:

```
miniscript src/geocode.ms "Eiffel Tower" --limit 1
miniscript src/geocode.ms reverse --lat 48.8583 --lon 2.2945 --zoom 18
miniscript src/geocode.ms lookup --osm-ids R253832,W175905 --polygon-geojson
miniscript src/geocode.ms search --q Berlin --format geojson --json
```

Underscores and dashes are the same in a name, `--name value` and `--name=value` are the same
form, and a boolean is `--name`, `--name false` or `--no-name` - which the service receives
as `1` or `0`, since it ignores the word `false`. `--json` prints the parsed JSON indented;
without it, and with `--format xml`, the body is printed as it came.

The command line is declared with the repo's cli library, so `--help` is generated from the
same table this page's parameter lists come from and the request is checked against: it
names every parameter with what it takes, and `--version` prints the version line. A name
that is not a parameter is refused by the parser, and a value the table cannot use - a
`limit` of 100, a `format` that is not one of the five - is reported before anything is
sent, rather than as a service refusal afterward.
