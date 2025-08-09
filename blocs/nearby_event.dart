part of 'nearby_bloc.dart';

@immutable
abstract class NearbyEvent extends Equatable {
  const NearbyEvent();

  @override
  List<Object> get props => [];
}

/// Event to start both scanning and advertising.
class StartNearbyServices extends NearbyEvent {}

/// Event to stop both scanning and advertising.
class StopNearbyServices extends NearbyEvent {}

/// Internal event to update the BLoC with a new status from the Bluetooth service.
class _NearbyStatusUpdated extends NearbyEvent {
  final NearbyStatus status;
  const _NearbyStatusUpdated(this.status);

  @override
  List<Object> get props => [status];
}
