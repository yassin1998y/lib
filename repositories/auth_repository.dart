import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

/// A repository dedicated to handling authentication and user creation.
class AuthRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  AuthRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  /// Creates a new user document in Firestore after sign-up.
  Future<void> createUser({
    required String uid,
    required String username,
    required String email,
    String? photoUrl,
  }) {
    final newUser = UserModel(
      id: uid,
      username: username,
      email: email,
      photoUrl: photoUrl ?? '',
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
      lastFreeSuperLike: DateTime.now().subtract(const Duration(days: 1)),
    );
    return _db.collection('users').doc(uid).set(newUser.toMap());
  }

  /// Handles the entire Google Sign-In flow.
  Future<UserCredential> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
          code: 'ERROR_ABORTED_BY_USER', message: 'Sign in aborted by user');
    }
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;

    if (user != null) {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await createUser(
          uid: user.uid,
          username: user.displayName ?? 'Google User',
          email: user.email ?? '',
          photoUrl: user.photoURL,
        );
      }
    }
    return userCredential;
  }

  /// Handles the entire Facebook Sign-In flow.
  Future<UserCredential> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login();
    if (result.status == LoginStatus.success) {
      final AccessToken accessToken = result.accessToken!;
      final AuthCredential credential =
          FacebookAuthProvider.credential(accessToken.token);
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final userDoc = await _db.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          final userData = await FacebookAuth.instance.getUserData();
          await createUser(
            uid: user.uid,
            username: userData['name'] ?? 'Facebook User',
            email: userData['email'] ?? '',
            photoUrl: userData['picture']?['data']?['url'],
          );
        }
      }
      return userCredential;
    } else {
      throw FirebaseAuthException(
        code: 'ERROR_FACEBOOK_LOGIN_FAILED',
        message: result.message,
      );
    }
  }

  /// Signs the user out from Firebase and any social providers.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint("Error signing out from Google: $e");
    }
    try {
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint("Error signing out from Facebook: $e");
    }
    await _auth.signOut();
  }
}
