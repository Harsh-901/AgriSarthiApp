/// Deterministic field mapper — Phase 2 of the AutoFill Agent pipeline.
///
/// **Replaces the on-device Gemma LLM entirely.**
///
/// Maps each extracted form field (id / name / label) to a value from the OCR
/// data using a scored alias table. No ML, no network — runs in <10 ms.
///
/// Strategy:
///  1. Normalise the field's id, name, and label (lowercase, no spaces/dashes).
///  2. Score every OCR key alias against the normalised candidates.
///  3. Pick the highest-score OCR value (min score threshold: 60).
///  4. For `<select>` fields, additionally snap the value to the closest option.
///  5. Anything with score < threshold is returned as null → highlighted for user.
class FieldMapperService {
  FieldMapperService._();
  static final FieldMapperService instance = FieldMapperService._();

  /// Returns {fieldId/fieldName → value | null} for every field in the list.
  ///
  /// Fields where we cannot find a confident match are mapped to `null` —
  /// the caller should highlight those and prompt the user.
  Map<String, String?> map({
    required List<Map<String, dynamic>> fields,
    required Map<String, dynamic> ocrData,
  }) {
    final result = <String, String?>{};
    for (final field in fields) {
      final key = (field['id'] as String? ?? '').isNotEmpty
          ? field['id'] as String
          : field['name'] as String? ?? '';
      if (key.isEmpty) continue;

      final label = field['label'] as String? ?? '';
      final type = field['type'] as String? ?? 'text';
      final options = field['options'] as List<dynamic>?;

      final value = _findValue(
        fieldId: key,
        fieldName: field['name'] as String? ?? '',
        label: label,
        type: type,
        options: options,
        ocrData: ocrData,
      );
      result[key] = value;
    }
    return result;
  }

  // ─── Core matching ────────────────────────────────────────────────────────

  String? _findValue({
    required String fieldId,
    required String fieldName,
    required String label,
    required String type,
    required List<dynamic>? options,
    required Map<String, dynamic> ocrData,
  }) {
    // Normalise all candidates once
    final normId = _norm(fieldId);
    final normName = _norm(fieldName);
    final normLabel = _norm(label);

    int bestScore = 0;
    String? bestValue;

    for (final entry in _kAliasTable.entries) {
      final ocrKey = entry.key;
      final rawValue = ocrData[ocrKey];
      if (rawValue == null || rawValue.toString().isEmpty) continue;

      // Compute score: highest score across all aliases for this OCR key
      int score = 0;
      for (final alias in entry.value) {
        final s = _scoreAlias(alias, normId, normName, normLabel);
        if (s > score) score = s;
      }

      if (score > bestScore) {
        bestScore = score;
        bestValue = rawValue.toString();
      }
    }

    // Also try direct key match (fieldId exactly == OCR key)
    if (ocrData.containsKey(fieldId)) {
      final direct = ocrData[fieldId]?.toString();
      if (direct != null && direct.isNotEmpty) {
        bestScore = 100;
        bestValue = direct;
      }
    }

    if (bestScore < 60 || bestValue == null) return null;

    // For select, snap bestValue to closest matching option
    if (options != null && options.isNotEmpty) {
      return _snapToOption(bestValue, options);
    }

    return bestValue;
  }

  /// Score how well [alias] matches against the normalised field candidates.
  int _scoreAlias(
      String alias, String normId, String normName, String normLabel) {
    int best = 0;
    for (final candidate in [normId, normName, normLabel]) {
      if (candidate.isEmpty) continue;
      int s;
      if (candidate == alias) {
        s = 100;
      } else if (candidate.contains(alias) || alias.contains(candidate)) {
        s = 80;
      } else {
        s = _partialScore(alias, candidate);
      }
      if (s > best) best = s;
    }
    return best;
  }

  /// Checks how many chars of [a] appear as a subsequence in [b].
  int _partialScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    int i = 0;
    for (int j = 0; j < b.length && i < a.length; j++) {
      if (b[j] == a[i]) i++;
    }
    // Score = fraction of a matched × 60 (up to 60)
    return ((i / a.length) * 60).round();
  }

  // ─── Select snapping ──────────────────────────────────────────────────────

  String? _snapToOption(String value, List<dynamic> options) {
    final normValue = _norm(value);
    // Exact match on value or text first
    for (final opt in options) {
      final optMap = opt as Map<String, dynamic>;
      if (_norm(optMap['value']?.toString() ?? '') == normValue ||
          _norm(optMap['text']?.toString() ?? '') == normValue) {
        return optMap['value']?.toString();
      }
    }
    // Contains match
    for (final opt in options) {
      final optMap = opt as Map<String, dynamic>;
      final normOptText = _norm(optMap['text']?.toString() ?? '');
      if (normOptText.contains(normValue) || normValue.contains(normOptText)) {
        return optMap['value']?.toString();
      }
    }
    return value; // return raw and let form_filler.js try
  }

  // ─── Normaliser ──────────────────────────────────────────────────────────

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s_\-\.]+'), '');

  // ─── Alias table ──────────────────────────────────────────────────────────
  //
  // Maps each OCR data key → list of normalised field id/name/label fragments
  // that indicate this field should receive this data.
  //
  // Add more as new government portals are encountered.

  static const _kAliasTable = <String, List<String>>{
    // ── Identity ────────────────────────────────────────────────────────────
    'full_name': [
      'fullname',
      'name',
      'applicantname',
      'farmername',
      'holdername',
      'beneficiaryname',
      'ownername',
      'membername',
      'nameofreg',
      'applicant',
      'namefull',
      'fullnameapplicant',
      'registeredname',
    ],
    'aadhaar_number': [
      'aadhaar',
      'aadhar',
      'adhaar',
      'aadhaarnumber',
      'aadharno',
      'aadhaarno',
      'uidno',
      'uid',
      'uidainumber',
    ],
    'pan_number': [
      'pan',
      'pannumber',
      'panno',
      'permanentaccountnumber',
    ],
    'date_of_birth': [
      'dob',
      'dateofbirth',
      'birthdate',
      'bdate',
      'birth',
    ],
    // ── Contact ─────────────────────────────────────────────────────────────
    'phone': [
      'phone',
      'mobile',
      'mobilenumber',
      'phonenumber',
      'contact',
      'contactno',
      'mob',
      'cellphone',
      'mobilephone',
    ],
    'email': [
      'email',
      'emailid',
      'emailaddress',
      'mail',
    ],
    // ── Banking ─────────────────────────────────────────────────────────────
    'account_number': [
      'accountnumber',
      'accountno',
      'acno',
      'bankaccount',
      'bankaccountno',
      'bankacc',
      'accountnum',
      'accno',
    ],
    'ifsc_code': [
      'ifsc',
      'ifsccode',
      'ifsccod',
      'bankifsc',
    ],
    'bank_name': [
      'bankname',
      'bank',
      'nameofbank',
      'bankingname',
    ],
    'micr_code': [
      'micr',
      'micrcode',
    ],
    // ── Address ─────────────────────────────────────────────────────────────
    'state': [
      'state',
      'statename',
      'province',
    ],
    'district': [
      'district',
      'districtname',
      'dist',
      'jillha',
      'tehsil',
    ],
    'village': [
      'village',
      'villagename',
      'gram',
      'grampanchayat',
      'vill',
    ],
    'pincode': [
      'pincode',
      'pin',
      'postalcode',
      'zipcode',
      'zip',
    ],
    // ── Land / Farm ─────────────────────────────────────────────────────────
    'survey_number': [
      'surveynumber',
      'surveyno',
      'gatnumber',
      'gatno',
      'khasranumber',
      'khasrano',
      'landsurveynumber',
      'plotno',
      'plotnumber',
    ],
    'land_area_acres': [
      'landarea',
      'area',
      'acreage',
      'acres',
      'landsize',
      'areaacres',
      'cultivatedarea',
      'netarea',
    ],
    'land_area_hectares': [
      'hectares',
      'landareahectare',
      'areainhectare',
    ],
    'primary_crop': [
      'crop',
      'cropname',
      'maincrop',
      'primarycrop',
      'croptype',
    ],
  };
}
