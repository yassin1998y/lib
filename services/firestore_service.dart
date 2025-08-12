import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/material.dart';
import 'package:freegram/models/daily_task.dart';
import 'package:freegram/models/season_model.dart';
import 'package:freegram/models/season_pass_reward.dart';
import 'package:freegram/models/task_progress.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/screens/chat_screen.dart';
import 'package:freegram/screens/friends_list_screen.dart';
import 'package:freegram/screens/level_pass_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

/// A centralized service for all Firestore and Firebase operations.
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

  // --- User & Friend Methods ---

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
      lastFreeSuperLike: DateTime.now().subtract(const Duration(days: 1)),
    );
    return _db.collection('users').doc(uid).set(newUser.toMap());
  }

  Future<UserModel> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) {
      throw Exception('User not found');
    }
    return UserModel.fromDoc(doc);
  }

  Stream<UserModel> getUserStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => UserModel.fromDoc(doc));
  }

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

  Future<void> sendFriendRequest(String fromUserId, String toUserId) async {
    final batch = _db.batch();
    final fromUserRef = _db.collection('users').doc(fromUserId);
    final toUserRef = _db.collection('users').doc(toUserId);

    batch.update(fromUserRef, {
      'friendRequestsSent': FieldValue.arrayUnion([toUserId])
    });
    batch.update(toUserRef, {
      'friendRequestsReceived': FieldValue.arrayUnion([fromUserId])
    });

    await batch.commit();

    final fromUser = await getUser(fromUserId);
    await addNotification(
      userId: toUserId,
      type: 'friend_request_received',
      fromUserId: fromUserId,
      fromUsername: fromUser.username,
      fromUserPhotoUrl: fromUser.photoUrl,
    );
  }

  Future<void> acceptFriendRequest(
      String currentUserId, String requestingUserId) async {
    final batch = _db.batch();
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final requestingUserRef = _db.collection('users').doc(requestingUserId);

    batch.update(currentUserRef, {
      'friendRequestsReceived': FieldValue.arrayRemove([requestingUserId]),
      'friends': FieldValue.arrayUnion([requestingUserId])
    });
    batch.update(requestingUserRef, {
      'friendRequestsSent': FieldValue.arrayRemove([currentUserId]),
      'friends': FieldValue.arrayUnion([currentUserId])
    });

    final ids = [currentUserId, requestingUserId]..sort();
    final chatId = ids.join('_');
    final chatRef = _db.collection('chats').doc(chatId);
    batch.set(chatRef, {'chatType': 'friend_chat'}, SetOptions(merge: true));

    await batch.commit();

    await addXp(currentUserId, 50, isSeasonal: true);
    await addXp(requestingUserId, 50, isSeasonal: true);

    final currentUser = await getUser(currentUserId);
    await addNotification(
      userId: requestingUserId,
      type: 'request_accepted',
      fromUserId: currentUserId,
      fromUsername: currentUser.username,
      fromUserPhotoUrl: currentUser.photoUrl,
    );
  }

  Future<void> declineFriendRequest(
      String currentUserId, String requestingUserId) async {
    final batch = _db.batch();
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final requestingUserRef = _db.collection('users').doc(requestingUserId);

    batch.update(currentUserRef, {
      'friendRequestsReceived': FieldValue.arrayRemove([requestingUserId])
    });
    batch.update(requestingUserRef, {
      'friendRequestsSent': FieldValue.arrayRemove([currentUserId])
    });

    final ids = [currentUserId, requestingUserId]..sort();
    final chatId = ids.join('_');
    final chatRef = _db.collection('chats').doc(chatId);
    batch.delete(chatRef);

    await batch.commit();
  }

  Future<void> removeFriend(String currentUserId, String friendId) async {
    final batch = _db.batch();
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final friendUserRef = _db.collection('users').doc(friendId);

    batch.update(currentUserRef, {
      'friends': FieldValue.arrayRemove([friendId])
    });
    batch.update(friendUserRef, {
      'friends': FieldValue.arrayRemove([currentUserId])
    });

    await batch.commit();
  }

  Future<void> blockUser(String currentUserId, String userToBlockId) async {
    await removeFriend(currentUserId, userToBlockId);
    await _db.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayUnion([userToBlockId])
    });
    final ids = [currentUserId, userToBlockId]..sort();
    final chatId = ids.join('_');
    await deleteChat(chatId);
  }

  Future<void> unblockUser(String currentUserId, String userToUnblockId) {
    return _db.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayRemove([userToUnblockId])
    });
  }

  // --- Store & Reward Methods ---

  Future<void> grantAdReward(String userId) {
    return _db.collection('users').doc(userId).update({
      'superLikes': FieldValue.increment(1),
    });
  }

  Future<void> purchaseWithCoins(String userId,
      {required int coinCost, required int superLikeAmount}) async {
    final userRef = _db.collection('users').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        throw Exception("User does not exist!");
      }
      final user = UserModel.fromDoc(snapshot);

      if (user.coins < coinCost) {
        throw Exception("Not enough coins.");
      }

      transaction.update(userRef, {
        'coins': FieldValue.increment(-coinCost),
        'superLikes': FieldValue.increment(superLikeAmount),
      });
    });
  }

  // --- Post & Comment Methods ---
  Future<void> createPost({
    required String userId,
    required String username,
    required String caption,
    required String imageUrl,
    required String postType,
  }) async {
    await _db.collection('posts').add({
      'userId': userId,
      'username': username,
      'caption': caption,
      'imageUrl': imageUrl,
      'postType': postType,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await addXp(userId, 25, isSeasonal: true);
    await updateTaskProgress(userId, 'create_post', 1);
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
        await addXp(postOwnerId, 5, isSeasonal: true);
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
      await updateTaskProgress(userId, 'like_posts', 1);
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
      await addXp(postData['userId'], 10, isSeasonal: true);
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

  Future<QuerySnapshot> getFeedPosts(String currentUserId,
      {DocumentSnapshot? lastDocument}) async {
    final userModel = await getUser(currentUserId);
    List<String> friendIds = userModel.friends;
    friendIds.add(currentUserId);

    if (friendIds.isEmpty) {
      return _db
          .collection('posts')
          .where('userId', isEqualTo: 'nonexistent-user')
          .get();
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
    final commentsSnapshot = await _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .get();
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

    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add(data);
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
  Future<void> startOrGetChat(
      BuildContext context, String otherUserId, String otherUsername) async {
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
    return _db
        .collection('chats')
        .doc(chatId)
        .update({'typingStatus.$userId': isTyping});
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

    await addXp(senderId, 2, isSeasonal: true);
    await updateTaskProgress(senderId, 'send_messages', 1);
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
      String currentUserId, String otherUserId, String action) async {
    final userRef = _db.collection('users').doc(currentUserId);

    if (action == 'super_like') {
      final user = await getUser(currentUserId);
      if (user.superLikes < 1) {
        throw Exception("You have no Super Likes left.");
      }
      await userRef.update({'superLikes': FieldValue.increment(-1)});
    }

    await userRef.collection('swipes').doc(otherUserId).set({
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (action == 'super_like') {
      final currentUser = await getUser(currentUserId);
      await addNotification(
        userId: otherUserId,
        type: 'super_like',
        fromUserId: currentUserId,
        fromUsername: currentUser.username,
        fromUserPhotoUrl: currentUser.photoUrl,
      );
    }
  }

  Future<bool> checkForMatch(String currentUserId, String otherUserId) async {
    final otherUserSwipeDoc = await _db
        .collection('users')
        .doc(otherUserId)
        .collection('swipes')
        .doc(currentUserId)
        .get();

    if (!otherUserSwipeDoc.exists) {
      return false;
    }

    final otherUserAction = otherUserSwipeDoc.data()?['action'];
    return otherUserAction == 'smash' || otherUserAction == 'super_like';
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
      'chatType': 'friend_chat',
    }, SetOptions(merge: true));

    final batch = _db.batch();
    final user1Ref = _db.collection('users').doc(userId1);
    final user2Ref = _db.collection('users').doc(userId2);
    batch.update(user1Ref, {
      'friends': FieldValue.arrayUnion([userId2])
    });
    batch.update(user2Ref, {
      'friends': FieldValue.arrayUnion([userId1])
    });
    await batch.commit();

    await addXp(userId1, 100, isSeasonal: true);
    await addXp(userId2, 100, isSeasonal: true);
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
        .limit(50)
        .get();

    final candidates = querySnapshot.docs
        .where((doc) => doc.id != currentUserId)
        .map((doc) => UserModel.fromDoc(doc))
        .toList();

    candidates.sort((a, b) {
      final levelComparison = b.level.compareTo(a.level);
      if (levelComparison != 0) {
        return levelComparison;
      }

      final aSharedInterests =
          a.interests.where((i) => interests.contains(i)).length;
      final bSharedInterests =
          b.interests.where((i) => interests.contains(i)).length;
      return bSharedInterests.compareTo(aSharedInterests);
    });

    final sortedIds = candidates.map((u) => u.id).toList();
    final originalDocs =
    querySnapshot.docs.where((doc) => doc.id != currentUserId).toList();

    originalDocs.sort((a, b) {
      final aIndex = sortedIds.indexOf(a.id);
      final bIndex = sortedIds.indexOf(b.id);
      return aIndex.compareTo(bIndex);
    });

    return originalDocs.take(30).toList();
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

  // --- XP & Level Methods ---

  /// Adds XP to a user's lifetime and seasonal totals.
  Future<void> addXp(String userId, int amount, {bool isSeasonal = false}) async {
    final userRef = _db.collection('users').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) throw Exception("User does not exist!");

      final user = UserModel.fromDoc(snapshot);
      Map<String, dynamic> updates = {};

      // --- Lifetime XP and Level ---
      final newXp = user.xp + amount;
      final newLevel = 1 + (newXp ~/ 1000);
      updates['xp'] = newXp;
      if (newLevel > user.level) {
        updates['level'] = newLevel;
      }

      // --- Seasonal XP and Level ---
      if (isSeasonal) {
        final newSeasonXp = user.seasonXp + amount;
        final newSeasonLevel = 1 + (newSeasonXp ~/ 500); // Seasons level up faster
        updates['seasonXp'] = newSeasonXp;
        if (newSeasonLevel > user.seasonLevel) {
          updates['seasonLevel'] = newSeasonLevel;
        }
      }

      transaction.update(userRef, updates);
    });
  }

  // --- Daily Task Methods ---

  Future<List<DailyTask>> getDailyTasks() async {
    final snapshot = await _db.collection('daily_tasks').get();
    return snapshot.docs.map((doc) => DailyTask.fromDoc(doc)).toList();
  }

  Stream<QuerySnapshot> getUserTaskProgressStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('task_progress')
        .snapshots();
  }

  Future<void> updateTaskProgress(
      String userId, String taskId, int increment) async {
    final taskRef =
    _db.collection('users').doc(userId).collection('task_progress').doc(taskId);
    final taskDefDoc = await _db.collection('daily_tasks').doc(taskId).get();

    if (!taskDefDoc.exists) {
      debugPrint("Task definition for $taskId not found.");
      return;
    }
    final taskDef = DailyTask.fromDoc(taskDefDoc);

    return _db.runTransaction((transaction) async {
      final progressDoc = await transaction.get(taskRef);
      TaskProgress progress;

      if (!progressDoc.exists) {
        progress = TaskProgress(
            taskId: taskId,
            progress: 0,
            isCompleted: false,
            lastUpdated: DateTime.now());
      } else {
        progress = TaskProgress.fromDoc(progressDoc);
      }

      final now = DateTime.now();
      final lastUpdate = progress.lastUpdated;
      if (now.year > lastUpdate.year ||
          now.month > lastUpdate.month ||
          now.day > lastUpdate.day) {
        progress = TaskProgress(
            taskId: taskId,
            progress: 0,
            isCompleted: false,
            lastUpdated: now);
      }

      if (progress.isCompleted) {
        return;
      }

      final newProgressCount = progress.progress + increment;

      if (newProgressCount >= taskDef.requiredCount) {
        final updatedProgress = TaskProgress(
          taskId: taskId,
          progress: newProgressCount,
          isCompleted: true,
          lastUpdated: now,
        );
        transaction.set(taskRef, updatedProgress.toMap());

        await addXp(userId, taskDef.xpReward, isSeasonal: true);
        final userRef = _db.collection('users').doc(userId);
        transaction
            .update(userRef, {'coins': FieldValue.increment(taskDef.coinReward)});
      } else {
        final updatedProgress = TaskProgress(
          taskId: taskId,
          progress: newProgressCount,
          isCompleted: false,
          lastUpdated: now,
        );
        transaction.set(taskRef, updatedProgress.toMap());
      }
    });
  }

  // --- NEW: Seasonal Pass Methods ---

  /// Fetches the currently active season.
  Future<Season?> getCurrentSeason() async {
    final now = DateTime.now();
    final snapshot = await _db
        .collection('seasons')
        .where('startDate', isLessThanOrEqualTo: now)
        .orderBy('startDate', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final season = Season.fromDoc(snapshot.docs.first);

    // Check if the found season has already ended
    if (now.isAfter(season.endDate)) return null;

    return season;
  }

  /// Fetches the rewards for a specific season.
  Future<List<SeasonPassReward>> getRewardsForSeason(String seasonId) async {
    final snapshot = await _db
        .collection('seasons')
        .doc(seasonId)
        .collection('rewards')
        .orderBy('level')
        .get();
    return snapshot.docs.map((doc) => SeasonPassReward.fromDoc(doc)).toList();
  }

  /// Checks if a user needs to be reset for a new season and performs the reset.
  Future<void> checkAndResetSeason(String userId, Season currentSeason) async {
    final userRef = _db.collection('users').doc(userId);
    final user = await getUser(userId);

    if (user.currentSeasonId != currentSeason.id) {
      // New season! Reset the user's seasonal progress.
      await userRef.update({
        'currentSeasonId': currentSeason.id,
        'seasonXp': 0,
        'seasonLevel': 0,
        'claimedSeasonRewards': [],
      });
    }
  }

  /// Claims a specific reward from the seasonal pass for a user.
  Future<void> claimSeasonReward(String userId, SeasonPassReward reward) async {
    final userRef = _db.collection('users').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) throw Exception("User does not exist!");

      final user = UserModel.fromDoc(snapshot);

      if (user.seasonLevel < reward.level) {
        throw Exception("You have not reached the required level yet.");
      }
      if (user.claimedSeasonRewards.contains(reward.level)) {
        throw Exception("You have already claimed this reward.");
      }

      Map<String, dynamic> updates = {
        'claimedSeasonRewards': FieldValue.arrayUnion([reward.level])
      };

      switch (reward.type) {
        case RewardType.coins:
          updates['coins'] = FieldValue.increment(reward.amount);
          break;
        case RewardType.superLikes:
          updates['superLikes'] = FieldValue.increment(reward.amount);
          break;
        default:
          break;
      }

      transaction.update(userRef, updates);
    });
  }
}
