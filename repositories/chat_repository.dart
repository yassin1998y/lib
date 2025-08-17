import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/repositories/gamification_repository.dart';
import 'package:freegram/repositories/task_repository.dart';
import 'package:freegram/screens/chat_screen.dart';

/// A repository dedicated to all chat and messaging-related Firestore operations.
class ChatRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  // UPDATED: Now depends on the new repositories for cross-domain logic.
  final GamificationRepository _gamificationRepository;
  final TaskRepository _taskRepository;

  ChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    required GamificationRepository gamificationRepository,
    required TaskRepository taskRepository,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = firebaseAuth ?? FirebaseAuth.instance,
        _gamificationRepository = gamificationRepository,
        _taskRepository = taskRepository;

  /// Initiates a new chat or navigates to an existing one.
  Future<void> startOrGetChat(
      BuildContext context, String otherUserId, String otherUsername) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final currentUser = _auth.currentUser!;
    final ids = [currentUser.uid, otherUserId];
    ids.sort();
    final chatId = ids.join('_');
    final chatRef = _db.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();

    if (!chatDoc.exists) {
      await chatRef.set({
        'users': [currentUser.uid, otherUserId],
        'usernames': {
          currentUser.uid: currentUser.displayName ?? 'Anonymous',
          otherUserId: otherUsername,
        },
        'chatType': 'contact_request',
        'initiatorId': currentUser.uid,
      }, SetOptions(merge: true));
    }

    if (context.mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      navigator.push(MaterialPageRoute(
          builder: (_) =>
              ChatScreen(chatId: chatId, otherUsername: otherUsername)));
    }
  }

  /// Sends a new message in a chat.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String? text,
    String? imageUrl,
    String? replyToMessageId,
    String? replyToMessageText,
    String? replyToImageUrl,
    String? replyToSender,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();
    if (!chatDoc.exists) return;

    final chatData = chatDoc.data() as Map<String, dynamic>;
    final chatType = chatData['chatType'] ?? 'friend';

    if (chatType == 'contact_request') {
      final initiatorId = chatData['initiatorId'];
      final messagesFromInitiator = await chatRef
          .collection('messages')
          .where('senderId', isEqualTo: initiatorId)
          .count()
          .get();

      if (senderId == initiatorId && (messagesFromInitiator.count ?? 0) >= 2) {
        throw Exception(
            "You cannot send more than two messages until they reply.");
      }

      if (senderId != initiatorId) {
        throw Exception(
            "You cannot reply until you accept the friend request.");
      }
    }

    await chatRef.collection('messages').add({
      'text': text,
      'imageUrl': imageUrl,
      'senderId': senderId,
      'timestamp': FieldValue.serverTimestamp(),
      'isSeen': false,
      'isDelivered': true,
      'reactions': {},
      'replyToMessageId': replyToMessageId,
      'replyToMessageText': replyToMessageText,
      'replyToImageUrl': replyToImageUrl,
      'replyToSender': replyToSender,
    });

    final otherUserId =
    (chatData['users'] as List).firstWhere((id) => id != senderId);
    await chatRef.update({
      'lastMessage': imageUrl != null ? '📷 Photo' : text,
      'lastMessageIsImage': imageUrl != null,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'unreadCount.$otherUserId': FieldValue.increment(1),
    });

    // UPDATED: Calls the new repositories directly
    await _gamificationRepository.addXp(senderId, 2, isSeasonal: true);
    await _taskRepository.updateTaskProgress(senderId, 'send_messages', 1);
  }

  /// Edits an existing message.
  Future<void> editMessage(String chatId, String messageId, String newText) {
    final messageRef =
    _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
    return messageRef.update({
      'text': newText,
      'edited': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a message from a chat.
  Future<void> deleteMessage(String chatId, String messageId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Deletes an entire chat conversation and all its messages.
  Future<void> deleteChat(String chatId) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final messages = await chatRef.collection('messages').get();
    final batch = _db.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(chatRef);
    return batch.commit();
  }

  /// Toggles a reaction on a message.
  Future<void> toggleMessageReaction(
      String chatId, String messageId, String userId, String emoji) async {
    final messageRef =
    _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
    final doc = await messageRef.get();
    final reactions = Map<String, String>.from(doc.data()?['reactions'] ?? {});
    if (reactions[userId] == emoji) {
      reactions.remove(userId);
    } else {
      reactions[userId] = emoji;
    }
    await messageRef.update({'reactions': reactions});
  }

  /// Marks multiple messages as seen.
  Future<void> markMultipleMessagesAsSeen(
      String chatId, List<String> messageIds) {
    if (messageIds.isEmpty) return Future.value();
    final batch = _db.batch();
    for (final messageId in messageIds) {
      final messageRef = _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
      batch.update(messageRef, {'isSeen': true});
    }
    return batch.commit();
  }

  /// Resets the unread message count for a user in a specific chat.
  Future<void> resetUnreadCount(String chatId, String userId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .set({'unreadCount': {userId: 0}}, SetOptions(merge: true));
  }

  /// Updates the typing status of a user in a chat.
  Future<void> updateTypingStatus(
      String chatId, String userId, bool isTyping) {
    return _db
        .collection('chats')
        .doc(chatId)
        .update({'typingStatus.$userId': isTyping});
  }

  // --- STREAMS ---

  /// Provides a stream of all chats for a given user.
  Stream<QuerySnapshot> getChatsStream(String userId) {
    return _db
        .collection('chats')
        .where('users', arrayContains: userId)
        .orderBy('lastMessageTimestamp', descending: true)
        .snapshots();
  }

  /// Provides a stream for a single chat document.
  Stream<DocumentSnapshot> getChatStream(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }

  /// Provides a stream of messages for a given chat.
  Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Provides a stream of the total unread chat count for a user.
  Stream<int> getUnreadChatCountStream(String userId) {
    return _db
        .collection('chats')
        .where('users', arrayContains: userId)
        .where('unreadCount.$userId', isGreaterThan: 0)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
