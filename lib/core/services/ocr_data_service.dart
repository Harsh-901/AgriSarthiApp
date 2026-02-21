import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'farmer_service.dart';
import 'local_ocr_service.dart';
import 'ocr_field_extractor.dart';

/// Fetches OCR-extracted key-value data from the farmer's uploaded documents.
///
/// Fully local pipeline — no Groq or external OCR API:
///  1. Look up the farmer's UUID (id) by phone number from the `farmers` table.
///  2. Query `documents` table where `farmer_id = <uuid>`.
///  3. Each row contains a ready-to-use `document_url`.
///  4. Download the file; if PDF, pdfx renders pages to images first.
///  5. Google ML Kit text recognition runs on-device — fully offline.
///  6. [OcrFieldExtractor] parses raw text into structured key-value pairs.
///  7. FarmerProfile fields fill any gaps not found in documents.
class OcrDataService {
  static OcrDataService? _instance;
  OcrDataService._();
  static OcrDataService get instance => _instance ??= OcrDataService._();

  final _supabase = Supabase.instance.client;
  final _localOcr = LocalOcrService.instance;
  final _farmerSvc = FarmerService();

  /// Fetch merged OCR data for the currently logged-in farmer.
  ///
  /// Returns a flat [Map<String, dynamic>] with all extractable fields:
  ///   full_name, aadhaar_number, pan_number, date_of_birth,
  ///   account_number, ifsc_code, bank_name, land_area_acres,
  ///   survey_number, pincode, state, village, district, …
  Future<Map<String, dynamic>> fetchOcrData() async {
    final data = <String, dynamic>{};

    try {
      // ── 1. Resolve farmer UUID by phone (mirrors FarmerService logic) ─────
      final farmerId = await _getFarmerUuid();
      if (farmerId == null) {
        debugPrint('[OCR] No farmer UUID found — using profile fallback');
        return await _profileFallback();
      }

      // ── 2. Load all document rows for this farmer ─────────────────────────
      final rows = await _supabase
          .from('documents')
          .select('id, document_type, document_url')
          .eq('farmer_id', farmerId)
          .order('created_at', ascending: false)
          .limit(10) // OCR the 10 most recent uploads
          .timeout(const Duration(seconds: 15));

      if ((rows as List).isEmpty) {
        debugPrint(
            '[OCR] No documents for farmer $farmerId — using profile fallback');
        return await _profileFallback();
      }

      debugPrint('[OCR] Found ${rows.length} documents to process locally');

      // ── 3. Run local OCR on each document ─────────────────────────────────
      for (final row in rows) {
        // Normalise the database's document_type string to the canonical keys
        // expected by OcrFieldExtractor (aadhaar, pan_card, bank_passbook,
        // seven_twelve, eight_a, land_certificate, income_cert).
        final rawDocType =
            (row['document_type'] as String?)?.toLowerCase().trim() ?? '';
        final docType = _normaliseDocType(rawDocType);
        final url = row['document_url'] as String?;
        if (url == null || url.isEmpty) continue;

        debugPrint('[OCR] Processing $rawDocType → canonical: $docType …');

        // ── 4. On-device OCR (ML Kit + pdfx) ──────────────────────────────
        // Pass docType so LocalOcrService runs the right scripts
        // (e.g. Devanagari for 7/12, land cert).
        final rawText =
            await _localOcr.extractTextFromUrl(url, docType: docType);
        if (rawText.isEmpty) {
          debugPrint('[OCR] Empty text from $docType — skipping');
          continue;
        }

        // Preview first 200 chars so we can verify OCR quality in logs
        debugPrint(
            '[OCR] Preview: ${rawText.substring(0, rawText.length.clamp(0, 200))}');

        // ── 5. Document-type-aware field extraction ────────────────────────
        final extracted = OcrFieldExtractor.extract(rawText, docType: docType);
        debugPrint('[OCR] $docType → ${extracted.length} fields: '
            '${extracted.keys.join(', ')}');
        for (final e in extracted.entries) {
          debugPrint('[OCR]   $docType.${e.key} = ${e.value}');
          _setIfAbsent(data, e.key, e.value);
        }

        // Keep a generous raw-text snippet (800 chars) keyed per doc type
        // for SmartFormMapper Stage 2 and Gemma Stage 3.
        final rawKey = '${docType}_raw_text';
        _setIfAbsent(
            data, rawKey, rawText.substring(0, rawText.length.clamp(0, 800)));
      }
    } catch (e) {
      debugPrint('[OCR] Pipeline error: $e');
    }

    // ── 6. Merge FarmerProfile data for any missing fields ─────────────────
    await _mergeProfileFallback(data);

    debugPrint('[OCR] Final merged fields: ${data.keys.join(', ')}');
    return data;
  }

  // ── Farmer UUID lookup ─────────────────────────────────────────────────────

  /// Returns the farmer's UUID (`farmers.id`) by looking up their phone number.
  /// This mirrors the join between Supabase Auth (phone-based) and the
  /// `farmers` table.
  Future<String?> _getFarmerUuid() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      // Normalise phone (same logic as FarmerService._getPhoneFromUser)
      String phone = (user.phone ?? '').replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
      if (phone.startsWith('91') && phone.length == 12) {
        phone = phone.substring(2);
      } else if (phone.length > 10) {
        phone = phone.substring(phone.length - 10);
      }
      if (phone.isEmpty) return null;

      final row = await _supabase
          .from('farmers')
          .select('id')
          .eq('phone', phone)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      return row?['id'] as String?;
    } catch (e) {
      debugPrint('[OCR] Farmer UUID lookup error: $e');
      return null;
    }
  }

  // ── Profile merge helpers ──────────────────────────────────────────────────

  Future<void> _mergeProfileFallback(Map<String, dynamic> data) async {
    try {
      final profile = await _farmerSvc.getFarmerProfile();
      if (profile == null) return;
      _setIfAbsent(data, 'full_name', profile.fullName);
      _setIfAbsent(data, 'phone', profile.phoneNumber);
      _setIfAbsent(data, 'mobile_number', profile.phoneNumber);
      _setIfAbsent(data, 'state', profile.state);
      _setIfAbsent(data, 'district', profile.district);
      _setIfAbsent(data, 'village', profile.village);
      _setIfAbsent(data, 'land_area_acres', profile.landSize.toString());
      _setIfAbsent(data, 'primary_crop', profile.primaryCrop);
    } catch (e) {
      debugPrint('[OCR] Profile merge error: $e');
    }
  }

  Future<Map<String, dynamic>> _profileFallback() async {
    final data = <String, dynamic>{};
    await _mergeProfileFallback(data);
    return data;
  }

  void _setIfAbsent(Map<String, dynamic> map, String key, dynamic value) {
    if (value != null && value.toString().isNotEmpty && !map.containsKey(key)) {
      map[key] = value;
    }
  }

  /// Maps the database's freeform document_type string to the canonical key
  /// expected by [OcrFieldExtractor]. Keep this in sync with whatever values
  /// your Supabase `documents.document_type` column can contain.
  String _normaliseDocType(String raw) {
    final r = raw.toLowerCase().replaceAll(RegExp(r'[\s_\-/]+'), '');
    if (r.contains('aadhaar') ||
        r.contains('aadhar') ||
        r.contains('adhaar') ||
        r.contains('uid')) return 'aadhaar';
    if (r.contains('pan')) return 'pan_card';
    if (r.contains('passbook') ||
        r.contains('bankstatement') ||
        r.contains('bankaccount') ||
        r.contains('cheque') ||
        r.contains('bankdetail')) return 'bank_passbook';
    if (r.contains('712') ||
        r.contains('satbara') ||
        r.contains('sevenwelve') ||
        r.contains('seventwelve') ||
        r.contains('7twelve')) return 'seven_twelve';
    if (r.contains('8a') || r.contains('eighta') || r.contains('khatian')) {
      return 'eight_a';
    }
    if (r.contains('landcert') ||
        r.contains('landrecord') ||
        r.contains('landownership') ||
        r.contains('possession')) {
      return 'land_certificate';
    }
    if (r.contains('income') || r.contains('aay')) return 'income_cert';
    // Unknown — return raw so at least the raw_text key is usable
    return raw.replaceAll(RegExp(r'[\s/\\]+'), '_');
  }
}
