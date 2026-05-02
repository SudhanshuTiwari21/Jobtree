import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage keys
class StorageKeys {
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String salonData = 'salon_data';
  static const String seekerData = 'seeker_data';
  static const String userRole = 'user_role'; // 'salon' or 'seeker'
  static const String isLoggedIn = 'is_logged_in';
}

/// Auth Service - Manages authentication state and tokens
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Use secure storage for sensitive data (tokens)
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Cached values for quick access
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  Map<String, dynamic>? _cachedSalonData;
  Map<String, dynamic>? _cachedSeekerData;
  String? _cachedUserRole;

  /// Save access token
  Future<void> saveAccessToken(String token) async {
    _cachedAccessToken = token;
    await _secureStorage.write(key: StorageKeys.accessToken, value: token);
  }

  /// Save refresh token
  Future<void> saveRefreshToken(String token) async {
    _cachedRefreshToken = token;
    await _secureStorage.write(key: StorageKeys.refreshToken, value: token);
  }

  /// Save both tokens
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await saveAccessToken(accessToken);
    await saveRefreshToken(refreshToken);
    
    // Mark as logged in
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.isLoggedIn, true);
  }

  /// Get access token
  Future<String?> getAccessToken() async {
    if (_cachedAccessToken != null) {
      return _cachedAccessToken;
    }
    _cachedAccessToken = await _secureStorage.read(key: StorageKeys.accessToken);
    return _cachedAccessToken;
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null) {
      return _cachedRefreshToken;
    }
    _cachedRefreshToken = await _secureStorage.read(key: StorageKeys.refreshToken);
    return _cachedRefreshToken;
  }

  /// Save salon data (non-sensitive)
  Future<void> saveSalonData(dynamic salon) async {
    final prefs = await SharedPreferences.getInstance();
    if (salon is Map) {
      _cachedSalonData = Map<String, dynamic>.from(salon);
      await prefs.setString(StorageKeys.salonData, json.encode(salon));
    } else if (salon != null) {
      final salonMap = salon.toJson();
      _cachedSalonData = salonMap;
      await prefs.setString(StorageKeys.salonData, json.encode(salonMap));
    }
  }

  /// Get cached salon data
  Future<Map<String, dynamic>?> getSalonData() async {
    if (_cachedSalonData != null) {
      return _cachedSalonData;
    }
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(StorageKeys.salonData);
    if (data != null) {
      _cachedSalonData = json.decode(data);
      return _cachedSalonData;
    }
    return null;
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Save seeker data (non-sensitive)
  Future<void> saveSeekerData(dynamic seeker) async {
    final prefs = await SharedPreferences.getInstance();
    if (seeker is Map) {
      _cachedSeekerData = Map<String, dynamic>.from(seeker);
      await prefs.setString(StorageKeys.seekerData, json.encode(seeker));
    } else if (seeker != null) {
      final seekerMap = seeker.toJson();
      _cachedSeekerData = seekerMap;
      await prefs.setString(StorageKeys.seekerData, json.encode(seekerMap));
    }
    await saveUserRole('seeker');
  }

  /// Get cached seeker data
  Future<Map<String, dynamic>?> getSeekerData() async {
    if (_cachedSeekerData != null) return _cachedSeekerData;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(StorageKeys.seekerData);
    if (data != null) {
      _cachedSeekerData = json.decode(data);
      return _cachedSeekerData;
    }
    return null;
  }

  /// Save user role ('salon' or 'seeker')
  Future<void> saveUserRole(String role) async {
    _cachedUserRole = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.userRole, role);
  }

  /// Get user role
  Future<String?> getUserRole() async {
    if (_cachedUserRole != null) return _cachedUserRole;
    final prefs = await SharedPreferences.getInstance();
    _cachedUserRole = prefs.getString(StorageKeys.userRole);
    return _cachedUserRole;
  }

  /// Clear all tokens and data (logout)
  Future<void> clearTokens() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedSalonData = null;
    _cachedSeekerData = null;
    _cachedUserRole = null;
    
    await _secureStorage.delete(key: StorageKeys.accessToken);
    await _secureStorage.delete(key: StorageKeys.refreshToken);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.salonData);
    await prefs.remove(StorageKeys.seekerData);
    await prefs.remove(StorageKeys.userRole);
    await prefs.setBool(StorageKeys.isLoggedIn, false);
  }

  /// Clear cache only (for refresh)
  void clearCache() {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedSalonData = null;
    _cachedSeekerData = null;
    _cachedUserRole = null;
  }

  /// Update cached salon data
  void updateCachedSalonData(Map<String, dynamic> updates) {
    if (_cachedSalonData != null) {
      _cachedSalonData!.addAll(updates);
    }
  }

  /// Get salon ID from cached data
  Future<String?> getSalonId() async {
    final data = await getSalonData();
    return data?['id'];
  }

  /// Get phone number from cached data
  Future<String?> getPhoneNumber() async {
    final role = await getUserRole();
    if (role == 'seeker') {
      final data = await getSeekerData();
      return data?['phoneNumber'];
    }
    final data = await getSalonData();
    return data?['phoneNumber'];
  }

  /// Get seeker ID from cached data
  Future<String?> getSeekerId() async {
    final data = await getSeekerData();
    return data?['id'];
  }
}

