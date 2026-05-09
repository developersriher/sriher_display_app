import 'package:flutter/material.dart';

class AnimatedHeading extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const AnimatedHeading({super.key, required this.text, this.style});

  @override
  State<AnimatedHeading> createState() => _AnimatedHeadingState();
}

class _AnimatedHeadingState extends State<AnimatedHeading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedHeading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Text(
          widget.text.toUpperCase(),
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w900,
            color: Colors.blue,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
