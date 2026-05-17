# METAR Reader

A Ruby on Rails application that fetches live METAR weather reports for any airport in the world and translates the cryptic raw data into plain English.

**METAR** (Meteorological Aerodrome Report) is the standard format used by pilots and aviation authorities worldwide. It looks like this:

```
METAR KJFK 171851Z 18015KT 10SM FEW050 FEW250 25/15 A3005
```

METAR Reader turns that into something anyone can understand:

> - Few clouds at 5,000 feet
> - Temperature 77°F (25°C)
> - Wind from the South (180°) at 15 knots
> - Visibility 10 statute miles
> - Pressure 30.05 inHg

Observation times are automatically displayed in the user's local timezone.

---

## Features

- Search any ICAO airport code worldwide (e.g. `KJFK`, `KSLC`, `EGLL`, `OMDB`)
- Decodes wind direction, speed, and gusts into compass-point English
- Translates sky conditions, cloud layers, visibility, precipitation, and more
- Converts temperature from Celsius to Fahrenheit
- Displays observation time in the user's local timezone (detected from IP)
- Shows up to 5 recently searched airports for quick re-access
- Collapsible raw METAR for reference
- Data sourced live from [aviationweather.gov](https://aviationweather.gov)

---

## Requirements

- Ruby 3.2+
- Rails 8.1+
- SQLite3
- Node.js (for Tailwind CSS compilation)

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/shawnpk/metar
cd metar-reader
```

### 2. Install dependencies

```bash
bundle install
```

### 3. Set up the database

```bash
bin/rails db:prepare
```

### 4. Start the development server

```bash
bin/dev
```

The app will be available at **http://localhost:3000**.

---

## Usage

1. Enter a 4-letter ICAO airport code in the search box (e.g. `KSLC` for Salt Lake City)
2. Click **Decode**
3. Read the plain-English weather report
4. Use the **Recent searches** chips on the home page to quickly revisit airports

> **Tip:** US airports typically start with `K`, Canadian airports with `C`, UK airports with `EG`, and Australian airports with `Y`.

---

## Project Structure

```
app/
├── controllers/
│   ├── application_controller.rb   # IP-based timezone detection (via geocoder)
│   └── weather_controller.rb       # Handles search, display, and recent history
├── services/
│   ├── metar_fetcher_service.rb    # Fetches raw METAR from aviationweather.gov
│   └── metar_decoder_service.rb    # Parses and decodes METAR into structured data
└── views/
    └── weather/
        ├── index.html.erb          # Search form + recent airports
        └── show.html.erb           # Decoded weather report
```

---

## How METAR Decoding Works

The `MetarDecoderService` tokenizes the raw METAR string and extracts:

|    Field   |   Example  |              Decoded             |
|------------|------------|----------------------------------|
| Station    | `KJFK`       | Airport identifier               |
| Date/Time  | `171851Z`    | May 17, 6:51 PM EDT              |
| Wind       | `18015G25KT` | South at 15 knots, gusting to 25 |
| Visibility | `10SM`       | 10 statute miles                 |
| Sky        | `BKN040`     | Broken clouds at 4,000 ft        |
| Temp/Dew   | `25/15`      | 77°F (25°C) / 59°F (15°C)        |
| Altimeter  | `A3005`      | 30.05 inHg                       |
| Weather    | `+TSRA`      | Heavy thunderstorm with rain     |

---

## License

MIT
