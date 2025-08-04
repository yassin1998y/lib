import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:math';

// NEW: Predefined list of interests for seeding.
const List<String> _possibleInterests = [
  'Photography', 'Traveling', 'Hiking', 'Reading', 'Gaming', 'Cooking',
  'Movies', 'Music', 'Art', 'Sports', 'Yoga', 'Coding', 'Writing',
  'Dancing', 'Gardening', 'Fashion', 'Fitness', 'History',
];

class DatabaseSeeder {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Random _random = Random();

  // Helper to get a random subset of interests
  List<String> _getRandomInterests() {
    final count = _random.nextInt(4) + 2; // Get 2 to 5 interests
    return (_possibleInterests.toList()..shuffle()).sublist(0, count);
  }

  // Helper to get random user data
  Map<String, dynamic> _getRandomUserData(String username, String email) {
    const countries = ['USA', 'Canada', 'UK', 'Germany', 'France', 'Tunisia', 'Egypt', 'Algeria', 'Morocco'];
    const genders = ['Male', 'Female'];
    final photoNumber = _random.nextInt(1000);

    return {
      'username': username,
      'email': email,
      'followers': [],
      'following': [],
      'bio': 'This is a sample bio for $username.',
      'photoUrl': 'https://picsum.photos/seed/$photoNumber/200/200',
      'fcmToken': '',
      'presence': _random.nextBool(),
      'lastSeen': FieldValue.serverTimestamp(),
      'country': countries[_random.nextInt(countries.length)],
      'age': _random.nextInt(43) + 18, // Age between 18 and 60
      'gender': genders[_random.nextInt(genders.length)],
      'interests': _getRandomInterests(), // NEW: Assign random interests
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> seedUsers(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(const SnackBar(content: Text('Seeding database... This may take a moment.')));

      final List<Map<String, String>> usersToCreate = [
        {'username': 'Alice', 'email': 'alice@example.com'},
        {'username': 'Bob', 'email': 'bob@example.com'},
        {'username': 'Charlie', 'email': 'charlie@example.com'},
        {'username': 'Diana', 'email': 'diana@example.com'},
        {'username': 'Eve', 'email': 'eve@example.com'},
        {'username': 'Frank', 'email': 'frank@example.com'},
        {'username': 'Grace', 'email': 'grace@example.com'},
        {'username': 'Heidi', 'email': 'heidi@example.com'},
        {'username': 'Ivan', 'email': 'ivan@example.com'},
        {'username': 'Judy', 'email': 'judy@example.com'},
        {'username': 'Klaus', 'email': 'klaus@example.com'},
        {'username': 'Liam', 'email': 'liam@example.com'},
        {'username': 'Mona', 'email': 'mona@example.com'},
        {'username': 'Nate', 'email': 'nate@example.com'},
        {'username': 'Olivia', 'email': 'olivia@example.com'},
        {'username': 'Peter', 'email': 'peter@example.com'},
        {'username': 'Quinn', 'email': 'quinn@example.com'},
        {'username': 'Rachel', 'email': 'rachel@example.com'},
        {'username': 'Steve', 'email': 'steve@example.com'},
        {'username': 'Tina', 'email': 'tina@example.com'},
      ];

      final batch = _firestore.batch();

      for (var user in usersToCreate) {
        final userData = _getRandomUserData(user['username']!, user['email']!);
        // We can't create users with passwords directly, so we'll just create their Firestore docs.
        // This assumes users would be created via the app's sign-up flow.
        // For testing, we can manually create these accounts in Firebase Auth.
        // The UID will be different, so this just creates profile documents.
        final userRef = _firestore.collection('users').doc(); // Create with a random ID
        batch.set(userRef, userData);
      }

      await batch.commit();
      messenger.showSnackBar(const SnackBar(content: Text('Database seeded successfully with 20 users!')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error seeding database: $e')));
    }
  }
}
