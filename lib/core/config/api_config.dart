/// API Configuration for the AgriSarthi Backend
class ApiConfig {
  // Base URL for the backend
  // FOR EMULATOR USE: 'http://10.0.2.2:8000'
  // FOR PHYSICAL DEVICE USE: 'http://<YOUR_IP>:8000'
  // FOR PRODUCTION: 'https://agrisarthi.onrender.com'
  static const String baseUrl = 'http://192.168.0.103:8000';

  // API Endpoints
  static const String authLogin = '$baseUrl/api/auth/login/';
  static const String authVerify = '$baseUrl/api/auth/verify/';
  static const String authRegister = '$baseUrl/api/auth/register/';
  static const String authRefresh = '$baseUrl/api/auth/refresh/';
  static const String authLogout = '$baseUrl/api/auth/logout/';

  static const String farmersProfile = '$baseUrl/api/farmers/profile/';
  static const String documents = '$baseUrl/api/documents/';

  // Helper to get farmer-specific document endpoint
  static String farmerDocuments(String farmerId) =>
      '$baseUrl/api/documents/farmer/$farmerId/';

  static String farmerProfile(String farmerId) =>
      '$baseUrl/api/farmers/profile/$farmerId/';
}
