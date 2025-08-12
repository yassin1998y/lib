part of 'season_pass_bloc.dart';

@immutable
abstract class SeasonPassState extends Equatable {
  const SeasonPassState();

  @override
  List<Object?> get props => [];
}

class SeasonPassInitial extends SeasonPassState {}

class SeasonPassLoading extends SeasonPassState {}

class SeasonPassLoaded extends SeasonPassState {
  final Season currentSeason;
  final List<SeasonPassReward> rewards;
  final UserModel user;

  const SeasonPassLoaded({
    required this.currentSeason,
    required this.rewards,
    required this.user,
  });

  @override
  List<Object?> get props => [currentSeason, rewards, user];
}

class SeasonPassError extends SeasonPassState {
  final String message;

  const SeasonPassError(this.message);

  @override
  List<Object?> get props => [message];
}
