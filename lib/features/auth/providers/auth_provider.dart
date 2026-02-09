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
  unauthenticated,
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
  bool _isInitialized = false;

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
  bool get isInitialized => _isInitialized;

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
    _initializeAuth();
  }

  /// Initialize auth and restore session
  Future<void> _initializeAuth() async {
    try {
      debugPrint('AuthProvider: Initializing...');

      // Check for existing Supabase session
      final session = _supabase.auth.currentSession;

      if (session != null) {
        debugPrint('AuthProvider: Found existing session');
        _supabaseUser = session.user;
        _phoneNumber = _supabaseUser?.phone;

        // Load saved data from SharedPreferences
        await _loadLocalData();

        // Verify farmer profile
        await _checkFarmerProfile();

        _state = AuthState.authenticated;
      } else {
        debugPrint('AuthProvider: No existing session');
        _state = AuthState.unauthenticated;
      }

      // Listen for auth changes
      _listenToSupabaseAuth();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthProvider: Init error - $e');
      _state = AuthState.unauthenticated;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Listen to Supabase auth state changes
  void _listenToSupabaseAuth() {
    _supabase.auth.onAuthStateChange.listen((data) async {
      debugPrint('AuthProvider: Auth state changed - ${data.event}');

      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        _supabaseUser = data.session!.user;
        _phoneNumber = _supabaseUser?.phone;

        // Check for existing farmer profile
        await _checkFarmerProfile();

        _state = AuthState.authenticated;
        await _saveLocalData();
        notifyListeners();
      } else if (data.event == AuthChangeEvent.signedOut) {
        debugPrint('AuthProvider: User signed out');
        _supabaseUser = null;
        _farmerId = null;
        _isProfileComplete = false;
        _state = AuthState.unauthenticated;
        await _clearLocalData();
        notifyListeners();
      } else if (data.event == AuthChangeEvent.tokenRefreshed) {
        debugPrint('AuthProvider: Token refreshed');
        _supabaseUser = data.session?.user;
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
        debugPrint(
            'AuthProvider: Found farmer profile - id=${_farmerId}, complete=${_isProfileComplete}');
      } else {
        _isNewUser = true;
        _isProfileComplete = false;
        debugPrint('AuthProvider: No farmer profile found');
      }
    } catch (e) {
      debugPrint('AuthProvider: Error checking farmer profile - $e');
    }
  }

  /// Load saved data from SharedPreferences
  Future<void> _loadLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _farmerId = prefs.getString('farmer_id');
      _isProfileComplete = prefs.getBool('profile_complete') ?? false;
      debugPrint(
          'AuthProvider: Loaded local data - farmerId=$_farmerId, profileComplete=$_isProfileComplete');
    } catch (e) {
      debugPrint('AuthProvider: Error loading local data - $e');
    }
  }

  /// Save data to SharedPreferences
  Future<void> _saveLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_farmerId != null) {
        await prefs.setString('farmer_id', _farmerId!);
      }
      if (_phoneNumber != null) {
        await prefs.setString('phone_number', _phoneNumber!);
      }
      await prefs.setBool('profile_complete', _isProfileComplete);
      debugPrint('AuthProvider: Saved local data');
    } catch (e) {
      debugPrint('AuthProvider: Error saving local data - $e');
    }
  }

  /// Clear local data
  Future<void> _clearLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('farmer_id');
      await prefs.remove('phone_number');
      await prefs.remove('profile_complete');
      debugPrint('AuthProvider: Cleared local data');
    } catch (e) {
      debugPrint('AuthProvider: Error clearing local data - $e');
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

      debugPrint('AuthProvider: Sending OTP to $formattedPhone');

      // Use Supabase to send OTP via Twilio
      await _supabase.auth.signInWithOtp(
        phone: formattedPhone,
      );

      _state = AuthState.otpSent;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      debugPrint('AuthProvider: Send OTP error - ${e.message}');
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('AuthProvider: Send OTP error - $e');
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

      debugPrint('AuthProvider: Verifying OTP for $_phoneNumber');

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

      debugPrint('AuthProvider: OTP verified successfully');
      _supabaseUser = response.user;

      // Check for existing farmer profile
      await _checkFarmerProfile();

      _state = AuthState.authenticated;
      await _saveLocalData();
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      debugPrint('AuthProvider: Verify OTP error - ${e.message}');
      _state = AuthState.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('AuthProvider: Verify OTP error - $e');
      _state = AuthState.error;
      _errorMessage = 'Verification failed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Update profile completion status
  void setProfileComplete(bool complete) {
    _isProfileComplete = complete;
    _saveLocalData();
    notifyListeners();
  }

  /// Set farmer ID
  void setFarmerId(String id) {
    _farmerId = id;
    _saveLocalData();
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

  /// Sign out - only when user explicitly requests it
  Future<void> signOut() async {
    try {
      debugPrint('AuthProvider: Signing out...');
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('AuthProvider: Sign out error - $e');
    }

    _supabaseUser = null;
    _farmerId = null;
    _phoneNumber = null;
    _isNewUser = false;
    _isProfileComplete = false;
    _state = AuthState.unauthenticated;
    _currentRole = UserRole.farmer;

    await _clearLocalData();
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
