import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
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
        return '8A Document';
      case bankPassbook:
        return 'Bank Passbook';
      case other:
        return 'Other Document';
      default:
        return type;
    }
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

  DocumentModel copyWith({
    String? type,
    String? displayName,
    File? file,
    String? url,
    String? status,
  }) {
    return DocumentModel(
      type: type ?? this.type,
      displayName: displayName ?? this.displayName,
      file: file ?? this.file,
      url: url ?? this.url,
      status: status ?? this.status,
    );
  }
}

/// Service for uploading documents to Supabase Storage
///
/// Bucket naming convention:
/// - Single bucket: 'documents' with folder structure: documents/{farmer_id}/file.ext
/// - Per-farmer bucket: 'farmer-{farmer_id}' (created by backend)
class DocumentService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final FarmerService _farmerService = FarmerService();

  // Bucket configuration
  // Option 1: Single bucket for all farmers (recommended)
  static const String _singleBucketName = 'documents';

  // Option 2: Per-farmer bucket prefix
  static const String _farmerBucketPrefix = 'farmer-';

  /// Get farmer ID from the farmers table
  Future<String?> _getFarmerId() async {
    final profile = await _farmerService.getFarmerProfile();
    return profile?.id;
  }

  /// Get the bucket name for a farmer
  /// First tries per-farmer bucket, falls back to single bucket
  Future<String> _getBucketName(String farmerId) async {
    // Try per-farmer bucket first (created by Django or Edge Function)
    final perFarmerBucket = '$_farmerBucketPrefix$farmerId';

    try {
      // Check if per-farmer bucket exists
      await _supabase.storage.from(perFarmerBucket).list();
      debugPrint('DocumentService: Using per-farmer bucket: $perFarmerBucket');
      return perFarmerBucket;
    } catch (e) {
      // Bucket doesn't exist, use single bucket with folders
      debugPrint(
          'DocumentService: Per-farmer bucket not found, using $_singleBucketName');
      return _singleBucketName;
    }
  }

  /// Get the storage path for a document
  String _getStoragePath(String bucketName, String farmerId, String fileName) {
    if (bucketName == _singleBucketName) {
      // Single bucket - use folder structure
      return '$farmerId/$fileName';
    } else {
      // Per-farmer bucket - file at root
      return fileName;
    }
  }

  /// Upload all documents to Supabase Storage
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

    // Validate compulsory documents
    for (final docType in DocumentType.compulsory) {
      if (!documents.containsKey(docType)) {
        throw Exception(
            'Missing required document: ${DocumentType.getDisplayName(docType)}');
      }
    }

    // Get the appropriate bucket
    final bucketName = await _getBucketName(farmerId);
    debugPrint(
        'DocumentService: Using bucket: $bucketName for farmer: $farmerId');

    final uploadedDocs = <String, String>{};
    final errors = <String>[];

    // Upload each document
    for (final entry in documents.entries) {
      try {
        final docType = entry.key;
        final file = entry.value;

        // Determine file extension
        final ext = file.path.split('.').last.toLowerCase();
        final fileName = '$docType.$ext';
        final storagePath = _getStoragePath(bucketName, farmerId, fileName);

        debugPrint(
            'DocumentService: Uploading $docType to $bucketName/$storagePath');

        // Read file bytes
        final fileBytes = await file.readAsBytes();

        // Upload to Supabase Storage
        await _supabase.storage.from(bucketName).uploadBinary(
              storagePath,
              fileBytes,
              fileOptions: FileOptions(
                contentType: _getContentType(ext),
                upsert: true, // Overwrite if exists
              ),
            );

        // Get public URL
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

    final documents = <DocumentModel>[];
    final bucketName = await _getBucketName(farmerId);
    final folderPath = bucketName == _singleBucketName ? farmerId : '';

    try {
      // List files in the farmer's folder
      final files =
          await _supabase.storage.from(bucketName).list(path: folderPath);

      for (final file in files) {
        final docType = file.name.split('.').first;
        final storagePath =
            folderPath.isNotEmpty ? '$folderPath/${file.name}' : file.name;
        final url =
            _supabase.storage.from(bucketName).getPublicUrl(storagePath);

        documents.add(DocumentModel(
          type: docType,
          displayName: DocumentType.getDisplayName(docType),
          url: url,
          status: 'uploaded',
        ));
      }
    } catch (e) {
      debugPrint('DocumentService: Error listing documents - $e');
    }

    return documents;
  }

  /// Delete a document
  Future<bool> deleteDocument(String docType) async {
    final farmerId = await _getFarmerId();
    if (farmerId == null) return false;

    try {
      final bucketName = await _getBucketName(farmerId);
      final storagePath = _getStoragePath(bucketName, farmerId, docType);

      await _supabase.storage.from(bucketName).remove([storagePath]);
      return true;
    } catch (e) {
      debugPrint('DocumentService: Error deleting document - $e');
      return false;
    }
  }
}
