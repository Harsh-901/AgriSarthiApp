/// API Configuration for the AgriSarthi Backend
class ApiConfig {
  // Base URL for the backend
  // POINTING TO PRODUCTION DEPLOYMENT
  //static const String baseUrl = 'https://agrisarthi.onrender.com';
  static const String baseUrl = 'http://192.168.31.46:8000';

  // HuggingFace token — injected via --dart-define-from-file=.env at build time.
  // 1. Accept licence at: https://huggingface.co/litert-community/Gemma3-1B-IT
  // 2. Create a "Read" token at https://huggingface.co/settings/tokens
  // 3. Paste it in AgriSarthiApp/.env as:  HF_TOKEN=hf_...
  // Run the app with:  flutter run --dart-define-from-file=.env
  static const String huggingFaceToken = String.fromEnvironment('HF_TOKEN');

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

  // OCR extraction (Django backend — kept as optional cloud fallback)
  static const String ocrExtract = '$baseUrl/api/documents/ocr/extract/';
}
