part of 'season_pass_bloc.dart';

@immutable
abstract class SeasonPassEvent extends Equatable {
  const SeasonPassEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load all data for the current season pass.
class LoadSeasonPass extends SeasonPassEvent {}

/// Event triggered when a user taps the "Claim" button for a reward.
class ClaimReward extends SeasonPassEvent {
  final SeasonPassReward reward;

  const ClaimReward({required this.reward});

  @override
  List<Object?> get props => [reward];
}

/// Internal event to push updated data to the UI.
class _SeasonPassUpdated extends SeasonPassEvent {
  final Season currentSeason;
  final List<SeasonPassReward> rewards;
  final UserModel user;

  const _SeasonPassUpdated({
    required this.currentSeason,
    required this.rewards,
    required this.user,
  });

  @override
  List<Object?> get props => [currentSeason, rewards, user];
}
