import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/auth_bloc.dart';
import 'package:freegram/blocs/friends_bloc/friends_bloc.dart';
import 'package:freegram/blocs/nearby_bloc.dart';
import 'package:freegram/blocs/profile_bloc.dart';
import 'package:freegram/firebase_options.dart';
import 'package:freegram/screens/edit_profile_screen.dart';
import 'package:freegram/screens/login_screen.dart';
import 'package:freegram/screens/main_screen.dart';
import 'package:freegram/screens/onboarding_screen.dart';
import 'package:freegram/services/bluetooth_service.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:freegram/widgets/connectivity_wrapper.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the Google Mobile Ads SDK
  MobileAds.instance.initialize();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox('nearby_contacts');
  await Hive.openBox('user_profiles');
  await Hive.openBox('settings');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Centralized FirestoreService instance
    final firestoreService = FirestoreService();

    return MultiProvider(
      providers: [
        Provider<FirestoreService>.value(value: firestoreService),
        Provider<BluetoothService>(
          create: (_) => BluetoothService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              firestoreService: context.read<FirestoreService>(),
            )..add(CheckAuthentication()),
          ),
          BlocProvider<ProfileBloc>(
            create: (context) => ProfileBloc(
              firestoreService: context.read<FirestoreService>(),
            ),
          ),
          BlocProvider<NearbyBloc>(
            create: (context) => NearbyBloc(
              bluetoothService: context.read<BluetoothService>(),
            ),
          ),
          BlocProvider<FriendsBloc>(
            create: (context) => FriendsBloc(
              firestoreService: context.read<FirestoreService>(),
            ),
          ),
        ],
        child: MaterialApp(
          title: 'Freegram',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFFAFAFA),
          ),
          home: const ConnectivityWrapper(
            child: AuthWrapper(),
          ),
        ),
      ),
    );
  }
}

/// A wrapper widget that listens to the authentication state and shows the
/// appropriate screen (Login, Main, or EditProfile).
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is Authenticated) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: context
                .read<FirestoreService>()
                .getUser(state.user.uid)
                .then((model) => model.toMap()),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasData && snapshot.data != null) {
                final userData = snapshot.data!;
                final bool isProfileComplete =
                    userData['age'] != null &&
                        userData['age'] > 0 &&
                        userData['country'] != null &&
                        (userData['country'] as String).isNotEmpty;

                if (isProfileComplete) {
                  // If profile is complete, show the MainScreen but check
                  // if we need to show onboarding on top of it.
                  return const MainScreenWrapper();
                } else {
                  // If the profile is not complete, force the user to the edit screen
                  return EditProfileScreen(
                    currentUserData: userData,
                    isCompletingProfile: true,
                  );
                }
              }
              // If there's no user data, default to the login screen
              return const LoginScreen();
            },
          );
        }
        // If the user is not authenticated, show the login screen
        return const LoginScreen();
      },
    );
  }
}

/// A wrapper for the MainScreen that handles showing the OnboardingScreen
/// on top of it the first time the user logs in.
class MainScreenWrapper extends StatefulWidget {
  const MainScreenWrapper({super.key});

  @override
  State<MainScreenWrapper> createState() => _MainScreenWrapperState();
}

class _MainScreenWrapperState extends State<MainScreenWrapper> {
  @override
  void initState() {
    super.initState();
    // This ensures the check happens after the first frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOnboarding();
    });
  }

  void _checkOnboarding() {
    final settingsBox = Hive.box('settings');
    final bool hasSeenOnboarding =
    settingsBox.get('hasSeenOnboarding', defaultValue: false);

    if (!hasSeenOnboarding && mounted) {
      // Present OnboardingScreen as a full-screen dialog (modal route).
      // This pushes it on top of the existing MainScreen.
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => const OnboardingScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // This widget always builds the MainScreen.
    // The onboarding check in initState determines if something appears on top.
    return const MainScreen();
  }
}
