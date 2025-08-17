import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;

/// A helper class to manage loading and showing rewarded ads.
class AdHelper {
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Loads a rewarded ad and provides callbacks for success or failure.
  void loadRewardedAd({
    VoidCallback? onAdLoaded,
    Function(LoadAdError)? onAdFailedToLoad,
  }) {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isAdLoaded = false;
          onAdFailedToLoad?.call(error);
        },
      ),
    );
  }

  /// Shows the loaded rewarded ad.
  void showRewardedAd(Function() onReward) {
    if (!_isAdLoaded || _rewardedAd == null) {
      debugPrint("Rewarded ad is not ready to be shown.");
      // Attempt to load another ad for next time.
      loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _isAdLoaded = false;
        loadRewardedAd(); // Pre-load the next ad
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _isAdLoaded = false;
        loadRewardedAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onReward();
      },
    );
    _rewardedAd = null;
    _isAdLoaded = false;
  }
}
