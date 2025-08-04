part of 'profile_bloc.dart';

@immutable
abstract class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object> get props => [];
}

/// The initial state of the profile BLoC.
class ProfileInitial extends ProfileState {}

/// The state when a profile update is in progress.
class ProfileLoading extends ProfileState {}

/// The state when a profile update has completed successfully.
class ProfileUpdateSuccess extends ProfileState {}

/// The state when an error occurs during a profile update.
class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);

  @override
  List<Object> get props => [message];
}
