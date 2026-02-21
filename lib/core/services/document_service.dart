import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../config/api_config.dart';
import 'farmer_service.dart';

/// Document types for farmer verification
class DocumentType {
  static const String aadhaar = 'aadhaar';
  static const String panCard = 'pan_card';
  static const String landCertificate = 'land_certificate';
  static const String sevenTwelve = 'seven_twelve';
  static const String eightA = 'eight_a';
  static const String bankPassbook = 'bank_passbook';
  static const String other = 'other';

  static const List<String> compulsory = [
    aadhaar,
    panCard,
    landCertificate,
    sevenTwelve,
    eightA,
    bankPassbook,
  ];

  static String getDisplayName(String type) {
    switch (type) {
      case aadhaar:
        return 'Aadhaar Card';
      case panCard:
        return 'PAN Card';
      case landCertificate:
        return 'Land Certificate';
      case sevenTwelve:
        return '7/12 Extract';
      case eightA:
        return '8A Extract';
      case bankPassbook:
        return 'Bank Passbook';
      case other:
        return 'Other Document';
      default:
        return type;
    }
  }

  static String getDescription(String type) {
    switch (type) {
      case aadhaar:
        return 'We will extract your name, date of birth, and gender';
      case sevenTwelve:
        return 'We will extract your land size, village, and district';
      default:
        return '';
    }
  }
}

/// Model for OCR extraction result
class OCRExtractionResult {
  final bool success;
  final Map<String, dynamic> extractedData;
  final double confidence;
  final bool documentUploaded;
  final List<String> errors;

  OCRExtractionResult({
    required this.success,
    required this.extractedData,
    this.confidence = 0.0,
    this.documentUploaded = false,
    this.errors = const [],
  });

  factory OCRExtractionResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return OCRExtractionResult(
      success: json['success'] ?? false,
      extractedData: data['extracted'] as Map<String, dynamic>? ?? {},
      confidence: (data['confidence'] ?? 0.0).toDouble(),
      documentUploaded: data['document_uploaded'] ?? false,
      errors: List<String>.from(json['errors'] ?? []),
    );
  }
}

/// Model for document upload status
class DocumentModel {
  final String type;
  final String displayName;
  final File? file;
  final String? url;
  final String status; // pending, selected, uploading, uploaded, error

  DocumentModel({
    required this.type,
    required this.displayName,
    this.file,
    this.url,
    this.status = 'pending',
  });
}

/// Service for document upload and OCR extraction
class DocumentService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final FarmerService _farmerService = FarmerService();

  static const String _farmerBucketPrefix = 'farmer-';

  /// Get farmer ID from the farmers table
  Future<String?> _getFarmerId() async {
    final profile = await _farmerService.getFarmerProfile();
    return profile?.id;
  }

  /// Get bucket name for a farmer
  static String getBucketName(String farmerId) {
    return '$_farmerBucketPrefix$farmerId';
  }

  /// Get auth token for API calls
  String? _getAuthToken() {
    return _supabase.auth.currentSession?.accessToken;
  }

  /// Upload Aadhaar card and extract data via OCR
  Future<OCRExtractionResult> uploadAndExtractAadhaar(File file) async {
    return _uploadAndExtractOCR(file, 'aadhaar');
  }

  /// Upload 7/12 Extract and extract data via OCR
  Future<OCRExtractionResult> uploadAndExtractSevenTwelve(File file) async {
    return _uploadAndExtractOCR(file, 'seven-twelve');
  }

  /// Internal: Upload document and run OCR extraction
  Future<OCRExtractionResult> _uploadAndExtractOCR(
    File file,
    String documentType,
  ) async {
    try {
      final token = _getAuthToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final uri =
          Uri.parse('${ApiConfig.baseUrl}/api/documents/ocr/$documentType/');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      debugPrint('DocumentService: Uploading $documentType for OCR...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint(
          'DocumentService: OCR response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        return OCRExtractionResult.fromJson(jsonResponse);
      } else {
        debugPrint('DocumentService: OCR error: ${response.body}');
        return OCRExtractionResult(
          success: false,
          extractedData: {},
          errors: ['Server error: ${response.statusCode}'],
        );
      }
    } catch (e) {
      debugPrint('DocumentService: OCR extraction failed: $e');
      return OCRExtractionResult(
        success: false,
        extractedData: {},
        errors: ['Failed to process document: $e'],
      );
    }
  }

  /// Create a dedicated storage bucket for a farmer.
  Future<bool> createFarmerBucket(String farmerId) async {
    final bucketName = getBucketName(farmerId);

    debugPrint('========== BUCKET CREATION START ==========');
    debugPrint(
        'DocumentService: Creating bucket "$bucketName" for farmer "$farmerId"');

    // Step 1: Check if bucket already exists
    try {
      await _supabase.storage.from(bucketName).list();
      debugPrint('DocumentService: ✅ Bucket $bucketName already exists!');
      return true;
    } catch (e) {
      debugPrint(
          'DocumentService: Bucket does not exist yet (expected). Error: $e');
    }

    // Step 2: Try RPC function
    try {
      debugPrint('DocumentService: Calling RPC create_farmer_bucket...');
      final result = await _supabase.rpc('create_farmer_bucket', params: {
        'farmer_id': farmerId,
      });
      debugPrint('DocumentService: ✅ RPC returned: $result');
      return true;
    } catch (e) {
      debugPrint('DocumentService: ❌ RPC failed: $e');
    }

    // Step 3: Fallback - Try direct bucket creation
    try {
      debugPrint('DocumentService: Trying direct createBucket...');
      await _supabase.storage.createBucket(
        bucketName,
        const BucketOptions(
          public: true,
          fileSizeLimit: '10485760', // 10MB
          allowedMimeTypes: ['image/*', 'application/pdf'],
        ),
      );
      debugPrint('DocumentService: ✅ Direct bucket creation succeeded!');
      return true;
    } catch (e) {
      debugPrint('DocumentService: ❌ Direct bucket creation also failed: $e');
    }

    debugPrint('========== BUCKET CREATION FAILED ==========');
    return false;
  }

  /// Upload documents to storage (simplified for 2 docs)
  Future<Map<String, dynamic>> uploadDocuments(
    Map<String, File> documents, {
    String? otherDocumentName,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not authenticated');
    }

    final farmerId = await _getFarmerId();
    if (farmerId == null) {
      throw Exception(
          'Farmer profile not found. Please complete your profile first.');
    }

    // Ensure bucket exists
    final bucketName = await _ensureBucketExists(farmerId);
    debugPrint('DocumentService: Uploading to bucket: $bucketName');

    final uploadedDocs = <String, String>{};
    final errors = <String>[];

    // Upload each document
    for (final entry in documents.entries) {
      try {
        final docType = entry.key;
        final file = entry.value;

        final ext = file.path.split('.').last.toLowerCase();
        final fileName = '$docType.$ext';
        final storagePath = fileName;

        debugPrint(
            'DocumentService: Uploading $docType to $bucketName/$storagePath');

        final fileBytes = await file.readAsBytes();

        await _supabase.storage.from(bucketName).uploadBinary(
              storagePath,
              fileBytes,
              fileOptions: FileOptions(
                contentType: _getContentType(ext),
                upsert: true,
              ),
            );

        final url =
            _supabase.storage.from(bucketName).getPublicUrl(storagePath);

        uploadedDocs[docType] = url;
        debugPrint('DocumentService: Uploaded $docType successfully');
      } catch (e) {
        debugPrint('DocumentService: Error uploading ${entry.key} - $e');
        errors.add(
            'Failed to upload ${DocumentType.getDisplayName(entry.key)}: $e');
      }
    }

    if (errors.isNotEmpty && uploadedDocs.isEmpty) {
      throw Exception(errors.join('\n'));
    }

    return {
      'success': uploadedDocs.isNotEmpty,
      'uploaded': uploadedDocs.length,
      'total': documents.length,
      'urls': uploadedDocs,
      if (errors.isNotEmpty) 'errors': errors,
    };
  }

  /// Ensure bucket exists
  Future<String> _ensureBucketExists(String farmerId) async {
    final bucketName = getBucketName(farmerId);

    try {
      await _supabase.storage.from(bucketName).list();
      debugPrint(
          'DocumentService: Bucket $bucketName exists and is accessible.');
      return bucketName;
    } catch (e) {
      debugPrint(
          'DocumentService: Bucket $bucketName missing. Attempting to create...');

      final created = await createFarmerBucket(farmerId);
      if (created) {
        return bucketName;
      }

      throw Exception(
          'Bucket "$bucketName" not found and could not be created automatically.\n'
          'Please ensure the create_farmer_bucket RPC function exists in your Supabase project.');
    }
  }

  /// Get content type for file extension
  String _getContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  /// Get list of uploaded documents for the current farmer
  Future<List<DocumentModel>> getDocuments() async {
    final farmerId = await _getFarmerId();
    if (farmerId == null) {
      return [];
    }

    final bucketName = '$_farmerBucketPrefix$farmerId';
    final documents = <DocumentModel>[];

    try {
      final files = await _supabase.storage.from(bucketName).list();

      for (final file in files) {
        final docType = file.name.split('.').first;
        final url = _supabase.storage.from(bucketName).getPublicUrl(file.name);

        documents.add(DocumentModel(
          type: docType,
          displayName: DocumentType.getDisplayName(docType),
          url: url,
          status: 'uploaded',
        ));
      }
    } catch (e) {
      debugPrint(
          'DocumentService: Error listing documents (Bucket likely missing) - $e');
    }

    return documents;
  }
}
