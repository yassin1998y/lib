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
import 'package:timeago/timeago.dart' as timeago;
import 'package:path_provider/path_provider.dart';
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
    _scrollController.dispose();
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

      if (!mounted) return;
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

  /// Uploads an image or audio file to Cloudinary and returns the URL.
  Future<String?> _uploadToCloudinary(File file, {String resourceType = 'image'}) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/$resourceType/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'Prototype';

    final multipartFile = http.MultipartFile.fromBytes('file', await file.readAsBytes(), filename: path.basename(file.path));
    request.files.add(multipartFile);

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    } else {
      debugPrint('Cloudinary upload failed with status: ${response.statusCode}');
      return null;
    }
  }

  /// Shows a bottom sheet to choose between camera and gallery, then sends the image.
  Future<void> _sendImage() async {
    if (!mounted) return;
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

    if (!mounted) return;
    setState(() => _isUploading = true);

    try {
      final imageUrl = await _uploadToCloudinary(File(pickedFile.path));
      if (imageUrl == null) throw Exception('Image upload failed');

      final currentUser = FirebaseAuth.instance.currentUser!;
      if (!mounted) return;
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

  /// Shows a bottom sheet with message actions (react, reply, delete, edit).
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
              if (isMe && messageData['imageUrl'] == null) // Can only edit text messages
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editMessage(messageId, messageData['text']);
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

  /// Edits a message, showing a dialog for user input.
  void _editMessage(String messageId, String currentText) {
    final TextEditingController editController = TextEditingController(text: currentText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(hintText: 'Enter new message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (editController.text.trim().isNotEmpty) {
                if (mounted) {
                  context.read<FirestoreService>().editMessage(widget.chatId, messageId, editController.text.trim());
                }
              }
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Builds the "is typing..." indicator.
  Widget _buildTypingIndicator(String otherUserId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: context.read<FirestoreService>().getChatStream(widget.chatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final chatData = snapshot.data!.data() as Map<String, dynamic>;
        final typingStatus = chatData['typingStatus'] as Map<String, dynamic>? ?? {};

        if (typingStatus[otherUserId] == true) {
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
      color: Colors.grey.withOpacity(0.1),
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

    return StreamBuilder<DocumentSnapshot>(
      stream: firestoreService.getChatStream(widget.chatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(appBar: AppBar(title: Text(widget.otherUsername), backgroundColor: Colors.white, elevation: 1));
        }

        final chatData = snapshot.data!.data() as Map<String, dynamic>;
        final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUser.uid);

        return StreamBuilder<DocumentSnapshot>(
          stream: firestoreService.getUserStream(otherUserId),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final isOnline = userData?['presence'] ?? false;
            final lastSeenTimestamp = userData?['lastSeen'] as Timestamp?;
            final photoUrl = userData?['photoUrl'];

            String statusText = 'Offline';
            if (isOnline) {
              statusText = 'Online';
            } else if (lastSeenTimestamp != null) {
              final now = DateTime.now();
              final lastSeen = lastSeenTimestamp.toDate();
              final difference = now.difference(lastSeen);
              if (difference.inHours < 1) {
                statusText = 'last seen ${difference.inMinutes}m ago';
              } else if (difference.inHours < 24) {
                statusText = 'last seen ${difference.inHours}h ago';
              } else {
                statusText = 'last seen ${timeago.format(lastSeen)}';
              }
            }

            return Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                backgroundColor: Colors.white,
                elevation: 1,
                title: GestureDetector(
                  onTap: () {
                    // Navigate to the other user's profile
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: otherUserId),
                    ));
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                        child: (photoUrl == null || photoUrl.isEmpty)
                            ? Text(widget.otherUsername.isNotEmpty ? widget.otherUsername[0].toUpperCase() : '?')
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.otherUsername, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(statusText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
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

                        final messages = snapshot.data!.docs;
                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(8.0),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final messageDoc = messages[index];
                            final previousMessageDoc = index + 1 < messages.length ? messages[index + 1] : null;

                            final messageDate = (messageDoc['timestamp'] as Timestamp).toDate();
                            final previousMessageDate = (previousMessageDoc?['timestamp'] as Timestamp?)?.toDate();

                            // Show a date separator if the date is different from the previous message
                            final bool showDateSeparator = previousMessageDate == null ||
                                messageDate.day != previousMessageDate.day ||
                                messageDate.month != previousMessageDate.month ||
                                messageDate.year != previousMessageDate.year;

                            return Column(
                              children: [
                                if (showDateSeparator)
                                  DateSeparator(date: messageDate),
                                MessageBubble(
                                  messageDoc: messageDoc,
                                  isMe: messageDoc['senderId'] == currentUser.uid,
                                  onLongPress: () => _showMessageActions(context, messageDoc.id, messageDoc.data() as Map<String, dynamic>, messageDoc['senderId'] == currentUser.uid),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  _buildTypingIndicator(otherUserId),
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
            );
          },
        );
      },
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
    final Timestamp? timestamp = message['timestamp'] as Timestamp?;


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
      messageContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message['text'] ?? '',
            style: TextStyle(color: isMe ? Colors.white : Colors.black87),
          ),
          if (message['edited'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                'Edited',
                style: TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
        ],
      );
    }

    // Determine the delivery status icon based on the original request
    IconData statusIcon = Icons.done;
    Color statusColor = Colors.grey;
    if (isMe) {
      final bool isDelivered = message['isDelivered'] ?? false;
      if (isSeen) {
        statusIcon = Icons.done_all;
        statusColor = Colors.blue;
      } else if (isDelivered) {
        statusIcon = Icons.done_all;
        statusColor = Colors.grey;
      } else {
        statusIcon = Icons.done;
        statusColor = Colors.grey;
      }
    }


    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                          color: Colors.grey.withOpacity(0.2),
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
                            color: isMe ? Colors.blue.withOpacity(0.5) : Colors.grey.withOpacity(0.1),
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
                      statusIcon,
                      size: 16,
                      color: statusColor,
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
                          color: Colors.grey.withOpacity(0.5),
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
            if (timestamp != null)
              Padding(
                padding: EdgeInsets.only(top: 4.0, left: isMe ? 0 : 8.0, right: isMe ? 8.0 : 0),
                child: Text(
                  timeago.format(timestamp.toDate(), locale: 'en_short'),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A widget that displays a date separator in the chat.
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
