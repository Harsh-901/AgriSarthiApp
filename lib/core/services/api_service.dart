import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
<<<<<<< HEAD
=======
import '../config/api_config.dart';
>>>>>>> new

/// Service for communicating with the Django backend (AgriSarthi)
/// Uses Django JWT auth tokens (separate from Supabase auth)
class ApiService {
<<<<<<< HEAD
  static const String baseUrl = 'https://agrisarthi.onrender.com';
=======
  // For production: https://agrisarthi.onrender.com
  // For local development on emulator: http://10.0.2.2:8000
  // For local development on physical device: use your computer's IP (e.g., http://192.168.1.5:8000)
  static String get baseUrl => ApiConfig.baseUrl;
>>>>>>> new

  static const String _accessTokenKey = 'django_access_token';
  static const String _refreshTokenKey = 'django_refresh_token';
  static const String _farmerIdKey = 'django_farmer_id';

  String? _accessToken;
  String? _refreshToken;
  String? _djangoFarmerId;

  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Whether we have a Django auth token
  bool get isAuthenticated => _accessToken != null;
<<<<<<< HEAD
=======
  String? get accessToken => _accessToken;
>>>>>>> new
  String? get djangoFarmerId => _djangoFarmerId;

  /// Initialize - load saved tokens
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _djangoFarmerId = prefs.getString(_farmerIdKey);
    debugPrint('ApiService: Initialized. Has token: ${_accessToken != null}');
  }

  /// Save tokens locally
  Future<void> _saveTokens(
      String access, String refresh, String farmerId) async {
    _accessToken = access;
    _refreshToken = refresh;
    _djangoFarmerId = farmerId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, access);
    await prefs.setString(_refreshTokenKey, refresh);
    await prefs.setString(_farmerIdKey, farmerId);
  }

  /// Clear saved tokens
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _djangoFarmerId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_farmerIdKey);
  }

  /// Login to Django backend using phone + OTP
  /// Step 1: Send OTP
  Future<Map<String, dynamic>> sendDjangoOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
<<<<<<< HEAD
      );
=======
      ).timeout(const Duration(seconds: 10));
>>>>>>> new

      final data = jsonDecode(response.body);
      debugPrint('ApiService: Send OTP response: $data');
      return data;
    } catch (e) {
      debugPrint('ApiService: Send OTP error: $e');
<<<<<<< HEAD
      return {'success': false, 'message': 'Network error: $e'};
=======
      return {'success': false, 'message': 'Connection timed out or failed'};
>>>>>>> new
    }
  }

  /// Login to Django backend using phone + OTP
  /// Step 2: Verify OTP and get tokens
  Future<Map<String, dynamic>> verifyDjangoOtp(String phone, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
<<<<<<< HEAD
      );
=======
      ).timeout(const Duration(seconds: 10));
>>>>>>> new

      final data = jsonDecode(response.body);
      debugPrint('ApiService: Verify OTP response: ${data['success']}');

      if (data['success'] == true && data['data'] != null) {
        await _saveTokens(
          data['data']['access_token'],
          data['data']['refresh_token'],
          data['data']['farmer_id'],
        );
      }

      return data;
    } catch (e) {
      debugPrint('ApiService: Verify OTP error: $e');
<<<<<<< HEAD
      return {'success': false, 'message': 'Network error: $e'};
=======
      return {'success': false, 'message': 'Connection timed out'};
>>>>>>> new
    }
  }

  /// Refresh the access token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
<<<<<<< HEAD
      );
=======
      ).timeout(const Duration(seconds: 5));
>>>>>>> new

      final data = jsonDecode(response.body);
      if (data['success'] == true && data['data'] != null) {
        _accessToken = data['data']['access_token'];
        _refreshToken = data['data']['refresh_token'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_accessTokenKey, _accessToken!);
        await prefs.setString(_refreshTokenKey, _refreshToken!);
        return true;
      }
    } catch (e) {
      debugPrint('ApiService: Token refresh error: $e');
    }
    return false;
  }

  /// Make authenticated GET request to Django
  Future<Map<String, dynamic>> get(String endpoint) async {
    if (_accessToken == null) {
      return {'success': false, 'message': 'Not authenticated with server'};
    }

    try {
      var response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
<<<<<<< HEAD
      );
=======
      ).timeout(const Duration(seconds: 15));
>>>>>>> new

      // If 401, try refreshing token
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          response = await http.get(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_accessToken',
            },
<<<<<<< HEAD
          );
=======
          ).timeout(const Duration(seconds: 15));
>>>>>>> new
        } else {
          return {
            'success': false,
            'message': 'Session expired. Please re-login.'
          };
        }
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('ApiService: GET $endpoint error: $e');
<<<<<<< HEAD
      return {'success': false, 'message': 'Network error: $e'};
=======
      return {'success': false, 'message': 'Connection error or timeout'};
>>>>>>> new
    }
  }

  /// Make authenticated POST request to Django
  Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    if (_accessToken == null) {
      return {'success': false, 'message': 'Not authenticated with server'};
    }

    try {
      var response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode(body),
<<<<<<< HEAD
      );
=======
      ).timeout(const Duration(seconds: 15));
>>>>>>> new

      // If 401, try refreshing token
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          response = await http.post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_accessToken',
            },
            body: jsonEncode(body),
<<<<<<< HEAD
          );
=======
          ).timeout(const Duration(seconds: 15));
>>>>>>> new
        } else {
          return {
            'success': false,
            'message': 'Session expired. Please re-login.'
          };
        }
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('ApiService: POST $endpoint error: $e');
<<<<<<< HEAD
      return {'success': false, 'message': 'Network error: $e'};
=======
      return {'success': false, 'message': 'Connection error or timeout'};
>>>>>>> new
    }
  }
}
