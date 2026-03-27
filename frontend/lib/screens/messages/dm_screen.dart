import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/socket_service.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';

class DmScreen extends StatefulWidget {
  final String  recipientId;
  final String  recipientName;
  final String? recipientAvatar;

  const DmScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.recipientAvatar,
  });

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final _ctrl    = TextEditingController();
  final _scroll  = ScrollController();
  StreamSubscription? _dmSub, _typingSub;
  bool  _loading = true, _sending = false, _peerTyping = false;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _dmSub = SocketService.dmStream.listen(_onDm);
    _typingSub = SocketService.typingStream.listen(_onTyping);
  }

  @override
  void dispose() {
    _dmSub?.cancel(); _typingSub?.cancel(); _typingTimer?.cancel();
    _ctrl.dispose(); _scroll.dispose();
    SocketService.sendTyping(recipientId: widget.recipientId, isTyping: false);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiService.get('/messages/dm/${widget.recipientId}');
      final msgs = (res['messages'] as List?) ?? [];
      if (!mounted) return;
      setState(() { _messages.addAll(msgs.cast<Map<String, dynamic>>()); _loading = false; });
      _scrollToBottom();
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _onDm(Map<String, dynamic> data) {
    if (!mounted) return;
    final fromId = data['message']?['senderId']?['_id']?.toString()
                ?? data['from']?['id']?.toString() ?? '';
    if (fromId == widget.recipientId) {
      setState(() => _messages.add(data['message'] ?? data));
      _scrollToBottom();
    }
  }

  void _onTyping(Map<String, dynamic> data) {
    if (!mounted) return;
    if (data['userId']?.toString() == widget.recipientId) {
      setState(() => _peerTyping = data['isTyping'] == true);
      _typingTimer?.cancel();
      if (_peerTyping) _typingTimer = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => _peerTyping = false); });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    SocketService.sendTyping(recipientId: widget.recipientId, isTyping: false);
    setState(() => _sending = true);
    try {
      final res = await ApiService.post('/messages/dm', {'recipientId': widget.recipientId, 'content': text});
      if (!mounted) return;
      setState(() => _messages.add(res));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.errorRed));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.recipientName),
          if (_peerTyping) const Text('typing…', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      body: Column(children: [
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                controller: _scroll, padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m   = _messages[i];
                  final sid = m['senderId'] is Map ? (m['senderId']['_id'] ?? '').toString() : m['senderId']?.toString() ?? '';
                  return _Bubble(message: m, isMe: sid == widget.recipientId ? false : true);
                })),
        _InputBar(ctrl: _ctrl, sending: _sending, onSend: _send,
            onChanged: (v) => SocketService.sendTyping(recipientId: widget.recipientId, isTyping: v.isNotEmpty)),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  const _Bubble({required this.message, required this.isMe});
  @override
  Widget build(BuildContext context) => Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primaryBlue : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message['content']?.toString() ?? '', style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
    ),
  );
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  const _InputBar({required this.ctrl, required this.sending, required this.onSend, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
    child: Row(children: [
      Expanded(child: TextField(controller: ctrl, onChanged: onChanged,
          decoration: InputDecoration(hintText: 'Message…', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
      const SizedBox(width: 8),
      CircleAvatar(
        backgroundColor: AppColors.primaryBlue,
        child: IconButton(
          icon: sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send, color: Colors.white),
          onPressed: sending ? null : onSend,
        ),
      ),
    ]),
  );
}




