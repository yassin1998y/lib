import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:freegram/repositories/post_repository.dart';
import 'package:freegram/widgets/reel_player_widget.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class ReelsViewerScreen extends StatefulWidget {
  final DocumentSnapshot? initialPost;
  const ReelsViewerScreen({super.key, this.initialPost});

  @override
  State<ReelsViewerScreen> createState() => _ReelsViewerScreenState();
}

class _ReelsViewerScreenState extends State<ReelsViewerScreen> {
  late final PageController _pageController;
  final List<DocumentSnapshot> _reels = [];
  bool _isLoading = true;
  DocumentSnapshot? _lastDocument;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  // Video controller cache for preloading
  final LinkedHashMap<String, VideoPlayerController> _controllerCache = LinkedHashMap();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _reels.add(widget.initialPost!);
      _currentPage = 0;
    }
    _pageController = PageController(initialPage: _currentPage);
    _fetchReels();

    _pageController.addListener(() {
      final newPage = _pageController.page?.round() ?? 0;
      if (newPage != _currentPage) {
        // Dispose of the controller that is now 2 pages away
        _disposeControllerAt(_currentPage - 2);
        _disposeControllerAt(_currentPage + 2);
        // Preload the next controller
        _preloadControllerFor(newPage + 1);
        setState(() {
          _currentPage = newPage;
        });
      }

      if (_pageController.position.pixels >=
          _pageController.position.maxScrollExtent -
              MediaQuery.of(context).size.height &&
          !_isFetchingMore) {
        _fetchReels();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _controllerCache.values) {
      controller.dispose();
    }
    _controllerCache.clear();
    super.dispose();
  }

  Future<void> _preloadControllerFor(int index) async {
    if (index < 0 || index >= _reels.length) return;

    final post = _reels[index];
    final postId = post.id;

    if (_controllerCache.containsKey(postId)) return;

    final postData = post.data() as Map<String, dynamic>;
    final videoUrl = postData['imageUrl'];
    if (videoUrl == null || videoUrl.isEmpty) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    _controllerCache[postId] = controller;
    await controller.initialize();

    // Trim the cache if it gets too large
    if (_controllerCache.length > 5) {
      final keyToRemove = _controllerCache.keys.first;
      _controllerCache[keyToRemove]?.dispose();
      _controllerCache.remove(keyToRemove);
    }
  }

  void _disposeControllerAt(int index) {
    if (index < 0 || index >= _reels.length) return;
    final postId = _reels[index].id;
    if (_controllerCache.containsKey(postId)) {
      _controllerCache[postId]?.dispose();
      _controllerCache.remove(postId);
    }
  }

  Future<void> _fetchReels({bool isRefresh = false}) async {
    if (_isFetchingMore || (!_hasMore && !isRefresh)) return;

    if (isRefresh) {
      _reels.clear();
      _lastDocument = null;
      _hasMore = true;
      _errorMessage = null;
    }

    if (!mounted) return;
    setState(() {
      _isFetchingMore = true;
      if (_reels.isEmpty) _isLoading = true;
    });

    try {
      final querySnapshot = await context
          .read<PostRepository>()
          .getReelPosts(lastDocument: _lastDocument);

      if (querySnapshot.docs.length < 10) {
        _hasMore = false;
      }

      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        if (mounted) {
          setState(() {
            // Avoid adding duplicates if the initial post was already added
            for (var doc in querySnapshot.docs) {
              if (!_reels.any((element) => element.id == doc.id)) {
                _reels.add(doc);
              }
            }
          });
          // Preload the first couple of videos
          _preloadControllerFor(_currentPage);
          _preloadControllerFor(_currentPage + 1);
        }
      }
    } catch (e) {
      debugPrint("Error fetching reels: $e");
      if (mounted) {
        setState(() {
          if (_reels.isEmpty) {
            _errorMessage = "Could not load reels. Please try again.";
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _reels.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_reels.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _fetchReels(isRefresh: true),
      color: Colors.white,
      backgroundColor: Colors.black,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _reels.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _reels.length) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final reelDoc = _reels[index];
          return Hero(
            tag: reelDoc.id, // Match the tag from the thumbnail
            child: ReelPlayerWidget(
              key: ValueKey(reelDoc.id), // Use a key to ensure widget rebuilds
              post: reelDoc,
            ),
          );
        },
      ),
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
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchReels(isRefresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: () => _fetchReels(isRefresh: true),
      child: const CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Text(
                "No reels to show yet.",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
