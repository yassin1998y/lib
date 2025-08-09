import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:freegram/blocs/auth_bloc.dart';
import 'package:freegram/blocs/nearby_bloc.dart';
import 'package:freegram/blocs/profile_bloc.dart';
import 'package:freegram/firebase_options.dart';
import 'package:freegram/screens/login_screen.dart';
import 'package:freegram/screens/main_screen.dart';
import 'package:freegram/services/bluetooth_service.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:freegram/widgets/connectivity_wrapper.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Facebook SDK for Web.
  if (kIsWeb) {
    await FacebookAuth.instance.webAndDesktopInitialize(
      appId: "703196319414511", // Your App ID
      cookie: true,
      xfbml: true,
      version: "v20.0",
    );
  }

  // Initialize Firebase, Hive for local storage.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Hive.initFlutter();
  await Hive.openBox('nearby_contacts');
  await Hive.openBox('user_profiles');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Provide the FirestoreService at the top of the widget tree.
    return Provider<FirestoreService>(
      create: (_) => FirestoreService(),
      child: MultiBlocProvider(
        providers: [
          // Auth BLoC
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              firestoreService: context.read<FirestoreService>(),
            )..add(CheckAuthentication()),
          ),
          // Profile BLoC
          BlocProvider<ProfileBloc>(
            create: (context) => ProfileBloc(
              firestoreService: context.read<FirestoreService>(),
            ),
          ),
          // **NEW**: Nearby BLoC
          // This makes the NearbyBloc available throughout the app.
          BlocProvider<NearbyBloc>(
            create: (context) => NearbyBloc(
              bluetoothService: BluetoothService(),
            ),
          ),
        ],
        child: MaterialApp(
          title: 'Freegram',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFF0F2F5),
          ),
          home: const ConnectivityWrapper(
            child: AuthWrapper(),
          ),
        ),
      ),
    );
  }
}

/// A wrapper that listens to the authentication state and shows the
/// appropriate screen (Login or MainScreen).
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is Authenticated) {
          return const MainScreen();
        }
        // For any other state (Initial, Unauthenticated, AuthError), show the LoginScreen.
        return const LoginScreen();
      },
    );
  }
}
