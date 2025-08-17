// lib/screens/main_screen.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/auth_bloc.dart';
import 'package:freegram/blocs/friends_bloc/friends_bloc.dart';
import 'package:freegram/repositories/chat_repository.dart';
import 'package:freegram/repositories/notification_repository.dart';
import 'package:freegram/repositories/post_repository.dart';
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/screens/chat_list_screen.dart';
import 'package:freegram/screens/create_post_screen.dart';
import 'package:freegram/screens/discover_screen.dart';
import 'package:freegram/screens/match_screen.dart';
import 'package:freegram/screens/nearby_screen.dart';
import 'package:freegram/screens/notifications_screen.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/screens/store_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:freegram/widgets/post_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget> _widgetOptions;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      context.read<FriendsBloc>().add(LoadFriends());
      _setupFcm(authState.user.uid);
      _updateUserPresence(authState.user.uid, true);
      _widgetOptions = <Widget>[
        const FeedWidget(),
        const DiscoverScreen(),
        const ChatListScreen(),
        ProfileScreen(userId: authState.user.uid),
      ];
    } else {
      _widgetOptions = const [Center(child: Text("Error: Not Authenticated"))];
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      if (state == AppLifecycleState.resumed) {
        _updateUserPresence(authState.user.uid, true);
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        _updateUserPresence(authState.user.uid, false);
      }
    }
  }

  Future<void> _updateUserPresence(String uid, bool isOnline) async {
    try {
      if (mounted) {
        await context.read<UserRepository>().updateUserPresence(uid, isOnline);
      }
    } catch (e) {
      debugPrint("Could not update presence: $e");
    }
  }

  Future<void> _setupFcm(String uid) async {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission();
    final token = await fcm.getToken();
    if (token != null && mounted) {
      await context.read<UserRepository>().updateUser(uid, {'fcmToken': token});
    }
    fcm.onTokenRefresh.listen((newToken) async {
      if (mounted) {
        await context
            .read<UserRepository>()
            .updateUser(uid, {'fcmToken': newToken});
      }
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  Future<ImageSource?> _showImageSourceActionSheet(BuildContext context) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getFabConfig(int index) {
    switch (index) {
      case 0:
        return {
          'icon': Icons.add,
          'onPressed': () async {
            final source = await _showImageSourceActionSheet(context);
            if (source != null && mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CreatePostScreen(imageSource: source)));
            }
          },
        };
      case 1:
        return {
          'icon': Icons.whatshot,
          'onPressed': () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const MatchScreen()))
        };
      case 2:
        return {
          'icon': Icons.edit,
          'onPressed': () {/* TODO: Implement action to start a new chat */}
        };
      default:
        return {'icon': Icons.add, 'onPressed': () {}};
    }
  }

  Widget _buildChatIconWithBadge() {
    final authState = context.watch<AuthBloc>().state;
    if (authState is Authenticated) {
      return StreamBuilder<int>(
        stream: context
            .read<ChatRepository>()
            .getUnreadChatCountStream(authState.user.uid),
        builder: (context, snapshot) {
          final totalUnread = snapshot.data ?? 0;
          return Badge(
            label: Text(totalUnread.toString()),
            isLabelVisible: totalUnread > 0,
            child: _buildAnimatedIcon(Icons.chat_bubble_outline, 2),
          );
        },
      );
    }
    return _buildAnimatedIcon(Icons.chat_bubble_outline, 2);
  }

  Widget _buildActivityIconWithBadge() {
    final authState = context.watch<AuthBloc>().state;
    if (authState is Authenticated) {
      return StreamBuilder<int>(
        stream: context
            .read<NotificationRepository>()
            .getUnreadNotificationCountStream(authState.user.uid),
        builder: (context, snapshot) {
          final unreadCount = snapshot.data ?? 0;
          return Badge(
            label: Text(unreadCount.toString()),
            isLabelVisible: unreadCount > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.black87),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
          );
        },
      );
    }
    return IconButton(
      icon: const Icon(Icons.notifications_none, color: Colors.black87),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
    );
  }

  Widget _buildAnimatedIcon(IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    return IconButton(
      icon: Icon(icon,
          color: isSelected ? const Color(0xFF3498DB) : Colors.grey,
          size: isSelected ? 30 : 24),
      onPressed: () => _onItemTapped(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fabConfig = _getFabConfig(_selectedIndex);
    final bool showFab = _selectedIndex < 3;
    final authState = context.watch<AuthBloc>().state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Freegram',
            style:
            TextStyle(color: Color(0xFF3498DB), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined, color: Colors.black87),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const StoreScreen())),
          ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.bluetooth_searching, color: Colors.black87),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const NearbyScreen())),
            ),
          _buildActivityIconWithBadge(),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout' && authState is Authenticated) {
                await _updateUserPresence(authState.user.uid, false);
                if (mounted) {
                  context.read<AuthBloc>().add(SignOut());
                }
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(value: 'logout', child: Text('Logout'))
            ],
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _widgetOptions,
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
        onPressed: fabConfig['onPressed'],
        backgroundColor: const Color(0xFF3498DB),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(fabConfig['icon'],
              key: ValueKey<int>(_selectedIndex), color: Colors.white),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildAnimatedIcon(Icons.home, 0),
            _buildAnimatedIcon(Icons.people_outline, 1),
            if (showFab) const SizedBox(width: 40),
            _buildChatIconWithBadge(),
            _buildAnimatedIcon(Icons.person_outline, 3),
          ],
        ),
      ),
    );
  }
}

class FeedWidget extends StatefulWidget {
  const FeedWidget({super.key});

  @override
  State<FeedWidget> createState() => _FeedWidgetState();
}

class _FeedWidgetState extends State<FeedWidget> {
  final _scrollController = ScrollController();
  List<DocumentSnapshot> _posts = [];
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _postLimit = 10;

  @override
  void initState() {
    super.initState();
    _fetchFeedPosts();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300 &&
          !_isFetchingMore) {
        _fetchFeedPosts();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchFeedPosts({bool isRefresh = false}) async {
    if (_isFetchingMore || !_hasMore) return;
    if (isRefresh) {
      _posts = [];
      _lastDocument = null;
      _hasMore = true;
    }

    if (!mounted) return;
    setState(() {
      _isFetchingMore = true;
      if (_posts.isEmpty) _isLoading = true;
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
      return;
    }

    try {
      final postRepository = context.read<PostRepository>();
      final QuerySnapshot querySnapshot = await postRepository.getFeedPosts(
        currentUser.uid,
        lastDocument: _lastDocument,
      );

      if (querySnapshot.docs.length < _postLimit) {
        _hasMore = false;
      }
      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        _posts.addAll(querySnapshot.docs);
      }
    } catch (e) {
      debugPrint("Error fetching feed posts: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load posts: $e')),
        );
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _fetchFeedPosts(isRefresh: true),
        child: const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              child: Center(
                child: Text('No posts to show. Start adding friends!'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchFeedPosts(isRefresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return _isFetchingMore
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox();
          }
          return PostCard(post: _posts[index]);
        },
      ),
    );
  }
}
