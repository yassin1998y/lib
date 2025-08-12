import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

// Enum to handle different types of rewards.
enum RewardType { badge, coins, superLikes, profileBoost }

/// A model representing a single reward on the seasonal pass track.
class SeasonPassReward extends Equatable {
  final int level; // The season level required to unlock
  final String title;
  final RewardType type;
  final int amount; // e.g., number of coins or super likes

  const SeasonPassReward({
    required this.level,
    required this.title,
    required this.type,
    this.amount = 0,
  });

  /// Creates a `SeasonPassReward` instance from a Firestore `DocumentSnapshot`.
  factory SeasonPassReward.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SeasonPassReward(
      level: data['level'] ?? 0,
      title: data['title'] ?? 'Unnamed Reward',
      type: RewardType.values.firstWhere(
            (e) => e.toString() == 'RewardType.${data['type']}',
        orElse: () => RewardType.badge,
      ),
      amount: data['amount'] ?? 0,
    );
  }

  // Helper to get an icon for the UI based on the reward type.
  IconData get icon {
    switch (type) {
      case RewardType.coins:
        return Icons.monetization_on;
      case RewardType.superLikes:
        return Icons.star;
      case RewardType.profileBoost:
        return Icons.trending_up;
      case RewardType.badge:
        return Icons.shield;
      default:
        return Icons.card_giftcard;
    }
  }

  @override
  List<Object?> get props => [level, title, type, amount];
}
