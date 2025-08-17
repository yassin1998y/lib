import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/tasks_bloc/tasks_bloc.dart';
import 'package:freegram/models/daily_task.dart';
import 'package:freegram/models/task_progress.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/task_repository.dart'; // UPDATED IMPORT
import 'package:freegram/repositories/user_repository.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TasksBloc(
        // UPDATED: Provided the required taskRepository
        taskRepository: context.read<TaskRepository>(),
      )..add(LoadTasks()),
      child: const _TasksScreenView(),
    );
  }
}

class _TasksScreenView extends StatelessWidget {
  const _TasksScreenView();

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Daily Tasks & Rewards')),
        body: const Center(child: Text("Please log in to see your tasks.")),
      );
    }

    return StreamBuilder<UserModel>(
      stream: context.read<UserRepository>().getUserStream(currentUserId),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Daily Tasks & Rewards'),
          ),
          body: Column(
            children: [
              if (user != null) _buildLevelHeader(context, user),
              Expanded(
                child: BlocBuilder<TasksBloc, TasksState>(
                  builder: (context, state) {
                    if (state is TasksLoading || state is TasksInitial) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is TasksError) {
                      return Center(child: Text('Error: ${state.message}'));
                    }
                    if (state is TasksLoaded) {
                      if (state.allTasks.isEmpty) {
                        return const Center(
                            child: Text('No daily tasks available right now.'));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: state.allTasks.length,
                        itemBuilder: (context, index) {
                          final task = state.allTasks[index];
                          final progress = state.userProgress.firstWhere(
                                (p) => p.taskId == task.id,
                            orElse: () => TaskProgress(
                              taskId: task.id,
                              progress: 0,
                              isCompleted: false,
                              lastUpdated: DateTime.now(),
                            ),
                          );
                          return _TaskCard(task: task, progress: progress);
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLevelHeader(BuildContext context, UserModel user) {
    final xpForNextLevel = user.level * 1000;
    final currentLevelXp = (user.level - 1) * 1000;
    final xpInCurrentLevel = user.xp - currentLevelXp;
    final progressPercentage =
        xpInCurrentLevel / (xpForNextLevel - currentLevelXp);

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(25),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Level ${user.level}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${user.xp} / $xpForNextLevel XP',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progressPercentage,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DailyTask task;
  final TaskProgress progress;

  const _TaskCard({required this.task, required this.progress});

  @override
  Widget build(BuildContext context) {
    final double progressPercentage =
    (progress.progress / task.requiredCount).clamp(0.0, 1.0);
    final bool isCompleted = progress.isCompleted;

    return Card(
      elevation: isCompleted ? 0 : 2,
      color: isCompleted ? Colors.grey[200] : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      decoration:
                      isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (isCompleted)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.description, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progressPercentage,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                        isCompleted ? Colors.green : Colors.blue),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${progress.progress} / ${task.requiredCount}',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildRewardChip(
                    '${task.xpReward} XP', Icons.star, Colors.purple),
                const SizedBox(width: 8),
                _buildRewardChip(
                    '${task.coinReward} Coins', Icons.monetization_on, Colors.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardChip(String label, IconData icon, Color color) {
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label),
      backgroundColor: color.withAlpha(25),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
    );
  }
}
