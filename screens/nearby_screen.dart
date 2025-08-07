// ---
// lib/screens/nearby_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:freegram/main.dart'; // For BluetoothService and status service
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:freegram/widgets/sonar_view.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final MobileBluetoothService _bluetoothService;
  late final Box _contactsBox;
  StreamSubscription? _statusSubscription;
  NearbyStatus _currentStatus = NearbyStatus.idle;
  bool _isScanning = false;

  final Map<String, Map<String, dynamic>> _userProfileCache = {};

  @override
  void initState() {
    super.initState();
    final btService = BluetoothService();
    if (btService is MobileBluetoothService) {
      _bluetoothService = btService;
      _bluetoothService.start();
    }

    _contactsBox = Hive.box('nearby_contacts');
    _loadInitialProfiles();

    _statusSubscription = bluetoothStatusService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _currentStatus = status);
        if (status == NearbyStatus.userFound) {
          _loadInitialProfiles();
        }
      }
    });
  }

  @override
  void dispose() {
    if (_isScanning) {
      _bluetoothService.stopScanning();
    }
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _toggleScan(bool value) {
    setState(() {
      _isScanning = value;
    });
    if (_isScanning) {
      _bluetoothService.startScanning();
    } else {
      _bluetoothService.stopScanning();
    }
  }

  Future<void> _loadInitialProfiles() async {
    for (var key in _contactsBox.keys) {
      if (!_userProfileCache.containsKey(key)) {
        await _fetchUserProfile(key);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchUserProfile(String userId) async {
    final profileBox = Hive.box('user_profiles');
    if (profileBox.containsKey(userId)) {
      _userProfileCache[userId] = Map<String, dynamic>.from(profileBox.get(userId));
      return;
    }
    try {
      final doc = await context.read<FirestoreService>().getUser(userId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        profileBox.put(userId, data);
        _userProfileCache[userId] = data;
      }
    } catch (e) {
      debugPrint("Error fetching user profile for $userId: $e");
    }
  }

  String _getStatusMessage(NearbyStatus status) {
    if (_isScanning) {
      if (status == NearbyStatus.scanning) return "Scanning for nearby users...";
      if (status == NearbyStatus.advertising) return "Broadcasting your signal...";
      if (status == NearbyStatus.userFound) return "Found a new user!";
    }
    switch (status) {
      case NearbyStatus.idle:
        return "Ready to scan.";
      case NearbyStatus.permissionsDenied:
        return "Permissions denied. Grant in settings.";
      case NearbyStatus.adapterOff:
        return "Please turn on Bluetooth.";
      case NearbyStatus.error:
        return "An error occurred. Try again.";
      default:
        return "Initializing...";
    }
  }

  void _deleteFoundUser(String userId) {
    _contactsBox.delete(userId);
    _userProfileCache.remove(userId);
    if (mounted) setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User removed. They can be discovered again.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
      ),
      body: Column(
        children: [
          _buildSonarSection(),
          const Divider(height: 1),
          _buildFoundUsersSection(),
        ],
      ),
    );
  }

  Widget _buildSonarSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sonar Scan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(_getStatusMessage(_currentStatus), style: const TextStyle(color: Colors.grey)),
                ],
              ),
              Switch(
                value: _isScanning,
                onChanged: _toggleScan,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: SonarView(
              isScanning: _isScanning,
              foundUserAvatars: _buildSonarAvatars(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSonarAvatars() {
    final List<Widget> avatars = [];
    final sonarRadius = 100.0;

    _userProfileCache.forEach((userId, userData) {
      final photoUrl = userData['photoUrl'];
      final random = Random(userId.hashCode);
      final angle = random.nextDouble() * 2 * pi;
      final distance = (random.nextDouble() * 0.6 + 0.2) * sonarRadius;

      final position = Offset(
        cos(angle) * distance + sonarRadius - 20,
        sin(angle) * distance + sonarRadius - 20,
      );

      avatars.add(
        Positioned(
          left: position.dx,
          top: position.dy,
          child: CircleAvatar(
            radius: 20,
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
            child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person) : null,
          ),
        ),
      );
    });
    return avatars;
  }

  Widget _buildFoundUsersSection() {
    return Expanded(
      child: ValueListenableBuilder(
        valueListenable: _contactsBox.listenable(),
        builder: (context, Box box, _) {
          final contacts = box.keys.toList();
          if (contacts.isEmpty) {
            return const Center(
              child: Text("No users found yet.", style: TextStyle(color: Colors.grey)),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final userId = contacts[index];
              final userData = _userProfileCache[userId];

              if (userData == null) {
                return const Card(child: Center(child: CircularProgressIndicator()));
              }
              return CompactNearbyUserCard(
                userData: userData,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))),
                onDelete: () => _deleteFoundUser(userId),
              );
            },
          );
        },
      ),
    );
  }
}

class CompactNearbyUserCard extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const CompactNearbyUserCard({
    super.key,
    required this.userData,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = userData['photoUrl'];
    final username = userData['username'] ?? 'User';

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: GridTile(
          footer: Container(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            color: Colors.black.withAlpha((255 * 0.5).round()),
            child: Text(
              username,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          header: Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((255 * 0.6).round()),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
          child: (photoUrl != null && photoUrl.isNotEmpty)
              ? Image.network(
            photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 40, color: Colors.grey),
          )
              : const Icon(Icons.person, size: 40, color: Colors.grey),
        ),
      ),
    );
  }
}
