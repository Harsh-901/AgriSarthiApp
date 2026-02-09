import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class FarmerProfile {
  final String? id;
  final String phoneNumber;
  final String fullName;
  final String state;
  final String district;
  final String village;
  final double landSize;
  final String primaryCrop;
  final String preferredLanguage;
  final String? userId;
  final DateTime? createdAt;

  FarmerProfile({
    this.id,
    required this.phoneNumber,
    required this.fullName,
    required this.state,
    required this.district,
    required this.village,
    required this.landSize,
    required this.primaryCrop,
    required this.preferredLanguage,
    this.userId,
    this.createdAt,
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
      'language': preferredLanguage,
      // 'user_id': userId ?? SupabaseConfig.currentUser?.id,
    };
  }

  factory FarmerProfile.fromJson(Map<String, dynamic> json) {
    return FarmerProfile(
      id: json['id']?.toString(),
      phoneNumber: json['phone'] ?? '',
      fullName: json['name'] ?? '',
      state: json['state'] ?? '',
      district: json['district'] ?? '',
      village: json['village'] ?? '',
      landSize: (json['land_size'] ?? 0).toDouble(),
      primaryCrop: json['crop_type'] ?? '',
      preferredLanguage: json['language'] ?? '',
      // userId: json['user_id'],
      // createdAt: json['created_at'] != null
      //     ? DateTime.parse(json['created_at'])
      //     : null,
    );
  }
}

class FarmerService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Table name in Supabase
  static const String _tableName = 'farmers';

  // Create or update farmer profile
  Future<FarmerProfile?> saveFarmerProfile(FarmerProfile profile) async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if profile already exists
      final existingProfile = await getFarmerProfile();

      if (existingProfile != null) {
        // Update existing profile
        final response = await _client
            .from(_tableName)
            .update(profile.toJson())
            .eq('user_id', userId)
            .select()
            .single();

        return FarmerProfile.fromJson(response);
      } else {
        // Insert new profile
        final response = await _client
            .from(_tableName)
            .insert(profile.toJson())
            .select()
            .single();

        return FarmerProfile.fromJson(response);
      }
    } catch (e) {
      throw Exception('Failed to save profile: $e');
    }
  }

  // Get current farmer profile
  Future<FarmerProfile?> getFarmerProfile() async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        return null;
      }

      final response = await _client
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        return FarmerProfile.fromJson(response);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Check if farmer has completed profile
  Future<bool> hasCompletedProfile() async {
    final profile = await getFarmerProfile();
    return profile != null && profile.fullName.isNotEmpty;
  }

  // Get farmer by phone number
  Future<FarmerProfile?> getFarmerByPhone(String phoneNumber) async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .eq('phone', phoneNumber)
          .maybeSingle();

      if (response != null) {
        return FarmerProfile.fromJson(response);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
