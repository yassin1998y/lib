import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freegram/repositories/auth_repository.dart';
import 'package:meta/meta.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FirebaseAuth _firebaseAuth;
  final AuthRepository _authRepository;
  StreamSubscription<User?>? _authStateSubscription;

  AuthBloc({
    required AuthRepository authRepository,
    FirebaseAuth? firebaseAuth,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _authRepository = authRepository,
        super(AuthInitial()) {
    _authStateSubscription =
        _firebaseAuth.authStateChanges().listen((user) {
          add(CheckAuthentication());
        });

    on<CheckAuthentication>((event, emit) {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        emit(Authenticated(user));
      } else {
        emit(Unauthenticated());
      }
    });

    on<SignOut>((event, emit) async {
      await _authRepository.signOut();
    });

    on<SignInWithGoogle>((event, emit) async {
      try {
        await _authRepository.signInWithGoogle();
      } catch (e) {
        emit(AuthError(e.toString()));
        emit(Unauthenticated());
      }
    });

    on<SignInWithFacebook>((event, emit) async {
      try {
        await _authRepository.signInWithFacebook();
      } catch (e) {
        emit(AuthError(e.toString()));
        emit(Unauthenticated());
      }
    });
  }

  @override
  Future<void> close() {
    _authStateSubscription?.cancel();
    return super.close();
  }
}
