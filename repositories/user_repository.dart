import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/gamification_repository.dart';
import 'package:freegram/repositories/notification_repository.dart';

/// A repository dedicated to user and friend-related Firestore operations.
class UserRepository {
  final FirebaseFirestore _db;
  final rtdb.FirebaseDatabase _rtdb;
  // UPDATED: Now depends on the new repositories for cross-domain logic.
  final NotificationRepository _notificationRepository;
  final GamificationRepository _gamificationRepository;

  UserRepository({
    FirebaseFirestore? firestore,
    rtdb.FirebaseDatabase? rtdbInstance,
    required NotificationRepository notificationRepository,
    required GamificationRepository gamificationRepository,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _rtdb = rtdbInstance ?? rtdb.FirebaseDatabase.instance,
        _notificationRepository = notificationRepository,
        _gamificationRepository = gamificationRepository;

  // --- User Profile Methods ---

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

  // --- Friendship Methods ---

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
    // UPDATED: Calls NotificationRepository
    await _notificationRepository.addNotification(
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

    // UPDATED: Calls GamificationRepository
    await _gamificationRepository.addXp(currentUserId, 50, isSeasonal: true);
    await _gamificationRepository.addXp(requestingUserId, 50, isSeasonal: true);

    final currentUser = await getUser(currentUserId);
    // UPDATED: Calls NotificationRepository
    await _notificationRepository.addNotification(
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
    // This is a temporary solution. Ideally, the ChatRepository would handle chat deletion.
    await _db.collection('chats').doc(chatId).delete();
  }

  Future<void> unblockUser(String currentUserId, String userToUnblockId) {
    return _db.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayRemove([userToUnblockId])
    });
  }

  // --- Match / Swipe Methods ---

  Future<List<DocumentSnapshot>> getPotentialMatches(
      String currentUserId) async {
    final swipesSnapshot = await _db
        .collection('users')
        .doc(currentUserId)
        .collection('swipes')
        .get();
    final swipedUserIds = swipesSnapshot.docs.map((doc) => doc.id).toList();

    final querySnapshot = await _db.collection('users').limit(50).get();

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
      // UPDATED: Calls NotificationRepository
      await _notificationRepository.addNotification(
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

    // UPDATED: Calls GamificationRepository
    await _gamificationRepository.addXp(userId1, 100, isSeasonal: true);
    await _gamificationRepository.addXp(userId2, 100, isSeasonal: true);
  }

  // --- User Discovery Methods ---

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
}
