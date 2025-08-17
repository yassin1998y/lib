import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // FIX: Added this import for @immutable
import 'package:freegram/models/daily_task.dart';
import 'package:freegram/models/task_progress.dart';
import 'package:freegram/repositories/task_repository.dart';

part 'tasks_event.dart';
part 'tasks_state.dart';

class TasksBloc extends Bloc<TasksEvent, TasksState> {
  final TaskRepository _taskRepository;
  final FirebaseAuth _firebaseAuth;
  StreamSubscription? _taskProgressSubscription;
  List<DailyTask> _allTasksCache = [];

  TasksBloc({
    required TaskRepository taskRepository,
    FirebaseAuth? firebaseAuth,
  })  : _taskRepository = taskRepository,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(TasksInitial()) {
    on<LoadTasks>(_onLoadTasks);
    on<_TasksUpdated>(_onTasksUpdated);
  }

  Future<void> _onLoadTasks(LoadTasks event, Emitter<TasksState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      emit(const TasksError("User not authenticated."));
      return;
    }

    emit(TasksLoading());
    await _taskProgressSubscription?.cancel();

    try {
      _allTasksCache = await _taskRepository.getDailyTasks();

      _taskProgressSubscription = _taskRepository
          .getUserTaskProgressStream(user.uid)
          .listen((QuerySnapshot progressSnapshot) {
        final userProgress = progressSnapshot.docs
            .map((doc) => TaskProgress.fromDoc(doc))
            .toList();

        add(_TasksUpdated(
          allTasks: _allTasksCache,
          userProgress: userProgress,
        ));
      });
    } catch (e) {
      emit(TasksError(e.toString()));
    }
  }

  void _onTasksUpdated(_TasksUpdated event, Emitter<TasksState> emit) {
    emit(TasksLoaded(
      allTasks: event.allTasks,
      userProgress: event.userProgress,
    ));
  }

  @override
  Future<void> close() {
    _taskProgressSubscription?.cancel();
    return super.close();
  }
}
