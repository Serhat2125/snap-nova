import 'package:flutter/material.dart';
import '../main.dart' show localeService;
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ChatScreen — AI ile Sohbet
// ═══════════════════════════════════════════════════════════════════════════════

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  bool _isSending = false;

  late final List<_Message> _messages = [
    _Message(
      text: localeService.tr('chat_welcome'),
      isAI: true,
    ),
  ];

  late final List<String> _suggestions = [
    localeService.tr('chat_example_1'),
    localeService.tr('chat_example_2'),
    localeService.tr('chat_example_3'),
    localeService.tr('chat_example_4'),
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_Message(text: text, isAI: false));
      _isSending = true;
    });
    _textCtrl.clear();
    _scrollToBottom();

    // Simüle edilmiş AI yanıtı
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message(
          text: _aiReply(text),
          isAI: true,
        ));
        _isSending = false;
      });
      _scrollToBottom();
    });
  }

  String _aiReply(String q) {
    if (q.toLowerCase().contains('türev')) {
      return localeService.tr('chat_deriv_response');
    }
    if (q.toLowerCase().contains('integral')) {
      return localeService.tr('chat_integral_response');
    }
    if (q.toLowerCase().contains('newton')) {
      return localeService.tr('chat_newton_response');
    }
    return localeService.tr('chat_default_response');
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // ── Başlık ──────────────────────────────────────────────────────
            _buildHeader(),

            // ── Mesaj listesi ───────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: _messages.length + (_isSending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) return _TypingIndicator();
                  return _MessageBubble(msg: _messages[i]);
                },
              ),
            ),

            // ── Hızlı öneri chip'leri ───────────────────────────────────────
            if (_messages.length == 1 && !_isSending)
              _buildSuggestions(),

            // ── Girdi alanı ─────────────────────────────────────────────────
            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.cyan.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
            onPressed: () => Navigator.pop(context),
          ),
          // AI avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 10)
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SnapNova AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(localeService.tr('online'),
                      style: TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 10,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localeService.tr('example_questions'),
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _suggestions
                .map((s) => GestureDetector(
                      onTap: () {
                        _textCtrl.text = s;
                        _send();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
                        ),
                        child: Text(s,
                            style: const TextStyle(
                                color: AppColors.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
              color: AppColors.cyan.withValues(alpha: 0.14), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.22)),
              ),
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: localeService.tr('type_question'),
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF0070FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.35),
                      blurRadius: 10)
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.black87, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mesaj balonu ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _Message msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: msg.isAI
              ? null
              : const LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF0070FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: msg.isAI ? AppColors.surface : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isAI ? 4 : 18),
            bottomRight: Radius.circular(msg.isAI ? 18 : 4),
          ),
          border: msg.isAI
              ? Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.18))
              : null,
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isAI ? Colors.white : Colors.black87,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─── Yazıyor göstergesi ───────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.18)),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: ((_ctrl.value + i * 0.3) % 1.0)
                      .clamp(0.2, 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.cyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Mesaj modeli ─────────────────────────────────────────────────────────────

class _Message {
  final String text;
  final bool isAI;
  const _Message({required this.text, required this.isAI});
}
