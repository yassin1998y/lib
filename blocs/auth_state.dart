part of 'auth_bloc.dart';

@immutable
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// The initial state of the authentication BLoC.
class AuthInitial extends AuthState {}

/// The state when a user is successfully authenticated.
class Authenticated extends AuthState {
  final User user;
  const Authenticated(this.user);

  @override
  List<Object?> get props => [user];
}

/// The state when no user is authenticated.
class Unauthenticated extends AuthState {}
