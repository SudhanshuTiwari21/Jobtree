import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Shared Indian city list for job seeker + job owner flows.
/// Uses [countriesnow.space](https://countriesnow.space) (public) with a static fallback.
class IndiaCityService {
  IndiaCityService._();
  static final IndiaCityService instance = IndiaCityService._();

  List<String>? _cache;

  /// Offline / API-failure fallback (merged from prior app lists + common hubs).
  static const List<String> kFallbackCities = [
    'Mumbai', 'Delhi', 'Bangalore', 'Hyderabad', 'Chennai', 'Kolkata',
    'Pune', 'Ahmedabad', 'Jaipur', 'Lucknow', 'Chandigarh', 'Noida', 'Gurgaon',
    'Indore', 'Bhopal', 'Surat', 'Nagpur', 'Patna', 'Kanpur', 'Thane',
    'Visakhapatnam', 'Vadodara', 'Ghaziabad', 'Ludhiana', 'Agra', 'Nashik',
    'Faridabad', 'Meerut', 'Rajkot', 'Varanasi', 'Srinagar', 'Aurangabad',
    'Dhanbad', 'Amritsar', 'Navi Mumbai', 'Prayagraj', 'Ranchi', 'Howrah',
    'Coimbatore', 'Jabalpur', 'Gwalior', 'Vijayawada', 'Jodhpur', 'Madurai',
    'Raipur', 'Kota', 'Guwahati', 'Solapur', 'Hubli', 'Mysore',
    'Tiruchirappalli', 'Bareilly', 'Moradabad', 'Mysuru', 'Warangal', 'Guntur',
    'Bhubaneswar', 'Salem', 'Jalandhar', 'Tirunelveli', 'Malegaon',
    'Kozhikode', 'Ajmer', 'Akola', 'Belgaum', 'Tirupati', 'Udaipur', 'Latur',
  ];

  /// Clears in-memory cache (e.g. after logout — optional).
  void clearCache() => _cache = null;

  Future<List<String>> loadCities({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    List<String> result = List<String>.from(kFallbackCities);

    try {
      final response = await http
          .post(
            Uri.parse('https://countriesnow.space/api/v0.1/countries/cities'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'country': 'india'}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['error'] == false && data['data'] != null) {
          final raw = List<String>.from(data['data'] as List);
          final deduped = _dedupeAndSort(raw);
          if (deduped.isNotEmpty) result = deduped;
        }
      }
    } catch (e, st) {
      debugPrint('IndiaCityService: API failed, using fallback: $e\n$st');
    }

    _cache = result;
    return _cache!;
  }

  List<String> _dedupeAndSort(List<String> cities) {
    final seen = <String>{};
    final out = <String>[];
    for (final c in cities) {
      final t = c.trim();
      if (t.length <= 2) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }
}
