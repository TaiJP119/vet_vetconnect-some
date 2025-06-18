import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../global/common/toast.dart';
import 'package:flutter/material.dart'; // Import this for Navigator

class FirebaseAuthService {
  FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn _googleSignIn = GoogleSignIn();

  // Sign up with email and password
  Future<User?> signUpWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      await _storeUserDetails(credential.user);
      return credential.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        showToast(message: 'The email address is already in use.');
      } else {
        showToast(message: 'An error occurred: ${e.code}');
      }
    }
    return null;
  }

  // Sign in with email and password
  Future<User?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return credential.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        showToast(message: 'Invalid email or password.');
      } else {
        showToast(message: 'An error occurred: ${e.code}');
      }
    }
    return null;
  }

  // Sign in with Google
  Future<User?> signInWithGoogle(BuildContext context) async {
    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // The user canceled the login process
        return null;
      }

      // Obtain the Google authentication details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential for Firebase with the Google sign-in data
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in with Firebase using the Google credentials
      UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      // After successful sign-in, ensure user data is in Firestore
      await _ensureUserDocument(userCredential.user);

      // Check if the user needs to complete their profile
      await _checkAndStoreUserDetails(userCredential.user, context);

      return userCredential.user;
    } catch (e) {
      showToast(message: "Error during Google sign-in: $e");
    }
    return null;
  }

  // Ensure user document exists in Firestore
  Future<void> _ensureUserDocument(User? user) async {
    if (user != null) {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      DocumentSnapshot userDoc = await userRef.get();

      if (!userDoc.exists) {
        // If the document doesn't exist, create it with basic info
        await userRef.set({
          'email': user.email,
          // 'userID': user.uid,
          'username': user.displayName ?? user.email?.split('@')[0],
          'userRole': 'customer', // Default role
          'contact': "", // Empty contact field
          'address': "", // Empty address field
          // 'googleemail': user.email, // Store email as googleemail
        });
      }
    }
  }

  // Helper function to check if the user has completed their profile
  Future<void> _checkAndStoreUserDetails(
      User? user, BuildContext context) async {
    if (user != null) {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      // Check if the user already exists in Firestore
      DocumentSnapshot userDoc = await userRef.get();

      // Check if the user document exists and if any of the necessary fields are missing or empty
      if (!userDoc.exists ||
          userDoc['username'] == null ||
          userDoc['username'] == "" ||
          userDoc['contact'] == null ||
          userDoc['contact'] == "" ||
          userDoc['address'] == null ||
          userDoc['address'] == "") {
        // If not, store user email and other default details and prompt them to fill in profile
        await _storeUserDetails(user); // Call the method to store user details

        // Redirect the user to the profile completion screen
        // Navigator.pushNamed(context, '/completeProfile');
      }
    }
  }

  // Method to store user details in Firestore
  Future<void> _storeUserDetails(User? user) async {
    if (user != null) {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      // Read current user document first
      final userDoc = await userRef.get();
      final existingData = userDoc.data();

      // Only set userRole to 'customer' if it's not already set
      final String currentRole =
          existingData != null && existingData.containsKey('userRole')
              ? existingData['userRole']
              : 'customer';

      await userRef.set({
        'email': user.email,
        'username': user.displayName ?? user.email?.split('@')[0],
        'userRole': currentRole, // 🔒 Preserve existing role
        'contact': existingData?['contact'] ?? "", // Preserve or default
        'address': existingData?['address'] ?? "",
      }, SetOptions(merge: true));
    }
  }

  Future<void> saveUserTokenToFirestore(String userId) async {
    final fcmToken = await FirebaseMessaging.instance.getToken();

    // Make sure the token is not null before saving it to Firestore
    if (fcmToken != null) {
      try {
        // Update the Firestore user's document with the FCM token
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'fcmToken': fcmToken,
        });
        print("FCM Token saved successfully for user: $userId");
      } catch (error) {
        print("Error saving FCM Token: $error");
      }
    } else {
      print("FCM Token is null");
    }
  }

  // Sign out the user
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
