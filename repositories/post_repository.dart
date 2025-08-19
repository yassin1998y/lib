import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freegram/repositories/gamification_repository.dart';
import 'package:freegram/repositories/notification_repository.dart';
import 'package:freegram/repositories/task_repository.dart';
import 'package:freegram/repositories/user_repository.dart';

/// A repository dedicated to post and comment-related Firestore operations.
class PostRepository {
  final FirebaseFirestore _db;
  final UserRepository _userRepository;
  final GamificationRepository _gamificationRepository;
  final TaskRepository _taskRepository;
  final NotificationRepository _notificationRepository;

  PostRepository({
    FirebaseFirestore? firestore,
    required UserRepository userRepository,
    required GamificationRepository gamificationRepository,
    required TaskRepository taskRepository,
    required NotificationRepository notificationRepository,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _userRepository = userRepository,
        _gamificationRepository = gamificationRepository,
        _taskRepository = taskRepository,
        _notificationRepository = notificationRepository;

  Future<void> createPost({
    required String userId,
    required String username,
    required String caption,
    required String imageUrl,
    String? thumbnailUrl,
    required String postType,
  }) async {
    await _db.collection('posts').add({
      'userId': userId,
      'username': username,
      'caption': caption,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'postType': postType,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _gamificationRepository.addXp(userId, 25, isSeasonal: true);
    await _taskRepository.updateTaskProgress(userId, 'create_post', 1);
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
        await _gamificationRepository.addXp(postOwnerId, 5, isSeasonal: true);
        await _notificationRepository.addNotification(
          userId: postOwnerId,
          type: 'like',
          fromUsername: currentUserData['displayName'] ?? 'Anonymous',
          fromUserId: userId,
          fromUserPhotoUrl: currentUserData['photoURL'],
          postId: postId,
          postImageUrl: postImageUrl,
        );
      }
      await _taskRepository.updateTaskProgress(userId, 'like_posts', 1);
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
      await _gamificationRepository.addXp(postData['userId'], 10, isSeasonal: true);
      await _notificationRepository.addNotification(
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
    final userModel = await _userRepository.getUser(currentUserId);
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

  Future<QuerySnapshot> getReelPosts(
      {DocumentSnapshot? lastDocument, int limit = 10}) async {
    Query query = _db
        .collection('posts')
        .where('postType', isEqualTo: 'reel')
        .orderBy('timestamp', descending: true)
        .limit(limit);

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
}
