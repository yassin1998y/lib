import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:freegram/repositories/store_repository.dart';
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/screens/store_screen.dart';
import 'package:freegram/services/ad_helper.dart';
import 'package:freegram/widgets/draggable_card.dart';
import 'package:provider/provider.dart';
import 'match_animation_screen.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  final ValueNotifier<List<DocumentSnapshot>> _potentialMatches =
  ValueNotifier([]);
  bool _isLoading = true;
  String? _errorMessage;
  final GlobalKey<DraggableCardState> _cardKey = GlobalKey<DraggableCardState>();

  AdHelper? _adHelper;
  bool _isAdReady = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _adHelper = AdHelper();
      _adHelper!.loadRewardedAd(onAdLoaded: () {
        if (mounted) setState(() => _isAdReady = true);
      });
    }
    _fetchPotentialMatches();
  }

  @override
  void dispose() {
    _potentialMatches.dispose();
    super.dispose();
  }

  Future<void> _fetchPotentialMatches() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final currentUser = FirebaseAuth.instance.currentUser!;
    try {
      final matches = await context
          .read<UserRepository>()
          .getPotentialMatches(currentUser.uid);
      if (mounted) {
        _potentialMatches.value = matches;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Could not load matches. Please try again.";
        });
      }
      debugPrint("Error fetching potential matches: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onSwipe(String action, String otherUserId) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final userRepository = context.read<UserRepository>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await userRepository.recordSwipe(currentUser.uid, otherUserId, action);

      if (action == 'super_like') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Super Like Sent!"),
            backgroundColor: Colors.blue,
          ),
        );
      }

      if (action == 'smash' || action == 'super_like') {
        final isMatch =
        await userRepository.checkForMatch(currentUser.uid, otherUserId);
        if (isMatch && mounted) {
          final currentUserModel =
          await userRepository.getUser(currentUser.uid);
          final otherUserModel = await userRepository.getUser(otherUserId);

          await userRepository.createMatch(currentUser.uid, otherUserId);

          Navigator.of(context).push(
            PageRouteBuilder(
              opaque: false,
              pageBuilder: (context, _, __) => MatchAnimationScreen(
                currentUser: currentUserModel,
                matchedUser: otherUserModel,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (e.toString().contains("You have no Super Likes left.") && mounted) {
        _showOutOfSuperLikesDialog();
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text("An error occurred: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeTopCard(SwipeDirection direction) {
    if (_potentialMatches.value.isEmpty) return;

    final userDoc = _potentialMatches.value.first;
    final otherUserId = userDoc.id;
    String action;

    switch (direction) {
      case SwipeDirection.left:
        action = 'pass';
        break;
      case SwipeDirection.right:
        action = 'smash';
        break;
      case SwipeDirection.up:
        action = 'super_like';
        break;
      default:
        return;
    }

    _onSwipe(action, otherUserId);

    if (mounted) {
      setState(() {
        _potentialMatches.value = List.from(_potentialMatches.value)
          ..removeAt(0);
      });
    }
  }

  void _showOutOfSuperLikesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Out of Super Likes!"),
              content: const Text(
                  "Get more Super Likes from the store, or watch a short ad to get one for free."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StoreScreen()));
                  },
                  child: const Text("Go to Store"),
                ),
                if (_adHelper != null)
                  ElevatedButton(
                    onPressed: !_isAdReady
                        ? null
                        : () {
                      _adHelper!.showRewardedAd(() {
                        final currentUser =
                        FirebaseAuth.instance.currentUser!;
                        context
                            .read<StoreRepository>()
                            .grantAdReward(currentUser.uid);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              backgroundColor: Colors.green,
                              content: Text(
                                  "Success! 1 Super Like has been added.")),
                        );
                      });
                      setDialogState(() => _isAdReady = false);
                      _adHelper!.loadRewardedAd(onAdLoaded: () {
                        if (mounted) setDialogState(() => _isAdReady = true);
                      });
                    },
                    child: _isAdReady
                        ? const Text("Watch Ad (Free)")
                        : const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchPotentialMatches,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
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
          : _errorMessage != null
          ? _buildErrorState()
          : ValueListenableBuilder<List<DocumentSnapshot>>(
        valueListenable: _potentialMatches,
        builder: (context, matches, child) {
          if (matches.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'No new users right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchPotentialMatches,
                      child: const Text('Find More'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: List.generate(
                    min(matches.length, 3),
                        (index) {
                      final userDoc = matches[index];
                      final isTopCard = index == 0;

                      final card = isTopCard
                          ? DraggableCard(
                        key: _cardKey,
                        onSwipe: (direction) {
                          _removeTopCard(direction);
                        },
                        child: MatchCard(userDoc: userDoc),
                      )
                          : Transform.translate(
                        offset: Offset(0, 10.0 * index),
                        child: Transform.scale(
                          scale: 1 - (0.05 * index),
                          child: MatchCard(userDoc: userDoc),
                        ),
                      );

                      return card;
                    },
                  ).reversed.toList(),
                ),
              ),
              _buildActionButtons(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.close,
            color: Colors.red,
            onPressed: () =>
                _cardKey.currentState?.triggerSwipe(SwipeDirection.left),
          ),
          _buildActionButton(
            icon: Icons.star,
            color: Colors.blue,
            onPressed: () =>
                _cardKey.currentState?.triggerSwipe(SwipeDirection.up),
            isLarge: true,
          ),
          _buildActionButton(
            icon: Icons.favorite,
            color: Colors.green,
            onPressed: () =>
                _cardKey.currentState?.triggerSwipe(SwipeDirection.right),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool isLarge = false,
  }) {
    final size = isLarge ? 70.0 : 50.0;
    final iconSize = isLarge ? 40.0 : 25.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(76),
            spreadRadius: 2,
            blurRadius: 5,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: iconSize),
        onPressed: onPressed,
      ),
    );
  }
}

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
            Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.person, size: 80, color: Colors.grey),
              ),
            )
          else
            Container(
              color: Colors.grey[200],
              child: const Icon(Icons.person, size: 80, color: Colors.grey),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withAlpha(204)],
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
                    shadows: [
                      Shadow(blurRadius: 10.0, color: Colors.black54)
                    ],
                  ),
                ),
                if (interests.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: interests
                        .take(3)
                        .map((interest) => Chip(
                      label: Text(interest),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white.withAlpha(51),
                      labelStyle: const TextStyle(color: Colors.white),
                    ))
                        .toList(),
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
