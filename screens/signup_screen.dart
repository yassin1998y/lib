import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:provider/provider.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // Controllers to manage the input from text fields.
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Global key to validate the form.
  final _formKey = GlobalKey<FormState>();

  // State variable to manage the loading indicator.
  bool _isLoading = false;

  @override
  void dispose() {
    // Dispose controllers to free up resources when the widget is removed.
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Validates the form and attempts to sign up a new user.
  Future<void> _signUp() async {
    // 1. Validate the form using the GlobalKey. If invalid, stop execution.
    if (!_formKey.currentState!.validate()) return;

    // Prevent multiple submissions while an operation is in progress.
    if (_isLoading) return;

    // 2. Set loading state to true to show the progress indicator.
    setState(() {
      _isLoading = true;
    });

    // Keep references to context-dependent objects before the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final firestoreService = context.read<FirestoreService>();

    try {
      // 3. Create the user with Firebase Authentication.
      UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      User? user = userCredential.user;

      if (user != null) {
        // 4. Update the user's display name in Firebase Auth.
        await user.updateDisplayName(_usernameController.text.trim());

        // 5. Use the centralized FirestoreService to create the user document.
        await firestoreService.createUser(
          uid: user.uid,
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
        );
      }
      // After successful sign-up, the AuthBloc's authStateChanges listener
      // will automatically detect the new user and navigate to the main screen.
    } on FirebaseAuthException catch (e) {
      // 6. Handle specific Firebase authentication errors.
      // Check if the widget is still in the tree before showing a SnackBar.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'An unknown sign-up error occurred.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      // Handle any other unexpected errors.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('An unexpected error occurred: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      // 7. Always set loading state back to false, regardless of success or failure.
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Transparent app bar for a cleaner look.
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Ensure the back button is visible and uses the correct color.
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3498DB)),
                ),
                const SizedBox(height: 48.0),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Please enter a username'
                      : null,
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none),
                  ),
                  validator: (value) =>
                  (value == null || !value.contains('@'))
                      ? 'Please enter a valid email'
                      : null,
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none),
                  ),
                  validator: (value) => (value == null || value.length < 6)
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : const Text('Sign Up',
                      style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
