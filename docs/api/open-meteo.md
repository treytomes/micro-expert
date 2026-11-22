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
