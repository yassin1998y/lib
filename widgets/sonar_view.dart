import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// A widget that displays a sonar-style radar animation.
class SonarView extends StatefulWidget {
  final bool isScanning;
  final List<Widget> foundUserAvatars;

  const SonarView({
    super.key,
    required this.isScanning,
    this.foundUserAvatars = const [],
  });

  @override
  State<SonarView> createState() => _SonarViewState();
}

class _SonarViewState extends State<SonarView> with TickerProviderStateMixin {
  late AnimationController _sonarController;

  @override
  void initState() {
    super.initState();
    _sonarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Start the animation only if scanning is active
    if (widget.isScanning) {
      _sonarController.repeat();
    }
  }

  @override
  void didUpdateWidget(SonarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Control the animation based on the scanning state
    if (widget.isScanning && !_sonarController.isAnimating) {
      _sonarController.repeat();
    } else if (!widget.isScanning && _sonarController.isAnimating) {
      _sonarController.stop();
    }
  }

  @override
  void dispose() {
    _sonarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: CustomPaint(
        painter: SonarPainter(animation: _sonarController),
        child: Stack(
          children: [
            // Center icon representing the current user
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.5),
                ),
                child: const Icon(Icons.person, color: Colors.white),
              ),
            ),
            // Spread the found user avatars around the sonar
            ...widget.foundUserAvatars,
          ],
        ),
      ),
    );
  }
}

/// A custom painter that draws the sonar rings and pulsing wave.
class SonarPainter extends CustomPainter {
  final Animation<double> animation;
  final Paint _sonarPaint;

  SonarPainter({required this.animation})
      : _sonarPaint = Paint()
    ..color = Colors.blue.withOpacity(0.5)
    ..style = PaintingStyle.stroke,
        super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;

    // Draw the concentric circles
    for (int i = 1; i <= 3; i++) {
      _sonarPaint.strokeWidth = 1.0;
      _sonarPaint.color = Colors.blue.withOpacity(0.3);
      canvas.drawCircle(center, maxRadius * (i / 3), _sonarPaint);
    }

    // Draw the animated pulsing wave
    if (animation.value > 0) {
      _sonarPaint.strokeWidth = 2.0;
      // The wave fades out as it expands
      _sonarPaint.color = Colors.blue.withOpacity(1.0 - animation.value);
      canvas.drawCircle(center, maxRadius * animation.value, _sonarPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
