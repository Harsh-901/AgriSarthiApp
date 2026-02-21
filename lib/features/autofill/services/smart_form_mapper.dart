import 'package:flutter/foundation.dart';
import 'field_mapper_service.dart';
import 'autofill_llm_service.dart';

// ─── Data classes ─────────────────────────────────────────────────────────────

/// A field the chatbot must ask the user about.
class FieldQuery {
  final String key;
  final String label;
  final String type;
  final List<Map<String, String>>? options;

  /// Pre-filled guess extracted in Stage 2 (null if completely missing).
  final String? hintValue;

  /// true  = found in docs but low confidence → show hint, ask to confirm
  /// false = not found at all → blank input
  final bool isUncertain;

  const FieldQuery({
    required this.key,
    required this.label,
    required this.type,
    this.options,
    this.hintValue,
    required this.isUncertain,
  });
}

/// Result returned by [SmartFormMapper.map].
class SmartMappingResult {
  /// Fields mapped with high confidence — can be injected directly.
  final Map<String, String> confident;

  /// Fields that need user input (uncertain or completely missing).
  final List<FieldQuery> needsUser;

  const SmartMappingResult({
    required this.confident,
    required this.needsUser,
  });
}

// ─── SmartFormMapper ──────────────────────────────────────────────────────────

/// 3-stage pipeline that maps form fields to OCR data values.
///
/// Stage 1 — Alias match  (deterministic, <1 ms/field, ~60-70% coverage)
/// Stage 2 — Targeted snippet search  (label-driven regex on relevant doc text)
/// Stage 3 — Gemma LLM  (only residual fields + tiny focused snippets)
///
/// Gemma is called with a much smaller, focused prompt than before, eliminating
/// the token-overflow crashes that plagued the old all-at-once approach.
class SmartFormMapper {
  SmartFormMapper._();
  static final SmartFormMapper instance = SmartFormMapper._();

  final _alias = FieldMapperService.instance;
  final _llm = AutofillLlmService.instance;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Map [fields] (from dom_extractor.js) to values from [ocrData].
  ///
  /// [ocrData] is the full map from OcrDataService, including `*_raw_text` keys.
  /// [onLlmProgress] is called before the LLM stage starts (optional).
  Future<SmartMappingResult> map({
    required List<Map<String, dynamic>> fields,
    required Map<String, dynamic> ocrData,
    Future<void> Function()? ensureLlmReady,
    ValueChanged<double>? onLlmProgress,
  }) async {
    final confident = <String, String>{};
    final needsUser = <FieldQuery>[];

    // ── Stage 1: Alias match ────────────────────────────────────────────────
    final aliasResult = _alias.map(fields: fields, ocrData: ocrData);

    final leftover = <Map<String, dynamic>>[];
    for (final field in fields) {
      final key = _keyOf(field);
      if (key.isEmpty) continue;

      final val = aliasResult[key];
      if (val != null && val.isNotEmpty) {
        confident[key] = val;
        debugPrint('[SmartMapper] Stage1 ✓ $key = $val');
      } else {
        leftover.add(field);
      }
    }

    debugPrint(
        '[SmartMapper] Stage1: ${confident.length} confident, ${leftover.length} leftover');

    if (leftover.isEmpty) {
      return SmartMappingResult(confident: confident, needsUser: needsUser);
    }

    // ── Stage 2: Targeted snippet search ───────────────────────────────────
    final stillMissing = <Map<String, dynamic>>[];
    for (final field in leftover) {
      final key = _keyOf(field);
      final label = (field['label'] as String? ?? '').toLowerCase();
      final type = field['type'] as String? ?? 'text';

      final result =
          _targetedSearch(label: label, type: type, ocrData: ocrData);

      if (result != null) {
        // Found something — mark uncertain (chatbot will ask to confirm)
        debugPrint(
            '[SmartMapper] Stage2 ~ $key = ${result.value}  (uncertain)');
        final options = _castOptions(field['options']);
        needsUser.add(FieldQuery(
          key: key,
          label: field['label'] as String? ?? key,
          type: type,
          options: options,
          hintValue: result.value,
          isUncertain: true,
        ));
      } else {
        stillMissing.add(field);
      }
    }

    debugPrint(
        '[SmartMapper] Stage2: ${needsUser.length} uncertain, ${stillMissing.length} still missing');

    if (stillMissing.isEmpty) {
      return SmartMappingResult(confident: confident, needsUser: needsUser);
    }

    // ── Stage 3: Gemma LLM (only residual fields + focused snippets) ────────
    //
    // Build a compact OCR map for Gemma: only values relevant to the remaining
    // field types + at most one targeted raw-text snippet per doc type needed.
    // This keeps the prompt well under 2048 tokens.
    final focusedOcr = _buildFocusedOcrForLlm(stillMissing, ocrData);

    debugPrint('[SmartMapper] Stage3: calling Gemma with '
        '${stillMissing.length} fields, ${focusedOcr.length} focused keys');

    Map<String, String?> llmResult = {};
    try {
      if (ensureLlmReady != null) await ensureLlmReady();
      llmResult = await _llm.mapFieldsToProfile(
        ocrData: focusedOcr,
        extractedFields: stillMissing,
      );
    } catch (e) {
      debugPrint('[SmartMapper] Stage3 Gemma error: $e');
    }

    for (final field in stillMissing) {
      final key = _keyOf(field);
      final val = llmResult[key];
      final type = field['type'] as String? ?? 'text';
      final options = _castOptions(field['options']);

      if (val != null && val.isNotEmpty) {
        // Gemma found something — treat as uncertain (confirm in chatbot)
        debugPrint('[SmartMapper] Stage3 ~ $key = $val (llm, uncertain)');
        needsUser.add(FieldQuery(
          key: key,
          label: field['label'] as String? ?? key,
          type: type,
          options: options,
          hintValue: val,
          isUncertain: true,
        ));
      } else {
        // Completely missing — chatbot asks without hint
        debugPrint('[SmartMapper] Stage3 ✗ $key = missing');
        needsUser.add(FieldQuery(
          key: key,
          label: field['label'] as String? ?? key,
          type: type,
          options: options,
          hintValue: null,
          isUncertain: false,
        ));
      }
    }

    debugPrint('[SmartMapper] Final: ${confident.length} confident, '
        '${needsUser.length} needs user');

    return SmartMappingResult(confident: confident, needsUser: needsUser);
  }

  // ─── Stage 2: Targeted snippet search ─────────────────────────────────────

  _SnippetResult? _targetedSearch({
    required String label,
    required String type,
    required Map<String, dynamic> ocrData,
  }) {
    // Each entry: (label-keywords, preferred-doc-keys, regex-pattern)
    for (final rule in _kSnippetRules) {
      if (!rule.matchesLabel(label, type)) continue;

      // Try preferred doc keys first, then fall back to all raw text
      final docKeys = [
        ...rule.preferredDocKeys,
        // generic fallback — any *_raw_text key
        ...ocrData.keys.where((k) => k.endsWith('_raw_text')),
      ].toSet();

      for (final docKey in docKeys) {
        final raw = ocrData[docKey]?.toString() ?? '';
        if (raw.isEmpty) continue;

        final m = rule.pattern.firstMatch(raw);
        if (m != null) {
          final value = (m.groupCount >= 1 ? m.group(1) : m.group(0)) ?? '';
          if (value.isNotEmpty) {
            return _SnippetResult(value: value.trim(), docKey: docKey);
          }
        }
      }
    }
    return null;
  }

  // ─── Stage 3: Build focused OCR for Gemma ─────────────────────────────────

  /// Returns a stripped-down OCR map for Gemma — structured fields that are
  /// relevant to [fields] + at most one short raw-text snippet per needed doc type.
  Map<String, dynamic> _buildFocusedOcrForLlm(
    List<Map<String, dynamic>> fields,
    Map<String, dynamic> ocrData,
  ) {
    final result = <String, dynamic>{};

    // Always include all structured (non-raw) keys — they're small
    for (final entry in ocrData.entries) {
      if (!entry.key.endsWith('_raw_text')) {
        result[entry.key] = entry.value;
      }
    }

    // For each field, determine which doc type is most relevant and include
    // a short (≤200 char) snippet of that doc's raw text
    final includedDocKeys = <String>{};
    for (final field in fields) {
      final label = (field['label'] as String? ?? '').toLowerCase();
      final type = field['type'] as String? ?? '';

      final docKey = _preferredDocKeyForLabel(label, type, ocrData);
      if (docKey != null && !includedDocKeys.contains(docKey)) {
        final raw = ocrData[docKey]?.toString() ?? '';
        if (raw.isNotEmpty) {
          // Take only the most relevant 200 chars
          result[docKey] = raw.length > 200 ? raw.substring(0, 200) : raw;
          includedDocKeys.add(docKey);
        }
      }
    }

    return result;
  }

  String? _preferredDocKeyForLabel(
      String label, String type, Map<String, dynamic> ocrData) {
    for (final rule in _kSnippetRules) {
      if (!rule.matchesLabel(label, type)) continue;
      for (final dk in rule.preferredDocKeys) {
        if (ocrData.containsKey(dk)) return dk;
      }
    }
    // Fall back to the first available raw text
    for (final key in ocrData.keys) {
      if (key.endsWith('_raw_text')) return key;
    }
    return null;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _keyOf(Map<String, dynamic> field) {
    final id = field['id'] as String? ?? '';
    return id.isNotEmpty ? id : (field['name'] as String? ?? '');
  }

  List<Map<String, String>>? _castOptions(dynamic raw) {
    if (raw is! List) return null;
    return raw.map((o) {
      final m = o as Map<String, dynamic>;
      return {
        'value': (m['value'] ?? '').toString(),
        'text': (m['text'] ?? m['value'] ?? '').toString(),
      };
    }).toList();
  }

  // ─── Snippet rule table ────────────────────────────────────────────────────
  //
  // Each rule defines:
  //  • keywords  — substrings in the field's label that trigger this rule
  //  • types     — field type constraints (empty = any)
  //  • preferredDocKeys — document raw-text keys to search first
  //  • pattern   — regex; group(1) is the extracted value if present

  static final _kSnippetRules = <_SnippetRule>[
    // ── Identity ──────────────────────────────────────────────────────────
    _SnippetRule(
      keywords: ['aadhaar', 'aadhar', 'uid', 'adhaar'],
      preferredDocKeys: ['aadhaar_raw_text'],
      pattern: RegExp(r'\b(\d{4}[\s\-]?\d{4}[\s\-]?\d{4})\b'),
    ),
    _SnippetRule(
      keywords: ['pan', 'permanent account'],
      preferredDocKeys: ['pan_card_raw_text'],
      pattern: RegExp(r'\b([A-Z]{5}[0-9]{4}[A-Z])\b'),
    ),
    _SnippetRule(
      keywords: ['dob', 'birth', 'date of birth', 'janm'],
      types: ['date', 'text'],
      preferredDocKeys: ['aadhaar_raw_text', 'pan_card_raw_text'],
      pattern: RegExp(
          r'\b(0?[1-9]|[12][0-9]|3[01])[\/\-](0?[1-9]|1[012])[\/\-](19|20\d\d)\b'),
    ),
    // ── Banking ───────────────────────────────────────────────────────────
    _SnippetRule(
      keywords: ['ifsc'],
      preferredDocKeys: ['bank_passbook_raw_text'],
      pattern: RegExp(r'\b([A-Z]{4}0[A-Z0-9]{6})\b'),
    ),
    _SnippetRule(
      keywords: ['account', 'acc no', 'khata', 'bank account'],
      preferredDocKeys: ['bank_passbook_raw_text'],
      pattern: RegExp(r'(?:account|a\/c|acc)[^\d]{0,10}(\d{9,18})',
          caseSensitive: false),
    ),
    _SnippetRule(
      keywords: ['micr'],
      preferredDocKeys: ['bank_passbook_raw_text'],
      pattern: RegExp(r'MICR[^\d]{0,5}(\d{9})', caseSensitive: false),
    ),
    _SnippetRule(
      keywords: ['bank name', 'bank'],
      preferredDocKeys: ['bank_passbook_raw_text'],
      pattern: RegExp(
          r'(State Bank of India|Bank of Baroda|Bank of Maharashtra|Canara Bank|Punjab National Bank|Union Bank|HDFC Bank|ICICI Bank|Axis Bank|Bank of India|Central Bank)',
          caseSensitive: false),
    ),
    // ── Land / Farm ───────────────────────────────────────────────────────
    _SnippetRule(
      keywords: ['survey', 'gat', 'khasra', 'plot'],
      preferredDocKeys: [
        'seven_twelve_raw_text',
        'land_certificate_raw_text',
        'eight_a_raw_text',
      ],
      pattern: RegExp(
          r'(?:survey|gat|gata|s\.?\s*no)[^\d]{0,10}([\d]+(?:[\/\-][\d]+)?)',
          caseSensitive: false),
    ),
    _SnippetRule(
      keywords: ['land', 'area', 'hectare', 'acre', 'bigha'],
      preferredDocKeys: [
        'seven_twelve_raw_text',
        'land_certificate_raw_text',
      ],
      pattern: RegExp(r'([\d]+(?:\.[\d]+)?)\s*(?:acres?|hectares?|bigha)',
          caseSensitive: false),
    ),
    _SnippetRule(
      keywords: ['crop', 'fasal', 'pik'],
      preferredDocKeys: ['seven_twelve_raw_text'],
      pattern: RegExp(
          r'(?:crop|fasal|pik)[^\w]{0,5}([A-Za-z\u0900-\u097F]{3,20})',
          caseSensitive: false),
    ),
    // ── Income ────────────────────────────────────────────────────────────
    _SnippetRule(
      keywords: ['income', 'annual income', 'aay'],
      preferredDocKeys: [],
      pattern: RegExp(r'(?:Rs\.?|₹)\s*([\d,]+)', caseSensitive: false),
    ),
    // ── Address ───────────────────────────────────────────────────────────
    _SnippetRule(
      keywords: ['pincode', 'pin code', 'postal', 'zip'],
      preferredDocKeys: ['aadhaar_raw_text'],
      pattern: RegExp(r'\b([1-9][0-9]{5})\b'),
    ),
    _SnippetRule(
      keywords: ['taluka', 'tehsil', 'block'],
      preferredDocKeys: ['seven_twelve_raw_text', 'aadhaar_raw_text'],
      pattern: RegExp(
          r'(?:taluka|tehsil|block)\s*[:\-]?\s*([A-Za-z\u0900-\u097F]{3,30})',
          caseSensitive: false),
    ),
    _SnippetRule(
      keywords: ['village', 'gram', 'gaon', 'vill'],
      preferredDocKeys: ['seven_twelve_raw_text', 'aadhaar_raw_text'],
      pattern: RegExp(
          r'(?:village|gram|vill)\s*[:\-]?\s*([A-Za-z\u0900-\u097F]{3,30})',
          caseSensitive: false),
    ),
    _SnippetRule(
      keywords: ['district', 'zila', 'jillha'],
      preferredDocKeys: ['aadhaar_raw_text', 'seven_twelve_raw_text'],
      pattern: RegExp(
          r'(?:dist(?:rict)?|jillha|zila)\s*[:\-]?\s*([A-Za-z\u0900-\u097F\s]{3,30})',
          caseSensitive: false),
    ),
    // ── Contact ───────────────────────────────────────────────────────────
    _SnippetRule(
      keywords: ['mobile', 'phone', 'contact'],
      preferredDocKeys: ['aadhaar_raw_text'],
      pattern: RegExp(r'\b([6-9]\d{9})\b'),
    ),
  ];
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

class _SnippetResult {
  final String value;
  final String docKey;
  const _SnippetResult({required this.value, required this.docKey});
}

class _SnippetRule {
  final List<String> keywords;
  final List<String> types; // empty = any type
  final List<String> preferredDocKeys;
  final RegExp pattern;

  const _SnippetRule({
    required this.keywords,
    this.types = const [],
    required this.preferredDocKeys,
    required this.pattern,
  });

  bool matchesLabel(String normLabel, String type) {
    if (types.isNotEmpty && !types.contains(type)) return false;
    return keywords.any((k) => normLabel.contains(k));
  }
}
