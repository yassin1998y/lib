import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/material.dart';
import 'package:freegram/screens/chat_screen.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final rtdb.FirebaseDatabase _rtdb = rtdb.FirebaseDatabase.instance;

  // --- User Methods ---

  /// Creates a new user document in Firestore upon sign-up.
  Future<void> createUser({
    required String uid,
    required String username,
    required String email,
  }) {
    return _db.collection('users').doc(uid).set({
      'username': username,
      'email': email,
      'followers': [],
      'following': [],
      'bio': '',
      'photoUrl': '',
      'fcmToken': '',
      'presence': false,
      'lastSeen': FieldValue.serverTimestamp(),
      'country': '',
      'age': 0,
      'gender': '',
      'interests': [],
      'createdAt': FieldValue.serverTimestamp(),
      'nearbyContacts': [],
    });
  }

  /// Gets a real-time stream of a user's document.
  Stream<DocumentSnapshot> getUserStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  /// Gets a single snapshot of a user's document.
  Future<DocumentSnapshot> getUser(String uid) {
    return _db.collection('users').doc(uid).get();
  }

  /// Updates a user's document with the given data.
  Future<void> updateUser(String uid, Map<String, dynamic> data) {
    return _db.collection('users').doc(uid).update(data);
  }

  /// Updates a user's presence status in both Firestore and Realtime Database.
  Future<void> updateUserPresence(String uid, bool isOnline) async {
    final userStatusFirestoreRef = _db.collection('users').doc(uid);
    final userStatusDatabaseRef = _rtdb.ref('status/$uid');
    final status = {
      'presence': isOnline,
      'lastSeen': rtdb.ServerValue.timestamp,
    };
    await userStatusDatabaseRef.set(status);
    await userStatusFirestoreRef.update({
      'presence': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// Adds a user to the current user's following list and the current user to the other user's followers list.
  Future<void> followUser(String currentUserId, String userIdToFollow) async {
    await _db.collection('users').doc(currentUserId).update({
      'following': FieldValue.arrayUnion([userIdToFollow])
    });
    await _db.collection('users').doc(userIdToFollow).update({
      'followers': FieldValue.arrayUnion([currentUserId])
    });
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await addNotification(
        userId: userIdToFollow,
        type: 'follow',
        fromUsername: currentUser.displayName ?? 'Anonymous',
        fromUserId: currentUser.uid,
        fromUserPhotoUrl: currentUser.photoURL,
      );
    }
  }

  /// Removes a user from the current user's following list and the current user from the other user's followers list.
  Future<void> unfollowUser(String currentUserId, String userIdToUnfollow) async {
    await _db.collection('users').doc(currentUserId).update({
      'following': FieldValue.arrayRemove([userIdToUnfollow])
    });
    await _db.collection('users').doc(userIdToUnfollow).update({
      'followers': FieldValue.arrayRemove([currentUserId])
    });
  }

  /// Fetches a paginated list of users for the Explore tab.
  Future<QuerySnapshot> getPaginatedUsers({required int limit, DocumentSnapshot? lastDocument}) {
    Query query = _db.collection('users').orderBy('username').limit(limit);
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.get();
  }

  /// Fetches a list of recommended users based on shared interests.
  Future<List<DocumentSnapshot>> getRecommendedUsers(List<String> interests, String currentUserId) async {
    if (interests.isEmpty) return [];
    final querySnapshot = await _db
        .collection('users')
        .where('interests', arrayContainsAny: interests)
        .limit(30)
        .get();
    return querySnapshot.docs.where((doc) => doc.id != currentUserId).toList();
  }

  /// Searches for users by username.
  Stream<QuerySnapshot> searchUsers(String query) {
    return _db
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: query)
        .where('username', isLessThanOrEqualTo: '$query\uf8ff')
        .snapshots();
  }

  /// Syncs contacts found via Bluetooth to the user's Firestore document.
  Future<void> syncNearbyContacts(String userId, List<String> contactIds) {
    return _db.collection('users').doc(userId).update({
      'nearbyContacts': FieldValue.arrayUnion(contactIds)
    });
  }

  // --- Post & Comment Methods ---

  /// Creates a new post document.
  Future<void> createPost({
    required String userId,
    required String username,
    required String caption,
    required String imageUrl,
    required String postType, // 'image' or 'reel'
  }) {
    return _db.collection('posts').add({
      'userId': userId,
      'username': username,
      'caption': caption,
      'imageUrl': imageUrl,
      'postType': postType,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a post and all its associated likes and comments.
  Future<void> deletePost(String postId) async {
    final postRef = _db.collection('posts').doc(postId);
    final batch = _db.batch();

    final commentsSnapshot = await postRef.collection('comments').get();
    for (var doc in commentsSnapshot.docs) {
      batch.delete(doc.reference);
    }

    final likesSnapshot = await postRef.collection('likes').get();
    for (var doc in likesSnapshot.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(postRef);
    return batch.commit();
  }

  /// Toggles a like on a post and sends a notification if applicable.
  Future<void> togglePostLike({
    required String postId,
    required String userId,
    required String postOwnerId,
    required String postImageUrl,
    required Map<String, dynamic> currentUserData,
  }) async {
    final likeRef = _db.collection('posts').doc(postId).collection('likes').doc(userId);
    final likeDoc = await likeRef.get();

    if (likeDoc.exists) {
      await likeRef.delete();
    } else {
      await likeRef.set({'userId': userId});
      if (postOwnerId != userId) {
        await addNotification(
          userId: postOwnerId,
          type: 'like',
          fromUsername: currentUserData['displayName'] ?? 'Anonymous',
          fromUserId: userId,
          fromUserPhotoUrl: currentUserData['photoURL'],
          postId: postId,
          postImageUrl: postImageUrl,
        );
      }
    }
  }

  /// Adds a comment to a post and sends a notification.
  Future<void> addComment({
    required String postId,
    required String userId,
    required String username,
    required String commentText,
    String? userPhotoUrl,
  }) async {
    final postRef = _db.collection('posts').doc(postId);
    final postDoc = await postRef.get();
    final postData = postDoc.data();
    if (postData == null) return;

    await postRef.collection('comments').add({
      'text': commentText,
      'username': username,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (postData['userId'] != userId) {
      await addNotification(
        userId: postData['userId'],
        type: 'comment',
        fromUsername: username,
        fromUserId: userId,
        fromUserPhotoUrl: userPhotoUrl,
        postId: postId,
        postImageUrl: postData['imageUrl'],
        commentText: commentText,
      );
    }
  }

  /// Fetches posts for a user's feed (posts from people they follow).
  Future<QuerySnapshot> getFeedPosts(List<String> followingIds, {DocumentSnapshot? lastDocument}) {
    var query = _db
        .collection('posts')
        .where('userId', whereIn: followingIds)
        .orderBy('timestamp', descending: true)
        .limit(10);
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.get();
  }

  /// Gets a real-time stream of a user's own posts for their profile.
  Stream<QuerySnapshot> getUserPostsStream(String userId) {
    return _db.collection('posts').where('userId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots();
  }

  /// Gets a single snapshot of a post document.
  Future<DocumentSnapshot> getPost(String postId) {
    return _db.collection('posts').doc(postId).get();
  }

  /// Gets a real-time stream of a post's likes.
  Stream<QuerySnapshot> getPostLikesStream(String postId) {
    return _db.collection('posts').doc(postId).collection('likes').snapshots();
  }

  /// Gets a real-time stream of a post's comments.
  Stream<QuerySnapshot> getPostCommentsStream(String postId, {int? limit}) {
    Query query = _db.collection('posts').doc(postId).collection('comments').orderBy('timestamp', descending: true);
    if (limit != null) {
      query = query.limit(limit);
    }
    return query.snapshots();
  }

  /// Fetches the like and comment count for a post.
  Future<Map<String, int>> getPostStats(String postId) async {
    final likesSnapshot = await _db.collection('posts').doc(postId).collection('likes').get();
    final commentsSnapshot = await _db.collection('posts').doc(postId).collection('comments').get();
    return {'likes': likesSnapshot.size, 'comments': commentsSnapshot.size};
  }

  // --- Notification Methods ---

  /// Adds a new notification to a user's subcollection.
  Future<void> addNotification({
    required String userId,
    required String type,
    required String fromUsername,
    required String fromUserId,
    String? fromUserPhotoUrl,
    String? postId,
    String? postImageUrl,
    String? commentText,
  }) {
    return _db.collection('users').doc(userId).collection('notifications').add({
      'type': type,
      'fromUsername': fromUsername,
      'fromUserId': fromUserId,
      'fromUserPhotoUrl': fromUserPhotoUrl,
      'postId': postId,
      'postImageUrl': postImageUrl,
      'commentText': commentText,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  /// Gets a real-time stream of all notifications for a user.
  Stream<QuerySnapshot> getNotificationsStream(String userId) {
    return _db.collection('users').doc(userId).collection('notifications').orderBy('timestamp', descending: true).limit(50).snapshots();
  }

  /// Gets a real-time stream of the unread notification count.
  Stream<int> getUnreadNotificationCountStream(String userId) {
    return _db.collection('users').doc(userId).collection('notifications').where('read', isEqualTo: false).snapshots().map((snapshot) => snapshot.docs.length);
  }

  /// Marks a single notification as read.
  Future<void> markNotificationAsRead(String userId, String notificationId) {
    return _db.collection('users').doc(userId).collection('notifications').doc(notificationId).update({'read': true});
  }

  /// Marks all of a user's unread notifications as read.
  Future<bool> markAllNotificationsAsRead(String userId) async {
    final notificationsRef = _db.collection('users').doc(userId).collection('notifications');
    final unreadNotifications = await notificationsRef.where('read', isEqualTo: false).get();
    if (unreadNotifications.docs.isEmpty) return false;

    final batch = _db.batch();
    for (var doc in unreadNotifications.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
    return true;
  }

  // --- Chat Methods ---

  /// Creates a new chat or navigates to an existing one.
  Future<void> startChat(BuildContext context, String otherUserId, String otherUsername) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final currentUser = FirebaseAuth.instance.currentUser!;
    final ids = [currentUser.uid, otherUserId];
    ids.sort();
    final chatId = ids.join('_');
    final chatRef = _db.collection('chats').doc(chatId);

    await chatRef.set({
      'users': [currentUser.uid, otherUserId],
      'usernames': {
        currentUser.uid: currentUser.displayName ?? 'Anonymous',
        otherUserId: otherUsername,
      },
    }, SetOptions(merge: true));

    // Pop the current modal/dialog before pushing the new screen
    Navigator.of(context).pop();
    navigator.push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUsername: otherUsername)));
  }

  /// Gets a real-time stream of a user's chats, ordered by the most recent message.
  Stream<QuerySnapshot> getChatsStream(String userId) {
    return _db.collection('chats').where('users', arrayContains: userId).orderBy('lastMessageTimestamp', descending: true).snapshots();
  }

  /// Gets a real-time stream of a single chat document.
  Stream<DocumentSnapshot> getChatStream(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }

  /// Gets a real-time stream of the total unread chat count for a user.
  Stream<int> getUnreadChatCountStream(String userId) {
    return _db.collection('chats').where('users', arrayContains: userId).where('unreadCount.$userId', isGreaterThan: 0).snapshots().map((snapshot) => snapshot.docs.length);
  }

  /// Resets the unread message count for the current user in a specific chat.
  Future<void> resetUnreadCount(String chatId, String userId) {
    return _db.collection('chats').doc(chatId).set({'unreadCount': {userId: 0}}, SetOptions(merge: true));
  }

  /// Updates the typing status for a user in a chat.
  Future<void> updateTypingStatus(String chatId, String userId, bool isTyping) {
    return _db.collection('chats').doc(chatId).update({'typingStatus.$userId': isTyping});
  }

  /// Sends a new message (text or image) in a chat.
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

    final chatDoc = await chatRef.get();
    final List<dynamic> users = (chatDoc.data() as Map<String, dynamic>)['users'];
    final otherUserId = users.firstWhere((id) => id != senderId);

    // TODO: Implement logic to send a push notification to the other user's FCM token.
    // When the push notification is successfully received, update `isDelivered` to `true`.
    // For now, we'll assume it's delivered instantly.
    await chatRef.update({
      'lastMessage': imageUrl != null ? '📷 Photo' : text,
      'lastMessageIsImage': imageUrl != null,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'unreadCount.$otherUserId': FieldValue.increment(1),
    });
  }

  /// Edits an existing message.
  Future<void> editMessage(String chatId, String messageId, String newText) {
    final messageRef = _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
    return messageRef.update({
      'text': newText,
      'edited': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }


  /// Deletes a message from a chat.
  Future<void> deleteMessage(String chatId, String messageId) {
    return _db.collection('chats').doc(chatId).collection('messages').doc(messageId).delete();
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

  /// Marks messages in a chat as seen by the current user.
  void markMessagesAsSeen(String chatId, String currentUserId, List<QueryDocumentSnapshot> messages) {
    final batch = _db.batch();
    for (var message in messages) {
      final messageData = message.data() as Map<String, dynamic>;
      if (messageData['senderId'] != currentUserId && (messageData['isSeen'] == null || messageData['isSeen'] == false)) {
        batch.update(message.reference, {'isSeen': true});
      }
    }
    batch.commit();
  }

  /// **NEW:** Marks a list of messages as seen in a single batch write.
  Future<void> markMultipleMessagesAsSeen(String chatId, List<String> messageIds) {
    if (messageIds.isEmpty) return Future.value();
    final batch = _db.batch();
    for (final messageId in messageIds) {
      final messageRef = _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
      batch.update(messageRef, {'isSeen': true});
    }
    return batch.commit();
  }


  /// Gets a real-time stream of messages in a chat.
  Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _db.collection('chats').doc(chatId).collection('messages').orderBy('timestamp', descending: true).snapshots();
  }

  /// Adds or removes a reaction from a message.
  Future<void> toggleMessageReaction(String chatId, String messageId, String userId, String emoji) async {
    final messageRef = _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
    final doc = await messageRef.get();
    final reactions = Map<String, String>.from(doc.data()?['reactions'] ?? {});
    if (reactions[userId] == emoji) {
      reactions.remove(userId);
    } else {
      reactions[userId] = emoji;
    }
    await messageRef.update({'reactions': reactions});
  }

  // --- Match / Swipe Methods ---

  /// Fetches potential matches for the current user.
  Future<List<DocumentSnapshot>> getPotentialMatches(String currentUserId) async {
    final userDoc = await getUser(currentUserId);
    final currentUserCountry = (userDoc.data() as Map<String, dynamic>)['country'];
    final swipesSnapshot = await _db.collection('users').doc(currentUserId).collection('swipes').get();
    final swipedUserIds = swipesSnapshot.docs.map((doc) => doc.id).toList();

    final querySnapshot = await _db
        .collection('users')
        .where('country', isEqualTo: currentUserCountry)
        .where('presence', isEqualTo: true)
        .limit(20)
        .get();

    return querySnapshot.docs.where((doc) => doc.id != currentUserId && !swipedUserIds.contains(doc.id)).toList();
  }

  /// Records a user's swipe action ('smash' or 'pass').
  Future<void> recordSwipe(String currentUserId, String otherUserId, String action) {
    return _db.collection('users').doc(currentUserId).collection('swipes').doc(otherUserId).set({
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Checks if a 'smash' action resulted in a mutual match.
  Future<bool> checkForMatch(String currentUserId, String otherUserId) async {
    final otherUserSwipe = await _db.collection('users').doc(otherUserId).collection('swipes').doc(currentUserId).get();
    return otherUserSwipe.exists && otherUserSwipe.data()?['action'] == 'smash';
  }

  /// Creates a new chat document when a mutual match occurs.
  Future<void> createMatch(String userId1, String userId2) async {
    final ids = [userId1, userId2]..sort();
    final chatId = ids.join('_');
    final user1Doc = await getUser(userId1);
    final user2Doc = await getUser(userId2);
    await _db.collection('chats').doc(chatId).set({
      'users': ids,
      'usernames': {
        userId1: (user1Doc.data() as Map<String, dynamic>)['username'],
        userId2: (user2Doc.data() as Map<String, dynamic>)['username'],
      },
      'lastMessage': 'You matched! Say hello.',
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
