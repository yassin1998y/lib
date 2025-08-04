// main.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animations/animations.dart';
import 'package:card_swiper/card_swiper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart'; // NEW: Added for future Reels feature

import 'firebase_options.dart';
import 'seed_database.dart';
import 'services/firestore_service.dart';

// --- BLoC for Authentication ---
abstract class AuthEvent {}
class CheckAuthentication extends AuthEvent {}
class SignOut extends AuthEvent {}

abstract class AuthState {}
class AuthInitial extends AuthState {}
class Authenticated extends AuthState {
  final User user;
  Authenticated(this.user);
}
class Unauthenticated extends AuthState {}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final FirebaseAuth _firebaseAuth;
  StreamSubscription<User?>? _authStateSubscription;

  AuthBloc({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(AuthInitial()) {
    on<CheckAuthentication>((event, emit) {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        emit(Authenticated(user));
      } else {
        emit(Unauthenticated());
      }
    });

    on<SignOut>((event, emit) async {
      await _firebaseAuth.signOut();
      emit(Unauthenticated());
    });

    _authStateSubscription = _firebaseAuth.authStateChanges().listen((user) {
      add(CheckAuthentication());
    });
  }

  @override
  Future<void> close() {
    _authStateSubscription?.cancel();
    return super.close();
  }
}

// --- NEW: BLoC for Profile Management ---
abstract class ProfileEvent {}
class LoadProfile extends ProfileEvent {
  final String userId;
  LoadProfile(this.userId);
}
class UpdateProfile extends ProfileEvent {
  final String userId;
  final Map<String, dynamic> data;
  final XFile? imageFile;
  UpdateProfile({required this.userId, required this.data, this.imageFile});
}

abstract class ProfileState {}
class ProfileInitial extends ProfileState {}
class ProfileLoading extends ProfileState {}
class ProfileLoaded extends ProfileState {
  final DocumentSnapshot user;
  ProfileLoaded(this.user);
}
class ProfileUpdateSuccess extends ProfileState {}
class ProfileError extends ProfileState {
  final String message;
  ProfileError(this.message);
}

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final FirestoreService _firestoreService;
  final FirebaseAuth _firebaseAuth;

  ProfileBloc({required FirestoreService firestoreService, FirebaseAuth? firebaseAuth})
      : _firestoreService = firestoreService,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        super(ProfileInitial()) {
    on<LoadProfile>((event, emit) async {
      emit(ProfileLoading());
      try {
        final user = await _firestoreService.getUser(event.userId);
        if (user.exists) {
          emit(ProfileLoaded(user));
        } else {
          emit(ProfileError("User not found"));
        }
      } catch (e) {
        emit(ProfileError(e.toString()));
      }
    });

    on<UpdateProfile>((event, emit) async {
      emit(ProfileLoading());
      try {
        String? photoUrl;
        if (event.imageFile != null) {
          photoUrl = await _uploadToCloudinary(event.imageFile!);
        }

        final Map<String, dynamic> updatedData = Map.from(event.data);
        if (photoUrl != null) {
          updatedData['photoUrl'] = photoUrl;
        }

        await _firestoreService.updateUser(event.userId, updatedData);

        final currentUser = _firebaseAuth.currentUser!;
        if (updatedData.containsKey('username')) {
          await currentUser.updateDisplayName(updatedData['username']);
        }
        if (photoUrl != null) {
          await currentUser.updatePhotoURL(photoUrl);
        }

        emit(ProfileUpdateSuccess());
      } catch (e) {
        emit(ProfileError("Failed to update profile: $e"));
      }
    });
  }

  Future<String?> _uploadToCloudinary(XFile image) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'Prototype';

    final bytes = await image.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: image.name);
    request.files.add(multipartFile);

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    } else {
      return null;
    }
  }
}

// --- Service to broadcast Bluetooth status updates ---
enum NearbyStatus {
  idle,
  checkingPermissions,
  permissionsDenied,
  checkingAdapter,
  adapterOff,
  startingServices,
  advertising,
  scanning,
  userFound,
  error,
}

class BluetoothStatusService {
  final _statusController = StreamController<NearbyStatus>.broadcast();
  Stream<NearbyStatus> get statusStream => _statusController.stream;

  void updateStatus(NearbyStatus status) {
    _statusController.add(status);
  }

  void dispose() {
    _statusController.close();
  }
}

// Global instance to be accessible by the Bluetooth service and UI
final bluetoothStatusService = BluetoothStatusService();

// --- Bluetooth Service (Refactored for Platform-Specific Implementation) ---
abstract class BluetoothService {
  factory BluetoothService() => kIsWeb ? WebBluetoothService() : MobileBluetoothService();
  Future<void> start();
  Future<void> stop();
  void dispose();
}

class WebBluetoothService implements BluetoothService {
  @override
  Future<void> start() async {
    debugPrint("[Bluetooth] Web platform, BLE not supported.");
    bluetoothStatusService.updateStatus(NearbyStatus.error);
  }
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

class MobileBluetoothService implements BluetoothService {
  final _blePeripheral = FlutterBlePeripheral();
  final Guid _serviceUuid = Guid("cdd0dc25-5240-4158-a111-3a40b5215c50");
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  Future<bool> _requestPermissions() async {
    bluetoothStatusService.updateStatus(NearbyStatus.checkingPermissions);
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ].request();

      final allGranted = statuses.values.every((status) => status.isGranted);
      if (!allGranted) {
        debugPrint("[Bluetooth] Permissions not granted.");
        bluetoothStatusService.updateStatus(NearbyStatus.permissionsDenied);
      }
      return allGranted;
    }
    return true;
  }

  @override
  Future<void> start() async {
    await stop();
    bluetoothStatusService.updateStatus(NearbyStatus.startingServices);

    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("[Bluetooth] BLE not supported on this device.");
      bluetoothStatusService.updateStatus(NearbyStatus.error);
      return;
    }

    if (!await _requestPermissions()) return;

    bluetoothStatusService.updateStatus(NearbyStatus.checkingAdapter);
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      debugPrint("[Bluetooth] Adapter state changed to: $state");
      if (state == BluetoothAdapterState.on) {
        _startAdvertising();
        _startScanning();
      } else {
        bluetoothStatusService.updateStatus(NearbyStatus.adapterOff);
        stop();
      }
    });
  }

  Future<void> _startAdvertising() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final advertiseData = AdvertiseData(
      serviceUuid: _serviceUuid.toString(),
      manufacturerId: 0x0118,
      manufacturerData: utf8.encode(currentUser.uid),
    );

    try {
      if (await _blePeripheral.isAdvertising) await _blePeripheral.stop();
      await _blePeripheral.start(advertiseData: advertiseData);
      debugPrint("[Bluetooth] Started advertising with UID: ${currentUser.uid}");
      bluetoothStatusService.updateStatus(NearbyStatus.advertising);
    } catch (e) {
      debugPrint("[Bluetooth] Error starting advertising: $e");
      bluetoothStatusService.updateStatus(NearbyStatus.error);
    }
  }

  void _startScanning() {
    if (_isScanning) return;
    _isScanning = true;
    debugPrint("[Bluetooth] Starting scan...");
    bluetoothStatusService.updateStatus(NearbyStatus.scanning);

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.advertisementData.manufacturerData.containsKey(0x0118)) {
            final manufacturerData = r.advertisementData.manufacturerData[0x0118]!;
            final foundUserId = utf8.decode(manufacturerData);
            debugPrint("[Bluetooth] Found Freegram User: $foundUserId at RSSI: ${r.rssi}");
            bluetoothStatusService.updateStatus(NearbyStatus.userFound);
            if (foundUserId != FirebaseAuth.instance.currentUser?.uid) {
              _handleFoundUser(foundUserId);
            }
          }
        }
      }, onError: (e) {
        debugPrint("[Bluetooth] Scan error: $e");
        bluetoothStatusService.updateStatus(NearbyStatus.error);
      });
      FlutterBluePlus.startScan(timeout: null);
    } catch (e) {
      debugPrint("[Bluetooth] Could not start scan: $e");
      _isScanning = false;
      bluetoothStatusService.updateStatus(NearbyStatus.error);
    }
  }

  void _handleFoundUser(String foundUserId) {
    final box = Hive.box('nearby_contacts');
    final existingContact = box.get(foundUserId);
    if (existingContact == null || DateTime.now().difference(DateTime.parse(existingContact['timestamp'])).inHours >= 1) {
      debugPrint("[Bluetooth] New or expired contact found. Saving card for user: $foundUserId");
      box.put(foundUserId, {'id': foundUserId, 'timestamp': DateTime.now().toIso8601String()});
    }
  }

  @override
  Future<void> stop() async {
    debugPrint("[Bluetooth] Stopping services...");
    bluetoothStatusService.updateStatus(NearbyStatus.idle);
    _adapterStateSubscription?.cancel();
    _scanSubscription?.cancel();
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint("[Bluetooth] Error stopping scan: $e");
    }
    try {
      if (await _blePeripheral.isAdvertising) await _blePeripheral.stop();
    } catch (e) {
      debugPrint("[Bluetooth] Error stopping advertising: $e");
    }
    _isScanning = false;
  }

  @override
  void dispose() {
    stop();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('nearby_contacts');
  await Hive.openBox('user_profiles');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FreegramApp());
}

class FreegramApp extends StatelessWidget {
  const FreegramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<FirestoreService>(create: (_) => FirestoreService()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc()..add(CheckAuthentication()),
          ),
          BlocProvider<ProfileBloc>(
            create: (context) => ProfileBloc(firestoreService: context.read<FirestoreService>()),
          ),
        ],
        child: MaterialApp(
          title: 'Freegram',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFF1F5F8),
            visualDensity: VisualDensity.adaptivePlatformDensity,
            fontFamily: 'Inter',
          ),
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // Pre-load profile data when authenticated
          context.read<ProfileBloc>().add(LoadProfile(state.user.uid));
        }
      },
      builder: (context, state) {
        if (state is Authenticated) {
          return const ProfileCompletionWrapper();
        }
        if (state is Unauthenticated) {
          return const LoginScreen();
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class ProfileCompletionWrapper extends StatelessWidget {
  const ProfileCompletionWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = context.select((AuthBloc bloc) => (bloc.state as Authenticated).user);

    return StreamBuilder<DocumentSnapshot>(
      stream: context.read<FirestoreService>().getUserStream(currentUser.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const LoginScreen();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final age = userData['age'] as int? ?? 0;
        final gender = userData['gender'] as String? ?? '';
        final country = userData['country'] as String? ?? '';

        if (age == 0 || gender.isEmpty || country.isEmpty) {
          return EditProfileScreen(currentUserData: userData, isCompletingProfile: true);
        }

        return const MainScreen();
      },
    );
  }
}

// --- Login & Sign Up Screens ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Login failed')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Freegram', textAlign: TextAlign.center, style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF3498DB))),
                const SizedBox(height: 48.0),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: 'Email', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none)),
                  validator: (value) => (value == null || !value.contains('@')) ? 'Please enter a valid email' : null,
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none)),
                  validator: (value) => (value == null || value.length < 6) ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB), padding: const EdgeInsets.symmetric(vertical: 16.0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0))),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Log In', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
                const SizedBox(height: 16.0),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SignUpScreen())),
                  child: const Text("Don't have an account? Sign Up", style: TextStyle(color: Color(0xFF3498DB))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      User? user = userCredential.user;
      if (user != null) {
        await user.updateDisplayName(_usernameController.text.trim());
        await context.read<FirestoreService>().createUser(
          uid: user.uid,
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Sign up failed')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black87)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Create Account', textAlign: TextAlign.center, style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF3498DB))),
                const SizedBox(height: 48.0),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(labelText: 'Username', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none)),
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter a username' : null,
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: 'Email', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none)),
                  validator: (value) => (value == null || !value.contains('@')) ? 'Please enter a valid email' : null,
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none)),
                  validator: (value) => (value == null || value.length < 6) ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB), padding: const EdgeInsets.symmetric(vertical: 16.0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0))),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Sign Up', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Main Screen with Bottom Navigation ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget> _widgetOptions;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final currentUser = context.read<AuthBloc>().state as Authenticated;
    _setupFcm(currentUser.user.uid);
    _updateUserPresence(currentUser.user.uid, true);
    _widgetOptions = <Widget>[
      const FeedWidget(),
      const DiscoverScreen(),
      const ChatListScreen(),
      ProfileScreen(userId: currentUser.user.uid),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      if (state == AppLifecycleState.resumed) {
        _updateUserPresence(authState.user.uid, true);
      } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        _updateUserPresence(authState.user.uid, false);
      }
    }
  }

  Future<void> _updateUserPresence(String uid, bool isOnline) async {
    try {
      await context.read<FirestoreService>().updateUserPresence(uid, isOnline);
    } catch (e) {
      // Errors are expected if the user is offline, so we can ignore them.
    }
  }

  Future<void> _setupFcm(String uid) async {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission();
    final token = await fcm.getToken();
    if (token != null) {
      await context.read<FirestoreService>().updateUser(uid, {'fcmToken': token});
    }
    fcm.onTokenRefresh.listen((newToken) async {
      await context.read<FirestoreService>().updateUser(uid, {'fcmToken': newToken});
    });
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  // NEW: Helper to show image source selection bottom sheet
  Future<ImageSource?> _showImageSourceActionSheet(BuildContext context) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getFabConfig(int index) {
    switch (index) {
      case 0: // Feed
        return {
          'icon': Icons.add,
          'onPressed': () async {
            final source = await _showImageSourceActionSheet(context);
            if (source != null && mounted) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatePostScreen(imageSource: source)));
            }
          },
        };
      case 1: // Discover
        return {'icon': Icons.whatshot, 'onPressed': () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchScreen()))};
      case 2: // Chat
        return {'icon': Icons.edit, 'onPressed': () {/* TODO: Start new chat */}};
      default:
        return {'icon': Icons.add, 'onPressed': () {}};
    }
  }

  Widget _buildChatIconWithBadge() {
    final currentUser = (context.read<AuthBloc>().state as Authenticated).user;
    return StreamBuilder<int>(
      stream: context.read<FirestoreService>().getUnreadChatCountStream(currentUser.uid),
      builder: (context, snapshot) {
        final totalUnread = snapshot.data ?? 0;
        return Badge(
          label: Text(totalUnread.toString()),
          isLabelVisible: totalUnread > 0,
          child: _buildAnimatedIcon(Icons.chat_bubble_outline, 2),
        );
      },
    );
  }

  Widget _buildActivityIconWithBadge() {
    final currentUser = (context.read<AuthBloc>().state as Authenticated).user;
    return StreamBuilder<int>(
      stream: context.read<FirestoreService>().getUnreadNotificationCountStream(currentUser.uid),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return Badge(
          label: Text(unreadCount.toString()),
          isLabelVisible: unreadCount > 0,
          child: IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black87),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedIcon(IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    return IconButton(
      icon: Icon(icon, color: isSelected ? const Color(0xFF3498DB) : Colors.grey, size: isSelected ? 30 : 24),
      onPressed: () => _onItemTapped(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fabConfig = _getFabConfig(_selectedIndex);
    final bool showFab = _selectedIndex < 3;
    final authState = context.watch<AuthBloc>().state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Freegram', style: TextStyle(color: Color(0xFF3498DB), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          if (!kIsWeb) ScannerIcon(isScanning: _isScanning, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NearbyScreen()))),
          _buildActivityIconWithBadge(),
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.red),
            onPressed: () => DatabaseSeeder().seedUsers(context),
            tooltip: 'Seed Database',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout' && authState is Authenticated) {
                await _updateUserPresence(authState.user.uid, false);
                context.read<AuthBloc>().add(SignOut());
              }
            },
            itemBuilder: (BuildContext context) => [const PopupMenuItem<String>(value: 'logout', child: Text('Logout'))],
          ),
        ],
      ),
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, primaryAnimation, secondaryAnimation) => FadeThroughTransition(animation: primaryAnimation, secondaryAnimation: secondaryAnimation, child: child),
        child: IndexedStack(key: ValueKey<int>(_selectedIndex), index: _selectedIndex, children: _widgetOptions),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
        onPressed: fabConfig['onPressed'],
        backgroundColor: const Color(0xFF3498DB),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(fabConfig['icon'], key: ValueKey<int>(_selectedIndex), color: Colors.white),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildAnimatedIcon(Icons.home, 0),
            _buildAnimatedIcon(Icons.people_outline, 1),
            if (showFab) const SizedBox(width: 40),
            _buildChatIconWithBadge(),
            _buildAnimatedIcon(Icons.person_outline, 3),
          ],
        ),
      ),
    );
  }
}

// --- Discover Screen (REDESIGNED) ---
const List<String> _possibleInterests = [
  'Photography', 'Traveling', 'Hiking', 'Reading', 'Gaming', 'Cooking',
  'Movies', 'Music', 'Art', 'Sports', 'Yoga', 'Coding', 'Writing',
  'Dancing', 'Gardening', 'Fashion', 'Fitness', 'History',
];

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.white,
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.black,
          tabs: const [Tab(text: 'For You'), Tab(text: 'Explore')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [ForYouTab(), ExploreTab()],
      ),
    );
  }
}

// NEW: Compact User Card for Discover Grids
class CompactUserCard extends StatelessWidget {
  final DocumentSnapshot userDoc;
  const CompactUserCard({super.key, required this.userDoc});

  @override
  Widget build(BuildContext context) {
    final userData = userDoc.data() as Map<String, dynamic>;
    final userId = userDoc.id;
    final photoUrl = userData['photoUrl'];
    final username = userData['username'] ?? 'User';
    final isOnline = userData['presence'] ?? false;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          isScrollControlled: true,
          builder: (_) => UserInfoPopup(userId: userId),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: GridTile(
          footer: Container(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            color: Colors.black.withOpacity(0.5),
            child: Text(
              username,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photoUrl != null && photoUrl.isNotEmpty)
                Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 40, color: Colors.grey),
                )
              else
                const Icon(Icons.person, size: 40, color: Colors.grey),
              if (isOnline)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// REDESIGNED: Explore Tab with 5-column grid
class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});
  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  final _scrollController = ScrollController();
  List<DocumentSnapshot> _allUsers = [];
  List<DocumentSnapshot> _filteredUsers = [];
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _documentLimit = 25; // Increased limit for 5 columns

  String _searchQuery = '';
  String? _selectedCountry;
  RangeValues _ageRange = const RangeValues(18, 80);
  String _genderFilter = 'All';
  List<String> _selectedInterests = [];
  bool _showNearbyOnly = false;

  final List<String> _countries = ['All', 'USA', 'Canada', 'UK', 'Germany', 'France', 'Tunisia', 'Egypt', 'Algeria', 'Morocco'];

  @override
  void initState() {
    super.initState();
    _getUsers();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300 && !_isFetchingMore) {
        _getUsers();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _getUsers({bool isRefresh = false}) async {
    if (_isFetchingMore || _showNearbyOnly) return;
    if (isRefresh) {
      _allUsers = [];
      _lastDocument = null;
      _hasMore = true;
    }
    if (!_hasMore) return;

    setState(() {
      _isFetchingMore = true;
      if (_allUsers.isEmpty) _isLoading = true;
    });

    try {
      final querySnapshot = await context.read<FirestoreService>().getPaginatedUsers(
        limit: _documentLimit,
        lastDocument: _lastDocument,
      );

      if (querySnapshot.docs.length < _documentLimit) _hasMore = false;
      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        _allUsers.addAll(querySnapshot.docs);
      }
      _applyFilters();
    } catch (e) {
      debugPrint("Error fetching users: $e");
    }

    if (mounted) setState(() { _isFetchingMore = false; _isLoading = false; });
  }

  Future<void> _getNearbyUsers() async {
    setState(() => _isLoading = true);
    final nearbyBox = Hive.box('nearby_contacts');
    final profileBox = Hive.box('user_profiles');
    List<DocumentSnapshot> nearbyUsers = [];

    for (var key in nearbyBox.keys) {
      final profileData = profileBox.get(key);
      if (profileData != null) {
        nearbyUsers.add(MockDocumentSnapshot(key, Map<String, dynamic>.from(profileData)));
      } else {
        try {
          final doc = await context.read<FirestoreService>().getUser(key);
          if (doc.exists) {
            profileBox.put(key, doc.data());
            nearbyUsers.add(doc);
          }
        } catch (e) {
          debugPrint("Could not fetch nearby user profile: $e");
        }
      }
    }

    _allUsers = nearbyUsers;
    _applyFilters();
    setState(() => _isLoading = false);
  }

  void _applyFilters() {
    List<DocumentSnapshot> tempFiltered = List.from(_allUsers);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    tempFiltered = tempFiltered.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (doc.id == currentUserId) return false;

      final userAge = data['age'] as int? ?? 0;
      final userGender = data['gender'] as String? ?? '';
      final userCountry = data['country'] as String? ?? '';
      final username = data['username'] as String? ?? '';
      final userInterests = List<String>.from(data['interests'] ?? []);

      if (_searchQuery.isNotEmpty && !username.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
      if (_selectedCountry != null && _selectedCountry != 'All' && userCountry != _selectedCountry) return false;
      if (userAge < _ageRange.start || userAge > _ageRange.end) return false;
      if (_genderFilter != 'All' && userGender != _genderFilter) return false;
      if (_selectedInterests.isNotEmpty && !_selectedInterests.any((interest) => userInterests.contains(interest))) return false;
      return true;
    }).toList();

    tempFiltered.sort((a, b) {
      final aPresence = (a.data() as Map<String, dynamic>)['presence'] ?? false;
      final bPresence = (b.data() as Map<String, dynamic>)['presence'] ?? false;
      if (aPresence && !bPresence) return -1;
      if (!aPresence && bPresence) return 1;
      return 0;
    });

    if (mounted) setState(() => _filteredUsers = tempFiltered);
  }

  void _onFilterChanged() {
    if (_showNearbyOnly) {
      _getNearbyUsers();
    } else {
      _getUsers(isRefresh: true);
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.8,
              builder: (_, scrollController) => Container(
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    SwitchListTile(title: const Text('Show only nearby users'), value: _showNearbyOnly, onChanged: (val) => setModalState(() => _showNearbyOnly = val)),
                    const Divider(),
                    DropdownButtonFormField<String>(
                      value: _selectedCountry ?? 'All',
                      decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                      items: _countries.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                      onChanged: (newValue) => setModalState(() => _selectedCountry = newValue == 'All' ? null : newValue),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Age Range: ${_ageRange.start.round()} - ${_ageRange.end.round()}'),
                        RangeSlider(
                          values: _ageRange, min: 13, max: 100, divisions: 87,
                          labels: RangeLabels(_ageRange.start.round().toString(), _ageRange.end.round().toString()),
                          onChanged: (RangeValues values) => setModalState(() => _ageRange = values),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Gender'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['All', 'Male', 'Female'].map((gender) => ChoiceChip(
                        label: Text(gender),
                        selected: _genderFilter == gender,
                        onSelected: (selected) { if (selected) setModalState(() => _genderFilter = gender); },
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Interests'),
                    Wrap(
                      spacing: 8.0, runSpacing: 4.0,
                      children: _possibleInterests.map((interest) {
                        final isSelected = _selectedInterests.contains(interest);
                        return FilterChip(
                          label: Text(interest), selected: isSelected,
                          onSelected: (selected) => setModalState(() => selected ? _selectedInterests.add(interest) : _selectedInterests.remove(interest)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        child: const Text('Apply Filters'),
                        onPressed: () { _onFilterChanged(); Navigator.pop(context); },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFilters() {
    List<Widget> chips = [];
    if (_showNearbyOnly) chips.add(InputChip(label: const Text('Nearby'), onDeleted: () => setState(() { _showNearbyOnly = false; _onFilterChanged(); })));
    if (_selectedCountry != null && _selectedCountry != 'All') chips.add(InputChip(label: Text(_selectedCountry!), onDeleted: () => setState(() { _selectedCountry = null; _applyFilters(); })));
    if (_genderFilter != 'All') chips.add(InputChip(label: Text(_genderFilter), onDeleted: () => setState(() { _genderFilter = 'All'; _applyFilters(); })));
    if (_ageRange.start > 18 || _ageRange.end < 80) chips.add(InputChip(label: Text('${_ageRange.start.round()}-${_ageRange.end.round()}'), onDeleted: () => setState(() { _ageRange = const RangeValues(18, 80); _applyFilters(); })));
    for (String interest in _selectedInterests) chips.add(InputChip(label: Text(interest), onDeleted: () => setState(() { _selectedInterests.remove(interest); _applyFilters(); })));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: chips.map((chip) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: chip)).toList())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(hintText: 'Search by username...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  onChanged: (value) { _searchQuery = value; _applyFilters(); },
                ),
              ),
              IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterSheet),
            ],
          ),
        ),
        _buildActiveFilters(),
        Expanded(
          child: _isLoading
              ? const UserGridSkeleton(crossAxisCount: 5)
              : RefreshIndicator(
            onRefresh: () => _getUsers(isRefresh: true),
            child: _filteredUsers.isEmpty
                ? const Center(child: Text("No users found. Try adjusting your filters."))
                : GridView.builder(
              controller: _scrollController,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 0.8, crossAxisSpacing: 2, mainAxisSpacing: 2),
              itemCount: _filteredUsers.length + (_hasMore && !_showNearbyOnly ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredUsers.length) return const Center(child: CircularProgressIndicator());
                final user = _filteredUsers[index];
                return CompactUserCard(userDoc: user);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// REDESIGNED: For You Tab with 5-column grid and functional Edit Profile button
class ForYouTab extends StatefulWidget {
  const ForYouTab({super.key});
  @override
  State<ForYouTab> createState() => _ForYouTabState();
}

class _ForYouTabState extends State<ForYouTab> {
  List<DocumentSnapshot>? _recommendedUsers;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecommendedUsers();
  }

  Future<void> _fetchRecommendedUsers() async {
    setState(() => _isLoading = true);
    final currentUser = FirebaseAuth.instance.currentUser!;
    try {
      final userDoc = await context.read<FirestoreService>().getUser(currentUser.uid);
      final userData = userDoc.data() as Map<String, dynamic>;
      final List<String> myInterests = List<String>.from(userData['interests'] ?? []);

      if (myInterests.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final users = await context.read<FirestoreService>().getRecommendedUsers(myInterests, currentUser.uid);
      users.sort((a, b) {
        final aInterests = List<String>.from((a.data() as Map<String, dynamic>)['interests'] ?? []);
        final bInterests = List<String>.from((b.data() as Map<String, dynamic>)['interests'] ?? []);
        final aShared = aInterests.where((i) => myInterests.contains(i)).length;
        final bShared = bInterests.where((i) => myInterests.contains(i)).length;
        return bShared.compareTo(aShared);
      });

      if (mounted) setState(() { _recommendedUsers = users; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error fetching recommendations: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const UserGridSkeleton(crossAxisCount: 5);
    }

    if (_recommendedUsers == null || _recommendedUsers!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Add interests to your profile to get personalized recommendations!", textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final currentUser = FirebaseAuth.instance.currentUser!;
                  final userDoc = await context.read<FirestoreService>().getUser(currentUser.uid);
                  if (userDoc.exists && mounted) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditProfileScreen(currentUserData: userDoc.data() as Map<String, dynamic>),
                    ));
                  }
                },
                child: const Text('Edit Profile'),
              )
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchRecommendedUsers,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 0.8, crossAxisSpacing: 2, mainAxisSpacing: 2),
        itemCount: _recommendedUsers!.length,
        itemBuilder: (context, index) {
          final user = _recommendedUsers![index];
          return CompactUserCard(userDoc: user);
        },
      ),
    );
  }
}

// Skeleton loader for the grid
class UserGridSkeleton extends StatelessWidget {
  final int crossAxisCount;
  const UserGridSkeleton({super.key, this.crossAxisCount = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 4, mainAxisSpacing: 4),
        itemCount: 15,
        itemBuilder: (context, index) => Card(clipBehavior: Clip.antiAlias, child: Container(color: Colors.white)),
      ),
    );
  }
}

// Mock DocumentSnapshot for Hive data
class MockDocumentSnapshot implements DocumentSnapshot {
  final String _id;
  final Map<String, dynamic> _data;
  MockDocumentSnapshot(this._id, this._data);
  @override
  dynamic operator [](Object field) => _data[field];
  @override
  dynamic get(Object field) {
    if (_data.containsKey(field)) return _data[field];
    throw StateError('Field does not exist in mock snapshot');
  }
  @override
  Map<String, dynamic> data() => _data;
  @override
  String get id => _id;
  @override
  bool get exists => true;
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
  @override
  DocumentReference<Object?> get reference => throw UnimplementedError();
}

// User Info Popup Widget
class UserInfoPopup extends StatelessWidget {
  final String userId;
  const UserInfoPopup({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollController) => StreamBuilder<DocumentSnapshot>(
        stream: context.read<FirestoreService>().getUserStream(userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final username = userData['username'] ?? 'User';
          final photoUrl = userData['photoUrl'] ?? '';
          final country = userData['country'] ?? 'Not specified';
          final age = userData['age'] ?? 0;
          final bio = userData['bio'] ?? 'No bio yet.';
          final interests = List<String>.from(userData['interests'] ?? []);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: ListView(
              controller: scrollController,
              children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 40,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40)) : null,
                ),
                const SizedBox(height: 12),
                Text('$username, $age', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(country, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 16),
                Text(bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 16),
                if (interests.isNotEmpty)
                  Wrap(
                    spacing: 8.0, runSpacing: 4.0, alignment: WrapAlignment.center,
                    children: interests.map((interest) => Chip(label: Text(interest), backgroundColor: Colors.blue.withOpacity(0.1), labelStyle: const TextStyle(color: Colors.blue))).toList(),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () { Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))); },
                        child: const Text('View Profile'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<FirestoreService>().startChat(context, userId, username),
                        child: const Text('Message'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- ScannerIcon and its Painter ---
class ScannerIcon extends StatefulWidget {
  final VoidCallback onTap;
  final bool isScanning;
  const ScannerIcon({super.key, required this.onTap, required this.isScanning});
  @override
  State<ScannerIcon> createState() => _ScannerIconState();
}

class _ScannerIconState extends State<ScannerIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (widget.isScanning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ScannerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) _controller.repeat();
    else if (!widget.isScanning && _controller.isAnimating) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(painter: ScannerPainter(_controller.value, widget.isScanning), size: const Size(24, 24)),
        ),
      ),
    );
  }
}

class ScannerPainter extends CustomPainter {
  final double animationValue;
  final bool isScanning;
  ScannerPainter(this.animationValue, this.isScanning);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final dotPaint = Paint()..color = isScanning ? Colors.blue : Colors.black87;
    canvas.drawCircle(center, 2.5, dotPaint);
    if (isScanning) {
      final pingPaint = Paint()..color = Colors.blue.withAlpha((255 * (1.0 - animationValue)).toInt())..style = PaintingStyle.stroke..strokeWidth = 2.0;
      canvas.drawCircle(center, maxRadius * animationValue, pingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- Feed Screen & Related Widgets ---
class FeedWidget extends StatefulWidget {
  const FeedWidget({super.key});
  @override
  State<FeedWidget> createState() => _FeedWidgetState();
}

class _FeedWidgetState extends State<FeedWidget> {
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  List<String> _followingIds = [];

  @override
  void initState() {
    super.initState();
    _getInitialFollowingAndPosts();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent && !_isLoading) {
        _getMorePosts();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _getInitialFollowingAndPosts() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final userDoc = await context.read<FirestoreService>().getUser(currentUser.uid);
    final userData = userDoc.data() as Map<String, dynamic>?;
    if (userData != null && userData.containsKey('following')) {
      _followingIds = List<String>.from(userData['following']);
    }
    _followingIds.add(currentUser.uid);
    if (mounted) await _getPosts(isRefresh: true);
  }

  Future<void> _getPosts({bool isRefresh = false}) async {
    if (_isLoading) return;
    if (mounted) setState(() => _isLoading = true);
    if (isRefresh) { _posts = []; _lastDocument = null; _hasMore = true; }
    if (!_hasMore || _followingIds.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final querySnapshot = await context.read<FirestoreService>().getFeedPosts(_followingIds, lastDocument: _lastDocument);
    if (querySnapshot.docs.length < 10) _hasMore = false;
    if (querySnapshot.docs.isNotEmpty) _lastDocument = querySnapshot.docs.last;
    if (mounted) setState(() { _posts.addAll(querySnapshot.docs); _isLoading = false; });
  }

  Future<void> _getMorePosts() async => await _getPosts();
  Future<void> _refreshFeed() async => await _getPosts(isRefresh: true);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshFeed,
      child: _posts.isEmpty && !_isLoading
          ? const Center(child: Text('Follow users to see their posts here!'))
          : ListView.builder(
        controller: _scrollController,
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) return const Center(child: CircularProgressIndicator());
          return PostCard(post: _posts[index]);
        },
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final DocumentSnapshot post;
  const PostCard({super.key, required this.post});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Future<void> _toggleLike() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final postData = widget.post.data() as Map<String, dynamic>;
    try {
      await context.read<FirestoreService>().togglePostLike(
        postId: widget.post.id,
        userId: currentUser.uid,
        postOwnerId: postData['userId'],
        postImageUrl: postData['imageUrl'],
        currentUserData: {
          'displayName': currentUser.displayName,
          'photoURL': currentUser.photoURL,
        },
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred: $e')));
    }
  }

  Future<void> _deletePost() async {
    final messenger = ScaffoldMessenger.of(context);
    final bool? shouldDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('Are you sure you want to permanently delete this post?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (shouldDelete == true) {
      try {
        await context.read<FirestoreService>().deletePost(widget.post.id);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Error deleting post: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final postData = widget.post.data() as Map<String, dynamic>;
    final String username = postData['username'] ?? 'Anonymous';
    final String userId = postData['userId'] ?? '';
    final String imageUrl = postData['imageUrl'] ?? 'https://placehold.co/600x400/E5E5E5/333333?text=No+Image';
    final String caption = postData['caption'] ?? '';
    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isOwner = currentUser?.uid == userId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))),
                  child: Row(
                    children: [
                      StreamBuilder<DocumentSnapshot>(
                        stream: context.read<FirestoreService>().getUserStream(userId),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const CircleAvatar(radius: 18, backgroundColor: Colors.grey);
                          final userData = snapshot.data!.data() as Map<String, dynamic>;
                          final photoUrl = userData['photoUrl'];
                          return CircleAvatar(
                            radius: 18,
                            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                            child: (photoUrl == null || photoUrl.isEmpty) ? Text(username.isNotEmpty ? username[0].toUpperCase() : 'A', style: const TextStyle(color: Colors.white)) : null,
                          );
                        },
                      ),
                      const SizedBox(width: 12.0),
                      Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Spacer(),
                if (isOwner) IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey), onPressed: _deletePost)
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postSnapshot: widget.post))),
            child: Image.network(
              imageUrl, fit: BoxFit.cover, width: double.infinity, height: 300,
              loadingBuilder: (context, child, loadingProgress) => loadingProgress == null ? child : Container(height: 300, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
              errorBuilder: (context, error, stackTrace) => Container(height: 300, color: Colors.grey[200], child: const Icon(Icons.error, color: Colors.red)),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: context.read<FirestoreService>().getPostLikesStream(widget.post.id),
            builder: (context, snapshot) {
              final likesCount = snapshot.data?.docs.length ?? 0;
              final userHasLiked = snapshot.data?.docs.any((doc) => doc.id == currentUser?.uid) ?? false;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    child: Row(
                      children: [
                        IconButton(icon: Icon(userHasLiked ? Icons.favorite : Icons.favorite_border, color: userHasLiked ? const Color(0xFFE74C3C) : Colors.black87), onPressed: _toggleLike),
                        IconButton(icon: const Icon(Icons.chat_bubble_outline), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: widget.post.id)))),
                      ],
                    ),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0), child: Text('$likesCount likes', style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(text: TextSpan(style: DefaultTextStyle.of(context).style, children: [TextSpan(text: '$username ', style: const TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: caption)])),
                const SizedBox(height: 8.0),
                StreamBuilder<QuerySnapshot>(
                  stream: context.read<FirestoreService>().getPostCommentsStream(widget.post.id, limit: 2),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: widget.post.id))), child: Text('View all comments', style: TextStyle(color: Colors.grey[600])));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: snapshot.data!.docs.map((doc) {
                        final commentData = doc.data() as Map<String, dynamic>;
                        return RichText(text: TextSpan(style: DefaultTextStyle.of(context).style.copyWith(color: Colors.grey[700]), children: [TextSpan(text: '${commentData['username'] ?? 'user'} ', style: const TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: commentData['text'] ?? '')]));
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Comments Screen ---
class CommentsScreen extends StatefulWidget {
  final String postId;
  const CommentsScreen({super.key, required this.postId});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _commentController = TextEditingController();

  Future<void> _postComment() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final commentText = _commentController.text.trim();
    if (currentUser != null && commentText.isNotEmpty) {
      await context.read<FirestoreService>().addComment(
        postId: widget.postId,
        userId: currentUser.uid,
        username: currentUser.displayName ?? 'Anonymous',
        commentText: commentText,
        userPhotoUrl: currentUser.photoURL,
      );
      _commentController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments'), backgroundColor: Colors.white, elevation: 1),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: context.read<FirestoreService>().getPostCommentsStream(widget.postId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No comments yet.'));
                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final comment = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(comment['username'] ?? 'user', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(comment['text'] ?? ''),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(hintText: 'Add a comment...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20.0), borderSide: BorderSide.none)),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send, color: Color(0xFF3498DB)), onPressed: _postComment),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Create Post Screen ---
class CreatePostScreen extends StatefulWidget {
  final ImageSource imageSource;
  const CreatePostScreen({super.key, required this.imageSource});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _captionController = TextEditingController();
  XFile? _imageFile;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pickImage();
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: widget.imageSource);
    if (pickedFile != null) {
      setState(() => _imageFile = pickedFile);
    } else {
      // If user cancels from camera/gallery, pop the screen
      Navigator.of(context).pop();
    }
  }

  Future<String?> _uploadToCloudinary(XFile image) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/image/upload');
    final request = http.MultipartRequest('POST', url)..fields['upload_preset'] = 'Prototype';
    final bytes = await image.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: image.name);
    request.files.add(multipartFile);
    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    } else {
      return null;
    }
  }

  Future<void> _createPost() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image.')));
      return;
    }
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final imageUrl = await _uploadToCloudinary(_imageFile!);
      if (imageUrl == null) throw Exception('Image upload failed');
      final currentUser = FirebaseAuth.instance.currentUser!;
      await context.read<FirestoreService>().createPost(
        userId: currentUser.uid,
        username: currentUser.displayName ?? 'Anonymous',
        caption: _captionController.text.trim(),
        imageUrl: imageUrl,
        postType: 'image', // NEW: Added for future Reels feature
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to create post: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('New Post', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_imageFile != null) TextButton(onPressed: _isLoading ? null : _createPost, child: const Text('Post', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)))
        ],
      ),
      body: _imageFile == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          Center(child: kIsWeb ? Image.network(_imageFile!.path, fit: BoxFit.contain) : Image.file(File(_imageFile!.path), fit: BoxFit.contain)),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: const Color.fromRGBO(0, 0, 0, 0.5),
              child: TextField(controller: _captionController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Write a caption...', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none), maxLines: 4),
            ),
          ),
          if (_isLoading) Container(color: const Color.fromRGBO(0, 0, 0, 0.7), child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
    );
  }
}

// --- Profile Screen & Related Widgets ---
class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow(String userIdToToggle, bool isCurrentlyFollowing) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final firestoreService = context.read<FirestoreService>();
      if (isCurrentlyFollowing) {
        await firestoreService.unfollowUser(currentUser.uid, userIdToToggle);
      } else {
        await firestoreService.followUser(currentUser.uid, userIdToToggle);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred: $e')));
    }
  }

  Widget _buildStatItem(String label, int count, List<String> userIds) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FollowListScreen(title: label, userIds: userIds))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(count.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), backgroundColor: Colors.white, elevation: 1),
      body: StreamBuilder<DocumentSnapshot>(
        stream: context.read<FirestoreService>().getUserStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('User not found.'));
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final bool isCurrentUserProfile = FirebaseAuth.instance.currentUser?.uid == widget.userId;
          final String username = userData['username'] ?? 'User';
          final String bio = userData['bio'] ?? '';
          final String photoUrl = userData['photoUrl'] ?? '';
          final List<String> followers = List<String>.from(userData['followers'] ?? []);
          final List<String> following = List<String>.from(userData['following'] ?? []);

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                              child: photoUrl.isEmpty ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40)) : null,
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildStatItem('Followers', followers.length, followers), _buildStatItem('Following', following.length, following)]))
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        if (bio.isNotEmpty) ...[const SizedBox(height: 4), Text(bio, style: const TextStyle(fontSize: 16))],
                        const SizedBox(height: 16),
                        if (isCurrentUserProfile)
                          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen(currentUserData: userData))), child: const Text('Edit Profile')))
                        else
                          Row(
                            children: [
                              Expanded(
                                child: StreamBuilder<DocumentSnapshot>(
                                    stream: context.read<FirestoreService>().getUserStream(FirebaseAuth.instance.currentUser!.uid),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) return const SizedBox();
                                      final currentUserData = snapshot.data!.data() as Map<String, dynamic>;
                                      final bool isFollowing = (currentUserData['following'] as List).contains(widget.userId);
                                      return ElevatedButton(
                                        onPressed: () => _toggleFollow(widget.userId, isFollowing),
                                        style: ElevatedButton.styleFrom(backgroundColor: isFollowing ? Colors.grey : const Color(0xFF3498DB)),
                                        child: Text(isFollowing ? 'Following' : 'Follow', style: const TextStyle(color: Colors.white)),
                                      );
                                    }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: OutlinedButton(onPressed: () => context.read<FirestoreService>().startChat(context, widget.userId, username), child: const Text('Message'))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(TabBar(controller: _tabController, labelColor: Colors.black, unselectedLabelColor: Colors.grey, indicatorColor: Colors.black, tabs: const [Tab(icon: Icon(Icons.grid_on)), Tab(icon: Icon(Icons.person_pin_outlined)), Tab(icon: Icon(Icons.bookmark_border))])),
                  pinned: true,
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [_buildPostsGrid(widget.userId), const Center(child: Text('Tagged posts will appear here.')), const Center(child: Text('Saved posts will appear here.'))],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostsGrid(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: context.read<FirestoreService>().getUserPostsStream(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No posts yet.'));
        final posts = snapshot.data!.docs;
        return GridView.builder(
          padding: const EdgeInsets.all(2.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return ProfilePostGridTile(post: post, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfilePostsViewerScreen(posts: posts, initialIndex: index))));
          },
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: Theme.of(context).scaffoldBackgroundColor, child: _tabBar);
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

class ProfilePostGridTile extends StatelessWidget {
  final DocumentSnapshot post;
  final VoidCallback onTap;
  const ProfilePostGridTile({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final postData = post.data() as Map<String, dynamic>;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(postData['imageUrl'], fit: BoxFit.cover),
          FutureBuilder<Map<String, int>>(
            future: context.read<FirestoreService>().getPostStats(post.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final stats = snapshot.data!;
              return Container(
                alignment: Alignment.center,
                color: Colors.black.withOpacity(0.3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(stats['likes'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    const Icon(Icons.comment, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(stats['comments'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ProfilePostsViewerScreen extends StatefulWidget {
  final List<DocumentSnapshot> posts;
  final int initialIndex;
  const ProfilePostsViewerScreen({super.key, required this.posts, required this.initialIndex});
  @override
  State<ProfilePostsViewerScreen> createState() => _ProfilePostsViewerScreenState();
}

class _ProfilePostsViewerScreenState extends State<ProfilePostsViewerScreen> {
  late PageController _pageController;
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.white, elevation: 1),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.posts.length,
        itemBuilder: (context, index) => SingleChildScrollView(child: PostCard(post: widget.posts[index])),
      ),
    );
  }
}

class FollowListScreen extends StatelessWidget {
  final String title;
  final List<String> userIds;
  const FollowListScreen({super.key, required this.title, required this.userIds});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: userIds.isEmpty
          ? const Center(child: Text('No users to display.'))
          : ListView.builder(
        itemCount: userIds.length,
        itemBuilder: (context, index) {
          return FutureBuilder<DocumentSnapshot>(
            future: context.read<FirestoreService>().getUser(userIds[index]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const ListTile(title: Text('Loading...'));
              final userData = snapshot.data!.data() as Map<String, dynamic>;
              final photoUrl = userData['photoUrl'];
              final username = userData['username'];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                  child: (photoUrl == null || photoUrl.isEmpty) ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?') : null,
                ),
                title: Text(username),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userIds[index]))),
              );
            },
          );
        },
      ),
    );
  }
}

// ENHANCED: EditProfileScreen with Interests and BLoC integration
class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> currentUserData;
  final bool isCompletingProfile;
  const EditProfileScreen({super.key, required this.currentUserData, this.isCompletingProfile = false});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  int? _selectedAge;
  String? _selectedCountry;
  String? _selectedGender;
  List<String> _selectedInterests = [];
  XFile? _imageFile;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  final List<String> _countries = ['USA', 'Canada', 'UK', 'Germany', 'France', 'Tunisia', 'Egypt', 'Algeria', 'Morocco'];
  final List<String> _genders = ['Male', 'Female'];
  final List<int> _ages = List<int>.generate(83, (i) => i + 18); // Ages 18-100

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.currentUserData['username']);
    _bioController = TextEditingController(text: widget.currentUserData['bio']);
    _selectedAge = widget.currentUserData['age'] == 0 ? null : widget.currentUserData['age'];
    _selectedCountry = widget.currentUserData['country'].isEmpty ? null : widget.currentUserData['country'];
    _selectedGender = widget.currentUserData['gender'].isEmpty ? null : widget.currentUserData['gender'];
    _selectedInterests = List<String>.from(widget.currentUserData['interests'] ?? []);
  }

  Future<void> _pickImage() async {
    final source = await context.findAncestorWidgetOfExactType<MainScreen>()?._showImageSourceActionSheet(context) ?? await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => Navigator.of(context).pop(ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.of(context).pop(ImageSource.gallery)),
          ],
        ),
      ),
    );

    if (source != null) {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() => _imageFile = pickedFile);
      }
    }
  }

  void _updateProfile() {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = FirebaseAuth.instance.currentUser!;
    final Map<String, dynamic> updatedData = {
      'username': _usernameController.text,
      'bio': _bioController.text,
      'age': _selectedAge,
      'country': _selectedCountry,
      'gender': _selectedGender,
      'interests': _selectedInterests,
    };

    context.read<ProfileBloc>().add(UpdateProfile(
      userId: currentUser.uid,
      data: updatedData,
      imageFile: _imageFile,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCompletingProfile ? 'Complete Your Profile' : 'Edit Profile'),
        automaticallyImplyLeading: !widget.isCompletingProfile,
        actions: [
          BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, state) {
              if (state is ProfileLoading) {
                return const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
              }
              return IconButton(icon: const Icon(Icons.check), onPressed: _updateProfile);
            },
          ),
        ],
      ),
      body: BlocConsumer<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfileUpdateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
            if (!widget.isCompletingProfile) Navigator.of(context).pop();
          }
          if (state is ProfileError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (widget.isCompletingProfile) Padding(padding: const EdgeInsets.only(bottom: 16.0), child: Text('Please complete your profile to continue.', style: Theme.of(context).textTheme.titleMedium)),
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _imageFile != null
                          ? (kIsWeb ? NetworkImage(_imageFile!.path) : FileImage(File(_imageFile!.path))) as ImageProvider?
                          : (widget.currentUserData['photoUrl'] != null && widget.currentUserData['photoUrl'].isNotEmpty ? NetworkImage(widget.currentUserData['photoUrl']) : null),
                      child: (_imageFile == null && (widget.currentUserData['photoUrl'] == null || widget.currentUserData['photoUrl'].isEmpty)) ? const Icon(Icons.camera_alt, size: 50) : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username'), validator: (value) => value!.isEmpty ? 'Please enter a username' : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: _bioController, decoration: const InputDecoration(labelText: 'Bio'), maxLines: 3),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _selectedAge, decoration: const InputDecoration(labelText: 'Age'),
                    items: _ages.map((int value) => DropdownMenuItem<int>(value: value, child: Text(value.toString()))).toList(),
                    onChanged: (newValue) => setState(() => _selectedAge = newValue),
                    validator: (value) => value == null ? 'Please select your age' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedCountry, decoration: const InputDecoration(labelText: 'Country'),
                    items: _countries.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                    onChanged: (newValue) => setState(() => _selectedCountry = newValue),
                    validator: (value) => value == null ? 'Please select your country' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedGender, decoration: const InputDecoration(labelText: 'Gender'),
                    items: _genders.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                    onChanged: (newValue) => setState(() => _selectedGender = newValue),
                    validator: (value) => value == null ? 'Please select your gender' : null,
                  ),
                  const SizedBox(height: 24),
                  const Align(alignment: Alignment.centerLeft, child: Text("Interests", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0, runSpacing: 4.0,
                    children: _possibleInterests.map((interest) {
                      final isSelected = _selectedInterests.contains(interest);
                      return FilterChip(
                        label: Text(interest), selected: isSelected,
                        onSelected: (selected) => setState(() => selected ? _selectedInterests.add(interest) : _selectedInterests.remove(interest)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Notifications Screen ---
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Future<void> _markAllAsRead() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final success = await context.read<FirestoreService>().markAllNotificationsAsRead(currentUser.uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'All notifications marked as read.' : 'No new notifications.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please log in.'));
    return Scaffold(
      appBar: AppBar(
        title: const Text("Activity"), backgroundColor: Colors.white, elevation: 1,
        actions: [PopupMenuButton<String>(onSelected: (value) { if (value == 'mark_all_read') _markAllAsRead(); }, itemBuilder: (BuildContext context) => [const PopupMenuItem<String>(value: 'mark_all_read', child: Text('Mark all as read'))])],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: context.read<FirestoreService>().getNotificationsStream(currentUser.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No notifications yet.'));
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final notifDoc = snapshot.data!.docs[index];
              final notif = notifDoc.data() as Map<String, dynamic>;
              if (notif['read'] == false) context.read<FirestoreService>().markNotificationAsRead(currentUser.uid, notifDoc.id);
              return NotificationTile(notification: notif);
            },
          );
        },
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  const NotificationTile({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    final String type = notification['type'] ?? '';
    final String fromUsername = notification['fromUsername'] ?? 'Someone';
    final String fromUserId = notification['fromUserId'] ?? '';
    final String? fromUserPhotoUrl = notification['fromUserPhotoUrl'];
    final String? postImageUrl = notification['postImageUrl'];
    final String? commentText = notification['commentText'];
    final String? postId = notification['postId'];
    final Timestamp? timestamp = notification['timestamp'];
    Widget title;
    IconData iconData = Icons.info;
    Color iconColor = Colors.grey;

    switch (type) {
      case 'like':
        title = RichText(text: TextSpan(style: DefaultTextStyle.of(context).style, children: [TextSpan(text: fromUsername, style: const TextStyle(fontWeight: FontWeight.bold)), const TextSpan(text: ' liked your post.')]));
        iconData = Icons.favorite; iconColor = Colors.red; break;
      case 'comment':
        title = RichText(text: TextSpan(style: DefaultTextStyle.of(context).style, children: [TextSpan(text: fromUsername, style: const TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: ' commented: ${commentText ?? ''}')]));
        iconData = Icons.comment; iconColor = Colors.blue; break;
      case 'follow':
        title = RichText(text: TextSpan(style: DefaultTextStyle.of(context).style, children: [TextSpan(text: fromUsername, style: const TextStyle(fontWeight: FontWeight.bold)), const TextSpan(text: ' started following you.')]));
        iconData = Icons.person_add; iconColor = Colors.green; break;
      default: title = const Text('New notification.');
    }

    return ListTile(
      leading: GestureDetector(
        onTap: () { if (fromUserId.isNotEmpty) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUserId))); },
        child: CircleAvatar(
          backgroundImage: (fromUserPhotoUrl != null && fromUserPhotoUrl.isNotEmpty) ? NetworkImage(fromUserPhotoUrl) : null,
          child: (fromUserPhotoUrl == null || fromUserPhotoUrl.isEmpty) ? Icon(iconData, color: iconColor, size: 20) : null,
        ),
      ),
      title: title,
      subtitle: Text(timestamp != null ? timeago.format(timestamp.toDate()) : '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: (postImageUrl != null && postImageUrl.isNotEmpty) ? SizedBox(width: 50, height: 50, child: ClipRRect(borderRadius: BorderRadius.circular(4.0), child: Image.network(postImageUrl, fit: BoxFit.cover))) : null,
      onTap: () async {
        if (postId != null) {
          final postDoc = await context.read<FirestoreService>().getPost(postId);
          if (postDoc.exists && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postSnapshot: postDoc)));
        } else if (type == 'follow' && fromUserId.isNotEmpty) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: fromUserId)));
        }
      },
    );
  }
}

// --- Post Detail Screen for Navigation ---
class PostDetailScreen extends StatelessWidget {
  final DocumentSnapshot postSnapshot;
  const PostDetailScreen({super.key, required this.postSnapshot});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: SingleChildScrollView(child: PostCard(post: postSnapshot)),
    );
  }
}

// --- Search Screen ---
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  Stream<QuerySnapshot>? _searchStream;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_searchController.text.isNotEmpty) {
        setState(() => _searchStream = context.read<FirestoreService>().searchUsers(_searchController.text));
      } else {
        setState(() => _searchStream = null);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(controller: _searchController, decoration: const InputDecoration(hintText: 'Search for a user...', border: InputBorder.none), autofocus: true),
        backgroundColor: Colors.white,
      ),
      body: _searchStream == null
          ? const Center(child: Text('Start typing to search for users.'))
          : StreamBuilder<QuerySnapshot>(
        stream: _searchStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No users found.'));
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final user = snapshot.data!.docs[index];
              final userData = user.data() as Map<String, dynamic>;
              final photoUrl = userData['photoUrl'];
              final username = userData['username'];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                  child: (photoUrl == null || photoUrl.isEmpty) ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?') : null,
                ),
                title: Text(username),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id))),
              );
            },
          );
        },
      ),
    );
  }
}

// --- Chat Screens ---
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"), backgroundColor: Colors.white, elevation: 1, toolbarHeight: 70,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Search...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.grey[200], border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide.none))),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: context.read<FirestoreService>().getChatsStream(currentUser.uid),
        builder: (context, chatSnapshot) {
          if (chatSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (chatSnapshot.hasError) return Center(child: Text('Error: ${chatSnapshot.error}'));
          if (!chatSnapshot.hasData || chatSnapshot.data!.docs.isEmpty) return const Center(child: Text('No active chats.'));

          var chats = chatSnapshot.data!.docs;
          if (_searchQuery.isNotEmpty) {
            chats = chats.where((chat) {
              final chatData = chat.data() as Map<String, dynamic>;
              final usernames = chatData['usernames'] as Map<String, dynamic>;
              final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUser.uid, orElse: () => '');
              final otherUsername = usernames[otherUserId] ?? 'User';
              return otherUsername.toLowerCase().contains(_searchQuery.toLowerCase());
            }).toList();
          }

          return ListView.builder(itemCount: chats.length, itemBuilder: (context, index) => ChatListItem(chat: chats[index], currentUserId: currentUser.uid));
        },
      ),
    );
  }
}

class ChatListItem extends StatelessWidget {
  final DocumentSnapshot chat;
  final String currentUserId;
  const ChatListItem({super.key, required this.chat, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final chatData = chat.data() as Map<String, dynamic>;
    final usernames = chatData['usernames'] as Map<String, dynamic>;
    final otherUserId = (chatData['users'] as List).firstWhere((id) => id != currentUserId, orElse: () => '');
    final otherUsername = usernames[otherUserId] ?? 'User';

    return StreamBuilder<DocumentSnapshot>(
      stream: context.read<FirestoreService>().getUserStream(otherUserId),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const ListTile();
        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final photoUrl = userData['photoUrl'];
        final isOnline = userData['presence'] ?? false;
        final unreadCount = (chatData['unreadCount'] as Map<String, dynamic>?)?[currentUserId] ?? 0;
        String lastMessage = chatData['lastMessage'] ?? '';
        if (chatData.containsKey('lastMessageIsImage') && chatData['lastMessageIsImage'] == true) lastMessage = '📷 Photo';
        final messageTimestamp = chatData['lastMessageTimestamp'] as Timestamp?;
        final formattedMessageTime = messageTimestamp != null ? timeago.format(messageTimestamp.toDate(), locale: 'en_short') : '';

        return Dismissible(
          key: Key(chat.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async => await showDialog(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text("Confirm Delete"), content: Text("Are you sure you want to delete your chat with $otherUsername?"),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
          onDismissed: (direction) {
            context.read<FirestoreService>().deleteChat(chat.id);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$otherUsername chat deleted")));
          },
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20.0), child: const Icon(Icons.delete_forever, color: Colors.white)),
          child: ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null, child: (photoUrl == null || photoUrl.isEmpty) ? Text(otherUsername.isNotEmpty ? otherUsername[0].toUpperCase() : '?') : null),
                if (isOnline) Positioned(bottom: -2, right: -2, child: Container(height: 14, width: 14, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))
              ],
            ),
            title: Text(otherUsername, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formattedMessageTime, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                if (unreadCount > 0) CircleAvatar(radius: 10, backgroundColor: const Color(0xFFE74C3C), child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
              ],
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id, otherUsername: otherUsername))),
          ),
        );
      },
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUsername;
  const ChatScreen({super.key, required this.chatId, required this.otherUsername});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Timer? _typingTimer;
  bool _isUploading = false;
  String? _replyingToMessageId;
  String? _replyingToMessageText;
  String? _replyingToSender;
  String? _replyingToImageUrl;

  @override
  void initState() {
    super.initState();
    context.read<FirestoreService>().resetUnreadCount(widget.chatId, FirebaseAuth.instance.currentUser!.uid);
    _messageController.addListener(_onTyping);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    _typingTimer?.cancel();
    _updateTypingStatus(false);
    super.dispose();
  }

  void _onTyping() {
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _updateTypingStatus(true);
    _typingTimer = Timer(const Duration(milliseconds: 1500), () => _updateTypingStatus(false));
  }

  Future<void> _updateTypingStatus(bool isTyping) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await context.read<FirestoreService>().updateTypingStatus(widget.chatId, currentUser.uid, isTyping);
    }
  }

  Future<void> _sendMessage() async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final messageText = _messageController.text.trim();
    if (messageText.isNotEmpty) {
      _typingTimer?.cancel();
      _updateTypingStatus(false);
      await context.read<FirestoreService>().sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.uid,
        text: messageText,
        replyToMessageId: _replyingToMessageId,
        replyToMessageText: _replyingToMessageText,
        replyToImageUrl: _replyingToImageUrl,
        replyToSender: _replyingToSender,
      );
      _messageController.clear();
      _cancelReply();
    }
  }

  Future<String?> _uploadToCloudinary(XFile image) async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/dq0mb16fk/image/upload');
    final request = http.MultipartRequest('POST', url)..fields['upload_preset'] = 'Prototype';
    final bytes = await image.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: image.name);
    request.files.add(multipartFile);
    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonMap = jsonDecode(responseString);
      return jsonMap['secure_url'];
    } else {
      return null;
    }
  }

  Future<void> _sendImage() async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await context.findAncestorWidgetOfExactType<MainScreen>()?._showImageSourceActionSheet(context) ?? await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => Navigator.of(context).pop(ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.of(context).pop(ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);
    try {
      final imageUrl = await _uploadToCloudinary(pickedFile);
      if (imageUrl == null) throw Exception('Image upload failed');
      final currentUser = FirebaseAuth.instance.currentUser!;
      await context.read<FirestoreService>().sendMessage(
        chatId: widget.chatId,
        senderId: currentUser.uid,
        imageUrl: imageUrl,
        replyToMessageId: _replyingToMessageId,
        replyToMessageText: _replyingToMessageText,
        replyToImageUrl: _replyingToImageUrl,
        replyToSender: _replyingToSender,
      );
      _cancelReply();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _startReply(String messageId, Map<String, dynamic> messageData) {
    setState(() {
      _replyingToMessageId = messageId;
      _replyingToMessageText = messageData['text'];
      _replyingToImageUrl = messageData['imageUrl'];
      _replyingToSender = messageData['senderId'] == FirebaseAuth.instance.currentUser!.uid ? 'You' : widget.otherUsername;
    });
  }

  void _cancelReply() => setState(() { _replyingToMessageId = null; _replyingToMessageText = null; _replyingToSender = null; _replyingToImageUrl = null; });

  void _showMessageActions(BuildContext context, String messageId, Map<String, dynamic> messageData, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) => IconButton(
                  icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                  onPressed: () { Navigator.of(context).pop(); context.read<FirestoreService>().toggleMessageReaction(widget.chatId, messageId, FirebaseAuth.instance.currentUser!.uid, emoji); },
                )).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () { Navigator.of(context).pop(); _startReply(messageId, messageData); }),
            if (isMe) ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)), onTap: () { Navigator.of(context).pop(); context.read<FirestoreService>().deleteMessage(widget.chatId, messageId); }),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final currentUser = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot>(
      stream: context.read<FirestoreService>().getChatStream(widget.chatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final chatData = snapshot.data!.data() as Map<String, dynamic>;
        final typingStatus = chatData['typingStatus'] as Map<String, dynamic>? ?? {};
        final otherUserId = typingStatus.keys.firstWhere((id) => id != currentUser.uid, orElse: () => '');
        if (otherUserId.isNotEmpty && typingStatus[otherUserId] == true) {
          return Padding(padding: const EdgeInsets.only(left: 16.0, bottom: 4.0), child: Row(children: [Text('${widget.otherUsername} is typing...', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic))]));
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingToMessageId == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.grey.withAlpha(25),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replying to $_replyingToSender', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                const SizedBox(height: 4),
                _replyingToImageUrl != null
                    ? Row(children: [Icon(Icons.photo, size: 16, color: Colors.grey[700]), const SizedBox(width: 4), Text('Photo', style: TextStyle(color: Colors.grey[700]))])
                    : Text(_replyingToMessageText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _cancelReply)
        ],
      ),
    );
  }

  Widget _buildReactions(Map<String, dynamic> reactions, bool isMe) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final uniqueReactions = reactions.values.toSet().toList();
    return Positioned(
      bottom: -8, right: isMe ? 10 : null, left: isMe ? null : 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.grey.withAlpha(128), spreadRadius: 1, blurRadius: 1)]),
        child: Text(uniqueReactions.join(' '), style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherUsername), backgroundColor: Colors.white, elevation: 1),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: context.read<FirestoreService>().getMessagesStream(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Say hello!'));
                WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<FirestoreService>().markMessagesAsSeen(widget.chatId, currentUser.uid, snapshot.data!.docs); });
                return ListView.builder(
                  reverse: true, padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final messageDoc = snapshot.data!.docs[index];
                    final message = messageDoc.data() as Map<String, dynamic>;
                    final bool isMe = message['senderId'] == currentUser.uid;
                    final bool isSeen = message['isSeen'] ?? false;
                    final String? imageUrl = message['imageUrl'];
                    final bool isReply = message['replyToMessageId'] != null;
                    final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});
                    Widget messageContent = imageUrl != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(12.0), child: Image.network(imageUrl, height: 200, width: 200, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : Container(height: 200, width: 200, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator()))))
                        : Text(message['text'] ?? '', style: TextStyle(color: isMe ? Colors.white : Colors.black87));

                    return GestureDetector(
                      onLongPress: () => _showMessageActions(context, messageDoc.id, message, isMe),
                      child: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                                  padding: imageUrl != null ? const EdgeInsets.all(4.0) : const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                  decoration: BoxDecoration(color: isMe ? const Color(0xFF3498DB) : Colors.white, borderRadius: BorderRadius.circular(20.0), boxShadow: [BoxShadow(color: Colors.grey.withAlpha(51), spreadRadius: 1, blurRadius: 2, offset: const Offset(0, 1))]),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (isReply) Container(
                                        padding: const EdgeInsets.all(8.0), margin: const EdgeInsets.only(bottom: 4.0),
                                        decoration: BoxDecoration(color: isMe ? Colors.blue.shade700.withAlpha(128) : Colors.grey.withAlpha(51), borderRadius: const BorderRadius.all(Radius.circular(12.0))),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(message['replyToSender'] ?? 'User', style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.white70 : Colors.black87)),
                                            const SizedBox(height: 2),
                                            if (message['replyToImageUrl'] != null) Row(children: [Icon(Icons.photo, size: 14, color: isMe ? Colors.white70 : Colors.grey[700]), const SizedBox(width: 4), Text('Photo', style: TextStyle(color: isMe ? Colors.white70 : Colors.grey[700]))])
                                            else Text(message['replyToMessageText'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: isMe ? Colors.white70 : Colors.grey[700])),
                                          ],
                                        ),
                                      ),
                                      messageContent,
                                    ],
                                  ),
                                ),
                                if (isMe) Padding(padding: const EdgeInsets.only(left: 4.0, bottom: 4.0), child: Icon(isSeen ? Icons.done_all : Icons.done, size: 16, color: isSeen ? Colors.blue : Colors.grey)),
                              ],
                            ),
                            _buildReactions(reactions, isMe),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildTypingIndicator(),
          Column(
            children: [
              _buildReplyPreview(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.photo_camera, color: Color(0xFF3498DB)), onPressed: _isUploading ? null : _sendImage),
                    Expanded(child: TextField(controller: _messageController, decoration: InputDecoration(hintText: 'Type a message...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20.0), borderSide: BorderSide.none)))),
                    IconButton(icon: const Icon(Icons.send, color: Color(0xFF3498DB)), onPressed: _isUploading ? null : _sendMessage),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Nearby Screen ---
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});
  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final BluetoothService _bluetoothService;
  late final Box _contactsBox;
  List<Map<String, dynamic>> _contacts = [];
  Timer? _syncTimer;
  StreamSubscription? _statusSubscription;
  NearbyStatus _currentStatus = NearbyStatus.idle;

  @override
  void initState() {
    super.initState();
    _bluetoothService = BluetoothService();
    _bluetoothService.start();
    _contactsBox = Hive.box('nearby_contacts');
    _loadContacts();
    _contactsBox.listenable().addListener(_loadContacts);
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _syncContactsWithFirestore());
    _syncContactsWithFirestore();
    _statusSubscription = bluetoothStatusService.statusStream.listen((status) {
      if (mounted) setState(() => _currentStatus = status);
    });
  }

  @override
  void dispose() {
    _bluetoothService.stop();
    _bluetoothService.dispose();
    _contactsBox.listenable().removeListener(_loadContacts);
    _syncTimer?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _loadContacts() {
    if (mounted) {
      final contactsData = _contactsBox.toMap().values.map((e) {
        final contact = Map<String, dynamic>.from(e);
        contact['timestamp'] = DateTime.parse(contact['timestamp']);
        return contact;
      }).toList();
      contactsData.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
      setState(() => _contacts = contactsData);
    }
  }

  Future<void> _syncContactsWithFirestore() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final contactsToSync = List<String>.from(_contacts.map((c) => c['id']));
    if (contactsToSync.isNotEmpty) {
      try {
        await context.read<FirestoreService>().syncNearbyContacts(currentUser.uid, contactsToSync);
      } catch (e) {
        // Errors can happen if the document doesn't exist yet, etc.
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    final profileBox = Hive.box('user_profiles');
    if (profileBox.containsKey(userId)) return Map<String, dynamic>.from(profileBox.get(userId));
    try {
      final doc = await context.read<FirestoreService>().getUser(userId);
      if (doc.exists) {
        final data = doc.data()!;
        profileBox.put(userId, data);
        return data as Map<String, dynamic>;
      }
    } catch (e) {
      // Handle potential network errors
    }
    return null;
  }

  String _getStatusMessage(NearbyStatus status) {
    switch (status) {
      case NearbyStatus.idle: return "Ready to start.";
      case NearbyStatus.checkingPermissions: return "Checking permissions...";
      case NearbyStatus.permissionsDenied: return "Permissions denied. Please grant permissions in settings.";
      case NearbyStatus.checkingAdapter: return "Checking Bluetooth adapter...";
      case NearbyStatus.adapterOff: return "Please turn on Bluetooth.";
      case NearbyStatus.startingServices: return "Starting services...";
      case NearbyStatus.advertising: return "Broadcasting your signal...";
      case NearbyStatus.scanning: return "Scanning for nearby users...";
      case NearbyStatus.userFound: return "Found a user! Saving contact...";
      case NearbyStatus.error: return "An error occurred. Please try again.";
      default: return "Initializing...";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Users'), backgroundColor: Colors.white, elevation: 1),
      body: Column(
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), color: Colors.blue.withOpacity(0.1),
            child: Row(
              children: [
                if (_currentStatus == NearbyStatus.scanning || _currentStatus == NearbyStatus.advertising) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else Icon(_currentStatus == NearbyStatus.error || _currentStatus == NearbyStatus.permissionsDenied ? Icons.error_outline : Icons.check_circle_outline, color: _currentStatus == NearbyStatus.error || _currentStatus == NearbyStatus.permissionsDenied ? Colors.red : Colors.green, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(_getStatusMessage(_currentStatus), style: const TextStyle(fontWeight: FontWeight.w500))),
              ],
            ),
          ),
          Expanded(
            child: _contacts.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Keep this screen open to discover others. Make sure your Bluetooth is on.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16))))
                : ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final String userId = contact['id'];
                final DateTime timestamp = contact['timestamp'];
                return FutureBuilder<Map<String, dynamic>?>(
                  future: _fetchUserProfile(userId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return ListTile(title: const Text('Loading user...'), subtitle: Text('Found ${timeago.format(timestamp)}'), leading: const CircleAvatar(backgroundColor: Colors.grey));
                    if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) return ListTile(title: const Text('Unknown User'), subtitle: Text('ID: $userId'), leading: const CircleAvatar(child: Icon(Icons.error)));
                    final userData = snapshot.data!;
                    final username = userData['username'] ?? 'No Name';
                    final photoUrl = userData['photoUrl'];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: ListTile(
                        leading: CircleAvatar(backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null, child: (photoUrl == null || photoUrl.isEmpty) ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?') : null),
                        title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Found ${timeago.format(timestamp)}'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Match Screen (Smash or Pass) ---
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  List<DocumentSnapshot> _potentialMatches = [];
  bool _isLoading = true;
  final SwiperController _swiperController = SwiperController();

  @override
  void initState() {
    super.initState();
    _fetchPotentialMatches();
  }

  Future<void> _fetchPotentialMatches() async {
    setState(() => _isLoading = true);
    final currentUser = FirebaseAuth.instance.currentUser!;
    try {
      final matches = await context.read<FirestoreService>().getPotentialMatches(currentUser.uid);
      if (mounted) setState(() { _potentialMatches = matches; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error fetching potential matches: $e");
    }
  }

  Future<void> _onSwipe(int index, String action) async {
    if (index >= _potentialMatches.length) return;
    final currentUser = FirebaseAuth.instance.currentUser!;
    final otherUser = _potentialMatches[index];
    final otherUserId = otherUser.id;
    await context.read<FirestoreService>().recordSwipe(currentUser.uid, otherUserId, action);
    if (action == 'smash') {
      final isMatch = await context.read<FirestoreService>().checkForMatch(currentUser.uid, otherUserId);
      if (isMatch && mounted) {
        await context.read<FirestoreService>().createMatch(currentUser.uid, otherUserId);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('It\'s a Match with ${otherUser['username']}!')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Match'), backgroundColor: Colors.transparent, elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _potentialMatches.isEmpty
          ? const Center(child: Text('No new users to match with right now. Check back later!'))
          : Column(
        children: [
          Expanded(
            child: Swiper(
              controller: _swiperController,
              itemCount: _potentialMatches.length,
              itemBuilder: (context, index) => MatchCard(userDoc: _potentialMatches[index]),
              loop: false, viewportFraction: 0.85, scale: 0.9,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(heroTag: 'pass_button', onPressed: () { _onSwipe(_swiperController.index, 'pass'); _swiperController.next(); }, backgroundColor: Colors.white, child: const Icon(Icons.close, color: Colors.red, size: 30)),
                FloatingActionButton(heroTag: 'smash_button', onPressed: () { _onSwipe(_swiperController.index, 'smash'); _swiperController.next(); }, backgroundColor: Colors.white, child: const Icon(Icons.favorite, color: Colors.green, size: 30)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchCard extends StatelessWidget {
  final DocumentSnapshot userDoc;
  const MatchCard({super.key, required this.userDoc});

  @override
  Widget build(BuildContext context) {
    final userData = userDoc.data() as Map<String, dynamic>;
    final photoUrl = userData['photoUrl'] ?? '';
    final username = userData['username'] ?? 'User';
    final age = userData['age'] ?? 0;
    final interests = List<String>.from(userData['interests'] ?? []);

    return Card(
      elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photoUrl.isNotEmpty) Image.network(photoUrl, fit: BoxFit.cover),
          Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.8)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
          Positioned(
            bottom: 20, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$username, $age', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                if (interests.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 4, children: interests.take(3).map((interest) => Chip(label: Text(interest), visualDensity: VisualDensity.compact, backgroundColor: Colors.white.withOpacity(0.2), labelStyle: const TextStyle(color: Colors.white))).toList())]
              ],
            ),
          ),
        ],
      ),
    );
  }
}
