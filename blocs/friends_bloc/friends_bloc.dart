import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/user_repository.dart'; // UPDATED
import 'package:meta/meta.dart';

part 'friends_event.dart';
part 'friends_state.dart';

class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  // UPDATED: Now uses UserRepository
  final UserRepository _userRepository;
  final FirebaseAuth _firebaseAuth;
  StreamSubscription<UserModel>? _friendshipSubscription;

  FriendsBloc({
    required UserRepository userRepository, // UPDATED
    FirebaseAuth? firebaseAuth,
  })  : _userRepository = userRepository, // UPDATED
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(FriendsInitial()) {
    on<LoadFriends>(_onLoadFriends);
    on<_FriendsUpdated>(_onFriendsUpdated);
    on<SendFriendRequest>(_onSendFriendRequest);
    on<AcceptFriendRequest>(_onAcceptFriendRequest);
    on<DeclineFriendRequest>(_onDeclineFriendRequest);
    on<RemoveFriend>(_onRemoveFriend);
    on<BlockUser>(_onBlockUser);
    on<UnblockUser>(_onUnblockUser);
    on<ToggleFavoriteFriend>(_onToggleFavoriteFriend);
  }

  void _onLoadFriends(LoadFriends event, Emitter<FriendsState> emit) {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      emit(const FriendsError("User not authenticated."));
      return;
    }

    emit(FriendsLoading());
    _friendshipSubscription?.cancel();
    // UPDATED: Calls the method on the new repository
    _friendshipSubscription = _userRepository.getUserStream(user.uid).listen(
          (userModel) {
        add(_FriendsUpdated(userModel));
      },
      onError: (error) {
        emit(FriendsError(error.toString()));
      },
    );
  }

  void _onFriendsUpdated(_FriendsUpdated event, Emitter<FriendsState> emit) {
    emit(FriendsLoaded(user: event.user));
  }

  Future<void> _onSendFriendRequest(
      SendFriendRequest event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null && state is FriendsLoaded) {
      final currentState = state as FriendsLoaded;

      final optimisticUser = UserModel(
        id: currentState.user.id,
        username: currentState.user.username,
        email: currentState.user.email,
        photoUrl: currentState.user.photoUrl,
        bio: currentState.user.bio,
        fcmToken: currentState.user.fcmToken,
        presence: currentState.user.presence,
        lastSeen: currentState.user.lastSeen,
        country: currentState.user.country,
        age: currentState.user.age,
        gender: currentState.user.gender,
        interests: currentState.user.interests,
        createdAt: currentState.user.createdAt,
        friends: currentState.user.friends,
        friendRequestsSent: [
          ...currentState.user.friendRequestsSent,
          event.toUserId
        ],
        friendRequestsReceived: currentState.user.friendRequestsReceived,
        blockedUsers: currentState.user.blockedUsers,
        coins: currentState.user.coins,
        superLikes: currentState.user.superLikes,
        lastFreeSuperLike: currentState.user.lastFreeSuperLike,
      );
      emit(FriendsRequestSent(user: optimisticUser));

      // UPDATED: Calls the method on the new repository
      await _userRepository.sendFriendRequest(user.uid, event.toUserId);
    }
  }

  Future<void> _onAcceptFriendRequest(
      AcceptFriendRequest event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      // UPDATED: Calls the method on the new repository
      await _userRepository.acceptFriendRequest(user.uid, event.fromUserId);
    }
  }

  Future<void> _onDeclineFriendRequest(
      DeclineFriendRequest event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      // UPDATED: Calls the method on the new repository
      await _userRepository.declineFriendRequest(user.uid, event.fromUserId);
    }
  }

  Future<void> _onRemoveFriend(
      RemoveFriend event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      // UPDATED: Calls the method on the new repository
      await _userRepository.removeFriend(user.uid, event.friendId);
    }
  }

  Future<void> _onBlockUser(BlockUser event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      // UPDATED: Calls the method on the new repository
      await _userRepository.blockUser(user.uid, event.userIdToBlock);
    }
  }

  Future<void> _onUnblockUser(
      UnblockUser event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      // UPDATED: Calls the method on the new repository
      await _userRepository.unblockUser(user.uid, event.userIdToUnblock);
    }
  }

  Future<void> _onToggleFavoriteFriend(
      ToggleFavoriteFriend event, Emitter<FriendsState> emit) async {
    debugPrint(
        "Toggling favorite status is not implemented in the current data model.");
  }

  @override
  Future<void> close() {
    _friendshipSubscription?.cancel();
    return super.close();
  }
}
