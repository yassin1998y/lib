import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freegram/models/season_model.dart';
import 'package:freegram/models/season_pass_reward.dart';
import 'package:freegram/models/user_model.dart';

/// A repository for all gamification features like XP, levels, seasons, and leaderboards.
class GamificationRepository {
  final FirebaseFirestore _db;

  GamificationRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // --- XP & Level Methods ---

  /// Adds XP to a user and updates their level if necessary.
  /// Also updates the seasonal leaderboard ranking in the same transaction.
  Future<void> addXp(String userId, int amount, {bool isSeasonal = false}) async {
    final userRef = _db.collection('users').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) throw Exception("User does not exist!");

      final user = UserModel.fromDoc(snapshot);
      Map<String, dynamic> updates = {};

      // Update lifetime XP and level
      final newXp = user.xp + amount;
      final newLevel = 1 + (newXp ~/ 1000);
      updates['xp'] = newXp;
      if (newLevel > user.level) {
        updates['level'] = newLevel;
      }

      // Prepare leaderboard data
      Map<String, dynamic> leaderboardData = {
        'username': user.username,
        'photoUrl': user.photoUrl,
        'country': user.country,
        'level': user.level, // Use the *old* level for the update
        'xp': user.xp,       // And the *old* XP
      };

      // Update seasonal XP and level if applicable
      if (isSeasonal) {
        final newSeasonXp = user.seasonXp + amount;
        final newSeasonLevel = 1 + (newSeasonXp ~/ 500);
        updates['seasonXp'] = newSeasonXp;
        if (newSeasonLevel > user.seasonLevel) {
          updates['seasonLevel'] = newSeasonLevel;
        }
        // Update leaderboard data with the new seasonal progress
        leaderboardData['level'] = newSeasonLevel;
        leaderboardData['xp'] = newSeasonXp;
      }

      // Only update the leaderboard if a season is active
      if (user.currentSeasonId.isNotEmpty) {
        final leaderboardRef = _db
            .collection('seasonal_leaderboards')
            .doc(user.currentSeasonId)
            .collection('rankings')
            .doc(userId);
        transaction.set(leaderboardRef, leaderboardData, SetOptions(merge: true));
      }

      transaction.update(userRef, updates);
    });
  }


  // --- Seasonal Pass Methods ---

  /// Gets the currently active season.
  Future<Season?> getCurrentSeason() async {
    final now = DateTime.now();
    final snapshot = await _db
        .collection('seasons')
        .where('startDate', isLessThanOrEqualTo: now)
        .orderBy('startDate', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final season = Season.fromDoc(snapshot.docs.first);

    // If the latest season has already ended, there is no active season.
    if (now.isAfter(season.endDate)) return null;

    return season;
  }

  /// Fetches all rewards for a specific season.
  Future<List<SeasonPassReward>> getRewardsForSeason(String seasonId) async {
    final snapshot = await _db
        .collection('seasons')
        .doc(seasonId)
        .collection('rewards')
        .orderBy('level')
        .get();
    return snapshot.docs.map((doc) => SeasonPassReward.fromDoc(doc)).toList();
  }

  /// Checks if the user's season data is up-to-date and resets it if a new season has started.
  Future<void> checkAndResetSeason(String userId, Season currentSeason) async {
    final userRef = _db.collection('users').doc(userId);
    final userDoc = await userRef.get();
    final user = UserModel.fromDoc(userDoc);

    if (user.currentSeasonId != currentSeason.id) {
      await userRef.update({
        'currentSeasonId': currentSeason.id,
        'seasonXp': 0,
        'seasonLevel': 0,
        'claimedSeasonRewards': [],
      });
    }
  }

  /// Claims a season pass reward for a user.
  Future<void> claimSeasonReward(String userId, SeasonPassReward reward) async {
    final userRef = _db.collection('users').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) throw Exception("User does not exist!");

      final user = UserModel.fromDoc(snapshot);

      if (user.seasonLevel < reward.level) {
        throw Exception("You have not reached the required level yet.");
      }
      if (user.claimedSeasonRewards.contains(reward.level)) {
        throw Exception("You have already claimed this reward.");
      }

      Map<String, dynamic> updates = {
        'claimedSeasonRewards': FieldValue.arrayUnion([reward.level])
      };

      switch (reward.type) {
        case RewardType.coins:
          updates['coins'] = FieldValue.increment(reward.amount);
          break;
        case RewardType.superLikes:
          updates['superLikes'] = FieldValue.increment(reward.amount);
          break;
        default:
        // For other reward types like badges, you might add logic here
          break;
      }

      transaction.update(userRef, updates);
    });
  }

  // --- Leaderboard Methods ---

  /// Fetches the global leaderboard for a given season.
  Future<QuerySnapshot> getGlobalLeaderboard(String seasonId, {int limit = 100}) {
    return _db
        .collection('seasonal_leaderboards')
        .doc(seasonId)
        .collection('rankings')
        .orderBy('level', descending: true)
        .orderBy('xp', descending: true)
        .limit(limit)
        .get();
  }

  /// Fetches the country-specific leaderboard for a given season.
  Future<QuerySnapshot> getCountryLeaderboard(String seasonId, String country, {int limit = 100}) {
    return _db
        .collection('seasonal_leaderboards')
        .doc(seasonId)
        .collection('rankings')
        .where('country', isEqualTo: country)
        .orderBy('level', descending: true)
        .orderBy('xp', descending: true)
        .limit(limit)
        .get();
  }

  /// Fetches the leaderboard data for a specific list of friends.
  Future<List<DocumentSnapshot>> getFriendsLeaderboard(String seasonId, List<String> friendIds) async {
    if (friendIds.isEmpty) {
      return [];
    }
    final rankingsRef = _db.collection('seasonal_leaderboards').doc(seasonId).collection('rankings');
    final List<Future<DocumentSnapshot>> futures = [];
    // Firestore 'in' queries are limited to 30 items, so we fetch one by one for simplicity.
    // For larger friend lists, this could be optimized by batching requests.
    for (String id in friendIds) {
      futures.add(rankingsRef.doc(id).get());
    }
    final results = await Future.wait(futures);
    // Filter out friends who may not have a leaderboard entry yet
    return results.where((doc) => doc.exists).toList();
  }

  /// Fetches a single user's ranking document from the leaderboard.
  Future<DocumentSnapshot> getUserRanking(String seasonId, String userId) {
    return _db
        .collection('seasonal_leaderboards')
        .doc(seasonId)
        .collection('rankings')
        .doc(userId)
        .get();
  }
}
