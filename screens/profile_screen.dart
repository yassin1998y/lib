import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/friends_bloc/friends_bloc.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/screens/edit_profile_screen.dart';
import 'package:freegram/screens/friends_list_screen.dart'; // NEW: Import FriendsListScreen
import 'package:freegram/screens/level_pass_screen.dart';
import 'package:freegram/screens/tasks_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'post_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildStatItem(String label, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(count.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  /// Creates a visually distinct badge based on the user's level.
  Widget _getBadgeForLevel(int level) {
    Color startColor;
    Color endColor;
    String tier = level.toString(); // Default to level number

    if (level >= 25) {
      startColor = Colors.amber;
      endColor = Colors.orangeAccent;
      tier = '$level';
    } else if (level >= 15) {
      startColor = Colors.blueGrey.shade200;
      endColor = Colors.grey.shade400;
      tier = '$level';
    } else if (level >= 5) {
      startColor = const Color(0xFFCD7F32);
      endColor = Colors.orange.shade300;
      tier = '$level';
    } else {
      startColor = Colors.blue;
      endColor = Colors.lightBlueAccent;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Center(
        child: Text(
          tier,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inSeconds < 60) {
      return 'Last seen just now';
    }
    return 'Last seen ${timeago.format(lastSeen)}';
  }

  Future<void> _confirmRemoveFriend(
      BuildContext context, UserModel profileUser) async {
    final bool? shouldRemove = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Friend?'),
          content: Text(
              'Are you sure you want to remove ${profileUser.username} as a friend?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldRemove == true && mounted) {
      context.read<FriendsBloc>().add(RemoveFriend(profileUser.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();
    final isCurrentUserProfile =
        FirebaseAuth.instance.currentUser?.uid == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: StreamBuilder<UserModel>(
        stream: firestoreService.getUserStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('User not found.'));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final user = snapshot.data!;
          final String lastSeenText =
          user.presence ? 'Online' : _formatLastSeen(user.lastSeen);

          // --- XP Calculation for Circular Progress ---
          final xpForNextLevel = user.level * 1000;
          final currentLevelXp = (user.level - 1) * 1000;
          final xpInCurrentLevel = user.xp - currentLevelXp;
          final progressPercentage = (xpForNextLevel - currentLevelXp) > 0
              ? xpInCurrentLevel / (xpForNextLevel - currentLevelXp)
              : 0.0;

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 90,
                              height: 90,
                              child: Stack(
                                clipBehavior: Clip.none,
                                fit: StackFit.expand,
                                children: [
                                  CircularProgressIndicator(
                                    value: progressPercentage,
                                    strokeWidth: 5,
                                    backgroundColor: Colors.grey[300],
                                    valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        Colors.blue),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(5.0),
                                    child: CircleAvatar(
                                      backgroundColor: Colors.grey[200],
                                      backgroundImage: user.photoUrl.isNotEmpty
                                          ? NetworkImage(user.photoUrl)
                                          : null,
                                      child: user.photoUrl.isEmpty
                                          ? Text(
                                          user.username.isNotEmpty
                                              ? user.username[0]
                                              .toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              fontSize: 40))
                                          : null,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -5,
                                    right: -5,
                                    child: GestureDetector(
                                      onTap: () =>
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                              const LevelPassScreen(),
                                            ),
                                          ),
                                      child: _getBadgeForLevel(user.level),
                                    ),
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                                children: [
                                  // --- UPDATED: Made the stat item tappable ---
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                        const FriendsListScreen(),
                                      ),
                                    ),
                                    child: _buildStatItem(
                                        'Friends', user.friends.length),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(user.username,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            if (user.presence)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        if (lastSeenText.isNotEmpty && !user.presence) ...[
                          const SizedBox(height: 4),
                          Text(lastSeenText,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 14)),
                        ],
                        if (user.bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(user.bio,
                              style: const TextStyle(fontSize: 16)),
                        ],
                        const SizedBox(height: 16),
                        if (isCurrentUserProfile)
                          _buildCurrentUserActionButtons(context, user)
                        else
                          _buildOtherUserActionButtons(user),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.black,
                      tabs: const [
                        Tab(icon: Icon(Icons.grid_on)),
                        Tab(icon: Icon(Icons.bookmark_border)),
                      ],
                    ),
                  ),
                  pinned: true,
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildPostsGrid(firestoreService, widget.userId),
                const Center(child: Text('Saved posts will appear here.')),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentUserActionButtons(BuildContext context, UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EditProfileScreen(currentUserData: user.toMap()))),
          child: const Text('Edit Profile'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.task_alt),
          label: const Text('View Daily Tasks'),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TasksScreen())),
        ),
      ],
    );
  }

  Widget _buildOtherUserActionButtons(UserModel profileUser) {
    return BlocBuilder<FriendsBloc, FriendsState>(
      builder: (context, state) {
        if (state is FriendsLoaded) {
          final currentUser = state.user;
          Widget friendButton;
          bool isFriend = currentUser.friends.contains(profileUser.id);

          if (isFriend) {
            friendButton = Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Friends'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                onPressed: () => _confirmRemoveFriend(context, profileUser),
              ),
            );
          } else if (currentUser.friendRequestsSent.contains(profileUser.id)) {
            friendButton = Expanded(
              child: ElevatedButton(
                onPressed: null,
                child: const Text('Request Sent'),
              ),
            );
          } else if (currentUser.friendRequestsReceived
              .contains(profileUser.id)) {
            friendButton = Expanded(
              child: ElevatedButton(
                onPressed: () => context
                    .read<FriendsBloc>()
                    .add(AcceptFriendRequest(profileUser.id)),
                child: const Text('Accept Request'),
              ),
            );
          } else if (currentUser.blockedUsers.contains(profileUser.id)) {
            return SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () =>
                    context.read<FriendsBloc>().add(UnblockUser(profileUser.id)),
                child: const Text('Unblock'),
              ),
            );
          } else {
            friendButton = Expanded(
              child: ElevatedButton(
                onPressed: () => context
                    .read<FriendsBloc>()
                    .add(SendFriendRequest(profileUser.id)),
                child: const Text('Add Friend'),
              ),
            );
          }

          return Row(
            children: [
              friendButton,
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  child: const Text('Message'),
                  onPressed: () => context.read<FirestoreService>().startOrGetChat(
                      context, profileUser.id, profileUser.username),
                ),
              ),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildPostsGrid(FirestoreService service, String userId) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
        return Future.value();
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: service.getUserPostsStream(userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No posts yet.'));
          }

          final posts = snapshot.data!.docs;

          return GridView.builder(
            padding: const EdgeInsets.all(2.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final postData = post.data() as Map<String, dynamic>;
              final isReel = postData['postType'] == 'reel';

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PostDetailScreen(postSnapshot: post),
                  ));
                },
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    Image.network(
                      postData['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.error),
                    ),
                    if (isReel)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(Icons.play_circle_filled,
                            color: Colors.white, size: 24),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
