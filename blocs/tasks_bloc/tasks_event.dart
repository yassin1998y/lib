part of 'tasks_bloc.dart';

@immutable
abstract class TasksEvent extends Equatable {
  const TasksEvent();

  @override
  List<Object> get props => [];
}

/// Event to load all daily task definitions and the user's current progress.
class LoadTasks extends TasksEvent {}

/// Internal event triggered when task progress data is updated from Firestore.
class _TasksUpdated extends TasksEvent {
  final List<DailyTask> allTasks;
  final List<TaskProgress> userProgress;

  const _TasksUpdated({required this.allTasks, required this.userProgress});

  @override
  List<Object> get props => [allTasks, userProgress];
}
