import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A type-safe, predictable model for representing user data across the app.
/// This model simplifies the data structure and provides robust type safety.
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

  // --- New, Simplified Friendship & Relationship Fields ---
  final List<String> friends;
  final List<String> friendRequestsSent;
  final List<String> friendRequestsReceived;
  final List<String> blockedUsers;

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
  });

  // Helper to safely convert Timestamps to DateTime
  static DateTime _toDateTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// **FIX**: This function is now backward-compatible.
  /// It can handle the old data structure (Map) and the new one (List).
  static List<String> _getList(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is List) {
      return List<String>.from(value);
    }
    // If the data is in the old Map format, get the keys and convert to a list.
    if (value is Map) {
      return value.keys.toList().cast<String>();
    }
    return []; // Default to an empty list if null or another type.
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
    };
  }

  @override
  List<Object?> get props => [
    id, username, email, photoUrl, bio, fcmToken, presence, lastSeen,
    country, age, gender, interests, createdAt, friends,
    friendRequestsSent, friendRequestsReceived, blockedUsers,
  ];
}
