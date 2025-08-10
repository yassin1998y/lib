import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart'; // Import the new UserModel
import 'package:freegram/screens/chat_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

/// A centralized service for all Firestore and Firebase operations.
/// This refactored version uses the type-safe `UserModel` for all user-related
/// operations, ensuring data consistency and preventing runtime errors.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final rtdb.FirebaseDatabase _rtdb = rtdb.FirebaseDatabase.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // --- Auth Methods ---

  Future<UserCredential> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
          code: 'ERROR_ABORTED_BY_USER', message: 'Sign in aborted by user');
    }
    final GoogleSignInAuthentication googleAuth =
    await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;

    if (user != null) {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        // Create a new user with the simplified, consistent data model.
        await createUser(
          uid: user.uid,
          username: user.displayName ?? 'Google User',
          email: user.email ?? '',
          photoUrl: user.photoURL,
        );
      }
    }
    return userCredential;
  }

  Future<UserCredential> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login();
    if (result.status == LoginStatus.success) {
      final AccessToken accessToken = result.accessToken!;
      final AuthCredential credential =
      FacebookAuthProvider.credential(accessToken.token);
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final userDoc = await _db.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          final userData = await FacebookAuth.instance.getUserData();
          await createUser(
            uid: user.uid,
            username: userData['name'] ?? 'Facebook User',
            email: userData['email'] ?? '',
            photoUrl: userData['picture']?['data']?['url'],
          );
        }
      }
      return userCredential;
    } else {
      throw FirebaseAuthException(
        code: 'ERROR_FACEBOOK_LOGIN_FAILED',
        message: result.message,
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint("Error signing out from Google: $e");
    }
    try {
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint("Error signing out from Facebook: $e");
    }
    await _auth.signOut();
  }

  // --- User & Friend Methods (Refactored for Type Safety and Simplicity) ---

  /// Creates a new user document in Firestore using the `UserModel`.
  Future<void> createUser({
    required String uid,
    required String username,
    required String email,
    String? photoUrl,
  }) {
    final newUser = UserModel(
      id: uid,
      username: username,
      email: email,
      photoUrl: photoUrl ?? '',
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
      // All relationship fields are initialized as empty lists.
    );
    return _db.collection('users').doc(uid).set(newUser.toMap());
  }

  /// Fetches a user document and returns it as a type-safe `UserModel`.
  Future<UserModel> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) {
      throw Exception('User not found');
    }
    return UserModel.fromDoc(doc);
  }

  /// Returns a stream of a user document, converted to a `UserModel`.
  Stream<UserModel> getUserStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => UserModel.fromDoc(doc));
  }

  /// Updates a user document with raw data. Used for profile edits.
  Future<void> updateUser(String uid, Map<String, dynamic> data) {
    return _db.collection('users').doc(uid).update(data);
  }

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

  /// Sends a friend request and a notification to the recipient.
  Future<void> sendFriendRequest(String fromUserId, String toUserId) async {
    final batch = _db.batch();
    final fromUserRef = _db.collection('users').doc(fromUserId);
    final toUserRef = _db.collection('users').doc(toUserId);

    batch.update(fromUserRef, {'friendRequestsSent': FieldValue.arrayUnion([toUserId])});
    batch.update(toUserRef, {'friendRequestsReceived': FieldValue.arrayUnion([fromUserId])});

    await batch.commit();

    // After committing, send a notification.
    final fromUser = await getUser(fromUserId);
    await addNotification(
      userId: toUserId,
      type: 'friend_request_received', // FIX: Standardized type name
      fromUserId: fromUserId,
      fromUsername: fromUser.username,
      fromUserPhotoUrl: fromUser.photoUrl,
    );
  }

  /// Private helper to add friendship operations to a batch.
  void _addFriendshipToBatch(WriteBatch batch, String currentUserId, String requestingUserId) {
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final requestingUserRef = _db.collection('users').doc(requestingUserId);

    batch.update(currentUserRef, {'friendRequestsReceived': FieldValue.arrayRemove([requestingUserId])});
    batch.update(requestingUserRef, {'friendRequestsSent': FieldValue.arrayRemove([currentUserId])});

    batch.update(currentUserRef, {'friends': FieldValue.arrayUnion([requestingUserId])});
    batch.update(requestingUserRef, {'friends': FieldValue.arrayUnion([currentUserId])});
  }

  /// Accepts a friend request and notifies the original sender.
  Future<void> acceptFriendRequest(String currentUserId, String requestingUserId) async {
    final batch = _db.batch();
    _addFriendshipToBatch(batch, currentUserId, requestingUserId);
    await batch.commit();

    // After committing, send a notification back to the original sender.
    final currentUser = await getUser(currentUserId);
    await addNotification(
      userId: requestingUserId,
      type: 'request_accepted',
      fromUserId: currentUserId,
      fromUsername: currentUser.username,
      fromUserPhotoUrl: currentUser.photoUrl,
    );
  }

  /// Accepts a contact request, becomes friends, unlocks the chat, and sends a notification.
  Future<void> acceptContactRequest({
    required String chatId,
    required String currentUserId,
    required String requestingUserId,
  }) async {
    final batch = _db.batch();
    final chatRef = _db.collection('chats').doc(chatId);

    batch.update(chatRef, {'chatType': 'friend_chat'});
    _addFriendshipToBatch(batch, currentUserId, requestingUserId);

    await batch.commit();

    // After committing, send a notification back to the original sender.
    final currentUser = await getUser(currentUserId);
    await addNotification(
      userId: requestingUserId,
      type: 'request_accepted',
      fromUserId: currentUserId,
      fromUsername: currentUser.username,
      fromUserPhotoUrl: currentUser.photoUrl,
    );
  }

  /// Declines a friend request. Atomically updates both users' documents.
  Future<void> declineFriendRequest(String currentUserId, String requestingUserId) async {
    final batch = _db.batch();
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final requestingUserRef = _db.collection('users').doc(requestingUserId);

    batch.update(currentUserRef, {'friendRequestsReceived': FieldValue.arrayRemove([requestingUserId])});
    batch.update(requestingUserRef, {'friendRequestsSent': FieldValue.arrayRemove([currentUserId])});

    await batch.commit();
  }

  /// Removes a friend. Atomically updates both users' documents.
  Future<void> removeFriend(String currentUserId, String friendId) async {
    final batch = _db.batch();
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final friendUserRef = _db.collection('users').doc(friendId);

    batch.update(currentUserRef, {'friends': FieldValue.arrayRemove([friendId])});
    batch.update(friendUserRef, {'friends': FieldValue.arrayRemove([currentUserId])});

    await batch.commit();
  }

  /// Blocks a user, ensuring they are removed as a friend first.
  Future<void> blockUser(String currentUserId, String userToBlockId) async {
    await removeFriend(currentUserId, userToBlockId);
    await _db.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayUnion([userToBlockId])
    });
  }

  /// Unblocks a user.
  Future<void> unblockUser(String currentUserId, String userToUnblockId) {
    return _db.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayRemove([userToUnblockId])
    });
  }

  // --- Post & Comment Methods ---
  Future<void> createPost({
    required String userId,
    required String username,
    required String caption,
    required String imageUrl,
    required String postType,
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

  Future<void> togglePostLike({
    required String postId,
    required String userId,
    required String postOwnerId,
    required String postImageUrl,
    required Map<String, dynamic> currentUserData,
  }) async {
    final likeRef =
    _db.collection('posts').doc(postId).collection('likes').doc(userId);
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

  Future<QuerySnapshot> getFeedPosts(String currentUserId, {DocumentSnapshot? lastDocument}) async {
    final userModel = await getUser(currentUserId);
    List<String> friendIds = userModel.friends;
    friendIds.add(currentUserId);

    if (friendIds.isEmpty) {
      return _db.collection('posts').where('userId', isEqualTo: 'nonexistent-user').get();
    }

    Query query = _db
        .collection('posts')
        .where('userId', whereIn: friendIds.take(30).toList())
        .orderBy('timestamp', descending: true)
        .limit(10);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.get();
  }

  Stream<QuerySnapshot> getUserPostsStream(String userId) {
    return _db
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<DocumentSnapshot> getPost(String postId) {
    return _db.collection('posts').doc(postId).get();
  }

  Stream<QuerySnapshot> getPostLikesStream(String postId) {
    return _db.collection('posts').doc(postId).collection('likes').snapshots();
  }

  Stream<QuerySnapshot> getPostCommentsStream(String postId, {int? limit}) {
    Query query = _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: true);
    if (limit != null) {
      query = query.limit(limit);
    }
    return query.snapshots();
  }

  Future<Map<String, int>> getPostStats(String postId) async {
    final likesSnapshot =
    await _db.collection('posts').doc(postId).collection('likes').get();
    final commentsSnapshot =
    await _db.collection('posts').doc(postId).collection('comments').get();
    return {'likes': likesSnapshot.size, 'comments': commentsSnapshot.size};
  }

  // --- Notification Methods ---
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
    final data = <String, dynamic>{
      'type': type,
      'fromUsername': fromUsername,
      'fromUserId': fromUserId,
      'fromUserPhotoUrl': fromUserPhotoUrl,
      'postId': postId,
      'postImageUrl': postImageUrl,
      'commentText': commentText,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    };

    if (type == 'friend_request_received') {
      data['status'] = 'pending';
    }

    return _db.collection('users').doc(userId).collection('notifications').add(data);
  }

  Stream<QuerySnapshot> getNotificationsStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  Stream<int> getUnreadNotificationCountStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markNotificationAsRead(String userId, String notificationId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  Future<bool> markAllNotificationsAsRead(String userId) async {
    final notificationsRef =
    _db.collection('users').doc(userId).collection('notifications');
    final unreadNotifications =
    await notificationsRef.where('read', isEqualTo: false).get();
    if (unreadNotifications.docs.isEmpty) return false;

    final batch = _db.batch();
    for (var doc in unreadNotifications.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
    return true;
  }

  // --- Chat Methods ---
  Future<void> startOrGetChat(BuildContext context, String otherUserId, String otherUsername) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final currentUser = FirebaseAuth.instance.currentUser!;
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

  Stream<QuerySnapshot> getChatsStream(String userId) {
    return _db
        .collection('chats')
        .where('users', arrayContains: userId)
        .orderBy('lastMessageTimestamp', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot> getChatStream(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }

  Stream<int> getUnreadChatCountStream(String userId) {
    return _db
        .collection('chats')
        .where('users', arrayContains: userId)
        .where('unreadCount.$userId', isGreaterThan: 0)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> resetUnreadCount(String chatId, String userId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .set({'unreadCount': {userId: 0}}, SetOptions(merge: true));
  }

  Future<void> updateTypingStatus(
      String chatId, String userId, bool isTyping) {
    return _db.collection('chats').doc(chatId).update({'typingStatus.$userId': isTyping});
  }

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
    final chatData = chatDoc.data() as Map<String, dynamic>;
    final chatType = chatData['chatType'] ?? 'friend';

    if (chatType == 'contact_request') {
      final initiatorId = chatData['initiatorId'];
      final messagesFromInitiator = await chatRef.collection('messages')
          .where('senderId', isEqualTo: initiatorId).count().get();

      if (senderId == initiatorId && (messagesFromInitiator.count ?? 0) >= 2) {
        throw Exception("You cannot send more than two messages until they reply.");
      }

      if (senderId != initiatorId) {
        await acceptContactRequest(
          chatId: chatId,
          currentUserId: senderId,
          requestingUserId: initiatorId,
        );
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

    final otherUserId = (chatData['users'] as List).firstWhere((id) => id != senderId);
    await chatRef.update({
      'lastMessage': imageUrl != null ? '📷 Photo' : text,
      'lastMessageIsImage': imageUrl != null,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'unreadCount.$otherUserId': FieldValue.increment(1),
    });
  }

  Future<void> editMessage(String chatId, String messageId, String newText) {
    final messageRef =
    _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
    return messageRef.update({
      'text': newText,
      'edited': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage(String chatId, String messageId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

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

  void markMessagesAsSeen(String chatId, String currentUserId,
      List<QueryDocumentSnapshot> messages) {
    final batch = _db.batch();
    for (var message in messages) {
      final messageData = message.data() as Map<String, dynamic>;
      if (messageData['senderId'] != currentUserId &&
          (messageData['isSeen'] == null || messageData['isSeen'] == false)) {
        batch.update(message.reference, {'isSeen': true});
      }
    }
    batch.commit();
  }

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

  Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

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

  // --- Match / Swipe Methods ---
  Future<List<DocumentSnapshot>> getPotentialMatches(
      String currentUserId) async {
    final userDoc = await _db.collection('users').doc(currentUserId).get();
    final currentUserCountry =
    (userDoc.data() as Map<String, dynamic>)['country'];
    final swipesSnapshot = await _db
        .collection('users')
        .doc(currentUserId)
        .collection('swipes')
        .get();
    final swipedUserIds = swipesSnapshot.docs.map((doc) => doc.id).toList();

    final querySnapshot = await _db
        .collection('users')
        .where('country', isEqualTo: currentUserCountry)
        .where('presence', isEqualTo: true)
        .limit(20)
        .get();

    return querySnapshot.docs
        .where((doc) => doc.id != currentUserId && !swipedUserIds.contains(doc.id))
        .toList();
  }

  Future<void> recordSwipe(
      String currentUserId, String otherUserId, String action) {
    return _db
        .collection('users')
        .doc(currentUserId)
        .collection('swipes')
        .doc(otherUserId)
        .set({
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> checkForMatch(String currentUserId, String otherUserId) async {
    final otherUserSwipe = await _db
        .collection('users')
        .doc(otherUserId)
        .collection('swipes')
        .doc(currentUserId)
        .get();
    return otherUserSwipe.exists && otherUserSwipe.data()?['action'] == 'smash';
  }

  Future<void> createMatch(String userId1, String userId2) async {
    final ids = [userId1, userId2]..sort();
    final chatId = ids.join('_');
    final user1Doc = await getUser(userId1);
    final user2Doc = await getUser(userId2);
    await _db.collection('chats').doc(chatId).set({
      'users': ids,
      'usernames': {
        userId1: user1Doc.username,
        userId2: user2Doc.username,
      },
      'lastMessage': 'You matched! Say hello.',
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<QuerySnapshot> getPaginatedUsers(
      {required int limit, DocumentSnapshot? lastDocument}) {
    Query query = _db.collection('users').orderBy('username').limit(limit);
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.get();
  }

  Future<List<DocumentSnapshot>> getRecommendedUsers(
      List<String> interests, String currentUserId) async {
    if (interests.isEmpty) return [];
    final querySnapshot = await _db
        .collection('users')
        .where('interests', arrayContainsAny: interests)
        .limit(30)
        .get();
    return querySnapshot.docs.where((doc) => doc.id != currentUserId).toList();
  }

  Stream<QuerySnapshot> searchUsers(String query) {
    return _db
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: query)
        .where('username', isLessThanOrEqualTo: '$query\uf8ff')
        .snapshots();
  }

  Future<void> syncNearbyContacts(String userId, List<String> contactIds) {
    return _db
        .collection('users')
        .doc(userId)
        .update({'nearbyContacts': FieldValue.arrayUnion(contactIds)});
  }
}
