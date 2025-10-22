import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:carpal_app/models/user_profile.dart';
import 'package:carpal_app/services/user_profile_cache.dart';
import 'package:carpal_app/utils/profile_navigation.dart';

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
  bool _isSyncingProfile = false;

  final Map<String, UserProfile> _userProfiles = <String, UserProfile>{};
  final Set<String> _pendingProfileRequests = <String>{};
  final Set<String> _backfilledSenderMessageIds = <String>{};

  static const int _maxMessageLength = 250;
  static const Duration _rateLimitDuration = Duration(seconds: 3);
  static const int _pageSize = 10;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _messages =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final Set<String> _animatedMessageIds = <String>{};

  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _initialLoadError;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _latestMessagesSubscription;
  DocumentSnapshot<Map<String, dynamic>>? _lastLoadedDocument;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialMessages();
  }

  static const List<String> _bannedWords = <String>[
    'badword',
    'offensive',
    'كلمةسيئة',
  ];

  @override
  void dispose() {
    _latestMessagesSubscription?.cancel();
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageFocusNode.dispose();
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

    final _SenderIdResolution senderResolution = _resolveSenderId(data);
    final String senderId = senderResolution.id;

    await FirebaseFirestore.instance.collection('reports').add({
      'messageId': messageId,
      'reportedAt': FieldValue.serverTimestamp(),
      'reporterId': user.uid,
      'reporterName': user.displayName,
      'senderId': senderId,
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
            child: _buildMessagesList(currentUser),
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

  Widget _buildMessagesList(User currentUser) {
    if (_isLoadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initialLoadError != null) {
      return Center(
        child: Text(
          _initialLoadError!,
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Text('ابدأ المحادثة الآن 👋'),
      );
    }

    return Stack(
      children: <Widget>[
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          itemCount: _messages.length,
          itemBuilder: (BuildContext context, int index) {
            final QueryDocumentSnapshot<Map<String, dynamic>> doc =
                _messages[index];
            final Map<String, dynamic> data = doc.data();
            final _SenderIdResolution senderResolution = _resolveSenderId(data);
            final String senderId = senderResolution.id;
            _ensureMessageHasSenderId(doc, data, senderResolution);
            final bool isCurrentUser = senderId == currentUser.uid;
            final UserProfile profile =
                _userProfiles[senderId] ?? _userProfileFromMessageData(senderId, data);
            final bool animate = _animatedMessageIds.remove(doc.id);

            return _MessageBubble(
              key: ValueKey<String>('msg-${doc.id}'),
              data: data,
              profile: profile,
              isCurrentUser: isCurrentUser,
              animate: animate,
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
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم إرسال البلاغ.'),
                    ),
                  );
                }
              },
              onProfileTap: () {
                if (senderId.isEmpty) {
                  return;
                }
                ProfileNavigation.pushProfile(
                  context: context,
                  userId: senderId,
                  initialProfile: profile,
                );
              },
            );
          },
        ),
        if (_isLoadingMore)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('... جاري تحميل رسائل أقدم'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) {
      return;
    }

    final double currentOffset = _scrollController.position.pixels;
    final double minOffset = _scrollController.position.minScrollExtent;
    if (currentOffset <= minOffset + 80) {
      _loadOlderMessages();
    }
  }

  bool get _isAtBottom {
    if (!_scrollController.hasClients) {
      return true;
    }
    final double maxOffset = _scrollController.position.maxScrollExtent;
    final double currentOffset = _scrollController.position.pixels;
    return (maxOffset - currentOffset) <= 80;
  }

  Future<void> _loadInitialMessages() async {
    _latestMessagesSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isLoadingInitial = true;
        _initialLoadError = null;
        _hasMore = true;
        _messages.clear();
        _animatedMessageIds.clear();
        _lastLoadedDocument = null;
      });
    }

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
          .instance
          .collection('global_chat')
          .orderBy('timestamp', descending: true)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(snapshot.docs.reversed);
        _messages.sort(_compareMessages);
        _lastLoadedDocument =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
        _isLoadingInitial = false;
        _initialLoadError = null;
      });

      _warmProfileCache(_messages);
      _listenForLatestMessages();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoadError = 'تعذّر تحميل الرسائل، حاول مرة أخرى لاحقًا.';
        _isLoadingInitial = false;
      });
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMore || _lastLoadedDocument == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
          .instance
          .collection('global_chat')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastLoadedDocument!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      final double previousMaxExtent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0;
      final double previousOffset = _scrollController.hasClients
          ? _scrollController.offset
          : 0;

      setState(() {
        _messages.insertAll(0, snapshot.docs.reversed);
        _messages.sort(_compareMessages);
        _lastLoadedDocument = snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
        _isLoadingMore = false;
      });

      _warmProfileCache(snapshot.docs);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        final double newMaxExtent = _scrollController.position.maxScrollExtent;
        final double diff = newMaxExtent - previousMaxExtent;
        final double targetOffset = previousOffset + diff;
        final double minExtent = _scrollController.position.minScrollExtent;
        final double maxExtent = _scrollController.position.maxScrollExtent;
        final double clampedOffset =
            targetOffset.clamp(minExtent, maxExtent).toDouble();
        _scrollController.jumpTo(clampedOffset);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر تحميل الرسائل الأقدم.'),
        ),
      );
    }
  }

  void _listenForLatestMessages() {
    _latestMessagesSubscription?.cancel();
    _latestMessagesSubscription = FirebaseFirestore.instance
        .collection('global_chat')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize)
        .snapshots()
        .listen(_handleLatestSnapshot);
  }

  void _handleLatestSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!mounted || snapshot.docs.isEmpty) {
      return;
    }

    final bool shouldAutoScroll = _isAtBottom;
    bool updated = false;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docsToWarm =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    setState(() {
      for (final DocumentChange<Map<String, dynamic>> change
          in snapshot.docChanges) {
        final DocumentSnapshot<Map<String, dynamic>> rawDoc = change.doc;
        if (rawDoc is! QueryDocumentSnapshot<Map<String, dynamic>>) {
          continue;
        }
        final QueryDocumentSnapshot<Map<String, dynamic>> doc = rawDoc;
        docsToWarm.add(doc);

        if (change.type == DocumentChangeType.added) {
          final bool exists =
              _messages.any((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                  d.id == doc.id);
          if (!exists) {
            _messages.add(doc);
            _animatedMessageIds.add(doc.id);
            updated = true;
          }
        } else if (change.type == DocumentChangeType.modified) {
          final int index = _messages.indexWhere(
              (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id == doc.id);
          if (index != -1) {
            _messages[index] = doc;
            updated = true;
          }
        } else if (change.type == DocumentChangeType.removed) {
          final int index = _messages.indexWhere(
              (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id == doc.id);
          if (index != -1) {
            _messages.removeAt(index);
            updated = true;
          }
        }
      }

      if (updated) {
        _messages.sort(_compareMessages);
      }
    });

    if (docsToWarm.isNotEmpty) {
      _warmProfileCache(docsToWarm);
    }

    if (updated && shouldAutoScroll) {
      _scrollToBottom();
    }
  }

  void _warmProfileCache(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, dynamic> data = doc.data();
      final _SenderIdResolution senderResolution = _resolveSenderId(data);
      final String senderId = senderResolution.id;
      _ensureMessageHasSenderId(doc, data, senderResolution);
      if (senderId.isEmpty) {
        continue;
      }
      if (_userProfiles.containsKey(senderId) ||
          _pendingProfileRequests.contains(senderId)) {
        continue;
      }
      _fetchUserProfile(senderId, data);
    }
  }

  _SenderIdResolution _resolveSenderId(Map<String, dynamic> data) {
    final String direct = _normalizeSenderValue(data['senderId']);
    if (direct.isNotEmpty) {
      data['senderId'] = direct;
      return _SenderIdResolution(direct, needsBackfill: false);
    }

    for (final String key in <String>['senderUid', 'userId', 'uid', 'sender_id']) {
      final String fallback = _normalizeSenderValue(data[key]);
      if (fallback.isNotEmpty) {
        data['senderId'] = fallback;
        return _SenderIdResolution(fallback, needsBackfill: true);
      }
    }

    return const _SenderIdResolution('', needsBackfill: false);
  }

  String _normalizeSenderValue(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value.trim();
    }
    if (value is DocumentReference<Object?>) {
      return value.id.trim();
    }
    return '';
  }

  void _ensureMessageHasSenderId(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
    _SenderIdResolution resolution,
  ) {
    if (!resolution.needsBackfill || resolution.id.isEmpty) {
      return;
    }

    final String current = (data['senderId'] as String?)?.trim() ?? '';
    if (current != resolution.id) {
      data['senderId'] = resolution.id;
    }

    if (_backfilledSenderMessageIds.contains(doc.id)) {
      return;
    }
    _backfilledSenderMessageIds.add(doc.id);
    unawaited(
      doc.reference
          .set(<String, dynamic>{'senderId': resolution.id}, SetOptions(merge: true))
          .catchError((_) {})
          .whenComplete(() {
        _backfilledSenderMessageIds.remove(doc.id);
      }),
    );
  }

  Future<void> _fetchUserProfile(
    String senderId,
    Map<String, dynamic> messageData,
  ) async {
    if (_pendingProfileRequests.contains(senderId)) {
      return;
    }

    final UserProfile? cachedProfile = UserProfileCache.get(senderId);
    final bool hasCacheEntry = UserProfileCache.hasEntry(senderId);
    if (cachedProfile != null || hasCacheEntry) {
      if (!mounted) return;
      setState(() {
        _userProfiles[senderId] = cachedProfile ??
            _userProfileFromMessageData(senderId, messageData);
      });
      return;
    }

    _pendingProfileRequests.add(senderId);
    try {
      final UserProfile? profile = await UserProfileCache.fetch(senderId);
      if (!mounted) return;
      setState(() {
        _userProfiles[senderId] = profile ??
            _userProfileFromMessageData(senderId, messageData);
      });
    } finally {
      _pendingProfileRequests.remove(senderId);
    }
  }

  int _compareMessages(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final Timestamp? aTimestamp = a.data()['timestamp'] as Timestamp?;
    final Timestamp? bTimestamp = b.data()['timestamp'] as Timestamp?;
    if (aTimestamp == null && bTimestamp == null) {
      return a.id.compareTo(b.id);
    }
    if (aTimestamp == null) {
      return -1;
    }
    if (bTimestamp == null) {
      return 1;
    }
    return aTimestamp.compareTo(bTimestamp);
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

class _SenderIdResolution {
  const _SenderIdResolution(this.id, {required this.needsBackfill});

  final String id;
  final bool needsBackfill;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.data,
    required this.profile,
    required this.isCurrentUser,
    this.onLongPress,
    this.onProfileTap,
    this.animate = false,
  });

  final Map<String, dynamic> data;
  final UserProfile profile;
  final bool isCurrentUser;
  final VoidCallback? onLongPress;
  final VoidCallback? onProfileTap;
  final bool animate;

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

    final Widget content = Padding(
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

    if (!animate) {
      return content;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: content,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
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
