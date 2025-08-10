import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/screens/comments_screen.dart';
import 'package:freegram/screens/post_detail_screen.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';

class PostCard extends StatefulWidget {
  final DocumentSnapshot post;
  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Future<void> _toggleLike() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final postData = widget.post.data() as Map<String, dynamic>;
    try {
      await context.read<FirestoreService>().togglePostLike(
        postId: widget.post.id,
        userId: currentUser.uid,
        postOwnerId: postData['userId'],
        postImageUrl: postData['imageUrl'],
        currentUserData: {
          'displayName': currentUser.displayName,
          'photoURL': currentUser.photoURL,
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e')),
        );
      }
    }
  }

  Future<void> _deletePost() async {
    final messenger = ScaffoldMessenger.of(context);

    final bool? shouldDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('Are you sure you want to permanently delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await context.read<FirestoreService>().deletePost(widget.post.id);
        messenger.showSnackBar(const SnackBar(content: Text('Post deleted')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Error deleting post: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();
    final postData = widget.post.data() as Map<String, dynamic>;
    final String username = postData['username'] ?? 'Anonymous';
    final String userId = postData['userId'] ?? '';
    final String imageUrl = postData['imageUrl'] ?? 'https://placehold.co/600x400/E5E5E5/333333?text=No+Image';
    final String caption = postData['caption'] ?? '';
    final bool isReel = postData['postType'] == 'reel';
    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isOwner = currentUser?.uid == userId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))),
                  child: Row(
                    children: [
                      StreamBuilder<UserModel>(
                        // FIX: Renamed getUserStream to getUserStream
                        stream: firestoreService.getUserStream(userId),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const CircleAvatar(radius: 18, backgroundColor: Colors.grey);
                          }
                          final user = snapshot.data!;
                          final photoUrl = user.photoUrl;
                          return CircleAvatar(
                            radius: 18,
                            backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                            child: (photoUrl.isEmpty)
                                ? Text(username.isNotEmpty ? username[0].toUpperCase() : 'A', style: const TextStyle(color: Colors.white))
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 12.0),
                      Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Spacer(),
                if (isOwner)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: _deletePost,
                  )
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postSnapshot: widget.post)));
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 300,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(height: 300, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator()));
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(height: 300, color: Colors.grey[200], child: const Icon(Icons.error, color: Colors.red));
                  },
                ),
                if (isReel)
                  const Icon(Icons.play_circle_outline, color: Colors.white, size: 60),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: firestoreService.getPostLikesStream(widget.post.id),
            builder: (context, snapshot) {
              final likesCount = snapshot.data?.docs.length ?? 0;
              final userHasLiked = snapshot.data?.docs.any((doc) => doc.id == currentUser?.uid) ?? false;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            userHasLiked ? Icons.favorite : Icons.favorite_border,
                            color: userHasLiked ? const Color(0xFFE74C3C) : Colors.black87,
                          ),
                          onPressed: _toggleLike,
                        ),
                        IconButton(
                            icon: const Icon(Icons.chat_bubble_outline),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: widget.post.id)))
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text('$likesCount likes', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(text: '$username ', style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: caption),
                    ],
                  ),
                ),
                const SizedBox(height: 8.0),
                StreamBuilder<QuerySnapshot>(
                  stream: firestoreService.getPostCommentsStream(widget.post.id, limit: 2),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: widget.post.id))),
                          child: Text('View all comments', style: TextStyle(color: Colors.grey[600]))
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: snapshot.data!.docs.map((doc) {
                        final commentData = doc.data() as Map<String, dynamic>;
                        return RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context).style.copyWith(color: Colors.grey[700]),
                            children: [
                              TextSpan(text: '${commentData['username'] ?? 'user'} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: commentData['text'] ?? ''),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
