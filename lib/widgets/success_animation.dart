import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:provider/provider.dart';
import '../controllers/note_provider.dart';

class SuccessAnimation extends StatefulWidget {
  final Widget child;
  final bool trigger;

  const SuccessAnimation({super.key, required this.child, required this.trigger});

  @override
  State<SuccessAnimation> createState() => _SuccessAnimationState();
}

class _SuccessAnimationState extends State<SuccessAnimation> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void didUpdateWidget(SuccessAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _confettiController.play();
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: pi / 2, // Phun xuống dưới
            maxBlastForce: 15,
            minBlastForce: 5,
            emissionFrequency: 0.05,
            numberOfParticles: 25,
            gravity: 0.2,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.amber,
              Colors.red,
            ],
          ),
        ),
      ],
    );
  }
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
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(999);

    // Nếu tiến độ là 0% hoặc nhỏ hơn, vẽ thanh rỗng ngay lập tức để tránh lỗi hoạt họa hoặc crash
    if (value <= 0.0) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: effectiveBorderRadius,
        ),
      );
    }

    int animTrigger = 0;
    try {
      final noteProvider = Provider.of<NoteProvider>(context);
      animTrigger = noteProvider.animationTrigger;
    } catch (_) {}

    return Container(
      key: ValueKey(animTrigger),
      height: height,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: effectiveBorderRadius,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final targetWidth = value.clamp(0.0, 1.0);
          
          // Tốc độ không đổi: 0% -> 100% chạy hết 3 giây (3000ms)
          // Thời gian chạy tỉ lệ thuận với tiến độ thực tế (ví dụ: 50% chạy hết 1.5 giây)
          // Đảm bảo thời gian chạy tối thiểu là 400ms để hiệu ứng luôn rõ nét
          final durationMs = (3000 * targetWidth).round().clamp(400, 3000);

          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: targetWidth),
            duration: Duration(milliseconds: durationMs),
            curve: Curves.easeOutBack, // Hiệu ứng nhún nhẹ (springy back) cực kỳ sang trọng
            builder: (context, animValue, child) {
              // Clamp kích thước chiều rộng để tránh giá trị âm gây lỗi render hoặc tràn viền
              final width = (constraints.maxWidth * animValue).clamp(0.0, constraints.maxWidth);
              return Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: effectiveBorderRadius,
                  boxShadow: [
                    if (animValue > 0)
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
