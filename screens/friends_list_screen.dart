import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/friends_bloc/friends_bloc.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';

class FriendsListScreen extends StatefulWidget {
  final int initialIndex;

  const FriendsListScreen({super.key, this.initialIndex = 0});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 3, vsync: this, initialIndex: widget.initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Friends'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Requests'),
            Tab(text: 'Blocked'),
          ],
        ),
      ),
      body: BlocBuilder<FriendsBloc, FriendsState>(
        builder: (context, state) {
          if (state is FriendsLoading || state is FriendsInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is FriendsError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is FriendsLoaded) {
            return TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsTab(state.user.friends),
                _buildRequestsTab(state.user.friendRequestsReceived),
                _buildBlockedTab(state.user.blockedUsers),
              ],
            );
          }
          return const Center(child: Text('Something went wrong.'));
        },
      ),
    );
  }

  Widget _buildFriendsTab(List<String> friendIds) {
    if (friendIds.isEmpty) {
      return const Center(child: Text('You have no friends yet.'));
    }
    return ListView.builder(
      itemCount: friendIds.length,
      itemBuilder: (context, index) {
        final userId = friendIds[index];
        return UserListTile(
          userId: userId,
        );
      },
    );
  }

  Widget _buildRequestsTab(List<String> requestIds) {
    if (requestIds.isEmpty) {
      return const Center(child: Text('You have no pending friend requests.'));
    }
    return ListView.builder(
      itemCount: requestIds.length,
      itemBuilder: (context, index) {
        final userId = requestIds[index];
        return UserListTile(
          userId: userId,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                tooltip: 'Accept',
                onPressed: () {
                  context.read<FriendsBloc>().add(AcceptFriendRequest(userId));
                },
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red),
                tooltip: 'Decline',
                onPressed: () {
                  context.read<FriendsBloc>().add(DeclineFriendRequest(userId));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBlockedTab(List<String> blockedUserIds) {
    if (blockedUserIds.isEmpty) {
      return const Center(child: Text('You have not blocked any users.'));
    }
    return ListView.builder(
      itemCount: blockedUserIds.length,
      itemBuilder: (context, index) {
        final userId = blockedUserIds[index];
        return UserListTile(
          userId: userId,
          trailing: OutlinedButton(
            child: const Text('Unblock'),
            onPressed: () {
              context.read<FriendsBloc>().add(UnblockUser(userId));
            },
          ),
        );
      },
    );
  }
}

class UserListTile extends StatelessWidget {
  final String userId;
  final Widget? trailing;

  const UserListTile({super.key, required this.userId, this.trailing});

  @override
  Widget build(BuildContext context) {
    final firestoreService = context.read<FirestoreService>();

    return FutureBuilder<UserModel>(
      future: firestoreService.getUser(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(
            leading: CircleAvatar(),
            title: Text('Loading...'),
          );
        }
        if (snapshot.hasError) {
          return const ListTile(
            leading: CircleAvatar(backgroundColor: Colors.red),
            title:
            Text('Error loading user', style: TextStyle(color: Colors.red)),
          );
        }

        final user = snapshot.data!;
        final photoUrl = user.photoUrl;

        return ListTile(
          leading: CircleAvatar(
            backgroundImage:
            (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
            child: (photoUrl.isEmpty)
                ? Text(user.username.isNotEmpty
                ? user.username[0].toUpperCase()
                : '?')
                : null,
          ),
          title: Text(user.username),
          trailing: trailing,
          onTap: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));
          },
        );
      },
    );
  }
}
