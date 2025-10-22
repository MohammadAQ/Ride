import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _previousMessageCount = 0;

  static const List<String> _bannedWords = <String>[
    'badword',
    'offensive',
    'كلمةسيئة',
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String rawMessage = _messageController.text.trim();

    if (user == null || rawMessage.isEmpty) {
      return;
    }

    final String filteredMessage = _filterMessage(rawMessage);

    await FirebaseFirestore.instance.collection('global_chat').add({
      'senderName': user.displayName ?? 'مستخدم',
      'senderId': user.uid,
      'message': filteredMessage,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
    _scrollToBottom();
  }

  String _filterMessage(String message) {
    String filtered = message;
    for (final String word in _bannedWords) {
      if (word.isEmpty) continue;
      final RegExp pattern = RegExp(
        '\\b' + RegExp.escape(word) + '\\b',
        caseSensitive: false,
      );
      filtered = filtered.replaceAll(pattern, '***');
    }
    return filtered;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _reportMessage({
    required String messageId,
    required Map<String, dynamic> data,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('reports').add({
      'messageId': messageId,
      'reportedAt': FieldValue.serverTimestamp(),
      'reporterId': user.uid,
      'reporterName': user.displayName,
      'senderId': data['senderId'],
      'senderName': data['senderName'],
      'message': data['message'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      final Widget content = const Center(
        child: Text('الرجاء تسجيل الدخول للوصول إلى المحادثة العامة.'),
      );

      if (widget.showAppBar) {
        return Scaffold(body: content);
      }

      return content;
    }

    final Widget chatContent = SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('global_chat')
                    .orderBy('timestamp', descending: false)
                    .snapshots(),
                builder: (
                  BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
                ) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('حدث خطأ: ${snapshot.error}'),
                    );
                  }

                  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                      snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('ابدأ المحادثة الآن 👋'),
                    );
                  }

                  if (docs.length != _previousMessageCount) {
                    _previousMessageCount = docs.length;
                    _scrollToBottom();
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (BuildContext context, int index) {
                      final QueryDocumentSnapshot<Map<String, dynamic>> doc =
                          docs[index];
                      final Map<String, dynamic>? data = doc.data();
                      if (data == null) {
                        return const SizedBox.shrink();
                      }

                      return _MessageBubble(
                        data: data,
                        isCurrentUser: data['senderId'] == currentUser.uid,
                        onLongPress: () async {
                          final bool? shouldReport = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('إبلاغ عن الرسالة'),
                                content: const Text('هل تريد الإبلاغ عن هذه الرسالة؟'),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('إلغاء'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('إبلاغ'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (shouldReport == true) {
                            await _reportMessage(messageId: doc.id, data: data);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم إرسال البلاغ.'),
                                ),
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
          ),
          _MessageInput(
            controller: _messageController,
            onSend: _sendMessage,
          ),
        ],
      ),
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('المحادثة العامة 💬'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: chatContent,
      );
    }

    return chatContent;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.data,
    required this.isCurrentUser,
    this.onLongPress,
  });

  final Map<String, dynamic> data;
  final bool isCurrentUser;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final Timestamp? timestamp = data['timestamp'] as Timestamp?;
    final DateTime? time = timestamp?.toDate();
    final String formattedTime = time == null
        ? ''
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final Color backgroundColor = isCurrentUser
        ? Colors.deepPurple.shade400
        : Colors.grey.shade200;
    final Color textColor = isCurrentUser ? Colors.white : Colors.black87;

    final Alignment alignment =
        isCurrentUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16).copyWith(
              topLeft: isCurrentUser ? const Radius.circular(16) : Radius.zero,
              topRight: isCurrentUser ? Radius.zero : const Radius.circular(16),
            ),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data['senderName'] ?? 'مستخدم',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: textColor.withOpacity(isCurrentUser ? 0.9 : 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data['message'] ?? '',
                  style: TextStyle(color: textColor, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  const _MessageInput({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                minLines: 1,
                maxLines: 4,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالتك...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.send),
              color: Colors.deepPurple,
            ),
          ],
        ),
      ),
    );
  }
}
