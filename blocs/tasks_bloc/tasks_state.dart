part of 'tasks_bloc.dart';

@immutable
abstract class TasksState extends Equatable {
  const TasksState();

  @override
  List<Object> get props => [];
}

/// The initial state before any task data is loaded.
class TasksInitial extends TasksState {}

/// The state when task data is being loaded.
class TasksLoading extends TasksState {}

/// The state when all tasks and user progress have been successfully loaded.
class TasksLoaded extends TasksState {
  final List<DailyTask> allTasks;
  final List<TaskProgress> userProgress;

  const TasksLoaded({required this.allTasks, required this.userProgress});

  @override
  List<Object> get props => [allTasks, userProgress];
}

/// The state when an error occurs while loading tasks.
class TasksError extends TasksState {
  final String message;
  const TasksError(this.message);

  @override
  List<Object> get props => [message];
}
