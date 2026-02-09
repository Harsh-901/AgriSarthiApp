import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';

/// Document types that match the backend requirements
class DocumentType {
  static const String aadhaar = 'aadhaar';
  static const String panCard = 'pan_card';
  static const String landCertificate = 'land_certificate';
  static const String sevenTwelve = 'seven_twelve';
  static const String eightA = 'eight_a';
  static const String bankPassbook = 'bank_passbook';
  static const String other = 'other';

  static const List<String> compulsoryTypes = [
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

/// Model for a document
class DocumentModel {
  final String? id;
  final String documentType;
  final String? documentUrl;
  final File? localFile;
  final String status; // 'pending', 'uploaded', 'verified', 'rejected'

  DocumentModel({
    this.id,
    required this.documentType,
    this.documentUrl,
    this.localFile,
    this.status = 'pending',
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id']?.toString(),
      documentType: json['document_type'] ?? '',
      documentUrl: json['document_url'],
      status: json['status'] ?? 'uploaded',
    );
  }

  bool get hasFile => localFile != null || documentUrl != null;
}

/// Service to handle document operations with the backend
class DocumentService {
  String? _accessToken;
  String? _farmerId;

  void setAuth(String accessToken, String farmerId) {
    _accessToken = accessToken;
    _farmerId = farmerId;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      };

  /// Get all documents for the current farmer
  Future<List<DocumentModel>> getDocuments() async {
    if (_accessToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse(ApiConfig.documents),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List docs = data['data']['documents'] ?? [];
          return docs.map((d) => DocumentModel.fromJson(d)).toList();
        }
      }
      return [];
    } catch (e) {
      throw Exception('Failed to fetch documents: $e');
    }
  }

  /// Upload all documents at once
  /// The backend requires all compulsory documents in a single request
  Future<Map<String, dynamic>> uploadDocuments(
    Map<String, File> documents, {
    String? otherDocName,
  }) async {
    if (_accessToken == null || _farmerId == null) {
      throw Exception('Not authenticated');
    }

    // Check if all compulsory documents are provided
    final missingDocs = DocumentType.compulsoryTypes
        .where((type) => !documents.containsKey(type))
        .toList();

    if (missingDocs.isNotEmpty) {
      throw Exception(
          'Missing required documents: ${missingDocs.map((t) => DocumentType.getDisplayName(t)).join(', ')}');
    }

    try {
      final uri = Uri.parse(ApiConfig.farmerDocuments(_farmerId!));
      final request = http.MultipartRequest('POST', uri);

      // Add auth header
      request.headers['Authorization'] = 'Bearer $_accessToken';

      // Add each document file
      for (final entry in documents.entries) {
        final file = entry.value;
        final mimeType = _getMimeType(file.path);

        request.files.add(
          await http.MultipartFile.fromPath(
            entry.key, // field name (document type)
            file.path,
            contentType: MediaType.parse(mimeType),
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final data = json.decode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Documents uploaded successfully',
          'documents': (data['data']['documents'] as List?)
                  ?.map((d) => DocumentModel.fromJson(d))
                  .toList() ??
              [],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to upload documents',
        };
      }
    } catch (e) {
      throw Exception('Failed to upload documents: $e');
    }
  }

  /// Upload a single document (for updating)
  Future<DocumentModel?> uploadSingleDocument(
    String documentType,
    File file,
  ) async {
    if (_accessToken == null || _farmerId == null) {
      throw Exception('Not authenticated');
    }

    try {
      final uri = Uri.parse(ApiConfig.documents);
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $_accessToken';

      final mimeType = _getMimeType(file.path);
      request.files.add(
        await http.MultipartFile.fromPath(
          documentType,
          file.path,
          contentType: MediaType.parse(mimeType),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return DocumentModel.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      throw Exception('Failed to upload document: $e');
    }
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
