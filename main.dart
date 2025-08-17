import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/auth_bloc.dart';
import 'package:freegram/blocs/friends_bloc/friends_bloc.dart';
import 'package:freegram/blocs/nearby_bloc.dart';
import 'package:freegram/blocs/profile_bloc.dart';
import 'package:freegram/firebase_options.dart';
import 'package:freegram/repositories/auth_repository.dart';
import 'package:freegram/repositories/chat_repository.dart';
import 'package:freegram/repositories/gamification_repository.dart';
import 'package:freegram/repositories/notification_repository.dart';
import 'package:freegram/repositories/post_repository.dart';
import 'package:freegram/repositories/store_repository.dart';
import 'package:freegram/repositories/task_repository.dart';
import 'package:freegram/repositories/user_repository.dart';
import 'package:freegram/screens/edit_profile_screen.dart';
import 'package:freegram/screens/login_screen.dart';
import 'package:freegram/screens/main_screen.dart';
import 'package:freegram/screens/onboarding_screen.dart';
import 'package:freegram/services/bluetooth_service.dart';
import 'package:freegram/widgets/connectivity_wrapper.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    MobileAds.instance.initialize();
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
    // Instantiate all repositories.
    final authRepository = AuthRepository();
    final notificationRepository = NotificationRepository();
    final gamificationRepository = GamificationRepository();
    final taskRepository =
    TaskRepository(gamificationRepository: gamificationRepository);
    final storeRepository = StoreRepository();

    // Instantiate repositories that depend on others.
    final userRepository = UserRepository(
      notificationRepository: notificationRepository,
      gamificationRepository: gamificationRepository,
    );
    final postRepository = PostRepository(
      userRepository: userRepository,
      gamificationRepository: gamificationRepository,
      taskRepository: taskRepository,
      notificationRepository: notificationRepository,
    );
    final chatRepository = ChatRepository(
      gamificationRepository: gamificationRepository,
      taskRepository: taskRepository,
    );

    return MultiProvider(
      providers: [
        // Provide all repositories to the widget tree.
        Provider<AuthRepository>.value(value: authRepository),
        Provider<UserRepository>.value(value: userRepository),
        Provider<PostRepository>.value(value: postRepository),
        Provider<ChatRepository>.value(value: chatRepository),
        Provider<NotificationRepository>.value(value: notificationRepository),
        Provider<GamificationRepository>.value(value: gamificationRepository),
        Provider<TaskRepository>.value(value: taskRepository),
        Provider<StoreRepository>.value(value: storeRepository),
        Provider<BluetoothService>(
          create: (_) => BluetoothService(userRepository: userRepository),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepository>(),
            )..add(CheckAuthentication()),
          ),
          BlocProvider<ProfileBloc>(
            create: (context) => ProfileBloc(
              userRepository: context.read<UserRepository>(),
            ),
          ),
          BlocProvider<NearbyBloc>(
            create: (context) => NearbyBloc(
              bluetoothService: context.read<BluetoothService>(),
            ),
          ),
          BlocProvider<FriendsBloc>(
            create: (context) => FriendsBloc(
              userRepository: context.read<UserRepository>(),
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

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is Authenticated) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: context
                .read<UserRepository>()
                .getUser(state.user.uid)
                .then((model) => model.toMap()),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasData && snapshot.data != null) {
                final userData = snapshot.data!;
                final bool isProfileComplete = userData['age'] != null &&
                    userData['age'] > 0 &&
                    userData['country'] != null &&
                    (userData['country'] as String).isNotEmpty;

                if (isProfileComplete) {
                  return const MainScreenWrapper();
                } else {
                  return EditProfileScreen(
                    currentUserData: userData,
                    isCompletingProfile: true,
                  );
                }
              }
              return const LoginScreen();
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}

class MainScreenWrapper extends StatefulWidget {
  const MainScreenWrapper({super.key});

  @override
  State<MainScreenWrapper> createState() => _MainScreenWrapperState();
}

class _MainScreenWrapperState extends State<MainScreenWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOnboarding();
    });
  }

  void _checkOnboarding() {
    final settingsBox = Hive.box('settings');
    final bool hasSeenOnboarding =
    settingsBox.get('hasSeenOnboarding', defaultValue: false);

    if (!hasSeenOnboarding && mounted) {
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
    return const MainScreen();
  }
}
