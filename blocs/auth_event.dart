part of 'auth_bloc.dart';

@immutable
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

/// Event to check the current authentication status.
class CheckAuthentication extends AuthEvent {}

/// Event to sign the user out.
class SignOut extends AuthEvent {}
