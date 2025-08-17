part of 'leaderboard_bloc.dart';

@immutable
abstract class LeaderboardState extends Equatable {
  const LeaderboardState();

  @override
  List<Object?> get props => [];
}

/// The initial state before any leaderboard data is loaded.
class LeaderboardInitial extends LeaderboardState {}

/// The state when leaderboard data is being fetched.
class LeaderboardLoading extends LeaderboardState {}

/// The state when leaderboard data has been successfully loaded.
class LeaderboardLoaded extends LeaderboardState {
  final List<DocumentSnapshot> rankings;
  final int currentTabIndex;
  final DocumentSnapshot? currentUserRanking;
  final int? currentUserRank;

  const LeaderboardLoaded({
    required this.rankings,
    required this.currentTabIndex,
    this.currentUserRanking,
    this.currentUserRank,
  });

  @override
  List<Object?> get props =>
      [rankings, currentTabIndex, currentUserRanking, currentUserRank];
}

/// The state when an error occurs while loading the leaderboard.
class LeaderboardError extends LeaderboardState {
  final String message;

  const LeaderboardError(this.message);

  @override
  List<Object> get props => [message];
}
