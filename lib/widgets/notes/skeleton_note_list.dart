import 'package:flutter/material.dart';

class SkeletonNoteList extends StatelessWidget {
  const SkeletonNoteList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (context, index) => const _SkeletonNoteCard(),
    );
  }
}

class _SkeletonNoteCard extends StatefulWidget {
  const _SkeletonNoteCard();

  @override
  State<_SkeletonNoteCard> createState() => _SkeletonNoteCardState();
}

class _SkeletonNoteCardState extends State<_SkeletonNoteCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[850]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[800]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Accent bar skeleton
              Container(
                width: 4,
                height: 54,
                decoration: BoxDecoration(
                  color: highlightColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title skeleton
                    _SkeletonLine(width: 150, height: 18, color: highlightColor),
                    const SizedBox(height: 12),
                    // Content/Progress skeleton
                    _SkeletonLine(width: double.infinity, height: 12, color: highlightColor),
                    const SizedBox(height: 12),
                    // Chips skeleton
                    Row(
                      children: [
                        _SkeletonLine(width: 60, height: 20, color: highlightColor),
                        const SizedBox(width: 8),
                        _SkeletonLine(width: 80, height: 20, color: highlightColor),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({required this.width, required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
