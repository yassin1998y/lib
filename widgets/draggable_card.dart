import 'dart:math';
import 'package:flutter/material.dart';

// Enum to represent the swipe direction
enum SwipeDirection { left, right, up, none }

class DraggableCard extends StatefulWidget {
  final Widget child;
  final Function(SwipeDirection direction) onSwipe;

  const DraggableCard({
    super.key,
    required this.child,
    required this.onSwipe,
  });

  @override
  State<DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<DraggableCard>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  late Animation<Offset> _slideAnimation;
  Offset _dragPosition = Offset.zero;
  SwipeDirection _swipeDirection = SwipeDirection.none;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    // No action needed on start
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition += details.delta;
      _updateSwipeDirection();
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Check if the swipe was significant enough to trigger an action
    if (_dragPosition.dx.abs() > screenWidth / 4 ||
        _dragPosition.dy < -screenHeight / 5) {
      _animateCardOffScreen();
    } else {
      // If not, animate the card back to the center
      _animateCardToCenter();
    }
  }

  void _updateSwipeDirection() {
    if (_dragPosition.dy < -60 && _dragPosition.dx.abs() < 60) {
      _swipeDirection = SwipeDirection.up;
    } else if (_dragPosition.dx > 40) {
      _swipeDirection = SwipeDirection.right;
    } else if (_dragPosition.dx < -40) {
      _swipeDirection = SwipeDirection.left;
    } else {
      _swipeDirection = SwipeDirection.none;
    }
  }

  void _animateCardOffScreen() {
    double endDx = _dragPosition.dx > 0 ? 500 : -500;
    double endDy = _dragPosition.dy;

    if (_swipeDirection == SwipeDirection.up) {
      endDy = -800;
    }

    _slideAnimation = Tween<Offset>(
      begin: _dragPosition,
      end: Offset(endDx, endDy),
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn));

    _animationController.forward().then((_) {
      widget.onSwipe(_swipeDirection);
    });
  }

  void _animateCardToCenter() {
    _slideAnimation = Tween<Offset>(
      begin: _dragPosition,
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.elasticOut));

    _animationController.forward().then((_) {
      setState(() {
        _dragPosition = Offset.zero;
        _swipeDirection = SwipeDirection.none;
        _animationController.reset();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = _animationController.isAnimating
        ? _slideAnimation.value
        : _dragPosition;
    final angle = position.dx / 1000; // Rotation based on horizontal drag

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: position,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            children: [
              widget.child,
              _buildActionOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionOverlay() {
    Color color;
    String text;
    IconData icon;

    switch (_swipeDirection) {
      case SwipeDirection.right:
        color = Colors.green;
        text = "LIKE";
        icon = Icons.favorite;
        break;
      case SwipeDirection.left:
        color = Colors.red;
        text = "NOPE";
        icon = Icons.close;
        break;
      case SwipeDirection.up:
        color = Colors.blue;
        text = "SUPER";
        icon = Icons.star;
        break;
      case SwipeDirection.none:
        return const SizedBox.shrink();
    }

    final opacity = min(_dragPosition.distance / 100, 1.0);

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.black.withOpacity(0.3),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 40),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
