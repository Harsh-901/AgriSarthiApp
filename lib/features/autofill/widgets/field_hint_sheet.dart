import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Conversational bottom sheet for a single form field the AI couldn't fill.
///
/// Returns the value the user entered / selected, or null if they skipped.
///
/// - select  → tap-to-choose chips for each option
/// - checkbox → Yes / No chips
/// - others   → text input with the right keyboard type
///
/// Usage:
/// ```dart
/// final value = await showFieldHintSheet(
///   context: context,
///   fieldLabel: 'Annual Income',
///   fieldType: 'number',
///   fieldRequired: true,
/// );
/// if (value != null) { /* inject into form */ }
/// ```
Future<String?> showFieldHintSheet({
  required BuildContext context,
  required String fieldLabel,
  required String fieldType,
  bool fieldRequired = false,
  List<Map<String, String>>? options, // [{value:'', text:''}] for select fields
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FieldHintSheet(
      fieldLabel: fieldLabel,
      fieldType: fieldType,
      fieldRequired: fieldRequired,
      options: options,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _FieldHintSheet extends StatefulWidget {
  final String fieldLabel;
  final String fieldType;
  final bool fieldRequired;
  final List<Map<String, String>>? options;

  const _FieldHintSheet({
    required this.fieldLabel,
    required this.fieldType,
    required this.fieldRequired,
    this.options,
  });

  @override
  State<_FieldHintSheet> createState() => _FieldHintSheetState();
}

class _FieldHintSheetState extends State<_FieldHintSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String? _selectedChip;

  bool get _isSelect => widget.fieldType == 'select';
  bool get _isCheckbox => widget.fieldType == 'checkbox';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    Navigator.of(context, rootNavigator: true).pop(value.trim());
  }

  void _skip() => Navigator.of(context, rootNavigator: true).pop(null);

  // ─── Keyboard type based on field type ───────────────────────────────────

  TextInputType get _keyboardType => switch (widget.fieldType) {
        'number' => TextInputType.number,
        'tel' => TextInputType.phone,
        'email' => TextInputType.emailAddress,
        'date' => TextInputType.datetime,
        _ => TextInputType.text,
      };

  List<TextInputFormatter> get _inputFormatters => switch (widget.fieldType) {
        'number' => [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        'tel' => [FilteringTextInputFormatter.digitsOnly],
        _ => [],
      };

  // ─── Natural-language question ────────────────────────────────────────────

  String get _question => _questionFor(widget.fieldLabel, widget.fieldType);

  // ─── Constraint hint ─────────────────────────────────────────────────────

  String? get _constraintHint =>
      _constraintFor(widget.fieldLabel, widget.fieldType);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── Bot avatar + question ────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: Color(0xFF2E7D32), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _question,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                            height: 1.4,
                          ),
                        ),
                        if (widget.fieldRequired) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '* Required',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFFE53935)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Constraint hint ──────────────────────────────────────────
              if (_constraintHint != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _constraintHint!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF5D4037)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Input area ───────────────────────────────────────────────
              if (_isCheckbox)
                _buildChips([
                  {'value': 'true', 'text': '✅  Yes'},
                  {'value': 'false', 'text': '❌  No'},
                ])
              else if (_isSelect &&
                  widget.options != null &&
                  widget.options!.isNotEmpty)
                _buildChips(widget.options!)
              else
                _buildTextField(),

              const SizedBox(height: 16),

              // ── Skip link ────────────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip this field',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Chip selector (select / checkbox) ───────────────────────────────────

  Widget _buildChips(List<Map<String, String>> opts) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opts.map((opt) {
        final val = opt['value']!;
        final txt = opt['text'] ?? val;
        final selected = _selectedChip == val;
        return ChoiceChip(
          label: Text(txt),
          selected: selected,
          onSelected: (_) {
            setState(() => _selectedChip = val);
            Future.delayed(const Duration(milliseconds: 100), () {
              _submit(val);
            });
          },
          selectedColor: const Color(0xFF4CAF50),
          labelStyle: TextStyle(
            color: selected ? Colors.white : const Color(0xFF1A1A1A),
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          backgroundColor: Colors.grey.shade100,
          side: BorderSide(
            color: selected ? const Color(0xFF4CAF50) : Colors.grey.shade300,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
      }).toList(),
    );
  }

  // ─── Free-text input ─────────────────────────────────────────────────────

  Widget _buildTextField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            keyboardType: _keyboardType,
            inputFormatters: _inputFormatters,
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
            decoration: InputDecoration(
              hintText: _placeholderFor(widget.fieldLabel, widget.fieldType),
              hintStyle:
                  const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onSubmitted: _submit,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => _submit(_ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Icon(Icons.send_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}

// ─── NLP question generator ───────────────────────────────────────────────────

String _questionFor(String label, String type) {
  final l = label.toLowerCase();

  if (_has(l, ['aadhaar', 'aadhar', 'uid'])) {
    return 'What is your 12-digit Aadhaar number?';
  }
  if (_has(l, ['pan', 'permanent account'])) {
    return 'What is your PAN card number?';
  }
  if (_has(l, ['father', 'pita'])) {
    return "What is your father's full name (as in government records)?";
  }
  if (_has(l, ['mother', 'mata'])) {
    return "What is your mother's full name?";
  }
  if (_has(l, ['name', 'naam'])) {
    return 'What is your full name (as on Aadhaar)?';
  }
  if (type == 'date' || _has(l, ['dob', 'birth', 'janm'])) {
    return 'What is your date of birth? (YYYY-MM-DD)';
  }
  if (_has(l, ['ifsc'])) {
    return 'What is your bank branch IFSC code? (11 characters, e.g. SBIN0001234)';
  }
  if (_has(l, ['account', 'khata', 'acc no'])) {
    return 'What is your bank account number?';
  }
  if (_has(l, ['bank name', 'bank'])) {
    return 'Which bank do you have your account in?';
  }
  if (_has(l, ['ifsc', 'micr'])) {
    return 'What is the MICR code on your cheque leaf? (9 digits)';
  }
  if (_has(l, ['survey', 'gat', 'khasra'])) {
    return 'What is your land survey / Gat number (from 7/12)?';
  }
  if (_has(l, ['land', 'area', 'hectare', 'acre'])) {
    return 'What is your total land area in the unit shown on this form?';
  }
  if (_has(l, ['crop', 'fasal', 'pik'])) {
    return 'What is the name of the primary crop you grow?';
  }
  if (_has(l, ['annual income', 'income', 'aay'])) {
    return 'What is your approximate annual household income in ₹?';
  }
  if (_has(l, ['pincode', 'pin code', 'postal'])) {
    return 'What is your 6-digit postal PIN code (from Aadhaar)?';
  }
  if (_has(l, ['taluka', 'tehsil', 'block'])) {
    return 'What is your taluka / tehsil name (from Form 7/12)?';
  }
  if (_has(l, ['village', 'gram', 'gaon'])) {
    return 'What is your village name (from land records)?';
  }
  if (_has(l, ['district', 'zila'])) {
    return 'What is your district name?';
  }
  if (_has(l, ['state'])) {
    return 'Which state do you live in?';
  }
  if (_has(l, ['address', 'pata'])) {
    return 'What is your full residential address (as on Aadhaar)?';
  }
  if (_has(l, ['mobile', 'phone', 'contact'])) {
    return 'What is your mobile number (10 digits)?';
  }
  if (_has(l, ['email', 'mail'])) {
    return 'What is your email address? (optional — skip if you don\'t have one)';
  }
  if (_has(l, ['captcha'])) {
    return 'What characters do you see in the CAPTCHA image on screen?';
  }
  if (_has(l, ['otp'])) {
    return 'What is the OTP sent to your registered mobile number?';
  }
  if (type == 'select') {
    return 'Please select the correct option for "$label":';
  }
  if (type == 'checkbox') {
    return 'Do you have / does this apply to you: "$label"?';
  }
  return 'Please tell me: $label';
}

// ─── Constraint hint strings ──────────────────────────────────────────────────

String? _constraintFor(String label, String type) {
  final l = label.toLowerCase();

  if (_has(l, ['aadhaar', 'aadhar', 'uid']))
    return 'Format: 12 digits (e.g. 1234 5678 9012)';
  if (_has(l, ['pan']))
    return 'Format: 5 letters + 4 digits + 1 letter (e.g. ABCDE1234F)';
  if (type == 'date' || _has(l, ['dob', 'birth']))
    return 'Format: YYYY-MM-DD or as shown on the form';
  if (_has(l, ['ifsc']))
    return '11-character code — found on the first page of your passbook';
  if (_has(l, ['account', 'acc no']))
    return 'No spaces. As printed in passbook';
  if (_has(l, ['pincode', 'pin'])) return '6-digit postal code';
  if (_has(l, ['mobile', 'phone'])) return '10-digit number without +91 or 0';
  if (_has(l, ['annual income', 'income']))
    return 'Enter a number in ₹. No commas.';
  if (_has(l, ['micr']))
    return '9-digit code at the bottom of your cheque leaf';
  if (_has(l, ['survey', 'gat', 'khasra']))
    return 'Shown on your Form 7/12 or land certificate';
  if (type == 'select') return 'Tap the option that applies to you';
  if (type == 'checkbox') return 'Tap Yes or No';
  return null;
}

// ─── Placeholder text ─────────────────────────────────────────────────────────

String _placeholderFor(String label, String type) {
  final l = label.toLowerCase();
  if (_has(l, ['aadhaar', 'aadhar'])) return '1234 5678 9012';
  if (_has(l, ['pan'])) return 'ABCDE1234F';
  if (type == 'date' || _has(l, ['dob', 'birth'])) return 'YYYY-MM-DD';
  if (_has(l, ['ifsc'])) return 'SBIN0001234';
  if (_has(l, ['mobile', 'phone'])) return '9876543210';
  if (_has(l, ['pincode', 'pin'])) return '411001';
  if (_has(l, ['income'])) return '150000';
  return 'Type your answer…';
}

bool _has(String text, List<String> keywords) =>
    keywords.any((k) => text.contains(k));
