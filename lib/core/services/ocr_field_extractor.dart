/// Document-type-aware OCR field extractor.
///
/// Each document type has its OWN extraction strategy — patterns are only
/// run where they make sense, preventing cross-document false matches:
///
///   aadhaar        → name, full address (with state/district/village),
///                    date_of_birth, aadhaar_number, gender, pincode
///   pan_card       → name, father_name, date_of_birth, pan_number
///   bank_passbook  → account_number, ifsc_code, bank_name, micr_code,
///                    branch, account_holder_name
///   seven_twelve   → survey_number, land_area_acres/hectares, primary_crop,
///                    owner_name, village, district, taluka
///   eight_a        → survey_number, land_area_acres, owner_name, village
///   land_certificate → survey_number, land_area_acres, owner_name
///   income_cert    → annual_income, name, village, district
///   (generic)      → best-effort extraction with all patterns but stricter
///                    context-checking
class OcrFieldExtractor {
  OcrFieldExtractor._();

  // ─── Public entry point ──────────────────────────────────────────────────

  /// Extract known fields from [rawText].
  ///
  /// [docType] must be one of:
  ///   aadhaar | pan_card | bank_passbook | seven_twelve | eight_a |
  ///   land_certificate | income_cert  — or null/empty for generic.
  static Map<String, dynamic> extract(String rawText, {String? docType}) {
    final data = <String, dynamic>{};
    final norm = (docType ?? '').toLowerCase().trim();
    final text = rawText;

    switch (norm) {
      case 'aadhaar':
      case 'adhaar':
      case 'aadhar':
        _extractAadhaar(text, data);
        break;
      case 'pan_card':
      case 'pan':
        _extractPan(text, data);
        break;
      case 'bank_passbook':
      case 'passbook':
      case 'bank_statement':
        _extractBankPassbook(text, data);
        break;
      case 'seven_twelve':
      case '7_12':
      case '7/12':
        _extractSevenTwelve(text, data);
        break;
      case 'eight_a':
      case '8_a':
        _extractEightA(text, data);
        break;
      case 'land_certificate':
      case 'land_record':
        _extractLandCertificate(text, data);
        break;
      case 'income_cert':
      case 'income_certificate':
        _extractIncomeCert(text, data);
        break;
      default:
        _extractGeneric(text, data, docType: norm);
    }

    return data;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AADHAAR CARD
  // Govt. format: Name → DOB/Year of Birth → Gender → Address → UID
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractAadhaar(String text, Map<String, dynamic> data) {
    // 1. Aadhaar UID — 12 digits, often printed as XXXX XXXX XXXX
    final uidM =
        RegExp(r'\b(\d{4}[\s\u00a0]?\d{4}[\s\u00a0]?\d{4})\b').firstMatch(text);
    if (uidM != null) {
      data['aadhaar_number'] =
          uidM.group(1)!.replaceAll(RegExp(r'[\s\u00a0]'), '');
    }

    // 2. Date of birth — "DOB: DD/MM/YYYY" or "Year of Birth: YYYY"
    final dobFull = RegExp(
            r'(?:DOB|Date\s+of\s+Birth)\s*:?\s*(0?[1-9]|[12]\d|3[01])[\/\-](0?[1-9]|1[012])[\/\-](19|20\d\d)',
            caseSensitive: false)
        .firstMatch(text);
    if (dobFull != null) {
      final d = dobFull.group(1)!.padLeft(2, '0');
      final mo = dobFull.group(2)!.padLeft(2, '0');
      final y = dobFull.group(3)!;
      data['date_of_birth'] = '$y-$mo-$d';
    } else {
      // Year of Birth only (some Aadhaar cards mask full DOB)
      final yobM =
          RegExp(r'Year\s+of\s+Birth\s*:?\s*(19|20\d\d)', caseSensitive: false)
              .firstMatch(text);
      if (yobM != null) data['year_of_birth'] = yobM.group(1);
    }

    // 3. Gender
    if (RegExp(r'\bMALE\b', caseSensitive: false).hasMatch(text) &&
        !RegExp(r'\bFEMALE\b', caseSensitive: false).hasMatch(text)) {
      data['gender'] = 'Male';
    } else if (RegExp(r'\bFEMALE\b', caseSensitive: false).hasMatch(text)) {
      data['gender'] = 'Female';
    }

    // 4. Name — labeled line "Name:" or the very first Title-Case line
    //    before DOB/Gender and after "Unique Identification Authority"
    _tryLabeledName(text, data, labels: ['Name', 'नाम', 'ನಾಮ', 'পেরু']);
    if (!data.containsKey('full_name')) {
      _tryFirstTitleCaseLine(text, data,
          stopWords: _kIdStopWords + ['UNIQUE', 'UIDAI', 'AUTHORITY']);
    }

    // 5. Pincode — 6-digit, usually part of the address block
    _tryPincode(text, data);

    // 6. State from address block
    _tryState(text, data);

    // 7. Address — capture the block between "Address" / "S/O" and the UID
    final addrM = RegExp(
            r'(?:Address|S/O|W/O|C/O|पता)[:\s]+([\s\S]{20,250})(?=\d{4}\s\d{4}\s\d{4})',
            caseSensitive: false)
        .firstMatch(text);
    if (addrM != null) {
      final raw = addrM.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
      data['full_address'] = raw;

      // Try to split village, district, state, pincode from address block
      _parseAddressBlock(raw, data);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAN CARD
  // Front: Name, Father's Name, DOB, PAN number (back has no useful data)
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractPan(String text, Map<String, dynamic> data) {
    // 1. PAN number — mandatory format: AAAAA9999A
    final panM = RegExp(r'\b([A-Z]{5}[0-9]{4}[A-Z])\b').firstMatch(text);
    if (panM != null) data['pan_number'] = panM.group(1);

    // 2. DOB — DD/MM/YYYY on front face
    final dobM =
        RegExp(r'\b(0?[1-9]|[12]\d|3[01])\/(0?[1-9]|1[012])\/(19|20\d\d)\b')
            .firstMatch(text);
    if (dobM != null) {
      final d = dobM.group(1)!.padLeft(2, '0');
      final mo = dobM.group(2)!.padLeft(2, '0');
      data['date_of_birth'] = '${dobM.group(3)}-$mo-$d';
    }

    // 3. Name/Father — PAN cards print two ALL-CAPS name lines:
    //    Line 1 = applicant name, Line 2 = father's name
    final capsLines =
        RegExp(r'^([A-Z]{2,}(?:\s[A-Z]{2,}){1,4})$', multiLine: true)
            .allMatches(text)
            .map((m) => m.group(1)!)
            .where((l) =>
                !l.contains('INCOME') &&
                !l.contains('TAX') &&
                !l.contains('INDIA') &&
                !l.contains('GOVERNMENT') &&
                !l.contains('PERMANENT') &&
                !l.contains('ACCOUNT') &&
                !l.contains('DEPT') &&
                !l.contains('CARD'))
            .toList();

    if (capsLines.isNotEmpty) data['full_name'] = _cleanName(capsLines[0]);
    if (capsLines.length >= 2) data['father_name'] = _cleanName(capsLines[1]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BANK PASSBOOK / BANK STATEMENT
  //
  // ALL bank field extraction requires label context (e.g. "IFSC:", "A/C No:")
  // to avoid false positives. NO unlabeled guessing.
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractBankPassbook(String text, Map<String, dynamic> data) {
    final flat = text.replaceAll(RegExp(r'[ \t]+'), ' ');

    // ── 1. IFSC — LABELED ONLY ───────────────────────────────────────────────
    // Must have "IFSC" keyword nearby. No unlabeled fallback.
    final ifscM = RegExp(
            r'IFSC\s*(?:Code|No\.?)?[:\s\-]*([A-Z]{4}[0O][A-Z0-9]{6})',
            caseSensitive: false)
        .firstMatch(flat);
    if (ifscM != null) {
      // Fix OCR O→0 at position 5 (always numeric zero in IFSC)
      final raw = ifscM.group(1)!.toUpperCase();
      final fixed =
          raw.length >= 5 ? raw.substring(0, 4) + '0' + raw.substring(5) : raw;
      data['ifsc_code'] = fixed;
    }

    // ── 2. Account number — LABELED ONLY ─────────────────────────────────────
    // Must have "Account", "A/C", "Acc" keyword nearby.
    final acM = RegExp(
            r'(?:account\s*(?:no\.?|number|num)|a[/\.]c\.?\s*(?:no\.?|number)|acc\.?\s*no\.?|khata\s*(?:no\.?|number))\s*[:\-\s]*(\d[\d\s]{7,19}\d)',
            caseSensitive: false)
        .firstMatch(flat);
    if (acM != null) {
      final numStr = acM.group(1)!.replaceAll(RegExp(r'\s'), '');
      if (numStr.length >= 9 && numStr.length <= 18) {
        data['account_number'] = numStr;
      }
    }

    // ── 3. MICR — LABELED ONLY ───────────────────────────────────────────────
    final micrM = RegExp(r'MICR\s*(?:Code|No\.?)?[:\s\-]*(\d[\d\s]{7,10}\d)',
            caseSensitive: false)
        .firstMatch(flat);
    if (micrM != null) {
      final n = micrM.group(1)!.replaceAll(' ', '');
      if (n.length == 9) data['micr_code'] = n;
    }

    // ── 4. Bank name ─────────────────────────────────────────────────────────
    _tryBankName(flat, data);

    // ── 5. Account holder name — LABELED ONLY ────────────────────────────────
    _tryLabeledName(flat, data, labels: [
      'Account Holder Name',
      'Account Holder',
      'Account Name',
      'Holder Name',
      'Customer Name',
      'Name',
    ]);

    // ── 6. Branch — LABELED ONLY ─────────────────────────────────────────────
    final branchM = RegExp(
            r'Branch(?:\s+Name)?\s*[:\-]\s*([A-Za-z][A-Za-z\s,\.]{3,45})',
            caseSensitive: false)
        .firstMatch(flat);
    if (branchM != null) {
      data['bank_branch'] = branchM
          .group(1)!
          .split('\n')
          .first
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
    }

    // ── 7. Account type ──────────────────────────────────────────────────────
    final typeM = RegExp(
            r'\b(Savings|Current|Recurring|Fixed\s+Deposit|NRE|NRO|PMJDY)\b',
            caseSensitive: false)
        .firstMatch(flat);
    if (typeM != null) data['account_type'] = typeM.group(1)!.trim();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7/12 EXTRACT (Satbara Utara / MahaaBhulekh)
  //
  // The official Maharashtra 7/12 is bilingual: English headers + Marathi data.
  // LocalOcrService now produces:  <latin text>\n\n---DEVANAGARI---\n<marathi>
  // This extractor searches both halves intelligently.
  //
  // Real field names on 7/12:
  //   "Gut No." / "Gat No." / "S.No." / गट क्र. / ग.नं.
  //   "Area (in Are)" / "Net Area" / "Pot-Kharaba" / क्षेत्रफळ (आर)
  //   "Right Holders" / "Khatedar Name" / खातेदार
  //   "Occupant" / "Cultivator" / कब्जेदार
  //   "Crop (Kharif)" / "Crop (Rabi)" / पीक / खरीप / रब्बी
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractSevenTwelve(String text, Map<String, dynamic> data) {
    // Split into Latin and Devanagari halves
    final parts = text.split('---DEVANAGARI---');
    final latin = parts[0];
    final devnagri = parts.length > 1 ? parts[1] : '';

    // ── 1. Survey / Gat number ────────────────────────────────────────────────
    // Try all known column header formats on the official 7/12 form
    final surveyPatterns = [
      RegExp(
          r'(?:Gut|Gat|Survey|G\.N\.|S\.)\s*No\.?\s*[:\-]?\s*([\d]+(?:[\/\-][\d]+)?)',
          caseSensitive: false),
      RegExp(r'\bGat\s*Krama\s*Nk?\b[^\d]*(\d+)', caseSensitive: false),
      // Devanagari pattern: गट क्र. or ग.नं.
      RegExp(r'(?:गट क्र\.?|ग\.नं\.?|गट नंबर)\s*([\d]+(?:[\/\-][\d]+)?)'),
    ];
    for (final p in surveyPatterns) {
      final m = p.firstMatch(text); // search full merged text
      if (m != null) {
        data['survey_number'] = m.group(1)!.trim();
        break;
      }
    }

    // ── 2. Land area ──────────────────────────────────────────────────────────
    // Maharashtra 7/12 uses "Are" (1 Are = 0.01 hectares) for area
    if (!data.containsKey('land_area_hectares')) {
      // a) Hectares labeled
      final ha = RegExp(
              r'(?:Area|क्षेत्रफळ|Net\s+Area)\s*[:\-]?\s*([\d]+(?:\.[\d]+)?)\s*(?:Hect(?:are)?s?|हे\.?|Ha\.?)',
              caseSensitive: false)
          .firstMatch(text);
      if (ha != null) {
        final v = double.tryParse(ha.group(1)!) ?? 0;
        data['land_area_hectares'] = v.toStringAsFixed(2);
        data['land_area_acres'] = (v * 2.471).toStringAsFixed(2);
      }

      // b) Are (Maharashtra unit) – 1 Are = 0.01 ha
      if (!data.containsKey('land_area_hectares')) {
        final are = RegExp(
                r'(?:Area|Net\s+Area|क्षेत्रफळ)\s*[\(]?(?:in\s+Are)?[\)]?\s*[:\-]?\s*([\d]+(?:\.[\d]+)?)\s*(?:Are|आर)',
                caseSensitive: false)
            .firstMatch(text);
        if (are != null) {
          final v = double.tryParse(are.group(1)!) ?? 0;
          final ha = v / 100;
          data['land_area_hectares'] = ha.toStringAsFixed(2);
          data['land_area_acres'] = (ha * 2.471).toStringAsFixed(2);
        }
      }

      // c) Acres labeled
      if (!data.containsKey('land_area_hectares')) {
        final ac = RegExp(
                r'(?:Area|Net\s+Area|Extent)\s*[:\-]?\s*([\d]+(?:\.[\d]+)?)\s*(?:Acres?|एकर)',
                caseSensitive: false)
            .firstMatch(text);
        if (ac != null) {
          data['land_area_acres'] = ac.group(1)!.trim();
          final acVal = double.tryParse(ac.group(1)!) ?? 0;
          data['land_area_hectares'] = (acVal / 2.471).toStringAsFixed(2);
        }
      }
    }

    // ── 3. Crops ──────────────────────────────────────────────────────────────
    // Try Kharif separately from Rabi
    final kharifM = RegExp(
            r'(?:Crop\s*[\(]?Kharif[\)]?|Kharif\s+Crop|खरीप\s+पीक|खरीप)[^\w]{0,5}([A-Za-z\u0900-\u097F][A-Za-z\u0900-\u097F\s,]{2,40})',
            caseSensitive: false)
        .firstMatch(text);
    if (kharifM != null) {
      data['kharif_crop'] =
          kharifM.group(1)!.split(RegExp(r'[,\/\n]')).first.trim();
      if (!data.containsKey('primary_crop'))
        data['primary_crop'] = data['kharif_crop'];
    }

    final rabiM = RegExp(
            r'(?:Crop\s*[\(]?Rabi[\)]?|Rabi\s+Crop|रब्बी\s+पीक|रब्बी)[^\w]{0,5}([A-Za-z\u0900-\u097F][A-Za-z\u0900-\u097F\s,]{2,40})',
            caseSensitive: false)
        .firstMatch(text);
    if (rabiM != null) {
      data['rabi_crop'] =
          rabiM.group(1)!.split(RegExp(r'[,\/\n]')).first.trim();
    }

    // Generic crop fallback
    if (!data.containsKey('primary_crop')) {
      final cropM = RegExp(
              r'(?:Crop|पीक|Fasal)\s*[:\-]?\s*([A-Za-z\u0900-\u097F][A-Za-z\u0900-\u097F\s]{2,40})',
              caseSensitive: false)
          .firstMatch(text);
      if (cropM != null) {
        data['primary_crop'] =
            cropM.group(1)!.split(RegExp(r'[,\/\n]')).first.trim();
      }
    }

    // ── 4. Owner / Right-holder name ──────────────────────────────────────────
    // Try Latin section first (English-medium prints have holder in Latin)
    _tryLabeledName(latin, data, labels: [
      'Right Holder',
      'Khatedar',
      'Occupant',
      'Owner',
      'Name',
      'Cultivator',
    ]);

    // Try Devanagari labeled extraction ONLY — no wild guessing.
    // The old fallback of "take first Devanagari line" was grabbing UI text
    // like "मागे जा" (Go Back button), so it's been removed.
    if (!data.containsKey('full_name') && devnagri.isNotEmpty) {
      final khatedar = RegExp(
              r'(?:खातेदार|कब्जेदार|मालक|नाव|नाम)\s*[:\-]?\s*([\u0900-\u097F][\u0900-\u097F\s\.]{3,50})')
          .firstMatch(devnagri);
      if (khatedar != null) {
        final candidate = khatedar.group(1)!.trim();
        // Filter out common Marathi UI/navigation words
        if (!_kMarathiStopWords.any((w) => candidate.contains(w))) {
          data['full_name'] = candidate;
        }
      }
    }

    // ── 5. Place names ────────────────────────────────────────────────────────
    // Search Latin section for English labels first, then Devanagari
    _tryLabeledPlace(
        latin, data, 'village', ['Village', 'Gram', 'Gaon', 'Mouza']);
    _tryLabeledPlace(latin, data, 'taluka', ['Taluka', 'Tehsil', 'Tq.']);
    _tryLabeledPlace(latin, data, 'district', ['District', 'Dist.', 'Jilha']);
    _tryState(latin, data);

    // Devanagari fallbacks
    if (devnagri.isNotEmpty) {
      if (!data.containsKey('village')) {
        _tryLabeledPlace(devnagri, data, 'village', ['गाव', 'ग्राम', 'मौजे']);
      }
      if (!data.containsKey('taluka')) {
        _tryLabeledPlace(devnagri, data, 'taluka', ['तालुका', 'तहसील']);
      }
      if (!data.containsKey('district')) {
        _tryLabeledPlace(devnagri, data, 'district', ['जिल्हा', 'जिल्ह्याचे']);
      }
    }
  }

  // Common Marathi UI/navigation words that appear in OCR but are NOT names
  static const _kMarathiStopWords = [
    'मागे जा', // Go Back
    'पुढे', // Next
    'सुरू करा', // Start
    'बंद', // Close
    'रद्द', // Cancel
    'सबमिट', // Submit
    'होम', // Home
    'शोधा', // Search
    'माहिती', // Information
    'सूचना', // Notice
    'अर्ज', // Application
    'महाराष्ट्र', // State names
    'मुंबई',
    'पुणे',
    'नागपूर',
    'ठाणे',
    'नाशिक',
    'औरंगाबाद',
    'सोलापूर',
    'सातारा',
    'कोल्हापूर',
    'रत्नागिरी',
    'तालुका',
    'जिल्हा',
    'गाव',
    'ग्राम',
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // 8-A REGISTER (Khatian / Rights-of-Record)
  // Similar to 7/12 but emphasizes owner list and land extent
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractEightA(String text, Map<String, dynamic> data) {
    // Shares many patterns with 7/12
    _extractSevenTwelve(text, data);

    // 8-A specific: Khasra number
    final khasraM = RegExp(r'Khasra\s*(?:No\.?|Number)?\s*[:\-]?\s*([\d\/\-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (khasraM != null && !data.containsKey('survey_number')) {
      data['survey_number'] = khasraM.group(1)!.trim();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAND CERTIFICATE / LAND POSSESSION CERT
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractLandCertificate(String text, Map<String, dynamic> data) {
    _tryLabeledName(text, data,
        labels: ['Name', 'Owner', 'Malik', 'Holder', 'Beneficiary']);
    _tryLabeledPlace(text, data, 'village', ['Village', 'Gram']);
    _tryLabeledPlace(text, data, 'taluka', ['Taluka', 'Tehsil']);
    _tryLabeledPlace(text, data, 'district', ['District', 'Jilha']);
    _tryState(text, data);

    // Survey / Khasra with or without label
    final surveyM = RegExp(
            r'(?:Survey|Gat|Khasra)\s*No\.?\s*[:\-]?\s*([\d\/\-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (surveyM != null) data['survey_number'] = surveyM.group(1)!.trim();

    final areaM = RegExp(r'([\d]+(?:\.[\d]+)?)\s*(?:acres?|hectares?|Hect\.?)',
            caseSensitive: false)
        .firstMatch(text);
    if (areaM != null) {
      final unit = areaM.group(0)!.toLowerCase();
      if (unit.contains('hect')) {
        final ha = double.tryParse(areaM.group(1)!) ?? 0;
        data['land_area_hectares'] = ha.toStringAsFixed(2);
        data['land_area_acres'] = (ha * 2.471).toStringAsFixed(2);
      } else {
        data['land_area_acres'] = areaM.group(1);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOME CERTIFICATE
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractIncomeCert(String text, Map<String, dynamic> data) {
    _tryLabeledName(text, data, labels: ['Name', 'Applicant', 'Holder']);
    _tryLabeledPlace(text, data, 'village', ['Village', 'Gram']);
    _tryLabeledPlace(text, data, 'taluka', ['Taluka', 'Tehsil']);
    _tryLabeledPlace(text, data, 'district', ['District', 'Jilha']);
    _tryState(text, data);

    // Annual income — labeled, must have Rs./₹ nearby
    final incomeM = RegExp(
            r'(?:annual\s+income|income|aay)\s*[:\-]?\s*(?:Rs\.?|₹)?\s*([\d,]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (incomeM != null) {
      data['annual_income'] = incomeM.group(1)!.replaceAll(',', '').trim();
    } else {
      final rupeeM = RegExp(r'(?:Rs\.?|₹)\s*([\d,]+)').firstMatch(text);
      if (rupeeM != null) {
        data['annual_income'] = rupeeM.group(1)!.replaceAll(',', '').trim();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GENERIC FALLBACK (unknown document type)
  // Run all patterns but only if label context confirms the match
  // ═══════════════════════════════════════════════════════════════════════════

  static void _extractGeneric(String text, Map<String, dynamic> data,
      {String? docType}) {
    // Try everything — the labeled versions are already context-safe
    _tryLabeledName(text, data, labels: ['Name', 'Applicant', 'naam', 'नाम']);

    // Aadhaar only if strong label context
    if (RegExp(r'\b(Aadhaar|UIDAI|Unique\s+Identification)',
            caseSensitive: false)
        .hasMatch(text)) {
      final m = RegExp(r'\b(\d{4}[\s]?\d{4}[\s]?\d{4})\b').firstMatch(text);
      if (m != null) {
        data['aadhaar_number'] = m.group(1)!.replaceAll(RegExp(r'\s'), '');
      }
    }

    // PAN only if strong format match
    final panM = RegExp(r'\b([A-Z]{5}[0-9]{4}[A-Z])\b').firstMatch(text);
    if (panM != null) data['pan_number'] = panM.group(1);

    // DOB — labeled only
    final dobM = RegExp(
            r'(?:DOB|Date\s+of\s+Birth)\s*:?\s*(0?[1-9]|[12]\d|3[01])[\/\-](0?[1-9]|1[012])[\/\-](19|20\d\d)',
            caseSensitive: false)
        .firstMatch(text);
    if (dobM != null) {
      data['date_of_birth'] =
          '${dobM.group(3)}-${dobM.group(2)!.padLeft(2, '0')}-${dobM.group(1)!.padLeft(2, '0')}';
    }

    // IFSC — strict format, no label needed
    final ifscM = RegExp(r'\b([A-Z]{4}0[A-Z0-9]{6})\b').firstMatch(text);
    if (ifscM != null) data['ifsc_code'] = ifscM.group(1);

    // Account number — labeled only
    final acM = RegExp(
            r'(?:account\s*(?:no|number)|a\/c)\s*[:\-]?\s*(\d{9,18})',
            caseSensitive: false)
        .firstMatch(text);
    if (acM != null) data['account_number'] = acM.group(1);

    _tryBankName(text, data);
    _tryPincode(text, data);
    _tryState(text, data);

    // Survey — labeled only
    final surveyM = RegExp(
            r'(?:Survey|Gat|Khasra)\s*No\.?\s*[:\-]?\s*([\d\/\-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (surveyM != null) data['survey_number'] = surveyM.group(1)!.trim();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Try to find a name after labeled keywords (case-insensitive).
  static void _tryLabeledName(
    String text,
    Map<String, dynamic> data, {
    required List<String> labels,
  }) {
    if (data.containsKey('full_name')) return;
    final pattern = labels.map(RegExp.escape).join('|');
    final m = RegExp('(?:$pattern)\\s*[:\\-]\\s*([A-Za-z][A-Za-z\\s\\.]{3,50})',
            caseSensitive: false)
        .firstMatch(text);
    if (m != null) {
      final candidate = _cleanName(m.group(1)!);
      if (candidate.split(' ').length >= 2 && !_isBankOrPlace(candidate)) {
        data['full_name'] = candidate;
      }
    }
  }

  /// Try to find a place name after labeled keywords.
  static void _tryLabeledPlace(
    String text,
    Map<String, dynamic> data,
    String key,
    List<String> labels,
  ) {
    if (data.containsKey(key)) return;
    final pattern = labels.map(RegExp.escape).join('|');
    final m = RegExp(
            '(?:$pattern)\\s*[:\\-]?\\s*([A-Za-z\u0900-\u097F][A-Za-z\u0900-\u097F\\s]{2,40})',
            caseSensitive: false)
        .firstMatch(text);
    if (m != null) {
      final val = m.group(1)!.trim().split('\n').first.trim();
      if (val.isNotEmpty) data[key] = val;
    }
  }

  /// Find the first Title-Case line that looks like a human name (≥2 words),
  /// excluding lines that match [stopWords].
  static void _tryFirstTitleCaseLine(
    String text,
    Map<String, dynamic> data, {
    List<String> stopWords = const [],
  }) {
    if (data.containsKey('full_name')) return;
    for (final line in text.split('\n')) {
      final clean = line.trim();
      if (clean.length < 4 || clean.length > 60) continue;
      // Must be 2–4 Title-Case words
      if (!RegExp(r'^([A-Z][a-z]+)(?:\s+[A-Z][a-z]+){1,3}$').hasMatch(clean))
        continue;
      final upper = clean.toUpperCase();
      if (stopWords.any((w) => upper.contains(w.toUpperCase()))) continue;
      if (_isBankOrPlace(clean)) continue;
      data['full_name'] = clean;
      return;
    }
  }

  static void _tryPincode(String text, Map<String, dynamic> data) {
    if (data.containsKey('pincode')) return;
    // 6-digit Indian PIN: starts with 1-9
    final m = RegExp(r'\b([1-9][0-9]{5})\b').firstMatch(text);
    if (m != null) data['pincode'] = m.group(1);
  }

  static void _tryState(String text, Map<String, dynamic> data) {
    if (data.containsKey('state')) return;
    for (final s in _kStates) {
      if (text.toLowerCase().contains(s.toLowerCase())) {
        data['state'] = s;
        return;
      }
    }
  }

  static void _tryBankName(String text, Map<String, dynamic> data) {
    if (data.containsKey('bank_name')) return;
    for (final bank in _kBankKeywords) {
      if (text.toLowerCase().contains(bank.toLowerCase())) {
        data['bank_name'] = bank;
        return;
      }
    }
  }

  /// Try to parse village/district/state/pincode out of a raw address block.
  static void _parseAddressBlock(String addr, Map<String, dynamic> data) {
    // Pincode is reliable — extract first
    if (!data.containsKey('pincode')) {
      final pm = RegExp(r'\b([1-9][0-9]{5})\b').firstMatch(addr);
      if (pm != null) data['pincode'] = pm.group(1);
    }

    // State
    if (!data.containsKey('state')) _tryState(addr, data);

    // Labeled district / village / taluka in address
    _tryLabeledPlace(addr, data, 'district', ['Dist', 'District']);
    _tryLabeledPlace(addr, data, 'village', ['Vill', 'Village', 'Gram']);
    _tryLabeledPlace(addr, data, 'taluka', ['Taluka', 'Tehsil']);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA TABLES
  // ═══════════════════════════════════════════════════════════════════════════

  static String _cleanName(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ').split('\n').first.trim();

  static bool _isBankOrPlace(String s) {
    final lower = s.toLowerCase();
    return _kBankKeywords.any((b) => lower.contains(b.toLowerCase())) ||
        _kStates.any((st) => lower.contains(st.toLowerCase()));
  }

  static const _kIdStopWords = [
    'UNIQUE',
    'UIDAI',
    'AUTHORITY',
    'IDENTIFICATION',
    'GOVT',
    'GOVERNMENT',
    'INCOME',
    'TAX',
    'DEPARTMENT',
    'PERMANENT',
    'ACCOUNT',
    'INDIA',
  ];

  static const _kBankKeywords = [
    'State Bank of India',
    'SBI',
    'Bank of Baroda',
    'BOB',
    'Bank of Maharashtra',
    'BOM',
    'Canara Bank',
    'Punjab National Bank',
    'PNB',
    'Union Bank of India',
    'Union Bank',
    'Indian Bank',
    'UCO Bank',
    'Bank of India',
    'Central Bank of India',
    'Central Bank',
    'HDFC Bank',
    'HDFC',
    'ICICI Bank',
    'ICICI',
    'Axis Bank',
    'Kotak Mahindra Bank',
    'Kotak',
    'IDBI Bank',
    'IDBI',
    'YES Bank',
    'Federal Bank',
    'Karnataka Bank',
    'South Indian Bank',
    'DCB Bank',
    'Grameen Bank',
    'Saraswat Bank',
    'Cosmos Bank',
    'Janata Sahakari Bank',
    'Nainital Bank',
    'Dena Bank',
    'Vijaya Bank',
    'Andhra Bank',
    'The Shamrao Vithal Co-operative Bank',
    'SVCB',
    'Apna Sahakari Bank',
  ];

  static const _kStates = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Delhi',
    'Jammu and Kashmir',
    'Ladakh',
    'Puducherry',
    'Chandigarh',
    'Dadra and Nagar Haveli',
    'Daman and Diu',
    'Lakshadweep',
    'Andaman and Nicobar',
  ];
}
