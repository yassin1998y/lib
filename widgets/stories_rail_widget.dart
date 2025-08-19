import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/user_repository.dart';
import 'package:provider/provider.dart';

class StoriesRailWidget extends StatelessWidget {
  const StoriesRailWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    // In a real implementation, you would fetch friends who have active stories.
    // For now, we'll use the user's general friends list as placeholders.
    return FutureBuilder<UserModel>(
      future: context.read<UserRepository>().getUser(currentUser.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _LoadingSkeleton();
        }
        final user = snapshot.data!;
        final friends = user.friends;

        return Container(
          height: 110,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            itemCount: friends.length + 1, // +1 for the "Add Story" button
            itemBuilder: (context, index) {
              if (index == 0) {
                return _AddStoryButton(photoUrl: user.photoUrl);
              }
              final friendId = friends[index - 1];
              return _StoryAvatar(userId: friendId);
            },
          ),
        );
      },
    );
  }
}

class _AddStoryButton extends StatelessWidget {
  final String? photoUrl;
  const _AddStoryButton({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            SizedBox(
              height: 70,
              width: 70,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                    photoUrl != null && photoUrl!.isNotEmpty
                        ? NetworkImage(photoUrl!)
                        : null,
                    child: photoUrl == null || photoUrl!.isEmpty
                        ? const Icon(Icons.person,
                        size: 30, color: Colors.white)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.add_circle,
                          color: Colors.blue, size: 24),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Your Story",
              style: TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final String userId;
  const _StoryAvatar({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel>(
      future: context.read<UserRepository>().getUser(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  CircleAvatar(radius: 35, backgroundColor: Colors.grey),
                  SizedBox(height: 4),
                  Text("...", style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        }
        final user = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: SizedBox(
            width: 70,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3.0),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.orange, Colors.pink],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 30,
                      backgroundImage: user.photoUrl.isNotEmpty
                          ? NetworkImage(user.photoUrl)
                          : null,
                      child: user.photoUrl.isEmpty
                          ? Text(user.username.isNotEmpty
                          ? user.username[0].toUpperCase()
                          : '?')
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.username,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        itemCount: 6,
        itemBuilder: (context, index) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  CircleAvatar(radius: 35, backgroundColor: Colors.grey),
                  SizedBox(height: 4),
                  Text("...", style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
