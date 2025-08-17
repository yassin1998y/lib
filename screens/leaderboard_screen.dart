import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/leaderboard_bloc/leaderboard_bloc.dart';
import 'package:freegram/repositories/gamification_repository.dart'; // UPDATED IMPORT
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/screens/profile_screen.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LeaderboardBloc(
        // UPDATED: Provided the required gamificationRepository
        gamificationRepository: context.read<GamificationRepository>(),
        userRepository: context.read<UserRepository>(),
      )..add(LoadLeaderboard()),
      child: const _LeaderboardView(),
    );
  }
}

class _LeaderboardView extends StatefulWidget {
  const _LeaderboardView();

  @override
  State<_LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<_LeaderboardView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 2);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        context
            .read<LeaderboardBloc>()
            .add(SwitchLeaderboardTab(tabIndex: _tabController.index));
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showRewardsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Season Rewards'),
        content: const Text(
            '🏆 Top 3 Global winners receive an exclusive profile badge and 5,000 coins!\n'
                '🥇 Top Country winners receive 1,000 coins.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seasonal Leaderboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showRewardsDialog,
            tooltip: 'View Rewards',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Country'),
            Tab(text: 'Global'),
          ],
        ),
      ),
      body: BlocConsumer<LeaderboardBloc, LeaderboardState>(
        listener: (context, state) {
          if (state is LeaderboardLoaded) {
            _tabController.animateTo(state.currentTabIndex);
          }
        },
        builder: (context, state) {
          if (state is LeaderboardLoading || state is LeaderboardInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is LeaderboardError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${state.message}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          if (state is LeaderboardLoaded) {
            if (state.rankings.isEmpty) {
              return const Center(
                child: Text('No rankings to display for this category.'),
              );
            }

            final topThree = state.rankings.take(3).toList();
            final theRest = state.rankings.skip(3).toList();

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      if (state.currentTabIndex != 0) // Don't show podium for friends
                        _PodiumWidget(topThree: topThree),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: state.currentTabIndex != 0 ? theRest.length : state.rankings.length,
                        itemBuilder: (context, index) {
                          final userDoc = state.currentTabIndex != 0 ? theRest[index] : state.rankings[index];
                          final rank = state.currentTabIndex != 0 ? index + 4 : index + 1;
                          final userData = userDoc.data() as Map<String, dynamic>;
                          return _RankingTile(
                            rank: rank,
                            userId: userDoc.id,
                            username: userData['username'] ?? 'N/A',
                            photoUrl: userData['photoUrl'] ?? '',
                            level: userData['level'] ?? 0,
                            xp: userData['xp'] ?? 0,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (state.currentUserRanking != null)
                  _CurrentUserRankBar(
                    rank: state.currentUserRank,
                    rankingData: state.currentUserRanking!,
                  ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _PodiumWidget extends StatelessWidget {
  final List<DocumentSnapshot> topThree;
  const _PodiumWidget({required this.topThree});

  @override
  Widget build(BuildContext context) {
    final firstPlace = topThree.isNotEmpty ? topThree[0] : null;
    final secondPlace = topThree.length > 1 ? topThree[1] : null;
    final thirdPlace = topThree.length > 2 ? topThree[2] : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (secondPlace != null)
            _PodiumPlacement(
              userDoc: secondPlace,
              rank: 2,
              color: Colors.grey[400]!,
              size: 50,
            ),
          if (firstPlace != null)
            _PodiumPlacement(
              userDoc: firstPlace,
              rank: 1,
              color: Colors.amber,
              size: 60,
            ),
          if (thirdPlace != null)
            _PodiumPlacement(
              userDoc: thirdPlace,
              rank: 3,
              color: const Color(0xFFCD7F32),
              size: 40,
            ),
        ],
      ),
    );
  }
}

class _PodiumPlacement extends StatelessWidget {
  final DocumentSnapshot userDoc;
  final int rank;
  final Color color;
  final double size;

  const _PodiumPlacement({
    required this.userDoc,
    required this.rank,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final userData = userDoc.data() as Map<String, dynamic>;
    final photoUrl = userData['photoUrl'] ?? '';
    final username = userData['username'] ?? 'N/A';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: userDoc.id)),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: size,
                backgroundColor: color,
                child: CircleAvatar(
                  radius: size - 4,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty ? Text(username.isNotEmpty ? username[0] : '?') : null,
                ),
              ),
              Positioned(
                bottom: -10,
                left: 0,
                right: 0,
                child: Center(
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: color,
                    child: Text(
                      rank.toString(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            'Level ${userData['level'] ?? 0}',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  final int rank;
  final String userId;
  final String username;
  final String photoUrl;
  final int level;
  final int xp;

  const _RankingTile({
    required this.rank,
    required this.userId,
    required this.username,
    required this.photoUrl,
    required this.level,
    required this.xp,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 50,
        child: Center(
          child: Text(
            '$rank',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty ? Text(username.isNotEmpty ? username[0] : '?') : null,
          ),
          const SizedBox(width: 12),
          Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      trailing: Text(
        'Level $level',
        style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
        );
      },
    );
  }
}

class _CurrentUserRankBar extends StatelessWidget {
  final int? rank;
  final DocumentSnapshot rankingData;

  const _CurrentUserRankBar({required this.rank, required this.rankingData});

  @override
  Widget build(BuildContext context) {
    final userData = rankingData.data() as Map<String, dynamic>;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25), // FIX: withOpacity deprecated
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _RankingTile(
          rank: rank ?? 0,
          userId: rankingData.id,
          username: userData['username'] ?? 'You',
          photoUrl: userData['photoUrl'] ?? '',
          level: userData['level'] ?? 0,
          xp: userData['xp'] ?? 0,
        ),
      ),
    );
  }
}
