import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freegram/models/user_model.dart';

/// A repository for all store and currency-related operations.
class StoreRepository {
  final FirebaseFirestore _db;

  StoreRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Grants a reward to a user for watching an ad.
  Future<void> grantAdReward(String userId) {
    return _db.collection('users').doc(userId).update({
      'superLikes': FieldValue.increment(1),
    });
  }

  /// Handles the purchase of an item using in-app coins.
  Future<void> purchaseWithCoins(String userId,
      {required int coinCost, required int superLikeAmount}) async {
    final userRef = _db.collection('users').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        throw Exception("User does not exist!");
      }
      final user = UserModel.fromDoc(snapshot);

      if (user.coins < coinCost) {
        throw Exception("Not enough coins.");
      }

      transaction.update(userRef, {
        'coins': FieldValue.increment(-coinCost),
        'superLikes': FieldValue.increment(superLikeAmount),
      });
    });
  }
}
