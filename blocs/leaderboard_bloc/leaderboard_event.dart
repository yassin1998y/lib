part of 'leaderboard_bloc.dart';

@immutable
abstract class LeaderboardEvent extends Equatable {
  const LeaderboardEvent();

  @override
  List<Object> get props => [];
}

/// Event to load the initial leaderboard data.
class LoadLeaderboard extends LeaderboardEvent {}

/// Event triggered when the user switches between the Friends, Country, and Global tabs.
class SwitchLeaderboardTab extends LeaderboardEvent {
  final int tabIndex; // 0: Friends, 1: Country, 2: Global

  const SwitchLeaderboardTab({required this.tabIndex});

  @override
  List<Object> get props => [tabIndex];
}

/// Internal event to push updated data to the UI.
class _LeaderboardUpdated extends LeaderboardEvent {
  final List<DocumentSnapshot> rankings;

  const _LeaderboardUpdated({required this.rankings});

  @override
  List<Object> get props => [rankings];
}
