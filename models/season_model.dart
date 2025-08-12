import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A model representing a single season in the game.
class Season extends Equatable {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;

  const Season({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
  });

  /// Creates a `Season` instance from a Firestore `DocumentSnapshot`.
  factory Season.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Season(
      id: doc.id,
      title: data['title'] ?? 'Unnamed Season',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
    );
  }

  @override
  List<Object?> get props => [id, title, startDate, endDate];
}
