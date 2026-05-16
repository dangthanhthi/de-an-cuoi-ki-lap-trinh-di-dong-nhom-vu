import 'dart:math';
import 'package:flutter/material.dart';

class SuccessAnimation extends StatefulWidget {
  final Widget child;
  final bool trigger;

  const SuccessAnimation({super.key, required this.child, required this.trigger});

  @override
  State<SuccessAnimation> createState() => _SuccessAnimationState();
}

class _SuccessAnimationState extends State<SuccessAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void didUpdateWidget(SuccessAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _particles.clear();
    for (int i = 0; i < 40; i++) {
      _particles.add(Particle(_random));
    }
    _controller.reset();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_controller.isAnimating)
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: ParticlePainter(_particles, _controller.value),
            ),
          ),
      ],
    );
  }
}

class Particle {
  late double x, y;
  late double vx, vy;
  late Color color;
  late double size;

  Particle(Random random) {
    x = 0.5; // Normalized center
    y = 0.5;
    double angle = random.nextDouble() * 2 * pi;
    double speed = random.nextDouble() * 0.5 + 0.2;
    vx = cos(angle) * speed;
    vy = sin(angle) * speed;
    color = Colors.primaries[random.nextInt(Colors.primaries.length)].withValues(alpha: 0.8);
    size = random.nextDouble() * 8 + 4;
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  ParticlePainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var p in particles) {
      final double x = size.width * (p.x + p.vx * progress);
      final double y = size.height * (p.y + p.vy * progress + 0.5 * progress * progress); // Gravity effect
      final double opacity = (1.0 - progress).clamp(0.0, 1.0);
      
      paint.color = p.color.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AnimatedProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color backgroundColor;
  final double height;
  final BorderRadius? borderRadius;

  const AnimatedProgressBar({
    super.key,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.height = 8.0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius ?? BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            width: constraints.maxWidth * value.clamp(0.0, 1.0),
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius ?? BorderRadius.circular(999),
              boxShadow: [
                if (value > 0)
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
