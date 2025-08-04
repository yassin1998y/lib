import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

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

  // State for the reply feature
  String? _replyingToMessageId;
  String? _replyingToMessageText;
  String? _replyingToSender;
  String? _replyingToImageUrl;

  @override
  void initState() {
    super.initState();
    // Reset unread count for the current user when entering the chat
    context.read<FirestoreService>().resetUnreadCount(widget.chatId, FirebaseAuth.instance.currentUser!.uid);
    _messageController.addListener(_onTyping);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    _typingTimer?.cancel();
    // Ensure typing status is set to false when leaving the screen
    _updateTypingStatus(false);
    super.dispose();
  }

  /// Updates the backend with the user's typing status.
  void _onTyping() {
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _updateTypingStatus(true);
    _typingTimer = Timer(const Duration(milliseconds: 1500), () {
      _updateTypingStatus(false);
    });
  }

  /// Calls the Firestore service to update the typing status.
  Future<void> _updateTypingStatus(bool isTyping) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await context.read<FirestoreService>().updateTypingStatus(widget.chatId, currentUser.uid, isTyping);
    }
  }

  /// Sends a text message using the Firestore service.
  Future<void> _sendMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final messageText = _messageController.text.trim();

    if (messageText.isNotEmpty) {
      _typingTimer?.cancel();
      _updateTypingStatus(false);

      await context.read<FirestoreService>().sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.uid,
        text: messageText,
        replyToMessageId: _replyingToMessageId,
        replyToMessageText: _replyingToMessageText,
        replyToImageUrl: _replyingToImageUrl,
        replyToSender: _replyingToSender,
      );

      _messageController.clear();
      _cancelReply();
    }
  }

  /// Uploads an image to Cloudinary and returns the URL.
  Future<String?> _uploadToCloudinary(XFile image) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'Prototype';

    final bytes = await image.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: image.name);
    request.files.add(multipartFile);

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    } else {
      return null;
    }
  }

  /// Shows a bottom sheet to choose between camera and gallery, then sends the image.
  Future<void> _sendImage() async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final imageUrl = await _uploadToCloudinary(pickedFile);
      if (imageUrl == null) throw Exception('Image upload failed');

      final currentUser = FirebaseAuth.instance.currentUser!;
      await context.read<FirestoreService>().sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.uid,
        imageUrl: imageUrl,
        replyToMessageId: _replyingToMessageId,
        replyToMessageText: _replyingToMessageText,
        replyToImageUrl: _replyingToImageUrl,
        replyToSender: _replyingToSender,
      );
      _cancelReply();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// Sets the state to show the reply preview.
  void _startReply(String messageId, Map<String, dynamic> messageData) {
    setState(() {
      _replyingToMessageId = messageId;
      _replyingToMessageText = messageData['text'];
      _replyingToImageUrl = messageData['imageUrl'];
      _replyingToSender = messageData['senderId'] == FirebaseAuth.instance.currentUser!.uid
          ? 'You'
          : widget.otherUsername;
    });
  }

  /// Clears the reply state.
  void _cancelReply() {
    setState(() {
      _replyingToMessageId = null;
      _replyingToMessageText = null;
      _replyingToSender = null;
      _replyingToImageUrl = null;
    });
  }

  /// Shows a bottom sheet with message actions (react, reply, delete).
  void _showMessageActions(BuildContext context, String messageId, Map<String, dynamic> messageData, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                    return IconButton(
                      icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.read<FirestoreService>().toggleMessageReaction(widget.chatId, messageId, FirebaseAuth.instance.currentUser!.uid, emoji);
                      },
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(context).pop();
                  _startReply(messageId, messageData);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.read<FirestoreService>().deleteMessage(widget.chatId, messageId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the "is typing..." indicator.
  Widget _buildTypingIndicator() {
    final currentUser = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot>(
      stream: context.read<FirestoreService>().getChatStream(widget.chatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final chatData = snapshot.data!.data() as Map<String, dynamic>;
        final typingStatus = chatData['typingStatus'] as Map<String, dynamic>? ?? {};
        final otherUserId = typingStatus.keys.firstWhere((id) => id != currentUser.uid, orElse: () => '');

        if (otherUserId.isNotEmpty && typingStatus[otherUserId] == true) {
          return Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
            child: Row(
              children: [
                Text(
                  '${widget.otherUsername} is typing...',
                  style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// Builds the preview of the message being replied to.
  Widget _buildReplyPreview() {
    if (_replyingToMessageId == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.grey.withAlpha(25),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $_replyingToSender',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                ),
                const SizedBox(height: 4),
                _replyingToImageUrl != null
                    ? Row(children: [Icon(Icons.photo, size: 16, color: Colors.grey[700]), const SizedBox(width: 4), Text('Photo', style: TextStyle(color: Colors.grey[700]))])
                    : Text(
                  _replyingToMessageText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _cancelReply,
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final firestoreService = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUsername),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: firestoreService.getMessagesStream(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Say hello!'));
                }

                // Mark messages as seen after the frame is built
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    firestoreService.markMessagesAsSeen(widget.chatId, currentUser.uid, snapshot.data!.docs);
                  }
                });

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final messageDoc = snapshot.data!.docs[index];
                    return MessageBubble(
                      messageDoc: messageDoc,
                      isMe: messageDoc['senderId'] == currentUser.uid,
                      onLongPress: () => _showMessageActions(context, messageDoc.id, messageDoc.data() as Map<String, dynamic>, messageDoc['senderId'] == currentUser.uid),
                    );
                  },
                );
              },
            ),
          ),
          _buildTypingIndicator(),
          Column(
            children: [
              _buildReplyPreview(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.photo_camera, color: Color(0xFF3498DB)),
                      onPressed: _isUploading ? null : _sendImage,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF3498DB)),
                      onPressed: _isUploading ? null : _sendMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A widget that displays a single chat message bubble.
class MessageBubble extends StatelessWidget {
  final DocumentSnapshot messageDoc;
  final bool isMe;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.messageDoc,
    required this.isMe,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final message = messageDoc.data() as Map<String, dynamic>;
    final bool isSeen = message['isSeen'] ?? false;
    final String? imageUrl = message['imageUrl'];
    final bool isReply = message['replyToMessageId'] != null;
    final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});

    Widget messageContent;
    if (imageUrl != null) {
      messageContent = ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Image.network(
          imageUrl,
          height: 200,
          width: 200,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(height: 200, width: 200, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
        ),
      );
    } else {
      messageContent = Text(
        message['text'] ?? '',
        style: TextStyle(color: isMe ? Colors.white : Colors.black87),
      );
    }

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: imageUrl != null ? const EdgeInsets.all(4.0) : const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                  decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF3498DB) : Colors.white,
                      borderRadius: BorderRadius.circular(20.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withAlpha(51),
                          spreadRadius: 1,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        )
                      ]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isReply)
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          margin: const EdgeInsets.only(bottom: 4.0),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue.shade700.withAlpha(128) : Colors.grey.withAlpha(51),
                            borderRadius: const BorderRadius.all(Radius.circular(12.0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['replyToSender'] ?? 'User',
                                style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.white70 : Colors.black87),
                              ),
                              const SizedBox(height: 2),
                              if (message['replyToImageUrl'] != null)
                                Row(children: [Icon(Icons.photo, size: 14, color: isMe ? Colors.white70 : Colors.grey[700]), const SizedBox(width: 4), Text('Photo', style: TextStyle(color: isMe ? Colors.white70 : Colors.grey[700]))])
                              else
                                Text(
                                  message['replyToMessageText'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: isMe ? Colors.white70 : Colors.grey[700]),
                                ),
                            ],
                          ),
                        ),
                      messageContent,
                    ],
                  ),
                ),
                if (isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                    child: Icon(
                      isSeen ? Icons.done_all : Icons.done,
                      size: 16,
                      color: isSeen ? Colors.blue : Colors.grey,
                    ),
                  ),
              ],
            ),
            if (reactions.isNotEmpty)
              Positioned(
                bottom: -8,
                right: isMe ? 10 : null,
                left: isMe ? null : 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withAlpha(128),
                          spreadRadius: 1,
                          blurRadius: 1,
                        )
                      ]
                  ),
                  child: Text(
                    reactions.values.toSet().toList().join(' '),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
