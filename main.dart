import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:freegram/blocs/auth_bloc.dart';
import 'package:freegram/blocs/profile_bloc.dart';
import 'package:freegram/screens/edit_profile_screen.dart';
import 'package:freegram/screens/login_screen.dart';
import 'package:freegram/screens/main_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_options.dart';

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
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void dispose() {
    _statusController.close();
  }
}

// Global instance to be accessible by the Bluetooth service and UI
final bluetoothStatusService = BluetoothStatusService();

// --- Bluetooth Service (Abstract and Implementations) ---
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
    // This method now only initializes permissions and adapter state.
    // Scanning and advertising are started manually.
    bluetoothStatusService.updateStatus(NearbyStatus.startingServices);

    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("[Bluetooth] BLE not supported on this device.");
      bluetoothStatusService.updateStatus(NearbyStatus.error);
      return;
    }

    final bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) return;

    bluetoothStatusService.updateStatus(NearbyStatus.checkingAdapter);
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      debugPrint("[Bluetooth] Adapter state changed to: $state");
      if (state != BluetoothAdapterState.on) {
        bluetoothStatusService.updateStatus(NearbyStatus.adapterOff);
        stop(); // Stop all services if adapter is turned off
      } else {
        bluetoothStatusService.updateStatus(NearbyStatus.idle); // Ready to scan
      }
    });
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;

    // Start both advertising and scanning when toggled on
    await _startAdvertising();
    _startDeviceScan();
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _isScanning = false;

    await _stopAdvertising();
    await _stopDeviceScan();
    bluetoothStatusService.updateStatus(NearbyStatus.idle);
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

  void _startDeviceScan() {
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
      bluetoothStatusService.updateStatus(NearbyStatus.error);
    }
  }

  void _handleFoundUser(String foundUserId) {
    final box = Hive.box('nearby_contacts');
    final existingContact = box.get(foundUserId);
    // Only add if new, or if found again after an hour.
    if (existingContact == null || DateTime.now().difference(DateTime.parse(existingContact['timestamp'])).inHours >= 1) {
      debugPrint("[Bluetooth] New or expired contact found. Saving card for user: $foundUserId");
      box.put(foundUserId, {'id': foundUserId, 'timestamp': DateTime.now().toIso8601String()});
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      if (await _blePeripheral.isAdvertising) await _blePeripheral.stop();
    } catch (e) {
      debugPrint("[Bluetooth] Error stopping advertising: $e");
    }
  }

  Future<void> _stopDeviceScan() async {
    _scanSubscription?.cancel();
    try {
      if (await FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint("[Bluetooth] Error stopping scan: $e");
    }
  }


  @override
  Future<void> stop() async {
    debugPrint("[Bluetooth] Stopping all services...");
    await stopScanning();
    _adapterStateSubscription?.cancel();
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
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is Authenticated) {
          return ProfileCompletionWrapper(user: state.user);
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
  final User user;
  const ProfileCompletionWrapper({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: context.read<FirestoreService>().getUserStream(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          // This can happen briefly after sign up. A loading screen is appropriate.
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
