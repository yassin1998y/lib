import 'package:card_swiper/card_swiper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  List<DocumentSnapshot> _potentialMatches = [];
  bool _isLoading = true;
  final SwiperController _swiperController = SwiperController();

  @override
  void initState() {
    super.initState();
    _fetchPotentialMatches();
  }

  /// Fetches a list of potential matches from the FirestoreService.
  Future<void> _fetchPotentialMatches() async {
    setState(() => _isLoading = true);
    final currentUser = FirebaseAuth.instance.currentUser!;
    try {
      final matches = await context.read<FirestoreService>().getPotentialMatches(currentUser.uid);
      if (mounted) {
        setState(() {
          _potentialMatches = matches;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint("Error fetching potential matches: $e");
    }
  }

  /// Records a swipe action and checks for a match.
  Future<void> _onSwipe(int index, String action) async {
    if (index >= _potentialMatches.length) return;

    final currentUser = FirebaseAuth.instance.currentUser!;
    final otherUser = _potentialMatches[index];
    final otherUserId = otherUser.id;

    // Use the centralized service to record the swipe
    await context.read<FirestoreService>().recordSwipe(currentUser.uid, otherUserId, action);

    if (action == 'smash') {
      // Use the centralized service to check for a match
      final isMatch = await context.read<FirestoreService>().checkForMatch(currentUser.uid, otherUserId);
      if (isMatch && mounted) {
        // Use the centralized service to create the chat/match document
        await context.read<FirestoreService>().createMatch(currentUser.uid, otherUserId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('It\'s a Match with ${otherUser['username']}!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a Match'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _potentialMatches.isEmpty
          ? const Center(child: Text('No new users to match with right now. Check back later!'))
          : Column(
        children: [
          Expanded(
            child: Swiper(
              controller: _swiperController,
              itemCount: _potentialMatches.length,
              itemBuilder: (context, index) {
                final userDoc = _potentialMatches[index];
                return MatchCard(userDoc: userDoc);
              },
              loop: false,
              viewportFraction: 0.85,
              scale: 0.9,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'pass_button',
                  onPressed: () {
                    _onSwipe(_swiperController.index, 'pass');
                    _swiperController.next();
                  },
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.close, color: Colors.red, size: 30),
                ),
                FloatingActionButton(
                  heroTag: 'smash_button',
                  onPressed: () {
                    _onSwipe(_swiperController.index, 'smash');
                    _swiperController.next();
                  },
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.favorite, color: Colors.green, size: 30),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card widget for displaying a potential match.
class MatchCard extends StatelessWidget {
  final DocumentSnapshot userDoc;
  const MatchCard({super.key, required this.userDoc});

  @override
  Widget build(BuildContext context) {
    final userData = userDoc.data() as Map<String, dynamic>;
    final photoUrl = userData['photoUrl'] ?? '';
    final username = userData['username'] ?? 'User';
    final age = userData['age'] ?? 0;
    final interests = List<String>.from(userData['interests'] ?? []);

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photoUrl.isNotEmpty)
            Image.network(photoUrl, fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$username, $age',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (interests.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: interests.take(3).map((interest) => Chip(
                      label: Text(interest),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      labelStyle: const TextStyle(color: Colors.white),
                    )).toList(),
                  )
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}
