import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:freegram/repositories/user_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

// --- Service-Specific Data Models ---

enum NearbyStatus {
  idle,
  scanning,
  advertising,
  userFound,
  permissionsDenied,
  adapterOff,
  error,
}

class BluetoothStatusService {
  static final BluetoothStatusService _instance =
  BluetoothStatusService._internal();
  factory BluetoothStatusService() => _instance;
  BluetoothStatusService._internal();

  final _statusController = StreamController<NearbyStatus>.broadcast();
  Stream<NearbyStatus> get statusStream => _statusController.stream;

  void updateStatus(NearbyStatus status) {
    _statusController.add(status);
  }
}

// --- Main Bluetooth Service ---

class BluetoothService {
  final BluetoothStatusService _statusService = BluetoothStatusService();
  final UserRepository _userRepository;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterStateSubscription;

  bool _shouldBeScanning = false;
  bool _shouldBeAdvertising = false;

  static final Guid _serviceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");
  static const int _companyId = 0xFFFF;

  // FIX: The constructor now correctly initializes the private _userRepository field.
  BluetoothService({required UserRepository userRepository})
      : _userRepository = userRepository;

  Future<void> start() async {
    if (_adapterStateSubscription != null) return;

    if (await _checkAndRequestPermissions()) {
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on) {
          _statusService.updateStatus(NearbyStatus.idle);
          if (_shouldBeScanning) startScanning();
          if (_shouldBeAdvertising) startAdvertising();
        } else {
          _statusService.updateStatus(NearbyStatus.adapterOff);
        }
      });
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    if (statuses[Permission.location]!.isGranted &&
        statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted &&
        statuses[Permission.bluetoothAdvertise]!.isGranted) {
      return true;
    } else {
      _statusService.updateStatus(NearbyStatus.permissionsDenied);
      return false;
    }
  }

  Future<void> startAdvertising() async {
    _shouldBeAdvertising = true;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null ||
        !(await _checkAndRequestPermissions()) ||
        FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    if (await _peripheral.isAdvertising) return;

    final userModel = await _userRepository.getUser(currentUser.uid);
    final payload = "${currentUser.uid}|${userModel.level}";

    final advertiseData = AdvertiseData(
      serviceUuid: _serviceUuid.toString(),
      manufacturerId: _companyId,
      manufacturerData: utf8.encode(payload),
    );

    try {
      await _peripheral.start(advertiseData: advertiseData);
      _statusService.updateStatus(NearbyStatus.advertising);
    } catch (e) {
      debugPrint("Error starting advertising: $e");
      _statusService.updateStatus(NearbyStatus.error);
    }
  }

  Future<void> stopAdvertising() async {
    _shouldBeAdvertising = false;
    if (await _peripheral.isAdvertising) {
      await _peripheral.stop();
    }
  }

  void startScanning() async {
    _shouldBeScanning = true;
    if (!(await _checkAndRequestPermissions()) ||
        FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    if (FlutterBluePlus.isScanningNow) return;

    _statusService.updateStatus(NearbyStatus.scanning);

    try {
      await FlutterBluePlus.startScan(
          withServices: [_serviceUuid], timeout: const Duration(days: 1));
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final manuData = r.advertisementData.manufacturerData;
          if (manuData.isNotEmpty && manuData.containsKey(_companyId)) {
            final payload = String.fromCharCodes(manuData[_companyId]!);
            _handleFoundUser(payload);
          }
        }
      });
    } catch (e) {
      debugPrint("Error starting scan: $e");
      _statusService.updateStatus(NearbyStatus.error);
    }
  }

  Future<void> stopScanning() async {
    _shouldBeScanning = false;
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();

    if (!FlutterBluePlus.isScanningNow && !(await _peripheral.isAdvertising)) {
      _statusService.updateStatus(NearbyStatus.idle);
    }
  }

  void _handleFoundUser(String payload) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final parts = payload.split('|');
    if (parts.length < 2) return;

    final userId = parts[0];
    final level = int.tryParse(parts[1]) ?? 1;

    if (userId.isEmpty || userId == currentUser?.uid) return;

    final contactsBox = Hive.box('nearby_contacts');
    final isNewUser = !contactsBox.containsKey(userId);

    contactsBox.put(userId, DateTime.now().toIso8601String());

    if (isNewUser) {
      try {
        final userModel = await _userRepository.getUser(userId);
        final profileBox = Hive.box('user_profiles');
        profileBox.put(userId, userModel.toMap()..['level'] = level);
        _statusService.updateStatus(NearbyStatus.userFound);
      } catch (e) {
        contactsBox.delete(userId);
        debugPrint("Could not fetch profile for nearby user $userId: $e");
      }
    }
  }

  void dispose() {
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
  }
}
