import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A model representing the definition of a daily task.
class DailyTask extends Equatable {
  final String id;
  final String title;
  final String description;
  final int xpReward;
  final int coinReward;
  final int requiredCount;

  const DailyTask({
    required this.id,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.coinReward,
    required this.requiredCount,
  });

  /// Creates a `DailyTask` instance from a Firestore `DocumentSnapshot`.
  factory DailyTask.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return DailyTask(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      xpReward: data['xpReward'] ?? 0,
      coinReward: data['coinReward'] ?? 0,
      requiredCount: data['requiredCount'] ?? 1,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    xpReward,
    coinReward,
    requiredCount,
  ];
}
