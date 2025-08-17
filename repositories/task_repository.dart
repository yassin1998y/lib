import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:freegram/models/daily_task.dart';
import 'package:freegram/models/task_progress.dart';
import 'package:freegram/repositories/gamification_repository.dart';

/// A repository dedicated to daily tasks and user progress.
class TaskRepository {
  final FirebaseFirestore _db;
  // This repository will depend on the GamificationRepository to grant XP.
  final GamificationRepository _gamificationRepository;

  TaskRepository({
    FirebaseFirestore? firestore,
    required GamificationRepository gamificationRepository,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _gamificationRepository = gamificationRepository;

  /// Fetches the definitions for all available daily tasks.
  Future<List<DailyTask>> getDailyTasks() async {
    final snapshot = await _db.collection('daily_tasks').get();
    return snapshot.docs.map((doc) => DailyTask.fromDoc(doc)).toList();
  }

  /// Provides a stream of a user's progress on their daily tasks.
  Stream<QuerySnapshot> getUserTaskProgressStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('task_progress')
        .snapshots();
  }

  /// Updates a user's progress on a specific task and grants rewards if completed.
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

      // Reset progress if it's a new day
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
        return; // Don't update a completed task
      }

      final newProgressCount = progress.progress + increment;

      if (newProgressCount >= taskDef.requiredCount) {
        // Task completed
        final updatedProgress = TaskProgress(
          taskId: taskId,
          progress: newProgressCount,
          isCompleted: true,
          lastUpdated: now,
        );
        transaction.set(taskRef, updatedProgress.toMap());

        // Grant rewards
        await _gamificationRepository.addXp(userId, taskDef.xpReward, isSeasonal: true);
        final userRef = _db.collection('users').doc(userId);
        transaction
            .update(userRef, {'coins': FieldValue.increment(taskDef.coinReward)});
      } else {
        // Task in progress
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
}
