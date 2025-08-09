part of 'nearby_bloc.dart';

@immutable
abstract class NearbyState extends Equatable {
  const NearbyState();

  @override
  List<Object> get props => [];
}

/// The initial state before any action is taken.
class NearbyInitial extends NearbyState {}

/// The state when services are active (scanning/advertising).
class NearbyActive extends NearbyState {
  final List<String> foundUserIds;
  final NearbyStatus status;

  const NearbyActive({required this.foundUserIds, required this.status});

  @override
  List<Object> get props => [foundUserIds, status];
}

/// The state when an error occurs.
class NearbyError extends NearbyState {
  final String message;
  const NearbyError(this.message);

  @override
  List<Object> get props => [message];
}
