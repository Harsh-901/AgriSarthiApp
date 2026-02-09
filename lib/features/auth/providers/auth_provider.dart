import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/farmer_service.dart';

enum AuthState {
  initial,
  loading,
  otpSent,
  authenticated,
  error,
}

enum UserRole {
  farmer,
  admin,
}

/// Auth Provider using Supabase Auth for OTP and Supabase DB for farmer profile
class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.initial;
  String? _errorMessage;
  UserRole _currentRole = UserRole.farmer;
  String? _phoneNumber;
  String? _farmerId;
  bool _isNewUser = false;
  bool _isProfileComplete = false;
  User? _supabaseUser;

  // Getters
  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  UserRole get currentRole => _currentRole;
  String? get phoneNumber => _phoneNumber;
  String? get accessToken => SupabaseConfig.currentSession?.accessToken;
  String? get farmerId => _farmerId;
  bool get isAuthenticated => _supabaseUser != null;
  bool get isNewUser => _isNewUser;
  bool get isProfileComplete => _isProfileComplete;
  User? get supabaseUser => _supabaseUser;

  final SupabaseClient _supabase = SupabaseConfig.client;
  final FarmerService _farmerService = FarmerService();

  // Get display phone number (10 digits only)
  String get displayPhoneNumber {
    final phone = _phoneNumber ?? _supabaseUser?.phone;
    if (phone == null || phone.isEmpty) return '';
    if (phone.startsWith('+91')) {
      return phone.substring(3);
    }
    if (phone.length > 10) {
      return phone.substring(phone.length - 10);
    }
    return phone;
  }

  AuthProvider() {
    _loadSession();
    _listenToSupabaseAuth();
  }

  /// Listen to Supabase auth state changes
  void _listenToSupabaseAuth() {
    _supabase.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        _supabaseUser = data.session!.user;
        _phoneNumber = _supabaseUser?.phone;

        // Check for existing farmer profile
        await _checkFarmerProfile();
        notifyListeners();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _supabaseUser = null;
        _farmerId = null;
        _isProfileComplete = false;
        notifyListeners();
      }
    });
  }

  /// Check if farmer has profile in Supabase
  Future<void> _checkFarmerProfile() async {
    try {
      final profile = await _farmerService.getFarmerProfile();
      if (profile != null) {
        _farmerId = profile.id;
        _isProfileComplete = profile.isComplete;
        _isNewUser = false;
      } else {
        _isNewUser = true;
        _isProfileComplete = false;
      }
    } catch (e) {
      debugPrint('Error checking farmer profile: $e');
    }
  }

  /// Load saved session from SharedPreferences
  Future<void> _loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _farmerId = prefs.getString('farmer_id');
      _phoneNumber = prefs.getString('phone_number');
      _isProfileComplete = prefs.getBool('profile_complete') ?? false;

      // Check Supabase session
      final session = _supabase.auth.currentSession;
      if (session != null) {
        _supabaseUser = session.user;
        _phoneNumber = _supabaseUser?.phone ?? _phoneNumber;
        _state = AuthState.authenticated;

        // Verify farmer profile
        await _checkFarmerProfile();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load session: $e');
    }
  }

  /// Save session to SharedPreferences
  Future<void> _saveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_farmerId != null) {
        await prefs.setString('farmer_id', _farmerId!);
      }
      if (_phoneNumber != null) {
        await prefs.setString('phone_number', _phoneNumber!);
      }
      await prefs.setBool('profile_complete', _isProfileComplete);
    } catch (e) {
      debugPrint('Failed to save session: $e');
    }
  }

  /// Clear session
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('farmer_id');
      await prefs.remove('phone_number');
      await prefs.remove('profile_complete');
    } catch (e) {
      debugPrint('Failed to clear session: $e');
    }
  }

  void setRole(UserRole role) {
    _currentRole = role;
    notifyListeners();
  }

  /// Send OTP using Supabase Auth (Twilio)
  Future<bool> sendOtp(String phoneNumber) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      // Format phone with country code
      String formattedPhone = phoneNumber;
      if (!phoneNumber.startsWith('+')) {
        formattedPhone = '+91$phoneNumber';
      }

      _phoneNumber = formattedPhone;

      // Use Supabase to send OTP via Twilio
      await _supabase.auth.signInWithOtp(
        phone: formattedPhone,
      );

      _state = AuthState.otpSent;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = 'Failed to send OTP. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Verify OTP using Supabase
  Future<bool> verifyOtp(String otp) async {
    if (_phoneNumber == null) {
      _errorMessage = 'Phone number not set';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }

    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      // Verify OTP with Supabase
      final response = await _supabase.auth.verifyOTP(
        phone: _phoneNumber!,
        token: otp,
        type: OtpType.sms,
      );

      if (response.user == null) {
        _state = AuthState.error;
        _errorMessage = 'Invalid OTP. Please try again.';
        notifyListeners();
        return false;
      }

      _supabaseUser = response.user;

      // Check for existing farmer profile
      await _checkFarmerProfile();

      _state = AuthState.authenticated;
      await _saveSession();
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = 'Verification failed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Update profile completion status
  void setProfileComplete(bool complete) {
    _isProfileComplete = complete;
    _saveSession();
    notifyListeners();
  }

  /// Set farmer ID
  void setFarmerId(String id) {
    _farmerId = id;
    _saveSession();
    notifyListeners();
  }

  /// Admin Login with Email/Password
  Future<bool> adminLogin(String email, String password) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        _supabaseUser = response.user;
        _currentRole = UserRole.admin;
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _state = AuthState.error;
        _errorMessage = 'Login failed. Please check your credentials.';
        notifyListeners();
        return false;
      }
    } on AuthException catch (e) {
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = 'Login failed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }

    _supabaseUser = null;
    _farmerId = null;
    _phoneNumber = null;
    _isNewUser = false;
    _isProfileComplete = false;
    _state = AuthState.initial;
    _currentRole = UserRole.farmer;

    await _clearSession();
    notifyListeners();
  }

  /// Reset state
  void resetState() {
    _state = AuthState.initial;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
