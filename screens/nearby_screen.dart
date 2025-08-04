import 'dart:async';

import 'package:flutter/material.dart';
import 'package:freegram/main.dart'; // For BluetoothService and status service
import 'package:freegram/screens/profile_screen.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final BluetoothService _bluetoothService;
  late final Box _contactsBox;
  StreamSubscription? _statusSubscription;
  NearbyStatus _currentStatus = NearbyStatus.idle;

  @override
  void initState() {
    super.initState();
    // Initialize and start the Bluetooth service
    _bluetoothService = BluetoothService();
    _bluetoothService.start();

    // Open the Hive box for nearby contacts
    _contactsBox = Hive.box('nearby_contacts');

    // Listen to status updates from the Bluetooth service
    _statusSubscription = bluetoothStatusService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _currentStatus = status;
        });
      }
    });
  }

  @override
  void dispose() {
    // Stop the Bluetooth service and cancel subscriptions to prevent memory leaks
    _bluetoothService.stop();
    _statusSubscription?.cancel();
    super.dispose();
  }

  /// Fetches a user's profile, first checking the local cache and then Firestore.
  Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    final profileBox = Hive.box('user_profiles');
    // Return cached data if available
    if (profileBox.containsKey(userId)) {
      return Map<String, dynamic>.from(profileBox.get(userId));
    }

    // Otherwise, fetch from Firestore
    try {
      final doc = await context.read<FirestoreService>().getUser(userId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Cache the newly fetched data
        profileBox.put(userId, data);
        return data;
      }
    } catch (e) {
      debugPrint("Error fetching user profile for $userId: $e");
    }
    return null;
  }

  /// Provides a user-friendly message based on the current Bluetooth status.
  String _getStatusMessage(NearbyStatus status) {
    switch (status) {
      case NearbyStatus.idle:
        return "Ready to start.";
      case NearbyStatus.checkingPermissions:
        return "Checking permissions...";
      case NearbyStatus.permissionsDenied:
        return "Permissions denied. Please grant permissions in settings.";
      case NearbyStatus.checkingAdapter:
        return "Checking Bluetooth adapter...";
      case NearbyStatus.adapterOff:
        return "Please turn on Bluetooth.";
      case NearbyStatus.startingServices:
        return "Starting services...";
      case NearbyStatus.advertising:
        return "Broadcasting your signal...";
      case NearbyStatus.scanning:
        return "Scanning for nearby users...";
      case NearbyStatus.userFound:
        return "Found a user! Saving contact...";
      case NearbyStatus.error:
        return "An error occurred. Please try again.";
      default:
        return "Initializing...";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Users'),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Status bar to show the current state of the Bluetooth service
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: Colors.blue.withOpacity(0.1),
            child: Row(
              children: [
                if (_currentStatus == NearbyStatus.scanning || _currentStatus == NearbyStatus.advertising)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    _currentStatus == NearbyStatus.error || _currentStatus == NearbyStatus.permissionsDenied
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: _currentStatus == NearbyStatus.error || _currentStatus == NearbyStatus.permissionsDenied
                        ? Colors.red
                        : Colors.green,
                    size: 20,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getStatusMessage(_currentStatus),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          // Reactive list that updates whenever the Hive box changes
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _contactsBox.listenable(),
              builder: (context, Box box, _) {
                final contacts = box.values.map((e) {
                  final contact = Map<String, dynamic>.from(e);
                  contact['timestamp'] = DateTime.parse(contact['timestamp']);
                  return contact;
                }).toList();

                // Sort contacts by most recently found
                contacts.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

                if (contacts.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "Keep this screen open to discover others. Make sure your Bluetooth is on.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    final String userId = contact['id'];
                    final DateTime timestamp = contact['timestamp'];

                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _fetchUserProfile(userId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return ListTile(
                            title: const Text('Loading user...'),
                            subtitle: Text('Found ${timeago.format(timestamp)}'),
                            leading: const CircleAvatar(backgroundColor: Colors.grey),
                          );
                        }
                        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                          return ListTile(
                            title: const Text('Unknown User'),
                            subtitle: Text('ID: $userId'),
                            leading: const CircleAvatar(child: Icon(Icons.error)),
                          );
                        }

                        final userData = snapshot.data!;
                        final username = userData['username'] ?? 'No Name';
                        final photoUrl = userData['photoUrl'];

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?')
                                  : null,
                            ),
                            title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Found ${timeago.format(timestamp)}'),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId))),
                          ),
                        );
                      },
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
