part of 'friends_bloc.dart';

@immutable
abstract class FriendsEvent extends Equatable {
  const FriendsEvent();

  @override
  List<Object> get props => [];
}

/// Event to initialize the friendship stream for the current user.
class LoadFriends extends FriendsEvent {}

/// Internal event triggered when the user's document stream pushes an update.
/// This now carries a type-safe UserModel.
class _FriendsUpdated extends FriendsEvent {
  final UserModel user;
  const _FriendsUpdated(this.user);

  @override
  List<Object> get props => [user];
}

/// Event to send a friend request to another user.
class SendFriendRequest extends FriendsEvent {
  final String toUserId;
  const SendFriendRequest(this.toUserId);

  @override
  List<Object> get props => [toUserId];
}

/// Event to accept a friend request from another user.
class AcceptFriendRequest extends FriendsEvent {
  final String fromUserId;
  const AcceptFriendRequest(this.fromUserId);

  @override
  List<Object> get props => [fromUserId];
}

/// Event to accept a contact request from the chat screen.
/// This also converts the chat to a friend_chat.
class AcceptContactRequest extends FriendsEvent {
  final String fromUserId;
  final String chatId;
  const AcceptContactRequest({required this.fromUserId, required this.chatId});

  @override
  List<Object> get props => [fromUserId, chatId];
}

/// Event to decline a friend request from another user.
class DeclineFriendRequest extends FriendsEvent {
  final String fromUserId;
  const DeclineFriendRequest(this.fromUserId);

  @override
  List<Object> get props => [fromUserId];
}

/// Event to remove an existing friend.
class RemoveFriend extends FriendsEvent {
  final String friendId;
  const RemoveFriend(this.friendId);

  @override
  List<Object> get props => [friendId];
}

/// Event to block a user.
class BlockUser extends FriendsEvent {
  final String userIdToBlock;
  const BlockUser(this.userIdToBlock);

  @override
  List<Object> get props => [userIdToBlock];
}

/// Event to unblock a user.
class UnblockUser extends FriendsEvent {
  final String userIdToUnblock;
  const UnblockUser(this.userIdToUnblock);

  @override
  List<Object> get props => [userIdToUnblock];
}

/// Event to toggle a friend's favorite status.
/// NOTE: The 'isFavorite' feature was in your original BLoC but not in the simplified
/// data model. This event is kept for potential future implementation, but the
/// associated logic in FirestoreService would need to be re-added.
class ToggleFavoriteFriend extends FriendsEvent {
  final String friendId;
  final bool isCurrentlyFavorite;
  const ToggleFavoriteFriend(this.friendId, this.isCurrentlyFavorite);

  @override
  List<Object> get props => [friendId, isCurrentlyFavorite];
}
