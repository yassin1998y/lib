part of 'profile_bloc.dart';

@immutable
abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

/// Event to update a user's profile data and optionally their profile image.
class ProfileUpdateEvent extends ProfileEvent {
  final String userId;
  final Map<String, dynamic> updatedData;
  final XFile? imageFile;

  const ProfileUpdateEvent({
    required this.userId,
    required this.updatedData,
    this.imageFile,
  });

  @override
  List<Object?> get props => [userId, updatedData, imageFile];
}
