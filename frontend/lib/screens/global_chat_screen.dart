import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:carpal_app/models/user_profile.dart';
import 'package:carpal_app/screens/profile_screen.dart';

class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  DateTime? _lastSentAt;
  String? _lastSentMessage;
  int _previousMessageCount = 0;
  bool _isSyncingProfile = false;

  final Map<String, UserProfile> _userProfiles = <String, UserProfile>{};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _profileSubscriptions =
      <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};

  static const int _maxMessageLength = 250;
  static const Duration _rateLimitDuration = Duration(seconds: 3);

  static const List<String> _bannedWords = <String>[
    'badword',
    'offensive',
    'كلمةسيئة',
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    for (final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub
        in _profileSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _ensureCurrentUserProfile(User user) async {
    if (_isSyncingProfile) return;
    _isSyncingProfile = true;
    try {
      final DocumentReference<Map<String, dynamic>> docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await docRef.get();
      final String sanitizedName =
          UserProfile.sanitizeDisplayName(user.displayName);
      final Map<String, dynamic> updates = <String, dynamic>{
        'displayName': sanitizedName,
      };
      final String? sanitizedEmail = UserProfile.sanitizeOptionalText(user.email);
      if (sanitizedEmail != null) {
        updates['email'] = sanitizedEmail;
      }

      if (!snapshot.exists) {
        await docRef.set(updates, SetOptions(merge: true));
      } else {
        await docRef.set(updates, SetOptions(merge: true));
      }
    } catch (_) {
      // Ignore errors during sync to avoid blocking chat usage.
    } finally {
      _isSyncingProfile = false;
    }
  }

  Future<void> _sendMessage() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String rawMessage = _messageController.text;

    if (user == null) {
      return;
    }

    final String trimmedMessage = rawMessage.trim();

    if (trimmedMessage.isEmpty) {
      _showError(context, 'الرسالة غير صالحة');
      return;
    }

    if (trimmedMessage.length > _maxMessageLength) {
      _showError(context, 'الرسالة طويلة للغاية');
      return;
    }

    final DateTime now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!) < _rateLimitDuration) {
      _showError(context, 'الرجاء الانتظار قبل إرسال رسالة جديدة');
      return;
    }

    if (_containsLinksOrEmails(trimmedMessage)) {
      _showError(context, 'الروابط والبريد الإلكتروني غير مسموح بها');
      return;
    }

    final String sanitized = _sanitizeMessage(trimmedMessage);

    if (sanitized.isEmpty) {
      _showError(context, 'الرسالة غير صالحة');
      return;
    }

    if (_lastSentMessage != null &&
        _normalizeMessage(sanitized) == _normalizeMessage(_lastSentMessage!)) {
      _showError(context, 'لا يمكن إرسال نفس الرسالة مرتين متتاليتين');
      return;
    }

    final String filteredMessage = _filterMessage(sanitized);

    try {
      await _ensureCurrentUserProfile(user);
      await FirebaseFirestore.instance.collection('global_chat').add({
        'senderName': UserProfile.sanitizeDisplayName(user.displayName),
        'senderId': user.uid,
        'message': filteredMessage,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _lastSentAt = now;
      _lastSentMessage = sanitized;
      _messageController.clear();
      _messageFocusNode.requestFocus();
      _scrollToBottom();
    } catch (e) {
      _showError(context, 'تعذّر إرسال الرسالة، حاول مرة أخرى');
    }
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

  bool _containsLinksOrEmails(String message) {
    final RegExp pattern = RegExp(
      r'(https?:\/\/\S+|\b[\w\.-]+@[\w\.-]+\.\w{2,}\b)',
      caseSensitive: false,
    );
    return pattern.hasMatch(message);
  }

  String _sanitizeMessage(String message) {
    String sanitized = message.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      '',
    );
    sanitized = sanitized.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    return sanitized;
  }

  String _normalizeMessage(String message) {
    return message
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
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

                  _preloadProfiles(docs);

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

                      final String senderId =
                          (data['senderId'] as String?)?.trim() ?? '';
                      final UserProfile profile = _userProfiles[senderId] ??
                          _userProfileFromMessageData(senderId, data);

                      return _MessageBubble(
                        data: data,
                        profile: profile,
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
                        onProfileTap: () {
                          if (senderId.isEmpty) {
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(
                                userId: senderId,
                                initialProfile: profile,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
          ),
          _MessageInput(
            controller: _messageController,
            focusNode: _messageFocusNode,
            onSend: _sendMessage,
            maxLength: _maxMessageLength,
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

  void _preloadProfiles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, dynamic>? data = doc.data();
      if (data == null) continue;
      final String senderId = (data['senderId'] as String?)?.trim() ?? '';
      if (senderId.isEmpty || _profileSubscriptions.containsKey(senderId)) {
        continue;
      }

      final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub =
          FirebaseFirestore.instance
              .collection('users')
              .doc(senderId)
              .snapshots()
              .listen((DocumentSnapshot<Map<String, dynamic>> snapshot) {
        final UserProfile profile =
            UserProfile.fromFirestoreSnapshot(snapshot);
        if (!mounted) return;
        setState(() {
          _userProfiles[senderId] = profile;
        });
      });

      _profileSubscriptions[senderId] = sub;
    }
  }

  UserProfile _userProfileFromMessageData(
    String senderId,
    Map<String, dynamic> data,
  ) {
    final String fallbackName =
        UserProfile.sanitizeDisplayName(data['senderName']);
    return UserProfile(
      id: senderId,
      displayName: fallbackName,
      email: null,
      phone: null,
      photoUrl: null,
      tripsCount: null,
      rating: null,
    );
  }

}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.data,
    required this.profile,
    required this.isCurrentUser,
    this.onLongPress,
    this.onProfileTap,
  });

  final Map<String, dynamic> data;
  final UserProfile profile;
  final bool isCurrentUser;
  final VoidCallback? onLongPress;
  final VoidCallback? onProfileTap;

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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          _Avatar(
            profile: profile,
            isCurrentUser: isCurrentUser,
            onTap: onProfileTap,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16).copyWith(
                    topLeft:
                        isCurrentUser ? const Radius.circular(16) : Radius.zero,
                    topRight:
                        isCurrentUser ? Radius.zero : const Radius.circular(16),
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
                      GestureDetector(
                        onTap: onProfileTap,
                        child: Text(
                          profile.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color:
                                textColor.withOpacity(isCurrentUser ? 0.9 : 0.8),
                          ),
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
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.profile,
    required this.isCurrentUser,
    this.onTap,
  });

  final UserProfile profile;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget avatarChild;
    if (profile.photoUrl != null) {
      avatarChild = CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(profile.photoUrl!),
      );
    } else {
      avatarChild = CircleAvatar(
        radius: 20,
        backgroundColor: isCurrentUser
            ? Colors.deepPurple.shade200
            : Colors.grey.shade400,
        child: Text(
          profile.initial,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: avatarChild,
    );
  }
}

class _MessageInput extends StatefulWidget {
  const _MessageInput({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.maxLength,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final int maxLength;

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  late int _currentLength;

  @override
  void initState() {
    super.initState();
    _currentLength = widget.controller.text.length;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    final String text = widget.controller.text;
    if (text.length > widget.maxLength) {
      widget.controller.text = text.substring(0, widget.maxLength);
      widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length),
      );
    }

    setState(() {
      _currentLength = widget.controller.text.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showCounter = _currentLength > 0;
    final bool atLimit = _currentLength >= widget.maxLength;

    return SafeArea(
      top: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => widget.onSend(),
                      minLines: 1,
                      maxLines: 4,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
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
                    onPressed: widget.onSend,
                    icon: const Icon(Icons.send),
                    color: Colors.deepPurple,
                  ),
                ],
              ),
              if (showCounter)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Text(
                    '${_currentLength}/${widget.maxLength}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: atLimit ? Colors.red.shade600 : Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
