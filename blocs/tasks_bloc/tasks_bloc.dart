import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freegram/models/daily_task.dart';
import 'package:freegram/models/task_progress.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:meta/meta.dart';

part 'tasks_event.dart';
part 'tasks_state.dart';

class TasksBloc extends Bloc<TasksEvent, TasksState> {
  final FirestoreService _firestoreService;
  final FirebaseAuth _firebaseAuth;
  StreamSubscription? _taskProgressSubscription;
  List<DailyTask> _allTasksCache = [];

  TasksBloc({
    required FirestoreService firestoreService,
    FirebaseAuth? firebaseAuth,
  })  : _firestoreService = firestoreService,
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
      // Fetch all task definitions once and cache them.
      _allTasksCache = await _firestoreService.getDailyTasks();

      // Listen to the user's progress stream.
      _taskProgressSubscription = _firestoreService
          .getUserTaskProgressStream(user.uid)
          .listen((QuerySnapshot progressSnapshot) {
        final userProgress = progressSnapshot.docs
            .map((doc) => TaskProgress.fromDoc(doc))
            .toList();

        // When progress updates, combine it with the cached task definitions.
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
