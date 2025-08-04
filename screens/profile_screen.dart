import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freegram/screens/chat_screen.dart';
import 'package:freegram/screens/edit_profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';

import 'post_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // Adjusted to 2 tabs
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Toggles the follow status for a user.
  Future<void> _toggleFollow(String userIdToToggle, bool isCurrentlyFollowing) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final firestoreService = context.read<FirestoreService>();
      if (isCurrentlyFollowing) {
        await firestoreService.unfollowUser(currentUser.uid, userIdToToggle);
      } else {
        await firestoreService.followUser(currentUser.uid, userIdToToggle);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e')),
        );
      }
    }
  }

  /// Builds a tappable stat item for followers/following.
  Widget _buildStatItem(String label, int count, List<String> userIds) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FollowListScreen(
            title: label,
            userIds: userIds,
          ),
        ));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(count.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();
    final isCurrentUserProfile = FirebaseAuth.instance.currentUser?.uid == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: firestoreService.getUserStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('User not found.'));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final String username = userData['username'] ?? 'User';
          final String bio = userData['bio'] ?? '';
          final String photoUrl = userData['photoUrl'] ?? '';
          final List<String> followers = List<String>.from(userData['followers'] ?? []);
          final List<String> following = List<String>.from(userData['following'] ?? []);

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
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                              child: photoUrl.isEmpty ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40)) : null,
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildStatItem('Followers', followers.length, followers),
                                  _buildStatItem('Following', following.length, following),
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(bio, style: const TextStyle(fontSize: 16)),
                        ],
                        const SizedBox(height: 16),
                        if (isCurrentUserProfile)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen(currentUserData: userData))),
                              child: const Text('Edit Profile'),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: StreamBuilder<DocumentSnapshot>(
                                  stream: firestoreService.getUserStream(FirebaseAuth.instance.currentUser!.uid),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) return const SizedBox();
                                    final currentUserData = snapshot.data!.data() as Map<String, dynamic>;
                                    final bool isFollowing = (currentUserData['following'] as List).contains(widget.userId);
                                    return ElevatedButton(
                                      onPressed: () => _toggleFollow(widget.userId, isFollowing),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFollowing ? Colors.grey : const Color(0xFF3498DB),
                                      ),
                                      child: Text(isFollowing ? 'Following' : 'Follow', style: const TextStyle(color: Colors.white)),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => firestoreService.startChat(context, widget.userId, username),
                                  child: const Text('Message'),
                                ),
                              ),
                            ],
                          ),
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

  /// Builds the grid of user posts.
  Widget _buildPostsGrid(FirestoreService service, String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: service.getUserPostsStream(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No posts yet.'));

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
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                  ),
                  if (isReel)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.play_circle_filled, color: Colors.white, size: 24),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// A custom delegate for making the TabBar stick under the AppBar.
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
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

/// A screen to display a list of users (e.g., followers or following).
class FollowListScreen extends StatelessWidget {
  final String title;
  final List<String> userIds;

  const FollowListScreen({super.key, required this.title, required this.userIds});

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: userIds.isEmpty
          ? const Center(child: Text('No users to display.'))
          : ListView.builder(
        itemCount: userIds.length,
        itemBuilder: (context, index) {
          return FutureBuilder<DocumentSnapshot>(
            future: firestoreService.getUser(userIds[index]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const ListTile(title: Text('Loading...'));
              }
              final userData = snapshot.data!.data() as Map<String, dynamic>;
              final photoUrl = userData['photoUrl'];
              final username = userData['username'];

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?')
                      : null,
                ),
                title: Text(username),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userIds[index]))),
              );
            },
          );
        },
      ),
    );
  }
}
