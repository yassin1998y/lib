import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  // FIX: Changed the StreamSubscription type to handle a single ConnectivityResult
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  bool _isConnected = true; // Assume connected initially

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    // FIX: Listen to the stream of ConnectivityResult
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    // FIX: checkConnectivity now returns a single ConnectivityResult
    var connectivityResult = await (Connectivity().checkConnectivity());
    _updateConnectionStatus(connectivityResult);
  }

  // FIX: The parameter is now correctly typed as ConnectivityResult
  void _updateConnectionStatus(ConnectivityResult result) {
    // FIX: Check if the result is not 'none'
    final hasConnection = result != ConnectivityResult.none;
    if (mounted) {
      setState(() {
        _isConnected = hasConnection;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnected) {
      return widget.child;
    } else {
      return const NoConnectionScreen();
    }
  }
}

class NoConnectionScreen extends StatelessWidget {
  const NoConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 80, color: Colors.grey),
                SizedBox(height: 24),
                Text(
                  'No Internet Connection',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Please check your connection to use Freegram.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
