import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_image_viewer/easy_image_viewer.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/media_utils.dart';

class ImageGridPreviewScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageGridPreviewScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<ImageGridPreviewScreen> createState() => _ImageGridPreviewScreenState();
}

class _ImageGridPreviewScreenState extends State<ImageGridPreviewScreen> {
  late int _currentIndex;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    
    // Scroll to the initial index on first build without auto-opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialIndex >= 0 && widget.initialIndex < widget.images.length) {
        _scrollToIndex(widget.initialIndex);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    
    // Grid parameters
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = 16.0;
    final spacing = 8.0;
    final columns = 3;
    final itemWidth = (screenWidth - (padding * 2) - (spacing * (columns - 1))) / columns;
    final itemHeight = itemWidth; // square aspect ratio
    
    final row = index ~/ columns;
    final offset = row * (itemHeight + spacing);
    
    if (_scrollController.position.hasContentDimensions) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _openFullViewer(int index) {
    final List<ImageProvider> providers = [];
    for (final value in widget.images) {
      final bytes = bytesFromDataUri(value);
      if (bytes != null) {
        providers.add(MemoryImage(bytes));
      } else {
        providers.add(CachedNetworkImageProvider(value));
      }
    }
    if (providers.isEmpty) return;

    showImageViewerPager(
      context,
      MultiImageProvider(providers, initialIndex: index),
      swipeDismissible: true,
      doubleTapZoomable: true,
      onPageChanged: (page) {
        setState(() {
          _currentIndex = page;
        });
        _scrollToIndex(page);
      },
      onViewerDismissed: (page) {
        setState(() {
          _currentIndex = page;
        });
        _scrollToIndex(page);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Hình ảnh (${widget.images.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: widget.images.length,
          itemBuilder: (context, index) {
            final isCurrent = index == _currentIndex;
            return GestureDetector(
              onTap: () => _openFullViewer(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent ? colorScheme.primary : Colors.transparent,
                    width: 3.0,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GridImageWidget(url: widget.images[index]),
                      if (isCurrent)
                        Container(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GridImageWidget extends StatelessWidget {
  final String url;

  const _GridImageWidget({required this.url});

  @override
  Widget build(BuildContext context) {
    if (isDataUri(url)) {
      final bytes = bytesFromDataUri(url);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
          ),
        );
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[850]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[800]! : Colors.grey[100]!;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Container(color: Colors.white),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
      ),
    );
  }
}
