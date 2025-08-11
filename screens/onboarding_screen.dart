import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // The content for each onboarding page
  final List<Map<String, String>> _onboardingData = [
    {
      "icon": "assets/icons/discover.png", // Placeholder, you'd add actual assets
      "title": "Discover & Connect",
      "description": "Explore profiles in the Discover tab and find new people who share your interests.",
    },
    {
      "icon": "assets/icons/match.png",
      "title": "Play the Match Game",
      "description": "Tap the flame icon to swipe through profiles. A right swipe is a 'like' - if they like you back, it's a match!",
    },
    {
      "icon": "assets/icons/store.png",
      "title": "Visit the Store",
      "description": "Get free daily rewards and purchase Super Likes to stand out from the crowd.",
    },
  ];

  void _onFinished() {
    // Use Hive to save that the user has completed onboarding
    final settingsBox = Hive.box('settings');
    settingsBox.put('hasSeenOnboarding', true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _onboardingData.length,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemBuilder: (context, index) {
                  return OnboardingPage(
                    title: _onboardingData[index]['title']!,
                    description: _onboardingData[index]['description']!,
                    iconData: _getIconData(index),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Skip Button
                  TextButton(
                    onPressed: _onFinished,
                    child: const Text("SKIP"),
                  ),

                  // Dots Indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _onboardingData.length,
                          (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 10,
                        width: _currentPage == index ? 30 : 10,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Colors.blue
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),

                  // Next / Done Button
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage == _onboardingData.length - 1) {
                        _onFinished();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    child: Text(
                      _currentPage == _onboardingData.length - 1
                          ? "DONE"
                          : "NEXT",
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to return actual icons since we can't use asset strings directly
  IconData _getIconData(int index) {
    switch (index) {
      case 0:
        return Icons.people_outline;
      case 1:
        return Icons.whatshot;
      case 2:
        return Icons.storefront_outlined;
      default:
        return Icons.info_outline;
    }
  }
}

class OnboardingPage extends StatelessWidget {
  final String title;
  final String description;
  final IconData iconData;

  const OnboardingPage({
    super.key,
    required this.title,
    required this.description,
    required this.iconData,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            iconData,
            size: 120,
            color: Colors.blue,
          ),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
