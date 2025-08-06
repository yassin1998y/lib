import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/message.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:path/path.dart' as path;
import 'profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUsername;
  const ChatScreen({super.key, required this.chatId, required this.otherUsername});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Timer? _typingTimer;
  bool _isUploading = false;
  final ScrollController _scrollController = ScrollController();
  late final FirestoreService _firestoreService;

  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<Message> _messages = [];
  StreamSubscription? _messageSubscription;
  String? _firstUnreadMessageId;
  bool _isInitialLoad = true;

  String? _replyingToMessageId;
  String? _replyingToMessageText;
  String? _replyingToSender;
  String? _replyingToImageUrl;

  @override
  void initState() {
    super.initState();
    _firestoreService = context.read<FirestoreService>();
    _firestoreService.resetUnreadCount(widget.chatId, FirebaseAuth.instance.currentUser!.uid);
    _messageController.addListener(_onTyping);
    _listenForMessages();
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    _typingTimer?.cancel();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _updateTypingStatus(false);
    super.dispose();
  }

  void _listenForMessages() {
    final currentUser = FirebaseAuth.instance.currentUser!;
    _messageSubscription = _firestoreService.getMessagesStream(widget.chatId).listen((snapshot) {
      if (_isInitialLoad && snapshot.docs.isNotEmpty) {
        final initialMessages = snapshot.docs.map((doc) => Message.fromDoc(doc)).toList();
        // **FIX:** Initial load is sorted oldest to newest.
        initialMessages.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
        _messages.addAll(initialMessages);
        _isInitialLoad = false;
      }

      for (final change in snapshot.docChanges) {
        final message = Message.fromDoc(change.doc);
        switch (change.type) {
          case DocumentChangeType.added:
            if (_messages.every((m) => m.id != message.id)) {
              final optimisticIndex = _messages.indexWhere((m) =>
              m.status == MessageStatus.sending &&
                  m.text == message.text &&
                  m.senderId == message.senderId);
              if (optimisticIndex != -1) {
                setState(() => _messages[optimisticIndex] = message);
              } else {
                _addMessageToList(message);
              }
            }
            break;
          case DocumentChangeType.modified:
            _updateMessageInList(message);
            break;
          case DocumentChangeType.removed:
            _removeMessageFromList(message);
            break;
        }
      }

      final serverMessages = snapshot.docs.map((doc) => Message.fromDoc(doc)).toList();
      final firstUnread = serverMessages
          .where((m) => m.senderId != currentUser.uid && m.status != MessageStatus.seen)
          .toList()
        ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));

      if (firstUnread.isNotEmpty && _firstUnreadMessageId == null) {
        setState(() {
          _firstUnreadMessageId = firstUnread.first.id;
        });
      }

      _markMessagesAsSeen(snapshot.docs);
    });
  }

  void _addMessageToList(Message message) {
    // **FIX:** Add to the end of the list (chronological order).
    final index = _messages.length;
    _messages.add(message);
    if (_listKey.currentState != null) {
      _listKey.currentState!.insertItem(index, duration: const Duration(milliseconds: 300));
    }
  }

  void _updateMessageInList(Message updatedMessage) {
    final index = _messages.indexWhere((m) => m.id == updatedMessage.id);
    if (index != -1) {
      setState(() => _messages[index] = updatedMessage);
    }
  }

  void _removeMessageFromList(Message messageToRemove) {
    final index = _messages.indexWhere((m) => m.id == messageToRemove.id);
    if (index != -1) {
      final removedItem = _messages.removeAt(index);
      if (_listKey.currentState != null) {
        _listKey.currentState!.removeItem(
          index,
              (context, animation) => SizeTransition(
            sizeFactor: animation,
            child: MessageBubble(message: removedItem, isMe: false, onLongPress: () {}),
          ),
          duration: const Duration(milliseconds: 300),
        );
      }
    }
  }

  void _markMessagesAsSeen(List<QueryDocumentSnapshot> docs) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final unreadMessageIds = docs
        .where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['senderId'] != currentUser.uid && (data['isSeen'] == null || data['isSeen'] == false);
    })
        .map((doc) => doc.id)
        .toList();
    if (unreadMessageIds.isNotEmpty) {
      _firestoreService.markMultipleMessagesAsSeen(widget.chatId, unreadMessageIds);
    }
  }

  void _onTyping() {
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _updateTypingStatus(true);
    _typingTimer = Timer(const Duration(milliseconds: 1500), () => _updateTypingStatus(false));
  }

  Future<void> _updateTypingStatus(bool isTyping) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await _firestoreService.updateTypingStatus(widget.chatId, currentUser.uid, isTyping);
    }
  }

  Future<void> _sendMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final messageText = _messageController.text.trim();
    if (messageText.isNotEmpty) {
      _typingTimer?.cancel();
      _updateTypingStatus(false);
      final optimisticMessage = Message.optimistic(
        senderId: currentUser.uid,
        text: messageText,
        replyToMessageId: _replyingToMessageId,
        replyToMessageText: _replyingToMessageText,
        replyToImageUrl: _replyingToImageUrl,
        replyToSender: _replyingToSender,
      );
      _addMessageToList(optimisticMessage);
      _messageController.clear();
      _cancelReply();
      try {
        await _firestoreService.sendMessage(
          chatId: widget.chatId,
          senderId: currentUser.uid,
          text: messageText,
          replyToMessageId: optimisticMessage.replyToMessageId,
          replyToMessageText: optimisticMessage.replyToMessageText,
          replyToImageUrl: optimisticMessage.replyToImageUrl,
          replyToSender: optimisticMessage.replyToSender,
        );
      } catch (e) {
        debugPrint("Error sending message: $e");
      }
    }
  }

  Future<String?> _uploadToCloudinary(File file, {String resourceType = 'image'}) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/$resourceType/upload');
    final request = http.MultipartRequest('POST', url)..fields['upload_preset'] = 'Prototype';
    final multipartFile = http.MultipartFile.fromBytes('file', await file.readAsBytes(), filename: path.basename(file.path));
    request.files.add(multipartFile);
    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      return jsonDecode(responseString)['secure_url'];
    }
    return null;
  }

  Future<void> _sendImage() async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => Navigator.of(context).pop(ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.of(context).pop(ImageSource.gallery)),
          ]),
        ));
    if (source == null) return;
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;
    setState(() => _isUploading = true);
    try {
      final imageUrl = await _uploadToCloudinary(File(pickedFile.path));
      if (imageUrl == null) throw Exception('Image upload failed');
      final currentUser = FirebaseAuth.instance.currentUser!;
      await _firestoreService.sendMessage(
          chatId: widget.chatId, senderId: currentUser.uid, imageUrl: imageUrl, replyToMessageId: _replyingToMessageId, replyToMessageText: _replyingToMessageText, replyToImageUrl: _replyingToImageUrl, replyToSender: _replyingToSender);
      _cancelReply();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _startReply(Message message) {
    setState(() {
      _replyingToMessageId = message.id;
      _replyingToMessageText = message.text;
      _replyingToImageUrl = message.imageUrl;
      _replyingToSender = message.senderId == FirebaseAuth.instance.currentUser!.uid ? 'You' : widget.otherUsername;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessageId = null;
      _replyingToMessageText = null;
      _replyingToSender = null;
      _replyingToImageUrl = null;
    });
  }

  void _showMessageActions(BuildContext context, Message message, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                return IconButton(
                  icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _firestoreService.toggleMessageReaction(widget.chatId, message.id, FirebaseAuth.instance.currentUser!.uid, emoji);
                  },
                );
              }).toList()),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () {
              Navigator.of(context).pop();
              _startReply(message);
            }),
            if (isMe && message.imageUrl == null)
              ListTile(leading: const Icon(Icons.edit), title: const Text('Edit'), onTap: () {
                Navigator.of(context).pop();
                _editMessage(message.id, message.text ?? '');
              }),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(context).pop();
                  _firestoreService.deleteMessage(widget.chatId, message.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _editMessage(String messageId, String currentText) {
    final editController = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(controller: editController, decoration: const InputDecoration(hintText: 'Enter new message')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                if (editController.text.trim().isNotEmpty) {
                  _firestoreService.editMessage(widget.chatId, messageId, editController.text.trim());
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(String otherUserId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestoreService.getChatStream(widget.chatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final chatData = snapshot.data!.data() as Map<String, dynamic>;
        final typingStatus = chatData['typingStatus'] as Map<String, dynamic>? ?? {};
        if (typingStatus[otherUserId] == true) {
          return Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
            child: Row(children: [Text('${widget.otherUsername} is typing...', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic))]),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestoreService.getChatStream(widget.chatId),
      builder: (context, chatSnapshot) {
        if (!chatSnapshot.hasData) {
          return Scaffold(appBar: AppBar(title: Text(widget.otherUsername)));
        }
        final chatData = chatSnapshot.data!.data() as Map<String, dynamic>;
        final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUser.uid);
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestoreService.getUserStream(otherUserId),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final isOnline = userData?['presence'] ?? false;
            final lastSeenTimestamp = userData?['lastSeen'] as Timestamp?;
            final photoUrl = userData?['photoUrl'];
            String statusText = 'Offline';
            if (isOnline) {
              statusText = 'Online';
            } else if (lastSeenTimestamp != null) {
              statusText = 'last seen ${timeago.format(lastSeenTimestamp.toDate())}';
            }
            return Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                backgroundColor: Colors.white,
                elevation: 1,
                title: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: otherUserId))),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 18, backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null, child: (photoUrl == null || photoUrl.isEmpty) ? Text(widget.otherUsername.isNotEmpty ? widget.otherUsername[0].toUpperCase() : '?') : null),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.otherUsername, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(statusText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
              ),
              body: Column(
                children: [
                  if (_isUploading) const LinearProgressIndicator(),
                  Expanded(
                    child: AnimatedList(
                      key: _listKey,
                      reverse: true, // This is the fix you requested
                      padding: const EdgeInsets.all(8.0),
                      initialItemCount: _messages.length,
                      itemBuilder: (context, index, animation) {
                        // Because the list is reversed, we access messages from the end.
                        final reversedIndex = _messages.length - 1 - index;
                        final message = _messages[reversedIndex];
                        final previousMessage = reversedIndex > 0 ? _messages[reversedIndex - 1] : null;

                        final messageDate = message.timestamp?.toDate();
                        final previousMessageDate = previousMessage?.timestamp?.toDate();

                        final bool showDateSeparator = messageDate != null &&
                            (previousMessageDate == null ||
                                messageDate.day != previousMessageDate.day ||
                                messageDate.month != previousMessageDate.month ||
                                messageDate.year != previousMessageDate.year);

                        final bool showUnreadSeparator = message.id == _firstUnreadMessageId;

                        return SizeTransition(
                          sizeFactor: animation,
                          child: Column(
                            children: [
                              if (showDateSeparator) DateSeparator(date: messageDate),
                              if (showUnreadSeparator) const UnreadSeparator(),
                              MessageBubble(
                                key: ValueKey(message.id),
                                message: message,
                                isMe: message.senderId == currentUser.uid,
                                onLongPress: () => _showMessageActions(context, message, message.senderId == currentUser.uid),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  _buildTypingIndicator(otherUserId),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.photo_camera, color: Color(0xFF3498DB)), onPressed: _isUploading ? null : _sendImage),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20.0), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.send, color: Color(0xFF3498DB)), onPressed: _isUploading ? null : _sendMessage),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    Widget messageContent;
    if (message.imageUrl != null) {
      messageContent = GestureDetector(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FullScreenImageScreen(imageUrl: message.imageUrl!),
          ));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: Image.network(
            message.imageUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null ? child : Container(color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
          ),
        ),
      );
    } else {
      messageContent = Text(message.text ?? '', style: TextStyle(color: isMe ? Colors.white : Colors.black87));
    }

    Widget statusWidget;
    if (isMe) {
      switch (message.status) {
        case MessageStatus.sending:
          statusWidget = const Text('sending...', style: TextStyle(fontSize: 10, color: Colors.grey));
          break;
        case MessageStatus.sent:
          statusWidget = const Icon(Icons.done, size: 16, color: Colors.grey);
          break;
        case MessageStatus.delivered:
          statusWidget = const Icon(Icons.done_all, size: 16, color: Colors.grey);
          break;
        case MessageStatus.seen:
          statusWidget = const Icon(Icons.done_all, size: 16, color: Colors.blue);
          break;
        case MessageStatus.error:
          statusWidget = const Icon(Icons.error, size: 16, color: Colors.red);
          break;
      }
    } else {
      statusWidget = const SizedBox.shrink();
    }

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: message.imageUrl != null ? const EdgeInsets.all(4.0) : const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                  decoration: BoxDecoration(color: isMe ? const Color(0xFF3498DB) : Colors.white, borderRadius: BorderRadius.circular(20.0), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 2, offset: const Offset(0, 1))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToMessageId != null)
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          margin: const EdgeInsets.only(bottom: 4.0),
                          decoration: BoxDecoration(color: isMe ? Colors.blue.withOpacity(0.5) : Colors.grey.withOpacity(0.1), borderRadius: const BorderRadius.all(Radius.circular(12.0))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(message.replyToSender ?? 'User', style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.white70 : Colors.black87)),
                            const SizedBox(height: 2),
                            if (message.replyToImageUrl != null)
                              Row(children: [Icon(Icons.photo, size: 14, color: isMe ? Colors.white70 : Colors.grey[700]), const SizedBox(width: 4), Text('Photo', style: TextStyle(color: isMe ? Colors.white70 : Colors.grey[700]))])
                            else
                              Text(message.replyToMessageText ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: isMe ? Colors.white70 : Colors.grey[700])),
                          ]),
                        ),
                      messageContent,
                    ],
                  ),
                ),
                if (message.reactions.isNotEmpty)
                  Positioned(
                    bottom: -8,
                    right: isMe ? 10 : null,
                    left: isMe ? null : 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.5), spreadRadius: 1, blurRadius: 1)]),
                      child: Text(message.reactions.values.toSet().toList().join(' '), style: const TextStyle(fontSize: 14)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(top: message.reactions.isNotEmpty ? 12.0 : 4.0, left: isMe ? 0 : 8.0, right: isMe ? 8.0 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.timestamp != null) Text(timeago.format(message.timestamp!.toDate(), locale: 'en_short'), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  if (isMe) const SizedBox(width: 4),
                  if (isMe) statusWidget,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DateSeparator extends StatelessWidget {
  final DateTime date;
  const DateSeparator({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final formattedDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (formattedDate.isAtSameMomentAs(today)) {
      dateText = 'Today';
    } else if (formattedDate.isAtSameMomentAs(yesterday)) {
      dateText = 'Yesterday';
    } else {
      dateText = '${date.month}/${date.day}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Text(
            dateText,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class UnreadSeparator extends StatelessWidget {
  const UnreadSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Unread Messages',
              style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class FullScreenImageScreen extends StatelessWidget {
  final String imageUrl;
  const FullScreenImageScreen({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(imageUrl),
        ),
      ),
    );
  }
}
