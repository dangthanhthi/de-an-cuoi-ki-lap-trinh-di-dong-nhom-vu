import 'package:flutter/material.dart';
import '../../utils/media_utils.dart';

class MultiImageGallery extends StatelessWidget {
  final List<String> images;
  final Function(int index) onTapImage;
  final double maxWidth;

  const MultiImageGallery({
    super.key,
    required this.images,
    required this.onTapImage,
    this.maxWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    final size = images.length;
    if (size == 1) {
      return GestureDetector(
        onTap: () => onTapImage(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: 240,
              maxWidth: maxWidth,
            ),
            child: _ImageWidget(url: images[0], fit: BoxFit.cover),
          ),
        ),
      );
    } else if (size == 2) {
      final double width = (maxWidth - 8) / 2;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildGridImage(0, width, 140),
          const SizedBox(width: 8),
          _buildGridImage(1, width, 140),
        ],
      );
    } else if (size == 3) {
      final double width = (maxWidth - 16) / 3;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildGridImage(0, width, 100),
          const SizedBox(width: 8),
          _buildGridImage(1, width, 100),
          const SizedBox(width: 8),
          _buildGridImage(2, width, 100),
        ],
      );
    } else {
      return _CardStackGallery(
        images: images,
        onTapImage: onTapImage,
        maxWidth: maxWidth,
      );
    }
  }

  Widget _buildGridImage(int index, double width, double height) {
    return GestureDetector(
      onTap: () => onTapImage(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: _ImageWidget(url: images[index], fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _ImageWidget extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _ImageWidget({required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (isDataUri(url)) {
      final bytes = bytesFromDataUri(url);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image, size: 30, color: Colors.grey),
          ),
        );
      }
    }
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, size: 30, color: Colors.grey),
      ),
    );
  }
}

class _CardStackGallery extends StatefulWidget {
  final List<String> images;
  final Function(int index) onTapImage;
  final double maxWidth;

  const _CardStackGallery({
    required this.images,
    required this.onTapImage,
    required this.maxWidth,
  });

  @override
  State<_CardStackGallery> createState() => _CardStackGalleryState();
}

class _CardStackGalleryState extends State<_CardStackGallery> {
  late PageController _pageController;
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onScroll);
  }

  void _onScroll() {
    if (mounted) {
      setState(() {
        _currentPage = _pageController.page ?? 0.0;
      });
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;
    return SizedBox(
      width: widget.maxWidth,
      height: 230,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = total - 1; i >= 0; i--) ...[
            _buildCard(i, total),
          ],
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => widget.onTapImage(index),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
          Positioned(
            right: 18,
            bottom: 22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${(_currentPage.round() + 1).clamp(1, total)}/$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(int index, int total) {
    final diff = index - _currentPage;

    if (diff <= -1.0) {
      return const SizedBox.shrink();
    }

    double xOffset = 0.0;
    double yOffset = 0.0;
    double scale = 1.0;
    double rotation = 0.0;
    double opacity = 1.0;

    if (diff < 0.0) {
      xOffset = diff * widget.maxWidth;
      rotation = diff * 0.15;
      opacity = 1.0 + diff;
    } else if (diff < 3.0) {
      final percent = diff;
      scale = 1.0 - (percent * 0.045);
      yOffset = -percent * 11;
      xOffset = percent * 8;

      if (index % 2 == 1) {
        rotation = percent * 0.025;
      } else {
        rotation = -percent * 0.025;
      }
    } else {
      opacity = 0.0;
    }

    return Positioned(
      left: 4,
      top: 20,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(xOffset, yOffset),
          child: Transform.rotate(
            angle: rotation,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: widget.maxWidth - 20,
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _ImageWidget(
                    url: widget.images[index],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
