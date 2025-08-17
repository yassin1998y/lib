import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/season_pass_bloc/season_pass_bloc.dart';
import 'package:freegram/models/season_model.dart';
import 'package:freegram/models/season_pass_reward.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/gamification_repository.dart'; // UPDATED IMPORT
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/screens/leaderboard_screen.dart';

class LevelPassScreen extends StatelessWidget {
  const LevelPassScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SeasonPassBloc(
        // UPDATED: Provided the required gamificationRepository
        gamificationRepository: context.read<GamificationRepository>(),
        userRepository: context.read<UserRepository>(),
      )..add(LoadSeasonPass()),
      child: const _LevelPassView(),
    );
  }
}

class _LevelPassView extends StatelessWidget {
  const _LevelPassView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Season Pass"),
      ),
      body: BlocBuilder<SeasonPassBloc, SeasonPassState>(
        builder: (context, state) {
          if (state is SeasonPassLoading || state is SeasonPassInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is SeasonPassError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is SeasonPassLoaded) {
            final user = state.user;
            final season = state.currentSeason;
            final rewards = state.rewards;

            final nextReward = rewards.firstWhere(
                  (reward) => reward.level > user.seasonLevel,
              orElse: () => rewards.last,
            );

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildSeasonHeader(context, season),
                const SizedBox(height: 24),
                _buildNextRewardCard(context, nextReward),
                const SizedBox(height: 24),
                _buildXpProgress(context, user),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text("All Rewards", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...rewards.map((reward) {
                  final isUnlocked = user.seasonLevel >= reward.level;
                  final isClaimed = user.claimedSeasonRewards.contains(reward.level);
                  return _RewardListItem(
                    reward: reward,
                    isUnlocked: isUnlocked,
                    isClaimed: isClaimed,
                  );
                }).toList(),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSeasonHeader(BuildContext context, Season season) {
    final daysLeft = season.endDate.difference(DateTime.now()).inDays;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              season.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.leaderboard, color: Colors.blue),
              tooltip: "View Leaderboard",
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Season ends in $daysLeft days",
          style: TextStyle(color: Colors.grey[600], fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildNextRewardCard(BuildContext context, SeasonPassReward nextReward) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.blue,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              "NEXT REWARD",
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),
            Icon(nextReward.icon, color: Colors.white, size: 40),
            const SizedBox(height: 8),
            Text(
              nextReward.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "at Level ${nextReward.level}",
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildXpProgress(BuildContext context, UserModel user) {
    final xpForNextLevel = (user.seasonLevel + 1) * 500;
    final currentLevelXp = user.seasonLevel * 500;
    final xpInCurrentLevel = user.seasonXp - currentLevelXp;
    final progressPercentage = (xpForNextLevel - currentLevelXp) > 0
        ? xpInCurrentLevel / (xpForNextLevel - currentLevelXp)
        : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Level ${user.seasonLevel}',
                style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Level ${user.seasonLevel + 1}',
                style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progressPercentage,
            minHeight: 12,
            backgroundColor: Colors.grey[300],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${xpForNextLevel - user.seasonXp} XP to next level',
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}

class _RewardListItem extends StatelessWidget {
  final SeasonPassReward reward;
  final bool isUnlocked;
  final bool isClaimed;

  const _RewardListItem({
    required this.reward,
    required this.isUnlocked,
    required this.isClaimed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isUnlocked ? Colors.blue.withAlpha(25) : null, // FIX: withOpacity deprecated
      child: ListTile(
        leading: Icon(
          reward.icon,
          color: isUnlocked ? Colors.blue : Colors.grey,
        ),
        title: Text(reward.title),
        subtitle: Text("Unlocked at Level ${reward.level}"),
        trailing: isUnlocked
            ? (isClaimed
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
          onPressed: () {
            context.read<SeasonPassBloc>().add(ClaimReward(reward: reward));
          },
          child: const Text("Claim"),
        ))
            : const Icon(Icons.lock, color: Colors.grey),
      ),
    );
  }
}
