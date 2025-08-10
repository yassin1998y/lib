part of 'friends_bloc.dart';

@immutable
abstract class FriendsState extends Equatable {
  const FriendsState();

  @override
  List<Object> get props => [];
}

/// The initial state before any friend data is loaded.
class FriendsInitial extends FriendsState {}

/// The state when friend data is being loaded.
class FriendsLoading extends FriendsState {}

/// The state when all friendship data has been successfully loaded.
/// It now holds a single, type-safe UserModel for the current user.
class FriendsLoaded extends FriendsState {
  final UserModel user;

  const FriendsLoaded({required this.user});

  @override
  List<Object> get props => [user];
}

/// The state when an error occurs while managing friendships.
class FriendsError extends FriendsState {
  final String message;
  const FriendsError(this.message);

  @override
  List<Object> get props => [message];
}
