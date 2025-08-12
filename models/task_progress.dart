import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A model for tracking a user's progress on a single daily task.
class TaskProgress extends Equatable {
  final String taskId;
  final int progress;
  final bool isCompleted;
  final DateTime lastUpdated;

  const TaskProgress({
    required this.taskId,
    required this.progress,
    required this.isCompleted,
    required this.lastUpdated,
  });

  /// Creates a `TaskProgress` instance from a Firestore `DocumentSnapshot`.
  factory TaskProgress.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return TaskProgress(
      taskId: doc.id,
      progress: data['progress'] ?? 0,
      isCompleted: data['isCompleted'] ?? false,
      lastUpdated: (data['lastUpdated'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }

  /// Converts a `TaskProgress` instance into a `Map` for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'progress': progress,
      'isCompleted': isCompleted,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  @override
  List<Object?> get props => [taskId, progress, isCompleted, lastUpdated];
}
