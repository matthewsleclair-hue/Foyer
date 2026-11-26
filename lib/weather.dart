import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;

class GeoPlace {
  GeoPlace(this.name, this.region, this.country, this.lat, this.lon);
  final String name;
  final String region;
  final String country;
  final double lat;
  final double lon;
  String get label => [name, region, country].where((s) => s.isNotEmpty).join(', ');
}

/// Today's sunrise and sunset where you are (from the weather place), or null until known.
class SunTimes {
  SunTimes(this.rise, this.set);
  final DateTime rise;
  final DateTime set;
}

SunTimes? kSun;

class WeatherNow {
  WeatherNow(this.temp, this.code, this.isDay);
  final double temp;
  final int code;
  final bool isDay;

  String get label {
    if (code == 0) return 'Clear';
    if (code == 1) return 'Mostly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code == 66 || code == 67) return 'Freezing rain';
    if (code >= 61 && code <= 65) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Showers';
    if (code == 85 || code == 86) return 'Snow showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Weather';
  }

  IconData get icon {
    if (code == 0 || code == 1) return isDay ? Icons.wb_sunny : Icons.nightlight_round;
    if (code == 2) return Icons.wb_cloudy;
    if (code == 3) return Icons.cloud;
    if (code == 45 || code == 48) return Icons.blur_on;
    if (code >= 51 && code <= 57) return Icons.grain;
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return Icons.water_drop;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return Icons.ac_unit;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.cloud;
  }
}

/// Open-Meteo: free, no account or key.
class WeatherApi {
  static Future<dynamic> _get(Uri uri) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await c.getUrl(uri);
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}', uri: uri);
      return jsonDecode(body);
    } finally {
      c.close(force: true);
    }
  }

  static Future<List<GeoPlace>> search(String q) async {
    final j = await _get(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q, 'count': '6', 'language': 'en', 'format': 'json'}));
    final list = (j?['results'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => GeoPlace(
              (m['name'] ?? '').toString(),
              (m['admin1'] ?? '').toString(),
              (m['country'] ?? '').toString(),
              (m['latitude'] as num).toDouble(),
              (m['longitude'] as num).toDouble(),
            ))
        .toList();
  }

  static Future<WeatherNow> now(double lat, double lon, bool fahrenheit) async {
    final j = await _get(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,weather_code,is_day',
      'daily': 'sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '1',
      'temperature_unit': fahrenheit ? 'fahrenheit' : 'celsius',
    }));
    final c = j['current'] as Map;
    // today's sunrise and sunset there (local times, which is the TV's own zone)
    try {
      final d = j['daily'] as Map;
      final rise = DateTime.parse('${(d['sunrise'] as List).first}');
      final set = DateTime.parse('${(d['sunset'] as List).first}');
      kSun = SunTimes(rise, set);
    } catch (_) {}
    return WeatherNow((c['temperature_2m'] as num).toDouble(),
        (c['weather_code'] as num).toInt(), (c['is_day'] as num) == 1);
  }
}
