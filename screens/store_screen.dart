import 'package:cloud_firestore/cloud_firestore.dart'; // NEW: Added missing import
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:freegram/models/user_model.dart';
import 'package:freegram/services/ad_helper.dart';
import 'package:freegram/services/firestore_service.dart';
import 'package:freegram/services/in_app_purchase_service.dart'; // FIX: Corrected typo
import 'package:provider/provider.dart';

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Store"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Get Items"),
              Tab(text: "Get Coins"),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildUserWallet(context, currentUser.uid),
            Expanded(
              child: TabBarView(
                children: [
                  _GetItemsTab(userId: currentUser.uid),
                  _GetCoinsTab(userId: currentUser.uid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserWallet(BuildContext context, String uid) {
    return StreamBuilder<UserModel>(
      stream: context.read<FirestoreService>().getUserStream(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.blue.withOpacity(0.1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _WalletItem(
                icon: Icons.star,
                label: "Super Likes",
                value: user.superLikes.toString(),
                color: Colors.blue,
              ),
              _WalletItem(
                icon: Icons.monetization_on,
                label: "Coins",
                value: user.coins.toString(),
                color: Colors.amber,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GetItemsTab extends StatefulWidget {
  final String userId;
  const _GetItemsTab({required this.userId});

  @override
  State<_GetItemsTab> createState() => _GetItemsTabState();
}

class _GetItemsTabState extends State<_GetItemsTab> {
  final AdHelper _adHelper = AdHelper();
  bool _isAdButtonLoading = false;
  bool _isCoinButtonLoading = false;

  @override
  void initState() {
    super.initState();
    _adHelper.loadRewardedAd();
  }

  void _showAd() {
    setState(() => _isAdButtonLoading = true);
    try {
      _adHelper.showRewardedAd(() {
        context.read<FirestoreService>().grantAdReward(widget.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                backgroundColor: Colors.green,
                content: Text("Success! 1 Super Like has been added.")),
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Colors.red,
            content: Text("Failed to show ad: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isAdButtonLoading = false);
      }
    }
  }

  void _purchaseWithCoins() async {
    setState(() => _isCoinButtonLoading = true);
    try {
      await context
          .read<FirestoreService>()
          .purchaseWithCoins(widget.userId, coinCost: 50, superLikeAmount: 5);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              backgroundColor: Colors.green,
              content: Text("Purchase successful! 5 Super Likes added.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.red,
              content: Text("Purchase failed: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCoinButtonLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          "Earn for Free",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _StoreItemCard(
          title: "Free Super Like",
          subtitle: "Watch a short ad to get one free Super Like.",
          icon: Icons.star,
          iconColor: Colors.blue,
          buttonText: "Watch Ad",
          isLoading: _isAdButtonLoading,
          onPressed: _showAd,
        ),
        const Divider(height: 32),
        const Text(
          "Spend Coins",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _StoreItemCard(
          title: "5 Super Likes",
          subtitle: "Get a pack of five Super Likes to stand out.",
          icon: Icons.star,
          iconColor: Colors.blue,
          buttonText: "50 Coins",
          isLoading: _isCoinButtonLoading,
          onPressed: _purchaseWithCoins,
        ),
      ],
    );
  }
}

class _GetCoinsTab extends StatefulWidget {
  final String userId;
  const _GetCoinsTab({required this.userId});

  @override
  State<_GetCoinsTab> createState() => _GetCoinsTabState();
}

class _GetCoinsTabState extends State<_GetCoinsTab> {
  late InAppPurchaseService _iapService;

  @override
  void initState() {
    super.initState();
    _iapService = InAppPurchaseService(onPurchaseSuccess: (int amount) {
      // When a purchase is successful, grant the coins via Firestore
      context
          .read<FirestoreService>()
          .updateUser(widget.userId, {'coins': FieldValue.increment(amount)});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Colors.green,
            content: Text("Success! $amount coins have been added.")),
      );
    });
    _iapService.initialize();
  }

  @override
  void dispose() {
    _iapService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _StoreItemCard(
          title: "100 Coins",
          subtitle: "A starter pack of coins.",
          icon: Icons.monetization_on,
          iconColor: Colors.amber,
          buttonText: "\$0.99",
          onPressed: () {
            _iapService.buyProduct('com.freegram.coins100');
          },
        ),
        const SizedBox(height: 12),
        _StoreItemCard(
          title: "550 Coins",
          subtitle: "Best value pack!",
          icon: Icons.monetization_on,
          iconColor: Colors.amber,
          buttonText: "\$4.99",
          onPressed: () {
            _iapService.buyProduct('com.freegram.coins550');
          },
        ),
      ],
    );
  }
}

class _StoreItemCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String buttonText;
  final VoidCallback onPressed;
  final bool isLoading;

  const _StoreItemCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.buttonText,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              child: isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _WalletItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
