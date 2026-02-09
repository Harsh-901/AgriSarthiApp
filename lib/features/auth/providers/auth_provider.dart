import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

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

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.initial;
  String? _errorMessage;
  UserRole _currentRole = UserRole.farmer;
  String? _phoneNumber;
  User? _user;

  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  UserRole get currentRole => _currentRole;
  String? get phoneNumber => _phoneNumber ?? _user?.phone;
  User? get user => _user;
  bool get isAuthenticated => _user != null;

  // Get display phone number (10 digits only, without country code)
  String get displayPhoneNumber {
    final phone = phoneNumber;
    if (phone == null || phone.isEmpty) return '';
    // Remove +91 prefix if present
    if (phone.startsWith('+91')) {
      return phone.substring(3);
    }
    // Remove any + and first 2 digits (country code)
    if (phone.startsWith('+') && phone.length > 10) {
      return phone.substring(phone.length - 10);
    }
    return phone;
  }

  final SupabaseClient _client = SupabaseConfig.client;

  AuthProvider() {
    _initializeAuth();
  }

  void _initializeAuth() {
    // Check for existing session
    final session = _client.auth.currentSession;
    if (session != null) {
      _user = session.user;
      _phoneNumber = session.user.phone;
      _state = AuthState.authenticated;
    }

    // Listen to auth state changes
    _client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        _user = session.user;
        _phoneNumber = session.user.phone;
        _state = AuthState.authenticated;
        notifyListeners();
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
        _phoneNumber = null;
        _state = AuthState.initial;
        notifyListeners();
      }
    });
  }

  void setRole(UserRole role) {
    _currentRole = role;
    notifyListeners();
  }

  // Send OTP to phone number (Farmer Login)
  Future<bool> sendOtp(String phoneNumber) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      // Format phone number to include country code if not present
      String formattedPhone = phoneNumber;
      if (!phoneNumber.startsWith('+')) {
        formattedPhone = '+91$phoneNumber'; // Default to India country code
      }

      _phoneNumber = formattedPhone;

      await _client.auth.signInWithOtp(
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

  // Verify OTP
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

      final response = await _client.auth.verifyOTP(
        phone: _phoneNumber!,
        token: otp,
        type: OtpType.sms,
      );

      if (response.user != null) {
        _user = response.user;
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _state = AuthState.error;
        _errorMessage = 'Invalid OTP. Please try again.';
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
      _errorMessage = 'Verification failed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  // Admin Login with Email/Password
  Future<bool> adminLogin(String email, String password) async {
    try {
      _state = AuthState.loading;
      _errorMessage = null;
      notifyListeners();

      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        _user = response.user;
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

  // Sign out
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      _user = null;
      _phoneNumber = null;
      _state = AuthState.initial;
      _currentRole = UserRole.farmer;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Sign out failed';
      notifyListeners();
    }
  }

  // Reset state
  void resetState() {
    _state = AuthState.initial;
    _errorMessage = null;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
