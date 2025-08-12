import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A type-safe, predictable model for representing user data across the app.
class UserModel extends Equatable {
  final String id;
  final String username;
  final String email;
  final String photoUrl;
  final String bio;
  final String fcmToken;
  final bool presence;
  final DateTime lastSeen;
  final String country;
  final int age;
  final String gender;
  final List<String> interests;
  final DateTime createdAt;

  // --- Friendship & Relationship Fields ---
  final List<String> friends;
  final List<String> friendRequestsSent;
  final List<String> friendRequestsReceived;
  final List<String> blockedUsers;

  // --- Store & Inventory Fields ---
  final int coins;
  final int superLikes;
  final DateTime lastFreeSuperLike;

  // --- Lifetime Level & XP Fields ---
  final int xp;
  final int level;

  // --- NEW: Seasonal Pass Fields ---
  final String currentSeasonId;
  final int seasonXp;
  final int seasonLevel;
  final List<int> claimedSeasonRewards; // List of claimed reward levels

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.photoUrl = '',
    this.bio = '',
    this.fcmToken = '',
    this.presence = false,
    required this.lastSeen,
    this.country = '',
    this.age = 0,
    this.gender = '',
    this.interests = const [],
    required this.createdAt,
    this.friends = const [],
    this.friendRequestsSent = const [],
    this.friendRequestsReceived = const [],
    this.blockedUsers = const [],
    this.coins = 0,
    this.superLikes = 1,
    required this.lastFreeSuperLike,
    this.xp = 0,
    this.level = 1,
    this.currentSeasonId = '',
    this.seasonXp = 0,
    this.seasonLevel = 0,
    this.claimedSeasonRewards = const [],
  });

  static DateTime _toDateTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<String> _getList(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is List) {
      return List<String>.from(value);
    }
    if (value is Map) {
      return value.keys.toList().cast<String>();
    }
    return [];
  }

  // Helper to safely convert a list of dynamics (from Firestore) to a list of ints.
  static List<int> _getIntList(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is List) {
      return List<int>.from(value);
    }
    return [];
  }

  /// Creates a `UserModel` instance from a Firestore `DocumentSnapshot`.
  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      id: doc.id,
      username: data['username'] ?? 'Anonymous',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      bio: data['bio'] ?? '',
      fcmToken: data['fcmToken'] ?? '',
      presence: data['presence'] ?? false,
      lastSeen: _toDateTime(data['lastSeen']),
      country: data['country'] ?? '',
      age: data['age'] ?? 0,
      gender: data['gender'] ?? '',
      interests: _getList(data, 'interests'),
      createdAt: _toDateTime(data['createdAt']),
      friends: _getList(data, 'friends'),
      friendRequestsSent: _getList(data, 'friendRequestsSent'),
      friendRequestsReceived: _getList(data, 'friendRequestsReceived'),
      blockedUsers: _getList(data, 'blockedUsers'),
      coins: data['coins'] ?? 0,
      superLikes: data['superLikes'] ?? 1,
      lastFreeSuperLike: _toDateTime(data['lastFreeSuperLike']),
      xp: data['xp'] ?? 0,
      level: data['level'] ?? 1,
      currentSeasonId: data['currentSeasonId'] ?? '',
      seasonXp: data['seasonXp'] ?? 0,
      seasonLevel: data['seasonLevel'] ?? 0,
      claimedSeasonRewards: _getIntList(data, 'claimedSeasonRewards'),
    );
  }

  /// Creates a `UserModel` instance from a standard Map.
  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      username: data['username'] ?? 'Anonymous',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      bio: data['bio'] ?? '',
      fcmToken: data['fcmToken'] ?? '',
      presence: data['presence'] ?? false,
      lastSeen: _toDateTime(data['lastSeen']),
      country: data['country'] ?? '',
      age: data['age'] ?? 0,
      gender: data['gender'] ?? '',
      interests: _getList(data, 'interests'),
      createdAt: _toDateTime(data['createdAt']),
      friends: _getList(data, 'friends'),
      friendRequestsSent: _getList(data, 'friendRequestsSent'),
      friendRequestsReceived: _getList(data, 'friendRequestsReceived'),
      blockedUsers: _getList(data, 'blockedUsers'),
      coins: data['coins'] ?? 0,
      superLikes: data['superLikes'] ?? 1,
      lastFreeSuperLike: _toDateTime(data['lastFreeSuperLike']),
      xp: data['xp'] ?? 0,
      level: data['level'] ?? 1,
      currentSeasonId: data['currentSeasonId'] ?? '',
      seasonXp: data['seasonXp'] ?? 0,
      seasonLevel: data['seasonLevel'] ?? 0,
      claimedSeasonRewards: _getIntList(data, 'claimedSeasonRewards'),
    );
  }

  /// Converts a `UserModel` instance into a `Map` for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'email': email,
      'photoUrl': photoUrl,
      'bio': bio,
      'fcmToken': fcmToken,
      'presence': presence,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'country': country,
      'age': age,
      'gender': gender,
      'interests': interests,
      'createdAt': Timestamp.fromDate(createdAt),
      'friends': friends,
      'friendRequestsSent': friendRequestsSent,
      'friendRequestsReceived': friendRequestsReceived,
      'blockedUsers': blockedUsers,
      'coins': coins,
      'superLikes': superLikes,
      'lastFreeSuperLike': Timestamp.fromDate(lastFreeSuperLike),
      'xp': xp,
      'level': level,
      'currentSeasonId': currentSeasonId,
      'seasonXp': seasonXp,
      'seasonLevel': seasonLevel,
      'claimedSeasonRewards': claimedSeasonRewards,
    };
  }

  @override
  List<Object?> get props => [
    id,
    username,
    email,
    photoUrl,
    bio,
    fcmToken,
    presence,
    lastSeen,
    country,
    age,
    gender,
    interests,
    createdAt,
    friends,
    friendRequestsSent,
    friendRequestsReceived,
    blockedUsers,
    coins,
    superLikes,
    lastFreeSuperLike,
    xp,
    level,
    currentSeasonId,
    seasonXp,
    seasonLevel,
    claimedSeasonRewards,
  ];
}
