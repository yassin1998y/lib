import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;

/// A helper class to manage loading and showing rewarded ads.
class AdHelper {
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;

  // Use test ad unit IDs for development.
  // Replace these with your actual AdMob ad unit IDs for production.
  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Loads a rewarded ad.
  void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isAdLoaded = false;
        },
      ),
    );
  }

  /// Shows the loaded rewarded ad.
  /// The [onReward] callback is triggered when the user successfully watches the ad.
  void showRewardedAd(Function() onReward) {
    if (!_isAdLoaded || _rewardedAd == null) {
      // If the ad isn't loaded yet, load it and try again later.
      loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadRewardedAd(); // Pre-load the next ad
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        loadRewardedAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        // Grant the reward when this callback is fired.
        onReward();
      },
    );
    _rewardedAd = null;
    _isAdLoaded = false;
  }
}
