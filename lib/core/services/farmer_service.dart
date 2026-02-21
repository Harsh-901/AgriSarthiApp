import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../config/api_config.dart';

class FarmerProfile {
  final String? id;
  final String phoneNumber;
  final String fullName;
  final String state;
  final String district;
  final String village;
  final double landSize;
  final String primaryCrop;
  final List<String> crops;
  final String preferredLanguage;
  final String? dateOfBirth;
  final String? gender;
  final String? aadhaarLastFour;
  final String? surveyNumber;
  final int? age;

  FarmerProfile({
    this.id,
    required this.phoneNumber,
    required this.fullName,
    required this.state,
    required this.district,
    required this.village,
    required this.landSize,
    required this.primaryCrop,
    this.crops = const [],
    required this.preferredLanguage,
    this.dateOfBirth,
    this.gender,
    this.aadhaarLastFour,
    this.surveyNumber,
    this.age,
  });

  Map<String, dynamic> toJson() {
    return {
      'phone': phoneNumber,
      'name': fullName,
      'state': state,
      'district': district,
      'village': village,
      'land_size': landSize,
      'crop_type': primaryCrop,
      'crops': crops,
      'language': preferredLanguage,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (gender != null) 'gender': gender,
      if (aadhaarLastFour != null) 'aadhaar_last_four': aadhaarLastFour,
      if (surveyNumber != null) 'survey_number': surveyNumber,
    };
  }

  factory FarmerProfile.fromJson(Map<String, dynamic> json) {
    // Parse crops - could be a JSON string or a list
    List<String> parseCrops(dynamic cropsData) {
      if (cropsData == null) return [];
      if (cropsData is List) return cropsData.cast<String>();
      if (cropsData is String) {
        try {
          final parsed = jsonDecode(cropsData);
          if (parsed is List) return parsed.cast<String>();
        } catch (_) {}
        return [cropsData];
      }
      return [];
    }

    return FarmerProfile(
      id: json['id']?.toString(),
      phoneNumber: json['phone'] ?? '',
      fullName: json['name'] ?? '',
      state: json['state'] ?? '',
      district: json['district'] ?? '',
      village: json['village'] ?? '',
      landSize: (json['land_size'] ?? 0).toDouble(),
      primaryCrop: json['crop_type'] ?? '',
      crops: parseCrops(json['crops']),
      preferredLanguage: json['language'] ?? '',
      dateOfBirth: json['date_of_birth']?.toString(),
      gender: json['gender']?.toString(),
      aadhaarLastFour: json['aadhaar_last_four']?.toString(),
      surveyNumber: json['survey_number']?.toString(),
      age: json['age'] as int? ?? json['calculated_age'] as int?,
    );
  }

  bool get isComplete =>
      fullName.isNotEmpty && state.isNotEmpty && village.isNotEmpty;
}

/// FarmerService that uses Supabase directly for profile management
/// Uses phone number as the unique identifier
class FarmerService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  /// Get 10-digit phone number from Supabase user
  String? _getPhoneFromUser() {
    final user = _supabase.auth.currentUser;
    if (user == null || user.phone == null) return null;

    String phone = user.phone!.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');

    // Standardize Indian numbers: 10 digits
    if (phone.startsWith('91') && phone.length == 12) {
      phone = phone.substring(2);
    } else if (phone.length > 10) {
      phone = phone.substring(phone.length - 10);
    }

    return phone;
  }

  /// Get auth token
  String? _getAuthToken() {
    return _supabase.auth.currentSession?.accessToken;
  }

  /// Get current user's farmer profile from Supabase
  Future<FarmerProfile?> getFarmerProfile() async {
    try {
      final phone = _getPhoneFromUser();
      if (phone == null) {
        debugPrint('FarmerService: No phone number for current user');
        return null;
      }

      debugPrint('FarmerService: Looking for farmer with phone=$phone');

      final response = await _supabase
          .from('farmers')
          .select()
          .eq('phone', phone)
          .maybeSingle();

      if (response != null) {
        debugPrint('FarmerService: Found existing profile');
        return FarmerProfile.fromJson(response);
      }

      debugPrint('FarmerService: No existing profile found');
      return null;
    } on PostgrestException catch (e) {
      debugPrint('FarmerService: PostgrestException - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('FarmerService: Error getting profile - $e');
      return null;
    }
  }

  /// Save or update farmer profile in Supabase
  /// Uses phone as the unique identifier
  Future<FarmerProfile?> saveFarmerProfile(FarmerProfile profile) async {
    try {
      final phone = _getPhoneFromUser();
      if (phone == null) {
        throw Exception('User not authenticated or no phone number');
      }

      debugPrint('FarmerService: Saving profile for phone $phone');

      // Check if profile exists
      final existing = await getFarmerProfile();

      // Ensure the phone in profile matches the authenticated user's phone
      final data = profile.toJson();
      data['phone'] = phone; // Always use the authenticated user's phone

      debugPrint('FarmerService: Profile data to save: $data');

      if (existing != null && existing.id != null) {
        // Update existing profile
        debugPrint(
            'FarmerService: Updating existing profile id=${existing.id}');

        final response = await _supabase
            .from('farmers')
            .update(data)
            .eq('id', existing.id!)
            .select()
            .single();

        debugPrint('FarmerService: Update successful');
        return FarmerProfile.fromJson(response);
      } else {
        // Insert new profile
        debugPrint('FarmerService: Inserting new profile');

        final response =
            await _supabase.from('farmers').insert(data).select().single();

        debugPrint('FarmerService: Insert successful');
        return FarmerProfile.fromJson(response);
      }
    } on PostgrestException catch (e) {
      debugPrint('FarmerService: PostgrestException - ${e.message}');
      debugPrint('FarmerService: Details - ${e.details}');
      debugPrint('FarmerService: Hint - ${e.hint}');
      throw Exception('Database error: ${e.message}');
    } catch (e) {
      debugPrint('FarmerService: Error saving profile - $e');
      throw Exception('Failed to save profile: $e');
    }
  }

  /// Auto-fill farmer profile using OCR-extracted data + crop selection
  /// Calls the backend /api/farmers/profile/auto-fill/ endpoint
  Future<FarmerProfile?> autoFillProfile({
    required Map<String, dynamic> aadhaarData,
    required Map<String, dynamic> sevenTwelveData,
    required List<String> selectedCrops,
    String language = 'hindi',
  }) async {
    try {
      final token = _getAuthToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Merge OCR data with user selections
      final payload = <String, dynamic>{
        // From Aadhaar
        if (aadhaarData['name'] != null &&
            aadhaarData['name'].toString().isNotEmpty)
          'name': aadhaarData['name'],
        if (aadhaarData['date_of_birth'] != null &&
            aadhaarData['date_of_birth'].toString().isNotEmpty)
          'date_of_birth': aadhaarData['date_of_birth'],
        if (aadhaarData['gender'] != null &&
            aadhaarData['gender'].toString().isNotEmpty)
          'gender': aadhaarData['gender'],
        if (aadhaarData['aadhaar_number_masked'] != null)
          'aadhaar_last_four': aadhaarData['aadhaar_number_masked']
              .toString()
              .replaceAll(RegExp(r'[^0-9]'), ''),

        // From 7/12
        if (sevenTwelveData['state'] != null &&
            sevenTwelveData['state'].toString().isNotEmpty)
          'state': sevenTwelveData['state'],
        if (sevenTwelveData['district'] != null &&
            sevenTwelveData['district'].toString().isNotEmpty)
          'district': sevenTwelveData['district'],
        if (sevenTwelveData['village'] != null &&
            sevenTwelveData['village'].toString().isNotEmpty)
          'village': sevenTwelveData['village'],
        if (sevenTwelveData['land_size'] != null &&
            (sevenTwelveData['land_size'] as num) > 0)
          'land_size': sevenTwelveData['land_size'],
        if (sevenTwelveData['survey_number'] != null &&
            sevenTwelveData['survey_number'].toString().isNotEmpty)
          'survey_number': sevenTwelveData['survey_number'],

        // User selections
        'crops': selectedCrops,
        'language': language,
      };

      debugPrint('FarmerService: Auto-filling profile with: $payload');

      final response = await http.post(
        Uri.parse(ApiConfig.farmersAutoFill),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      debugPrint('FarmerService: Auto-fill response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
          return FarmerProfile.fromJson(jsonResponse['data']);
        }
      }

      debugPrint('FarmerService: Auto-fill failed: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('FarmerService: Error auto-filling profile: $e');
      throw Exception('Failed to auto-fill profile: $e');
    }
  }

  /// Check if farmer has completed profile
  Future<bool> hasCompletedProfile() async {
    final profile = await getFarmerProfile();
    return profile != null && profile.isComplete;
  }

  /// Get farmer ID for the current user
  Future<String?> getFarmerId() async {
    final profile = await getFarmerProfile();
    return profile?.id;
  }
}
