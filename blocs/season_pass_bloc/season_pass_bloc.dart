import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // FIX: Added missing import for debugPrint
import 'package:freegram/models/season_model.dart';
import 'package:freegram/models/season_pass_reward.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:meta/meta.dart';

part 'season_pass_event.dart';
part 'season_pass_state.dart';

class SeasonPassBloc extends Bloc<SeasonPassEvent, SeasonPassState> {
  final FirestoreService _firestoreService;
  final FirebaseAuth _firebaseAuth;
  StreamSubscription<UserModel>? _userSubscription;

  Season? _currentSeason;
  List<SeasonPassReward> _rewards = [];

  SeasonPassBloc({
    required FirestoreService firestoreService,
    FirebaseAuth? firebaseAuth,
  })  : _firestoreService = firestoreService,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(SeasonPassInitial()) {
    on<LoadSeasonPass>(_onLoadSeasonPass);
    on<ClaimReward>(_onClaimReward);
    on<_SeasonPassUpdated>(_onSeasonPassUpdated);
  }

  Future<void> _onLoadSeasonPass(
      LoadSeasonPass event, Emitter<SeasonPassState> emit) async {
    emit(SeasonPassLoading());
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      emit(const SeasonPassError("User not authenticated."));
      return;
    }

    try {
      _currentSeason = await _firestoreService.getCurrentSeason();
      if (_currentSeason == null) {
        emit(const SeasonPassError("No active season found."));
        return;
      }

      await _firestoreService.checkAndResetSeason(user.uid, _currentSeason!);
      _rewards = await _firestoreService.getRewardsForSeason(_currentSeason!.id);

      _userSubscription?.cancel();
      _userSubscription =
          _firestoreService.getUserStream(user.uid).listen((userModel) {
            add(_SeasonPassUpdated(
              currentSeason: _currentSeason!,
              rewards: _rewards,
              user: userModel,
            ));
          });
    } catch (e) {
      emit(SeasonPassError(e.toString()));
    }
  }

  Future<void> _onClaimReward(
      ClaimReward event, Emitter<SeasonPassState> emit) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      emit(const SeasonPassError("User not authenticated."));
      return;
    }

    try {
      await _firestoreService.claimSeasonReward(user.uid, event.reward);
      // The user stream will automatically push the updated state.
    } catch (e) {
      // Optionally, emit a specific error state for claiming failures
      // For now, we'll let the loaded state persist.
      debugPrint("Error claiming reward: $e");
    }
  }

  void _onSeasonPassUpdated(
      _SeasonPassUpdated event, Emitter<SeasonPassState> emit) {
    emit(SeasonPassLoaded(
      currentSeason: event.currentSeason,
      rewards: event.rewards,
      user: event.user,
    ));
  }

  @override
  Future<void> close() {
    _userSubscription?.cancel();
    return super.close();
  }
}
