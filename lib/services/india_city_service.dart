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
    'Agra', 'Ahmedabad', 'Ajmer', 'Akola', 'Aligarh', 'Allahabad', 'Amravati', 'Amritsar',
    'Asansol', 'Aurangabad', 'Bangalore', 'Bareilly', 'Belgaum', 'Bhopal', 'Bhubaneswar',
    'Bikaner', 'Chandigarh', 'Chennai', 'Coimbatore', 'Cuttack', 'Dehradun', 'Delhi',
    'Dhanbad', 'Faridabad', 'Gandhinagar', 'Ghaziabad', 'Goa', 'Gorakhpur', 'Guntur',
    'Gurgaon', 'Guwahati', 'Gwalior', 'Howrah', 'Hubli', 'Hyderabad', 'Indore', 'Jabalpur',
    'Jaipur', 'Jalandhar', 'Jammu', 'Jamshedpur', 'Jodhpur', 'Kanpur', 'Kochi', 'Kolhapur',
    'Kolkata', 'Kota', 'Kozhikode', 'Lucknow', 'Ludhiana', 'Madurai', 'Malegaon', 'Mangalore',
    'Meerut', 'Moradabad', 'Mumbai', 'Mysore', 'Mysuru', 'Nagpur', 'Nashik', 'Navi Mumbai',
    'Noida', 'Patna', 'Prayagraj', 'Pune', 'Raipur', 'Rajkot', 'Ranchi', 'Salem', 'Shimla',
    'Solapur', 'Srinagar', 'Surat', 'Thane', 'Thiruvananthapuram', 'Tiruchirappalli',
    'Tirunelveli', 'Tirupati', 'Udaipur', 'Vadodara', 'Varanasi', 'Vijayawada',
    'Visakhapatnam', 'Warangal',
  ];

  /// Clears in-memory cache (e.g. after logout — optional).
  void clearCache() => _cache = null;

  /// [hindi] uses the same Latin city names; list is always sorted A–Z for pickers.
  Future<List<String>> loadCities({bool forceRefresh = false, bool hindi = false}) async {
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

    _cache = _dedupeAndSort(result, hindi: hindi);
    return _cache!;
  }

  List<String> _dedupeAndSort(List<String> cities, {bool hindi = false}) {
    final seen = <String>{};
    final out = <String>[];
    for (final c in cities) {
      final t = c.trim();
      if (t.length <= 2) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) out.add(t);
    }
    out.sort((a, b) {
      final ka = a.toLowerCase();
      final kb = b.toLowerCase();
      return ka.compareTo(kb);
    });
    return out;
  }
}
