# Weather Predict — Flutter Mini Project

A Flutter web weather app that searches places worldwide and displays the latest available weather conditions and a 7-day forecast.

Search using a city, region, and country, for example:

```text
Tanuku, Andhra Pradesh, India
```

## Features

- Worldwide place search, including region/country to distinguish similarly named places
- Current temperature, feels-like temperature, humidity, wind speed and gusts, wind direction, pressure, precipitation, cloud cover, UV index, and visibility
- Seven-day high/low temperature and condition forecast, with precipitation, UV index, sunrise, and sunset
- Celsius/Fahrenheit toggle
- Refresh by pulling down or automatically every 15 minutes
- Weather-dependent background and condition icons

Weather and geocoding data are provided by the free [Open-Meteo APIs](https://open-meteo.com/); no API key is required. “Latest available” means the most recent data returned by the provider and may not be an instantaneous local-station observation.

## Requirements

- Flutter SDK (3.0 or later)
- Google Chrome
- Internet access

## Run in Chrome

Open a terminal in the project folder and run:

```powershell
flutter pub get
flutter run -d chrome
```

To clone the project first:

```powershell
git clone https://github.com/Annamdevula-Nissi-Grace/Weather_Predict_flutterminiproject.git
cd Weather_Predict_flutterminiproject
flutter pub get
flutter run -d chrome
```

## Run tests

```powershell
flutter test
```

## Project structure

- `lib/main.dart` — app UI, worldwide location lookup, and weather API integration
- `test/widget_test.dart` — widget smoke test
- `web/` — Flutter web entry point and assets
- `pubspec.yaml` — Flutter and package dependencies
