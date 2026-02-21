import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/smart_form_mapper.dart';

// ─── Public API ───────────────────────────────────────────────────────────────

Future<Map<String, String>> showAutofillChatbotSheet({
  required BuildContext context,
  required List<FieldQuery> fieldsToAsk,
}) async {
  if (fieldsToAsk.isEmpty) return {};
  final result = await showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _AutofillChatbotSheet(fieldsToAsk: fieldsToAsk),
  );
  return result ?? {};
}

// ─── Message model ────────────────────────────────────────────────────────────

enum _MsgType { botGreeting, botQuestion, botDone, userReply, userSkip }

class _ChatMessage {
  final _MsgType type;
  final String text;

  /// For botQuestion messages: the field this question is about.
  final FieldQuery? field;

  /// For botQuestion with a hint: the index in fieldsToAsk for this question.
  /// Used to guard the confirm/edit buttons so only the CURRENT question
  /// responds to taps (prevents acting on past messages when scrolled up).
  final int? fieldIndex;

  const _ChatMessage({
    required this.type,
    required this.text,
    this.field,
    this.fieldIndex,
  });
}

// ─── Sheet widget ─────────────────────────────────────────────────────────────

class _AutofillChatbotSheet extends StatefulWidget {
  final List<FieldQuery> fieldsToAsk;
  const _AutofillChatbotSheet({required this.fieldsToAsk});

  @override
  State<_AutofillChatbotSheet> createState() => _AutofillChatbotSheetState();
}

class _AutofillChatbotSheetState extends State<_AutofillChatbotSheet> {
  final List<_ChatMessage> _messages = [];
  final Map<String, String> _answers = {};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  int _currentIndex = 0;
  bool _done = false;

  // When true, the text field is visible and the user is actively typing
  // a correction for an uncertain field (after tapping "Let me correct it").
  bool _editingHint = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startConversation());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─── Conversation flow ──────────────────────────────────────────────────

  void _startConversation() {
    final total = widget.fieldsToAsk.length;
    _addMsg(_ChatMessage(
      type: _MsgType.botGreeting,
      text: total == 1
          ? "Almost there! I just need to confirm one detail with you."
          : "Almost there! I need to confirm $total details with you.",
    ));
    Future.delayed(const Duration(milliseconds: 450), _askCurrentField);
  }

  void _askCurrentField() {
    if (!mounted) return;
    if (_currentIndex >= widget.fieldsToAsk.length) {
      _finish();
      return;
    }

    final field = widget.fieldsToAsk[_currentIndex];
    String question = _questionFor(field.label, field.type);

    if (field.isUncertain && field.hintValue != null) {
      question =
          '$question\n\n📄 I found **${field.hintValue}** in your documents — is this correct?';
    }

    setState(() {
      _editingHint = false;
      _ctrl.clear();
    });

    _addMsg(_ChatMessage(
      type: _MsgType.botQuestion,
      text: question,
      field: field,
      fieldIndex: _currentIndex,
    ));
  }

  /// Called when user confirms the pre-filled hint value ("Yes, correct").
  void _confirmHint(String value, int forFieldIndex) {
    if (forFieldIndex != _currentIndex) return; // stale button
    _submitAnswer(value);
  }

  /// Called when user taps "Let me correct it" — opens text input pre-filled.
  void _startEditHint(String hintValue, int forFieldIndex) {
    if (forFieldIndex != _currentIndex) return; // stale button
    setState(() {
      _editingHint = true;
      _ctrl.text = hintValue;
    });
    // Delay so the text field has time to render before requesting focus
    Future.delayed(
        const Duration(milliseconds: 120), () => _focus.requestFocus());
  }

  void _submitAnswer(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final field = widget.fieldsToAsk[_currentIndex];
    _answers[field.key] = trimmed;
    _addMsg(_ChatMessage(type: _MsgType.userReply, text: trimmed));
    _ctrl.clear();
    _currentIndex++;
    Future.delayed(const Duration(milliseconds: 350), _askCurrentField);
  }

  void _skipCurrent() {
    _addMsg(_ChatMessage(type: _MsgType.userSkip, text: 'Skipped'));
    _currentIndex++;
    Future.delayed(const Duration(milliseconds: 350), _askCurrentField);
  }

  void _finish() {
    setState(() => _done = true);
    _addMsg(const _ChatMessage(
      type: _MsgType.botDone,
      text: '✅ Got it! Filling your form now…',
    ));
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context, rootNavigator: true).pop(_answers);
    });
  }

  void _addMsg(_ChatMessage msg) {
    if (!mounted) return;
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  FieldQuery? get _currentField => _currentIndex < widget.fieldsToAsk.length
      ? widget.fieldsToAsk[_currentIndex]
      : null;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        height: screenH * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFFF0F4F0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildProgress(),
            Expanded(child: _buildChat()),
            if (!_done) _buildInputArea(),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: Color(0xFFE8EDE8))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.support_agent_rounded,
                    color: Color(0xFF2E7D32), size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AgriSarthi Assistant',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A))),
                  Text('Confirming your details',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B8F71))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Progress ──────────────────────────────────────────────────────────

  Widget _buildProgress() {
    final total = widget.fieldsToAsk.length;
    final answered = _answers.length;
    final progress = total == 0 ? 1.0 : _currentIndex / total;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _done ? 'All done!' : '$answered of $total answered',
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B8F71),
                    fontWeight: FontWeight.w500),
              ),
              Text('${(progress * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B8F71),
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: const Color(0xFFE8EDE8),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Chat list ─────────────────────────────────────────────────────────

  Widget _buildChat() {
    // Extra slot for chips when current field is select/checkbox
    final showChips = !_done &&
        _currentField != null &&
        (_currentField!.type == 'select' ||
            _currentField!.type == 'checkbox') &&
        !_editingHint;

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      itemCount: _messages.length + (showChips ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _messages.length) return _buildChips(_currentField!);
        return _buildBubble(_messages[i]);
      },
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    switch (msg.type) {
      case _MsgType.botGreeting:
      case _MsgType.botDone:
        return _BotBubble(text: msg.text);

      case _MsgType.botQuestion:
        final field = msg.field!;
        final isActive = msg.fieldIndex == _currentIndex;
        final hasHint = field.isUncertain && field.hintValue != null;

        return _BotBubble(
          text: msg.text,
          action: hasHint && isActive
              ? _HintButtons(
                  hintValue: field.hintValue!,
                  onConfirm: () =>
                      _confirmHint(field.hintValue!, msg.fieldIndex!),
                  onEdit: () =>
                      _startEditHint(field.hintValue!, msg.fieldIndex!),
                )
              : null,
        );

      case _MsgType.userReply:
        return _UserBubble(text: msg.text, isSkip: false);

      case _MsgType.userSkip:
        return _UserBubble(text: 'Skipped', isSkip: true);
    }
  }

  Widget _buildChips(FieldQuery field) {
    final opts = field.type == 'checkbox'
        ? [
            {'value': 'yes', 'text': '✅  Yes'},
            {'value': 'no', 'text': '❌  No'},
          ]
        : (field.options ?? []);

    if (opts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 44, bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: opts.map((opt) {
          final val = opt['value']!;
          final txt = opt['text'] ?? val;
          return ActionChip(
            label: Text(txt,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1B5E20))),
            backgroundColor: const Color(0xFFE8F5E9),
            side: const BorderSide(color: Color(0xFF4CAF50)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onPressed: () => _submitAnswer(val),
          );
        }).toList(),
      ),
    );
  }

  // ─── Input area ────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    final field = _currentField;
    if (field == null) return const SizedBox.shrink();

    // Chip-only fields: no text input unless user tapped "Edit this"
    final chipOnly =
        (field.type == 'select' || field.type == 'checkbox') && !_editingHint;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EDE8))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Editing correction banner
          if (_editingHint)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded,
                      size: 15, color: Color(0xFF6B8F71)),
                  const SizedBox(width: 6),
                  Text(
                    'Type the correct value below',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

          if (!chipOnly) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: _keyboardType(field.type),
                    inputFormatters: _inputFormatters(field.type),
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    style:
                        const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
                    decoration: InputDecoration(
                      hintText: _placeholder(field.label, field.type),
                      hintStyle: const TextStyle(
                          color: Color(0xFFBDBDBD), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF4F7F4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                            color: Color(0xFF4CAF50), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                    onSubmitted: _submitAnswer,
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(onTap: () => _submitAnswer(_ctrl.text)),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Skip / field label row
          Row(
            children: [
              Text(
                field.label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic),
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              TextButton(
                onPressed: _skipCurrent,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Skip',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  TextInputType _keyboardType(String type) => switch (type) {
        'number' => TextInputType.number,
        'tel' => TextInputType.phone,
        'email' => TextInputType.emailAddress,
        'date' => TextInputType.datetime,
        _ => TextInputType.text,
      };

  List<TextInputFormatter> _inputFormatters(String type) => switch (type) {
        'number' => [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        'tel' => [FilteringTextInputFormatter.digitsOnly],
        _ => <TextInputFormatter>[],
      };

  String _placeholder(String label, String type) {
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
}

// ─── Hint action buttons ──────────────────────────────────────────────────────

class _HintButtons extends StatelessWidget {
  final String hintValue;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;

  const _HintButtons({
    required this.hintValue,
    required this.onConfirm,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ActionBtn(
            label: '✅  Yes, correct',
            color: const Color(0xFF4CAF50),
            onTap: onConfirm,
          ),
          _ActionBtn(
            label: '✏️  Let me correct it',
            color: const Color(0xFF757575),
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ─── Bubble widgets ───────────────────────────────────────────────────────────

class _BotBubble extends StatelessWidget {
  final String text;
  final Widget? action; // optional hint buttons or null
  const _BotBubble({required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: Color(0xFF2E7D32), size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _parseText(text),
                ),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _parseText(String text) {
    // Render **bold** and newlines without external packages
    final spans = <InlineSpan>[];
    for (var pi = 0; pi < text.split('\n').length; pi++) {
      if (pi > 0) spans.add(const TextSpan(text: '\n'));
      final line = text.split('\n')[pi];
      final parts = line.split(RegExp(r'\*\*'));
      for (var bi = 0; bi < parts.length; bi++) {
        spans.add(TextSpan(
          text: parts[bi],
          style: bi.isOdd
              ? const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                  fontSize: 14)
              : const TextStyle(
                  color: Color(0xFF1A1A1A), fontSize: 14, height: 1.55),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  final bool isSkip;
  const _UserBubble({required this.text, required this.isSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 52),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSkip ? Colors.grey.shade200 : const Color(0xFF2E7D32),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: isSkip
                    ? []
                    : [
                        BoxShadow(
                          color:
                              const Color(0xFF2E7D32).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isSkip ? Colors.grey.shade500 : Colors.white,
                  fontSize: 14,
                  height: 1.4,
                  fontStyle: isSkip ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          color: Color(0xFF4CAF50),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── NLP question generator ───────────────────────────────────────────────────

String _questionFor(String label, String type) {
  final l = label.toLowerCase();

  if (_has(l, ['aadhaar', 'aadhar', 'uid', 'unique id'])) {
    return 'What is your 12-digit Aadhaar number?';
  }
  if (_has(l, ['pan', 'permanent account'])) {
    return 'What is your PAN card number? (10 characters, e.g. ABCDE1234F)';
  }
  if (_has(l, ['father', 'pita', "father's name"])) {
    return "What is your father's full name (as in government records)?";
  }
  if (_has(l, ['mother', 'mata', "mother's name"])) {
    return "What is your mother's full name?";
  }
  if (_has(l, ['spouse', 'husband', 'wife', 'pati', 'patni'])) {
    return "What is your spouse's full name?";
  }
  if (_has(l, ['name', 'naam', 'full name', 'applicant'])) {
    return 'What is your full name (exactly as printed on your Aadhaar)?';
  }
  if (type == 'date' || _has(l, ['dob', 'birth', 'janm', 'date of birth'])) {
    return 'What is your date of birth? (DD/MM/YYYY format)';
  }
  if (_has(l, ['gender', 'sex', 'ling'])) {
    return 'What is your gender? (Male / Female / Other)';
  }
  if (_has(l, ['ifsc', 'ifc'])) {
    return 'What is your bank branch IFSC code? (11 chars — found on cheque leaf or passbook front page)';
  }
  if (_has(l, ['account no', 'account number', 'acc no', 'khata no', 'a/c'])) {
    return 'What is your bank account number? (9–18 digits, found on passbook)';
  }
  if (_has(l, ['micr'])) {
    return 'What is the MICR code? (9-digit number printed at the bottom of your cheque leaf)';
  }
  if (_has(l, ['bank name', 'bank'])) {
    return 'What is the name of your bank? (e.g. State Bank of India)';
  }
  if (_has(l, ['branch'])) {
    return 'What is the name of your bank branch?';
  }
  if (_has(l, ['survey', 'gat no', 'khasra', 'gut no', 'plot'])) {
    return 'What is your Survey / Gat number? (from your 7/12 extract)';
  }
  if (_has(l, ['land area', 'area', 'hectare', 'acre', 'bigha', 'extent'])) {
    return 'What is your total land area? (in the unit the form shows)';
  }
  if (_has(l, ['crop', 'fasal', 'pik', 'kharif', 'rabi'])) {
    return 'What is the primary crop you grow on your land?';
  }
  if (_has(l, ['annual income', 'yearly income', 'income', 'aay'])) {
    return 'What is your approximate annual household income? (in ₹)';
  }
  if (_has(l, ['pincode', 'pin code', 'postal code', 'zip'])) {
    return 'What is your 6-digit PIN code? (from your Aadhaar card)';
  }
  if (_has(l, ['taluka', 'tehsil', 'block', 'taluk'])) {
    return 'What is your Taluka / Tehsil name? (from your Aadhaar or 7/12 extract)';
  }
  if (_has(l, ['village', 'gram', 'gaon', 'vill'])) {
    return 'What is your village name? (from your Aadhaar or 7/12 extract)';
  }
  if (_has(l, ['district', 'zila', 'jillha'])) {
    return 'What is your district name?';
  }
  if (_has(l, ['state', 'rajya'])) {
    return 'Which state do you live in?';
  }
  if (_has(l, ['address', 'pata', 'residence', 'flat', 'house'])) {
    return 'What is your full residential address? (as printed on your Aadhaar)';
  }
  if (_has(l, ['mobile', 'phone', 'contact', 'cell'])) {
    return 'What is your 10-digit mobile number?';
  }
  if (_has(l, ['email', 'mail', 'e-mail'])) {
    return "What is your email address? (tap Skip if you don't have one)";
  }
  if (_has(l, ['captcha'])) {
    return 'What characters do you see in the CAPTCHA image on screen?';
  }
  if (_has(l, ['otp'])) {
    return 'What is the OTP sent to your registered mobile number?';
  }
  if (_has(l, ['category', 'caste', 'jati'])) {
    return 'What is your caste/category? (e.g. General, OBC, SC, ST)';
  }
  if (_has(l, ['religion', 'dharm'])) {
    return 'What is your religion?';
  }
  if (type == 'select') {
    return 'Please select the correct option for "$label" from the choices below:';
  }
  if (type == 'checkbox') {
    return 'Does this apply to you: "$label"?  (Yes / No)';
  }
  return 'Please provide your $label:';
}

bool _has(String text, List<String> keywords) =>
    keywords.any((k) => text.contains(k));
