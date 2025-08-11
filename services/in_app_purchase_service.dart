import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

// Define your product IDs here. These must match the IDs you set up
// in the Google Play Console and App Store Connect.
const String _kProductId100Coins = 'com.freegram.coins100';
const String _kProductId550Coins = 'com.freegram.coins550';
const List<String> _kProductIds = <String>[
  _kProductId100Coins,
  _kProductId550Coins,
];

class InAppPurchaseService {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];

  // Callback to be triggered when a purchase is successful
  final Function(int amount) onPurchaseSuccess;

  InAppPurchaseService({required this.onPurchaseSuccess});

  /// Initializes the in-app purchase service.
  Future<void> initialize() async {
    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      debugPrint("In-app purchases not available.");
      return;
    }

    // Load product details from the respective app store
    await _loadProducts();

    // Listen to purchase updates
    _subscription =
        _inAppPurchase.purchaseStream.listen((List<PurchaseDetails> purchaseDetailsList) {
          _listenToPurchaseUpdated(purchaseDetailsList);
        }, onDone: () {
          _subscription.cancel();
        }, onError: (error) {
          // Handle error here.
        });
  }

  /// Fetches product details from the app store.
  Future<void> _loadProducts() async {
    final ProductDetailsResponse response =
    await _inAppPurchase.queryProductDetails(_kProductIds.toSet());
    if (response.error != null) {
      debugPrint('Failed to load products: ${response.error}');
      return;
    }
    if (response.productDetails.isEmpty) {
      debugPrint('No products found.');
      return;
    }
    _products = response.productDetails;
  }

  /// Handles the purchase stream updates.
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Show a pending UI if needed
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          // Handle error
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          _deliverPurchase(purchaseDetails);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Delivers the purchased item to the user.
  void _deliverPurchase(PurchaseDetails purchaseDetails) {
    int amount = 0;
    if (purchaseDetails.productID == _kProductId100Coins) {
      amount = 100;
    } else if (purchaseDetails.productID == _kProductId550Coins) {
      amount = 550;
    }

    if (amount > 0) {
      onPurchaseSuccess(amount);
    }
  }

  /// Initiates the purchase flow for a product.
  Future<void> buyProduct(String productId) async {
    final ProductDetails? productDetails = _getProduct(productId);
    if (productDetails == null) {
      debugPrint("Product not found: $productId");
      return;
    }

    final PurchaseParam purchaseParam =
    PurchaseParam(productDetails: productDetails);
    await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
  }

  /// Gets a product's details by its ID.
  ProductDetails? _getProduct(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// Disposes the stream subscription.
  void dispose() {
    _subscription.cancel();
  }
}
