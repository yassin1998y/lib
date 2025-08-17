import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:freegram/models/season_model.dart';
import 'package:freegram/models/season_pass_reward.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/gamification_repository.dart'; // UPDATED IMPORT
import 'package:freegram/repositories/user_repository.dart';
import 'package:meta/meta.dart';

part 'season_pass_event.dart';
part 'season_pass_state.dart';

class SeasonPassBloc extends Bloc<SeasonPassEvent, SeasonPassState> {
  // UPDATED: Now uses GamificationRepository
  final GamificationRepository _gamificationRepository;
  final UserRepository _userRepository;
  final FirebaseAuth _firebaseAuth;
  StreamSubscription<UserModel>? _userSubscription;

  Season? _currentSeason;
  List<SeasonPassReward> _rewards = [];

  SeasonPassBloc({
    // UPDATED: Dependencies changed
    required GamificationRepository gamificationRepository,
    required UserRepository userRepository,
    FirebaseAuth? firebaseAuth,
  })  : _gamificationRepository = gamificationRepository,
        _userRepository = userRepository,
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
      // UPDATED: Uses GamificationRepository
      _currentSeason = await _gamificationRepository.getCurrentSeason();
      if (_currentSeason == null) {
        emit(const SeasonPassError("No active season found."));
        return;
      }

      // UPDATED: Uses GamificationRepository
      await _gamificationRepository.checkAndResetSeason(user.uid, _currentSeason!);
      _rewards = await _gamificationRepository.getRewardsForSeason(_currentSeason!.id);

      _userSubscription?.cancel();
      _userSubscription =
          _userRepository.getUserStream(user.uid).listen((userModel) {
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
      // UPDATED: Uses GamificationRepository
      await _gamificationRepository.claimSeasonReward(user.uid, event.reward);
    } catch (e) {
      debugPrint("Error claiming reward: $e");
      // Optionally, emit an error state to the UI
      // emit(SeasonPassError("Failed to claim reward: ${e.toString()}"));
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
