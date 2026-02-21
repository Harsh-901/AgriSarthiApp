import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/farmer_service.dart';

/// Maps form file-input fields to the farmer's existing documents in Supabase
/// and injects them as Blobs via JavaScript — bypassing the native file picker.
///
/// Document matching is done by the `document_type` column values:
///   aadhaar | pan_card | land_certificate | seven_twelve | eight_a | bank_passbook
class DocumentAutoUploadService {
  DocumentAutoUploadService._();
  static final instance = DocumentAutoUploadService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FarmerService _farmerService = FarmerService();

  // ─── document_type → label keywords (label on the form → document_type) ───

  static const Map<String, List<String>> _labelToDocType = {
    'aadhaar': ['aadhaar', 'aadhar', 'uid', 'identity'],
    'pan_card': ['pan', 'permanent account'],
    'land_certificate': ['land certificate', 'land cert', 'bhumidharak'],
    'seven_twelve': ['7/12', 'seven twelve', 'satbara', '7-12', 'satbaara'],
    'eight_a': ['8a', 'eight a', '8-a', 'eightA', 'khate utara'],
    'bank_passbook': ['bank', 'passbook', 'khata', 'account'],
  };

  /// Given a file input's [label] and [name], determine which document_type
  /// it likely wants. Returns null if no match.
  static String? guessDocumentType(String label, String name) {
    final combined = '${label.toLowerCase()} ${name.toLowerCase()}';
    for (final entry in _labelToDocType.entries) {
      if (entry.value.any((kw) => combined.contains(kw))) {
        return entry.key;
      }
    }
    return null;
  }

  /// Fetch the farmer's document URL for [documentType] from Supabase.
  /// Returns null if not found.
  Future<String?> _getDocumentUrl(String farmerId, String documentType) async {
    try {
      final rows = await _supabase
          .from('documents')
          .select('document_url')
          .eq('farmer_id', farmerId)
          .eq('document_type', documentType)
          .order('created_at', ascending: false)
          .limit(1);

      if ((rows as List).isEmpty) return null;
      return rows.first['document_url'] as String?;
    } catch (e) {
      debugPrint('[DocUpload] Error fetching document URL: $e');
      return null;
    }
  }

  /// Download [url] and return the raw bytes.
  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) return response.bodyBytes;
      debugPrint('[DocUpload] Download failed: HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[DocUpload] Download error: $e');
      return null;
    }
  }

  /// Detect MIME type from URL or magic bytes.
  static String _detectMime(String url, Uint8List bytes) {
    final lc = url.toLowerCase();
    if (lc.endsWith('.pdf') ||
        (bytes.length >= 4 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46)) {
      return 'application/pdf';
    }
    if (lc.endsWith('.png') ||
        (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50)) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  /// Build the JavaScript snippet that injects a Blob as a fake FileList
  /// into the `<input type="file">` identified by [fieldKey] (id or name).
  static String buildInjectJs(
    String fieldKey,
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) {
    final base64Data = base64Encode(bytes);
    // language=javascript
    return '''
(function() {
  var el = document.getElementById(${_jsStr(fieldKey)}) ||
           document.querySelector('[name="${_jsStr(fieldKey, quote: false)}"]');
  if (!el) { return JSON.stringify({ok: false, reason: 'element not found'}); }

  try {
    var byteChars = atob(${_jsStr(base64Data)});
    var byteNums  = new Array(byteChars.length);
    for (var i = 0; i < byteChars.length; i++) {
      byteNums[i] = byteChars.charCodeAt(i);
    }
    var byteArr  = new Uint8Array(byteNums);
    var blob     = new Blob([byteArr], { type: ${_jsStr(mimeType)} });
    var file     = new File([blob], ${_jsStr(fileName)}, { type: ${_jsStr(mimeType)}, lastModified: Date.now() });
    var dt       = new DataTransfer();
    dt.items.add(file);
    el.files = dt.files;
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('input',  { bubbles: true }));
    return JSON.stringify({ok: true, name: ${_jsStr(fileName)}});
  } catch(e) {
    return JSON.stringify({ok: false, reason: e.toString()});
  }
})();
''';
  }

  static String _jsStr(String s, {bool quote = true}) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    return quote ? "'$escaped'" : escaped;
  }

  /// Try to auto-upload a document for the given file input field.
  ///
  /// Returns:
  ///  - `AutoUploadResult.success(fileName)` if injected OK
  ///  - `AutoUploadResult.notFound(docType)` if no doc exists
  ///  - `AutoUploadResult.skip()` if label doesn't match any document_type
  Future<AutoUploadResult> tryAutoUpload({
    required String fieldKey,
    required String fieldLabel,
    required Future<String> Function(String js) runJs,
  }) async {
    final docType = guessDocumentType(fieldLabel, fieldKey);
    if (docType == null) {
      debugPrint('[DocUpload] "$fieldLabel" → no matching document_type');
      return AutoUploadResult.skip();
    }

    final profile = await _farmerService.getFarmerProfile();
    if (profile?.id == null) {
      debugPrint('[DocUpload] No farmer profile');
      return AutoUploadResult.skip();
    }
    final farmerId = profile!.id!;

    final url = await _getDocumentUrl(farmerId, docType);
    if (url == null || url.isEmpty) {
      debugPrint('[DocUpload] No document found for type=$docType');
      return AutoUploadResult.notFound(docType);
    }

    final bytes = await _downloadBytes(url);
    if (bytes == null) {
      debugPrint('[DocUpload] Failed to download $url');
      return AutoUploadResult.notFound(docType);
    }

    final mimeType = _detectMime(url, bytes);
    final ext = mimeType.contains('pdf')
        ? 'pdf'
        : mimeType.contains('png')
            ? 'png'
            : 'jpg';
    final fileName = '$docType.$ext';

    final js = buildInjectJs(fieldKey, bytes, fileName, mimeType);
    final result = await runJs(js);
    debugPrint('[DocUpload] Inject result for $fieldKey: $result');

    try {
      final parsed = jsonDecode(result);
      if (parsed is String) {
        final inner = jsonDecode(parsed);
        if (inner['ok'] == true) return AutoUploadResult.success(fileName);
      } else if (parsed['ok'] == true) {
        return AutoUploadResult.success(fileName);
      }
    } catch (_) {}

    return AutoUploadResult.notFound(docType);
  }
}

// ─── Result type ──────────────────────────────────────────────────────────────

enum _AutoUploadStatus { success, notFound, skip }

class AutoUploadResult {
  final _AutoUploadStatus _status;
  final String? info;

  const AutoUploadResult._(_AutoUploadStatus status, [this.info])
      : _status = status;

  factory AutoUploadResult.success(String fileName) =>
      AutoUploadResult._(_AutoUploadStatus.success, fileName);
  factory AutoUploadResult.notFound(String docType) =>
      AutoUploadResult._(_AutoUploadStatus.notFound, docType);
  factory AutoUploadResult.skip() => AutoUploadResult._(_AutoUploadStatus.skip);

  bool get isSuccess => _status == _AutoUploadStatus.success;
  bool get isNotFound => _status == _AutoUploadStatus.notFound;
  bool get isSkip => _status == _AutoUploadStatus.skip;
}
