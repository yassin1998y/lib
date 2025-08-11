import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // FIX: Added import for debugPrint
import 'package:freegram/models/user_model.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:meta/meta.dart';

part 'friends_event.dart';
part 'friends_state.dart';

class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  final FirestoreService _firestoreService;
  final FirebaseAuth _firebaseAuth;
  StreamSubscription<UserModel>? _friendshipSubscription;

  FriendsBloc({
    required FirestoreService firestoreService,
    FirebaseAuth? firebaseAuth,
  })  : _firestoreService = firestoreService,
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
    _friendshipSubscription = _firestoreService.getUserStream(user.uid).listen(
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

      // Optimistically update the UI
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
        // FIX: Added the missing required parameter
        lastFreeSuperLike: currentState.user.lastFreeSuperLike,
      );
      emit(FriendsRequestSent(user: optimisticUser));

      // Perform the actual backend operation
      await _firestoreService.sendFriendRequest(user.uid, event.toUserId);
      // The user stream will push the final, correct state from Firestore automatically.
    }
  }

  Future<void> _onAcceptFriendRequest(
      AcceptFriendRequest event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _firestoreService.acceptFriendRequest(user.uid, event.fromUserId);
    }
  }

  Future<void> _onDeclineFriendRequest(
      DeclineFriendRequest event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _firestoreService.declineFriendRequest(user.uid, event.fromUserId);
    }
  }

  Future<void> _onRemoveFriend(
      RemoveFriend event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _firestoreService.removeFriend(user.uid, event.friendId);
    }
  }

  Future<void> _onBlockUser(BlockUser event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _firestoreService.blockUser(user.uid, event.userIdToBlock);
    }
  }

  Future<void> _onUnblockUser(
      UnblockUser event, Emitter<FriendsState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await _firestoreService.unblockUser(user.uid, event.userIdToUnblock);
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
