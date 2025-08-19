import 'package:chewie/chewie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/post_repository.dart';
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/screens/comments_screen.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class ReelPlayerWidget extends StatefulWidget {
  final DocumentSnapshot post;

  const ReelPlayerWidget({super.key, required this.post});

  @override
  State<ReelPlayerWidget> createState() => _ReelPlayerWidgetState();
}

class _ReelPlayerWidgetState extends State<ReelPlayerWidget>
    with TickerProviderStateMixin {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _isHeartAnimating = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    final postData = widget.post.data() as Map<String, dynamic>;
    final videoUrl = postData['imageUrl'];

    if (videoUrl == null || videoUrl.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    await _videoPlayerController.initialize();

    if (mounted) {
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController,
          autoPlay: true,
          looping: true,
          showControls: false,
          aspectRatio: _videoPlayerController.value.aspectRatio,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLike({bool forceLike = false}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final postData = widget.post.data() as Map<String, dynamic>;
    final postRepository = context.read<PostRepository>();

    if (forceLike) {
      final likesSnapshot =
      await postRepository.getPostLikesStream(widget.post.id).first;
      final userHasLiked =
      likesSnapshot.docs.any((doc) => doc.id == currentUser.uid);
      if (userHasLiked) return;
    }

    try {
      await postRepository.togglePostLike(
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

  Future<void> _onDoubleTap() async {
    setState(() => _isHeartAnimating = true);
    _animationController.forward();
    await _toggleLike(forceLike: true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      _animationController.reverse();
      setState(() => _isHeartAnimating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_chewieController == null) {
      return const Center(
          child: Text("Could not load video.",
              style: TextStyle(color: Colors.white)));
    }

    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Chewie(controller: _chewieController!),
          _buildOverlay(),
          Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isHeartAnimating ? 1 : 0,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: const Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 100,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    final postData = widget.post.data() as Map<String, dynamic>;
    final String username = postData['username'] ?? 'Anonymous';
    final String userId = postData['userId'] ?? '';
    final String caption = postData['caption'] ?? '';
    final currentUser = FirebaseAuth.instance.currentUser;

    return Stack(
      children: [
        // Gradient for text readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.5),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withOpacity(0.7)
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.4, 0.6, 1.0],
            ),
          ),
        ),
        // Back Button
        Positioned(
          top: 40,
          left: 16,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        // Main Content Overlay
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // User info and caption
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StreamBuilder<UserModel>(
                              stream: context
                                  .read<UserRepository>()
                                  .getUserStream(userId),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.grey);
                                }
                                final user = snapshot.data!;
                                final photoUrl = user.photoUrl;
                                return GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              ProfileScreen(userId: userId))),
                                  child: CircleAvatar(
                                    radius: 20,
                                    backgroundImage: (photoUrl.isNotEmpty)
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child: (photoUrl.isEmpty)
                                        ? Text(username.isNotEmpty
                                        ? username[0].toUpperCase()
                                        : 'A')
                                        : null,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Text(
                              username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                shadows: [
                                  Shadow(blurRadius: 2, color: Colors.black54)
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          caption,
                          style: const TextStyle(
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 2, color: Colors.black54)
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Action buttons
                  Column(
                    children: [
                      StreamBuilder<QuerySnapshot>(
                        stream: context
                            .read<PostRepository>()
                            .getPostLikesStream(widget.post.id),
                        builder: (context, snapshot) {
                          final likesCount = snapshot.data?.docs.length ?? 0;
                          final userHasLiked = snapshot.data?.docs
                              .any((doc) => doc.id == currentUser?.uid) ??
                              false;
                          return _ReelActionButton(
                            icon: userHasLiked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            label: likesCount.toString(),
                            color: userHasLiked ? Colors.red : Colors.white,
                            onTap: () => _toggleLike(),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      StreamBuilder<QuerySnapshot>(
                        stream: context
                            .read<PostRepository>()
                            .getPostCommentsStream(widget.post.id),
                        builder: (context, snapshot) {
                          final commentsCount =
                              snapshot.data?.docs.length ?? 0;
                          return _ReelActionButton(
                            icon: Icons.comment_bank_outlined,
                            label: commentsCount.toString(),
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) =>
                                      CommentsScreen(postId: widget.post.id)));
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _ReelActionButton(
                        icon: Icons.share,
                        label: 'Share',
                        onTap: () {
                          // TODO: Implement share functionality
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Share feature coming soon!')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ReelActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
