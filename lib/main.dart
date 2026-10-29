// Weather Information App - Flutter Lab Project
// Data source: Open-Meteo (https://open-meteo.com) - free, no API key needed.
//
// Features:
//  - Search weather by city name
//  - Current conditions (temp, feels like, humidity, wind, pressure)
//  - 7-day forecast
//  - Celsius / Fahrenheit toggle
//  - Loading and error handling

import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() => runApp(const WeatherApp());

// ---------------------------------------------------------------------------
// MODELS
// ---------------------------------------------------------------------------

class DailyForecast {
  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final int code;
  final double precipitation;
  final double uvIndex;
  final String sunrise;
  final String sunset;

  DailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.code,
    required this.precipitation,
    required this.uvIndex,
    required this.sunrise,
    required this.sunset,
  });
}

class WeatherData {
  final String city;
  final String region;
  final String country;
  final String timezone;
  final String updatedAt;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final double windGusts;
  final int windDirection;
  final double pressure;
  final double precipitation;
  final int cloudCover;
  final double uvIndex;
  final double visibility;
  final int code;
  final List<DailyForecast> daily;

  WeatherData({
    required this.city,
    required this.region,
    required this.country,
    required this.timezone,
    required this.updatedAt,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.windGusts,
    required this.windDirection,
    required this.pressure,
    required this.precipitation,
    required this.cloudCover,
    required this.uvIndex,
    required this.visibility,
    required this.code,
    required this.daily,
  });

  String get locationLabel =>
      [city, region, country].where((part) => part.isNotEmpty).join(', ');
}

// ---------------------------------------------------------------------------
// WEATHER CODE HELPERS (WMO codes used by Open-Meteo)
// ---------------------------------------------------------------------------

String describeCode(int code) {
  if (code == 0) return 'Clear sky';
  if (code == 1) return 'Mainly clear';
  if (code == 2) return 'Partly cloudy';
  if (code == 3) return 'Overcast';
  if (code == 45 || code == 48) return 'Foggy';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 71 && code <= 77) return 'Snow';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code == 85 || code == 86) return 'Snow showers';
  if (code == 95) return 'Thunderstorm';
  if (code == 96 || code == 99) return 'Thunderstorm with hail';
  return 'Unknown';
}

IconData iconForCode(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny;
  if (code == 2) return Icons.wb_cloudy_outlined;
  if (code == 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67) return Icons.grain;
  if (code >= 71 && code <= 77) return Icons.ac_unit;
  if (code >= 80 && code <= 82) return Icons.beach_access;
  if (code == 85 || code == 86) return Icons.ac_unit;
  if (code >= 95) return Icons.flash_on;
  return Icons.help_outline;
}

List<Color> gradientForCode(int code) {
  if (code == 0 || code == 1) {
    return [const Color(0xFF2193B0), const Color(0xFF6DD5ED)];
  }
  if (code == 2 || code == 3 || code == 45 || code == 48) {
    return [const Color(0xFF606C88), const Color(0xFF3F4C6B)];
  }
  if (code >= 51 && code <= 82) {
    return [const Color(0xFF373B44), const Color(0xFF4286F4)];
  }
  if (code >= 71 && code <= 77) {
    return [const Color(0xFF83A4D4), const Color(0xFFB6FBFF)];
  }
  if (code >= 95) {
    return [const Color(0xFF232526), const Color(0xFF414345)];
  }
  return [const Color(0xFF2193B0), const Color(0xFF6DD5ED)];
}

// ---------------------------------------------------------------------------
// SERVICE
// ---------------------------------------------------------------------------

class WeatherService {
  Future<WeatherData> fetchWeather(String city) async {
    final parts = city
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final searchName = parts.isEmpty ? city.trim() : parts.first;

    // Search by the city, then use the remaining query parts to disambiguate it.
    final geoUri = Uri.https(
      'geocoding-api.open-meteo.com',
      '/v1/search',
      {'name': searchName, 'count': '10', 'language': 'en', 'format': 'json'},
    );
    final geoRes = await http.get(geoUri).timeout(const Duration(seconds: 15));
    if (geoRes.statusCode != 200) {
      throw Exception('Could not look up the city (code ${geoRes.statusCode}).');
    }
    final geoJson = jsonDecode(geoRes.body) as Map<String, dynamic>;
    final results = geoJson['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw Exception('Place "$city" not found. Check the spelling.');
    }
    final places = results.cast<Map<String, dynamic>>();
    var place = places.first;
    var bestScore = -1;
    for (final candidate in places) {
      final searchableFields = [
        candidate['name'],
        candidate['admin1'],
        candidate['admin2'],
        candidate['admin3'],
        candidate['country'],
        candidate['country_code'],
      ].whereType<String>().map((value) => value.toLowerCase()).toList();
      var score = 0;
      for (final part in parts.skip(1)) {
        final queryPart = part.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (queryPart.isEmpty) continue;
        final normalizedFields = searchableFields
            .map((field) => field.replaceAll(RegExp(r'[^a-z0-9]'), ''));
        if (normalizedFields.any((field) => field == queryPart)) {
          score += 2;
        } else if (normalizedFields.any((field) => field.contains(queryPart))) {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        place = candidate;
      }
    }
    final lat = place['latitude'];
    final lon = place['longitude'];

    // Open-Meteo returns the latest available conditions for the place.
    final weatherUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current':
          'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,precipitation,cloud_cover,uv_index,visibility',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,uv_index_max,sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '7',
    });
    final res =
        await http.get(weatherUri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Weather service error (code ${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;

    final dates = daily['time'] as List<dynamic>;
    final maxes = daily['temperature_2m_max'] as List<dynamic>;
    final mins = daily['temperature_2m_min'] as List<dynamic>;
    final codes = daily['weather_code'] as List<dynamic>;
    final precipitation = daily['precipitation_sum'] as List<dynamic>;
    final uvIndexes = daily['uv_index_max'] as List<dynamic>;
    final sunrises = daily['sunrise'] as List<dynamic>;
    final sunsets = daily['sunset'] as List<dynamic>;

    final forecast = List<DailyForecast>.generate(
      dates.length,
      (i) => DailyForecast(
        date: DateTime.parse(dates[i] as String),
        maxTemp: (maxes[i] as num).toDouble(),
        minTemp: (mins[i] as num).toDouble(),
        code: (codes[i] as num).toInt(),
        precipitation: (precipitation[i] as num).toDouble(),
        uvIndex: (uvIndexes[i] as num).toDouble(),
        sunrise: sunrises[i] as String,
        sunset: sunsets[i] as String,
      ),
    );

    return WeatherData(
      city: place['name'] as String,
      region: (place['admin1'] ?? '') as String,
      country: (place['country'] ?? '') as String,
      timezone: (json['timezone'] ?? place['timezone'] ?? '') as String,
      updatedAt: current['time'] as String,
      temperature: (current['temperature_2m'] as num).toDouble(),
      feelsLike: (current['apparent_temperature'] as num).toDouble(),
      humidity: (current['relative_humidity_2m'] as num).toInt(),
      windSpeed: (current['wind_speed_10m'] as num).toDouble(),
      windGusts: (current['wind_gusts_10m'] as num).toDouble(),
      windDirection: (current['wind_direction_10m'] as num).toInt(),
      pressure: (current['pressure_msl'] as num).toDouble(),
      precipitation: (current['precipitation'] as num).toDouble(),
      cloudCover: (current['cloud_cover'] as num).toInt(),
      uvIndex: (current['uv_index'] as num).toDouble(),
      visibility: (current['visibility'] as num).toDouble(),
      code: (current['weather_code'] as num).toInt(),
      daily: forecast,
    );
  }
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const WeatherHomePage(),
    );
  }
}

class WeatherHomePage extends StatefulWidget {
  const WeatherHomePage({super.key});

  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage> {
  final _service = WeatherService();
  final _controller = TextEditingController();

  WeatherData? _weather;
  bool _loading = false;
  String? _error;
  bool _fahrenheit = false;
  Timer? _refreshTimer;
  String _lastQuery = 'Hyderabad';

  @override
  void initState() {
    super.initState();
    _search(_lastQuery);
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _search(_lastQuery),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String city) async {
    final query = city.trim();
    if (query.isEmpty) return;
    _lastQuery = query;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchWeather(query);
      setState(() => _weather = data);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  double _t(double celsius) =>
      _fahrenheit ? celsius * 9 / 5 + 32 : celsius;

  String get _unit => _fahrenheit ? '°F' : '°C';

  @override
  Widget build(BuildContext context) {
    final colors = _weather != null
        ? gradientForCode(_weather!.code)
        : [const Color(0xFF2193B0), const Color(0xFF6DD5ED)];

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'City, region, country (e.g. Tanuku, Andhra Pradesh, India)',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.9),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_controller.text),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(_fahrenheit ? '°F' : '°C'),
            selected: true,
            onSelected: (_) => setState(() => _fahrenheit = !_fahrenheit),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 56),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _search(
                    _controller.text.isEmpty ? 'Hyderabad' : _controller.text),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final w = _weather;
    if (w == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () => _search(w.city),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildCurrent(w),
          const SizedBox(height: 16),
          _buildDetails(w),
          const SizedBox(height: 16),
          _buildForecast(w),
        ],
      ),
    );
  }

  Widget _buildCurrent(WeatherData w) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          w.locationLabel,
          style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${DateFormat('EEEE, d MMM yyyy').format(DateTime.parse(w.updatedAt))}'
          '${w.timezone.isEmpty ? '' : ' • ${w.timezone}'}',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 3),
        Text(
          'Latest available • updated ${DateFormat('h:mm a').format(DateTime.parse(w.updatedAt))} local time',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Icon(iconForCode(w.code), color: Colors.white, size: 96),
        Text(
          '${_t(w.temperature).round()}$_unit',
          style: const TextStyle(
              color: Colors.white, fontSize: 72, fontWeight: FontWeight.w300),
        ),
        Text(
          describeCode(w.code),
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ],
    );
  }

  Widget _buildDetails(WeatherData w) {
    final items = [
      _Detail(Icons.thermostat, 'Feels like',
          '${_t(w.feelsLike).round()}$_unit'),
      _Detail(Icons.water_drop, 'Humidity', '${w.humidity}%'),
      _Detail(Icons.air, 'Wind', '${w.windSpeed.round()} km/h'),
      _Detail(Icons.air, 'Wind gusts', '${w.windGusts.round()} km/h'),
      _Detail(Icons.speed, 'Pressure', '${w.pressure.round()} hPa'),
      _Detail(Icons.grain, 'Precipitation', '${w.precipitation} mm'),
      _Detail(Icons.cloud, 'Cloud cover', '${w.cloudCover}%'),
      _Detail(Icons.wb_sunny_outlined, 'UV index', w.uvIndex.toStringAsFixed(1)),
      _Detail(Icons.visibility, 'Visibility',
          '${(w.visibility / 1000).toStringAsFixed(1)} km'),
      _Detail(Icons.explore, 'Wind direction',
          '${_compassDirection(w.windDirection)} (${w.windDirection}°)'),
    ];
    return Card(
      color: Colors.white.withValues(alpha: 0.2),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.65,
              children: items
                  .map((d) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(d.icon, color: Colors.white),
                          const SizedBox(height: 4),
                          Text(d.value,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          Text(d.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ))
                  .toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForecast(WeatherData w) {
    return Card(
      color: Colors.white.withValues(alpha: 0.2),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '7-Day Forecast',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
            ...w.daily.asMap().entries.map((e) {
              final i = e.key;
              final d = e.value;
              return ListTile(
                leading: Icon(iconForCode(d.code), color: Colors.white),
                isThreeLine: true,
                title: Text(
                  i == 0 ? 'Today' : DateFormat('EEEE').format(d.date),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${describeCode(d.code)} • Rain ${d.precipitation} mm • UV ${d.uvIndex.toStringAsFixed(1)}'
                  '\nSunrise ${DateFormat('h:mm a').format(DateTime.parse(d.sunrise))} • '
                  'Sunset ${DateFormat('h:mm a').format(DateTime.parse(d.sunset))}',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Text(
                  '${_t(d.maxTemp).round()}° / ${_t(d.minTemp).round()}°',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _compassDirection(int degrees) {
    const directions = [
      'N',
      'NE',
      'E',
      'SE',
      'S',
      'SW',
      'W',
      'NW',
    ];
    return directions[((degrees + 22) % 360) ~/ 45];
  }
}

class _Detail {
  final IconData icon;
  final String label;
  final String value;
  _Detail(this.icon, this.label, this.value);
}
