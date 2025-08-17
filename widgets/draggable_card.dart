import 'dart:math';
import 'package:flutter/material.dart';

// Enum to represent the swipe direction
enum SwipeDirection { left, right, up, none }

// FIX: The key is now passed to the StatefulWidget to access its state.
class DraggableCard extends StatefulWidget {
  final Widget child;
  final Function(SwipeDirection direction) onSwipe;

  const DraggableCard({
    required Key key, // Key is now required
    required this.child,
    required this.onSwipe,
  }) : super(key: key);

  @override
  // FIX: State class is now public to be accessed from the parent.
  DraggableCardState createState() => DraggableCardState();
}

// FIX: State class is now public.
class DraggableCardState extends State<DraggableCard>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
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

    // FIX: Reduced the swipe threshold to make it more sensitive.
    // It now only requires dragging 1/6th of the screen width.
    if (_dragPosition.dx.abs() > screenWidth / 6 ||
        _dragPosition.dy < -screenHeight / 6) {
      _animateCardOffScreen();
    } else {
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
    double endDx = 0;
    double endDy = 0;

    switch (_swipeDirection) {
      case SwipeDirection.left:
        endDx = -500;
        break;
      case SwipeDirection.right:
        endDx = 500;
        break;
      case SwipeDirection.up:
        endDy = -800;
        break;
      case SwipeDirection.none:
      // This case should ideally not be hit if called from _onPanEnd
      // but as a fallback, we can treat it as a cancel.
        _animateCardToCenter();
        return;
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

  /// NEW: Public method to trigger the swipe animation from the parent widget.
  void triggerSwipe(SwipeDirection direction) {
    if (direction == SwipeDirection.none) return;
    setState(() {
      _swipeDirection = direction;
    });
    _animateCardOffScreen();
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
