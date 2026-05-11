import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'app_responsive.dart';

/// In-app chat for one job application (salon owner ↔ seeker). Uses REST history + WebSocket `/ws/chat`.
class ApplicationChatScreen extends StatefulWidget {
  final String applicationId;
  final String languageCode;
  final String title;
  final bool isSalonOwner;

  const ApplicationChatScreen({
    super.key,
    required this.applicationId,
    required this.languageCode,
    required this.title,
    required this.isSalonOwner,
  });

  @override
  State<ApplicationChatScreen> createState() => _ApplicationChatScreenState();
}

class _ApplicationChatScreenState extends State<ApplicationChatScreen> {
  bool get _hi => widget.languageCode == 'hi';
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  bool _loading = true;
  String? _error;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;

  String _t(String en, String hi) => _hi ? hi : en;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hist = await _api.getChatMessages(widget.applicationId);
    if (!mounted) return;
    if (!hist.success || hist.data == null) {
      setState(() {
        _loading = false;
        _error = hist.message ?? _t('Could not load messages', 'मैसेज लोड नहीं हो सके');
      });
      return;
    }
    setState(() {
      _messages.clear();
      _messages.addAll(hist.data!);
      _loading = false;
    });
    _scrollToEnd();
    await _connectSocket();
  }

  Future<void> _connectSocket() async {
    final token = await _auth.getAccessToken();
    if (token == null || !mounted) return;
    try {
      final uri = ApiConfig.webSocketChatUri(token);
      final ch = WebSocketChannel.connect(uri);
      _channel = ch;
      _sub = ch.stream.listen(
        _onSocketData,
        onError: (_) {},
        onDone: () {},
      );
      // Wait for server { type: ready } then join room
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Chat connection failed', 'चैट कनेक्शन असफल'))),
        );
      }
    }
  }

  void _onSocketData(dynamic data) {
    Map<String, dynamic>? msg;
    try {
      msg = json.decode(data as String) as Map<String, dynamic>?;
    } catch (_) {
      return;
    }
    if (msg == null) return;
    final type = msg['type'] as String?;
    if (type == 'ready') {
      _channel?.sink.add(json.encode({
        'type': 'join',
        'applicationId': widget.applicationId,
      }));
      return;
    }
    if (type == 'joined') {
      return;
    }
    if (type == 'error') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg['message']?.toString() ?? 'Error')),
        );
      }
      return;
    }
    if (type == 'message' && msg['message'] is Map) {
      final m = Map<String, dynamic>.from(msg['message'] as Map);
      if (!mounted) return;
      final id = m['id']?.toString();
      if (id != null && _messages.any((x) => x['id']?.toString() == id)) return;
      setState(() => _messages.add(m));
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final payload = json.encode({
      'type': 'message',
      'applicationId': widget.applicationId,
      'body': text,
    });
    if (_channel != null) {
      try {
        _channel!.sink.add(payload);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t('Send failed — check connection', 'भेजने में त्रुटि'))),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Not connected', 'कनेक्ट नहीं है'))),
        );
      }
    }
  }

  bool _isMine(Map<String, dynamic> m) {
    final role = m['senderRole'] as String?;
    if (widget.isSalonOwner) return role == 'owner';
    return role == 'seeker';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF121A2C),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF121A2C)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ResponsiveContent(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final m = _messages[i];
                            final mine = _isMine(m);
                            final body = m['body']?.toString() ?? '';
                            final maxBubble = MediaQuery.sizeOf(context).width * 0.78;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(maxWidth: maxBubble.clamp(120, 520)),
                                decoration: BoxDecoration(
                                  color: mine ? const Color(0xFF3D3D7B) : Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(14),
                                    topRight: const Radius.circular(14),
                                    bottomLeft: Radius.circular(mine ? 14 : 4),
                                    bottomRight: Radius.circular(mine ? 4 : 14),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  body,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.35,
                                    color: mine ? Colors.white : const Color(0xFF121A2C),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
          Material(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _t('Type a message…', 'मैसेज लिखें…'),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _send,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF3D3D7B),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
