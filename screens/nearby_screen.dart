import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freegram/blocs/nearby_bloc.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/services/bluetooth_service.dart';
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:freegram/widgets/sonar_view.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final Map<String, UserModel> _userProfileCache = {};
  List<String> _lastKnownUserIds = [];

  bool _isBluetoothReady = false;
  bool _isLocationReady = false;

  late AnimationController _unleashController;
  late AnimationController _discoveryController;
  String? _currentUserPhotoUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unleashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _discoveryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadInitialProfiles();
    _fetchCurrentUserPhoto();
    _syncPermissionsAndHardwareState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unleashController.dispose();
    _discoveryController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPermissionsAndHardwareState();
    }
  }

  Future<void> _syncPermissionsAndHardwareState() async {
    final bluetoothPermission = await Permission.bluetoothScan.status;
    final isAdapterOn = FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

    final locationPermission = await Permission.location.status;
    final isLocationServiceOn = await Permission.location.serviceStatus.isEnabled;

    final bool isBtReady = bluetoothPermission.isGranted && isAdapterOn;
    final bool isLocReady = locationPermission.isGranted && isLocationServiceOn;

    if (mounted) {
      setState(() {
        _isBluetoothReady = isBtReady;
        _isLocationReady = isLocReady;
      });

      if (context.read<NearbyBloc>().state is NearbyActive && (!isBtReady || !isLocReady)) {
        context.read<NearbyBloc>().add(StopNearbyServices());
      }
    }
  }

  Future<void> _handleBluetoothToggle() async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
      return;
    }
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();
    if (statuses.values.every((s) => s.isGranted) && mounted) {
      setState(() => _isBluetoothReady = true);
    }
  }

  Future<void> _handleLocationToggle() async {
    final serviceStatus = await Permission.location.serviceStatus;
    if (!serviceStatus.isEnabled) {
      await AppSettings.openAppSettings(type: AppSettingsType.location);
      return;
    }
    final permissionStatus = await Permission.location.request();
    if (permissionStatus.isGranted && mounted) {
      setState(() => _isLocationReady = true);
    }
  }

  Future<void> _fetchCurrentUserPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userModel = await context.read<FirestoreService>().getUser(user.uid);
      if(mounted) {
        setState(() {
          _currentUserPhotoUrl = userModel.photoUrl;
        });
      }
    }
  }

  Future<void> _fetchProfilesForIds(List<String> userIds) async {
    final newIds = userIds.where((id) => !_userProfileCache.containsKey(id)).toList();
    if (newIds.isEmpty) return;

    for (var userId in newIds) {
      final profileBox = Hive.box('user_profiles');
      if (profileBox.containsKey(userId)) {
        _userProfileCache[userId] = UserModel.fromMap(userId, Map<String, dynamic>.from(profileBox.get(userId)));
      } else {
        try {
          final userModel = await context.read<FirestoreService>().getUser(userId);
          profileBox.put(userId, userModel.toMap());
          _userProfileCache[userId] = userModel;
        } catch (e) {
          debugPrint("Error fetching user profile for $userId: $e");
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _loadInitialProfiles() {
    final box = Hive.box('nearby_contacts');
    _fetchProfilesForIds(box.keys.cast<String>().toList());
  }

  String _getStatusMessage(NearbyStatus status, bool isScanning) {
    if (isScanning) {
      switch (status) {
        case NearbyStatus.scanning: return "Scanning for others...";
        case NearbyStatus.advertising: return "Making you discoverable...";
        case NearbyStatus.userFound: return "Found someone new!";
        default: return "Scanning & Broadcasting...";
      }
    }
    if (_isBluetoothReady && _isLocationReady) {
      return "Ready! Tap your picture to begin.";
    }
    return "Enable Bluetooth & Location to begin.";
  }

  void _deleteFoundUser(String userId) {
    final box = Hive.box('nearby_contacts');
    box.delete(userId);
    _userProfileCache.remove(userId);
    setState(() {});
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
      body: BlocConsumer<NearbyBloc, NearbyState>(
        listener: (context, state) {
          if (state is NearbyActive) {
            if (state.foundUserIds.length > _lastKnownUserIds.length) {
              _fetchProfilesForIds(state.foundUserIds);
              _discoveryController.forward(from: 0.0);
            }
            _lastKnownUserIds = state.foundUserIds;
          }
        },
        builder: (context, state) {
          bool isScanning = state is NearbyActive;
          NearbyStatus currentStatus = (state is NearbyActive) ? state.status : NearbyStatus.idle;
          List<String> foundUserIds = (state is NearbyActive) ? state.foundUserIds : [];

          return Column(
            children: [
              _buildControlSection(context, isScanning, currentStatus),
              const Divider(height: 1),
              _buildFoundUsersSection(foundUserIds),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlSection(BuildContext context, bool isScanning, NearbyStatus status) {
    bool canStartScan = _isBluetoothReady && _isLocationReady;

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToggleChip(
                label: "Bluetooth",
                icon: Icons.bluetooth,
                isEnabled: _isBluetoothReady,
                onChanged: _handleBluetoothToggle,
              ),
              _buildToggleChip(
                label: "Location",
                icon: Icons.location_on,
                isEnabled: _isLocationReady,
                onChanged: _handleLocationToggle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_getStatusMessage(status, isScanning), style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 16),

          SizedBox(
            height: 200,
            child: SonarView(
              isScanning: isScanning,
              unleashController: _unleashController,
              discoveryController: _discoveryController,
              centerAvatar: _buildCenterAvatar(canStartScan, isScanning),
              foundUserAvatars: _buildSonarAvatars(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool isEnabled,
    required VoidCallback onChanged,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1.0, end: isEnabled ? 1.05 : 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: FilterChip(
        label: Text(label),
        avatar: Icon(icon, color: isEnabled ? Colors.white : Colors.grey),
        selected: isEnabled,
        onSelected: isEnabled ? null : (_) => onChanged(),
        backgroundColor: Colors.grey[200],
        selectedColor: Colors.blue,
        labelStyle: TextStyle(color: isEnabled ? Colors.white : Colors.black),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildCenterAvatar(bool canStartScan, bool isScanning) {
    Widget avatar = GestureDetector(
      onTap: () {
        if (canStartScan && !isScanning) {
          _unleashController.forward(from: 0.0);
          context.read<NearbyBloc>().add(StartNearbyServices());
        } else if (isScanning) {
          context.read<NearbyBloc>().add(StopNearbyServices());
        }
      },
      child: CircleAvatar(
        radius: 30,
        backgroundColor: Colors.grey[300],
        backgroundImage: _currentUserPhotoUrl != null ? NetworkImage(_currentUserPhotoUrl!) : null,
        child: _currentUserPhotoUrl == null ? const Icon(Icons.person, size: 30, color: Colors.white) : null,
      ),
    );

    if (canStartScan && !isScanning) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1.0, end: 1.1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: avatar,
      );
    }
    return avatar;
  }

  List<Widget> _buildSonarAvatars() {
    final List<Widget> avatars = [];
    final sonarRadius = 100.0;

    _userProfileCache.forEach((userId, user) {
      final photoUrl = user.photoUrl;
      final random = Random(userId.hashCode);
      final angle = random.nextDouble() * 2 * pi;
      final distance = (random.nextDouble() * 0.6 + 0.2) * sonarRadius;

      final position = Offset(
        cos(angle) * distance + sonarRadius - 20,
        sin(angle) * distance + sonarRadius - 20,
      );

      final avatarWidget = TweenAnimationBuilder<double>(
        key: ValueKey(userId),
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: value,
              child: child,
            ),
          );
        },
        child: CircleAvatar(
          radius: 20,
          backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
          child: (photoUrl.isEmpty) ? const Icon(Icons.person) : null,
        ),
      );

      avatars.add(
        Positioned(
          left: position.dx,
          top: position.dy,
          child: avatarWidget,
        ),
      );
    });
    return avatars;
  }

  Widget _buildFoundUsersSection(List<String> userIds) {
    if (userIds.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text("No users found yet. Turn on the sonar!", style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return Expanded(
      child: GridView.builder(
        padding: const EdgeInsets.all(8.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: userIds.length,
        itemBuilder: (context, index) {
          final userId = userIds[index];
          final user = _userProfileCache[userId];

          if (user == null) {
            return const Card(child: Center(child: CircularProgressIndicator()));
          }
          return CompactNearbyUserCard(
            user: user,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))),
            onDelete: () => _deleteFoundUser(userId),
          );
        },
      ),
    );
  }
}

class CompactNearbyUserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const CompactNearbyUserCard({
    super.key,
    required this.user,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            (user.photoUrl.isNotEmpty)
                ? Image.network(
              user.photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 40, color: Colors.grey),
            )
                : const Icon(Icons.person, size: 40, color: Colors.grey),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            Positioned(
              bottom: 5,
              left: 5,
              right: 5,
              child: Text(
                user.username,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),

            if (user.presence)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
