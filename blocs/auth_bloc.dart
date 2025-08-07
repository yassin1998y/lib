import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:meta/meta.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FirebaseAuth _firebaseAuth;
  final FirestoreService _firestoreService; // Added FirestoreService
  StreamSubscription<User?>? _authStateSubscription;

  AuthBloc({
    required FirestoreService firestoreService, // Now required
    FirebaseAuth? firebaseAuth,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestoreService = firestoreService,
        super(AuthInitial()) {
    // Listen for authentication state changes from Firebase
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
      // Sign out from social providers as well
      await _firestoreService.signOut();
    });

    // Handle Google Sign-In (NEW)
    on<SignInWithGoogle>((event, emit) async {
      try {
        await _firestoreService.signInWithGoogle();
        // The authStateChanges listener will handle the state transition
      } catch (e) {
        // Optionally emit an error state to show in the UI
        emit(AuthError(e.toString()));
        // Ensure we revert to unauthenticated if sign-in fails
        emit(Unauthenticated());
      }
    });

    // Handle Facebook Sign-In (NEW)
    on<SignInWithFacebook>((event, emit) async {
      try {
        await _firestoreService.signInWithFacebook();
        // The authStateChanges listener will handle the state transition
      } catch (e) {
        // Optionally emit an error state to show in the UI
        emit(AuthError(e.toString()));
        // Ensure we revert to unauthenticated if sign-in fails
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
