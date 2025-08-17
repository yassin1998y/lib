import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freegram/models/season_model.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/repositories/gamification_repository.dart'; // UPDATED IMPORT
import 'package:freegram/repositories/user_repository.dart';
import 'package:meta/meta.dart';

part 'leaderboard_event.dart';
part 'leaderboard_state.dart';

class LeaderboardBloc extends Bloc<LeaderboardEvent, LeaderboardState> {
  // UPDATED: Now uses GamificationRepository
  final GamificationRepository _gamificationRepository;
  final UserRepository _userRepository;
  final FirebaseAuth _firebaseAuth;

  Season? _currentSeason;
  UserModel? _currentUser;
  int _currentTabIndex = 2; // Default to Global leaderboard

  LeaderboardBloc({
    // UPDATED: Dependencies changed
    required GamificationRepository gamificationRepository,
    required UserRepository userRepository,
    FirebaseAuth? firebaseAuth,
  })  : _gamificationRepository = gamificationRepository,
        _userRepository = userRepository,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(LeaderboardInitial()) {
    on<LoadLeaderboard>(_onLoadLeaderboard);
    on<SwitchLeaderboardTab>(_onSwitchTab);
  }

  Future<void> _onLoadLeaderboard(
      LoadLeaderboard event, Emitter<LeaderboardState> emit) async {
    emit(LeaderboardLoading());
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      emit(const LeaderboardError("User not authenticated."));
      return;
    }

    try {
      // UPDATED: Uses GamificationRepository
      _currentSeason = await _gamificationRepository.getCurrentSeason();
      if (_currentSeason == null) {
        emit(const LeaderboardError("No active season found."));
        return;
      }

      _currentUser = await _userRepository.getUser(user.uid);
      await _fetchAndEmitRankings(emit);
    } catch (e) {
      emit(LeaderboardError(e.toString()));
    }
  }

  Future<void> _onSwitchTab(
      SwitchLeaderboardTab event, Emitter<LeaderboardState> emit) async {
    if (_currentSeason == null || _currentUser == null) {
      add(LoadLeaderboard()); // Reload data if it's missing
      return;
    }
    _currentTabIndex = event.tabIndex;
    emit(LeaderboardLoading());
    try {
      await _fetchAndEmitRankings(emit);
    } catch (e) {
      emit(LeaderboardError(e.toString()));
    }
  }

  Future<void> _fetchAndEmitRankings(Emitter<LeaderboardState> emit) async {
    if (_currentSeason == null || _currentUser == null) {
      emit(const LeaderboardError("Cannot fetch rankings without an active season or user."));
      return;
    }

    List<DocumentSnapshot> rankings = [];
    switch (_currentTabIndex) {
      case 0: // Friends
        final friendIds = _currentUser?.friends ?? [];
        // UPDATED: Uses GamificationRepository
        rankings = await _gamificationRepository.getFriendsLeaderboard(_currentSeason!.id, friendIds);
        // UPDATED: Uses GamificationRepository
        final currentUserRankingDoc = await _gamificationRepository
            .getUserRanking(_currentSeason!.id, _currentUser!.id);
        if (currentUserRankingDoc.exists) {
          rankings.add(currentUserRankingDoc);
        }
        rankings.sort((a, b) {
          final levelA = a['level'] as int;
          final levelB = b['level'] as int;
          if (levelA != levelB) return levelB.compareTo(levelA);
          final xpA = a['xp'] as int;
          final xpB = b['xp'] as int;
          return xpB.compareTo(xpA);
        });
        break;
      case 1: // Country
        final country = _currentUser?.country ?? '';
        if (country.isNotEmpty) {
          // UPDATED: Uses GamificationRepository
          final snapshot = await _gamificationRepository.getCountryLeaderboard(_currentSeason!.id, country);
          rankings = snapshot.docs;
        }
        break;
      case 2: // Global
      default:
      // UPDATED: Uses GamificationRepository
        final snapshot = await _gamificationRepository.getGlobalLeaderboard(_currentSeason!.id);
        rankings = snapshot.docs;
        break;
    }

    // UPDATED: Uses GamificationRepository
    final currentUserRankingDoc = await _gamificationRepository.getUserRanking(
        _currentSeason!.id, _currentUser!.id);

    final currentUserRank = rankings.indexWhere((doc) => doc.id == _currentUser!.id);

    emit(LeaderboardLoaded(
      rankings: rankings,
      currentTabIndex: _currentTabIndex,
      currentUserRanking: currentUserRankingDoc.exists ? currentUserRankingDoc : null,
      currentUserRank: currentUserRank != -1 ? currentUserRank + 1 : null,
    ));
  }
}
