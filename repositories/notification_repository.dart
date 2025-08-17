import 'package:cloud_firestore/cloud_firestore.dart';

/// A repository dedicated to handling all user notification operations.
class NotificationRepository {
  final FirebaseFirestore _db;

  NotificationRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

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

  /// Provides a stream of notifications for a specific user.
  Stream<QuerySnapshot> getNotificationsStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Provides a stream of the count of unread notifications.
  Stream<int> getUnreadNotificationCountStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Marks a single notification as read.
  Future<void> markNotificationAsRead(String userId, String notificationId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  /// Marks all of a user's unread notifications as read.
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
}
