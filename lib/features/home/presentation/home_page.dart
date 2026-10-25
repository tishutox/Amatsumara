import 'dart:async';

import 'package:lumii_quest/core/responsive/breakpoints.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.navIconColor});

  final Color navIconColor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const List<String> _bannerPaths = [
    'banners/Albania.png',
    'banners/Romania.png',
    'banners/Switzerland.png',
  ];

  Timer? _bannerTimer;
  int _currentBannerIndex = 0;
  List<double>? _bannerAspectRatios;

  @override
  void initState() {
    super.initState();
    _loadBannerAspectRatios();
    _startBannerTimer();
  }

  Future<void> _loadBannerAspectRatios() async {
    final ratios = await Future.wait(_bannerPaths.map(_readAssetAspectRatio));
    if (!mounted) {
      return;
    }
    setState(() => _bannerAspectRatios = ratios);
  }

  Future<double> _readAssetAspectRatio(String assetPath) {
    final completer = Completer<double>();
    final stream = AssetImage(assetPath).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image.width / info.image.height);
        stream.removeListener(listener);
      },
      onError: (_, _) {
        completer.complete(3);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentBannerIndex = (_currentBannerIndex + 1) % _bannerPaths.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bannerAspectRatio = _bannerAspectRatios?[_currentBannerIndex] ?? 3;
    final isMobile = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    if (isMobile) {
      return _MobileDiscoverContent(
        bannerPaths: _bannerPaths,
        currentBannerIndex: _currentBannerIndex,
        bannerAspectRatio: bannerAspectRatio,
        navIconColor: widget.navIconColor,
      );
    }

    return _LargeDiscoverContent(
      bannerPaths: _bannerPaths,
      currentBannerIndex: _currentBannerIndex,
      bannerAspectRatio: bannerAspectRatio,
      navIconColor: widget.navIconColor,
    );
  }
}

class _MobileDiscoverContent extends StatelessWidget {
  const _MobileDiscoverContent({
    required this.bannerPaths,
    required this.currentBannerIndex,
    required this.bannerAspectRatio,
    required this.navIconColor,
  });

  final List<String> bannerPaths;
  final int currentBannerIndex;
  final double bannerAspectRatio;
  final Color navIconColor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: _BannerCarouselWidget(
            bannerPaths: bannerPaths,
            currentBannerIndex: currentBannerIndex,
            bannerAspectRatio: bannerAspectRatio,
            navIconColor: navIconColor,
            borderRadius: 14,
            margin: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 18),
        ContentLayout.widthBox(
          child: const _ComingSoonCard(
            title: 'Discover Content Coming Soon',
            description:
                'This area is prepared as a placeholder. The final Discover content will be added next.',
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: ContentLayout.widthBox(
            child: const _ComingSoonCard(
              title: 'Additional Modules',
              description:
                  'More Discover sections will appear below the banner here.',
            ),
          ),
        ),
      ],
    );
  }
}

class _LargeDiscoverContent extends StatelessWidget {
  const _LargeDiscoverContent({
    required this.bannerPaths,
    required this.currentBannerIndex,
    required this.bannerAspectRatio,
    required this.navIconColor,
  });

  final List<String> bannerPaths;
  final int currentBannerIndex;
  final double bannerAspectRatio;
  final Color navIconColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isExpanded = constraints.maxWidth >= Breakpoints.expanded;
        return SingleChildScrollView(
          padding: ContentLayout.pagePadding,
          child: ContentLayout.widthBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BannerCarouselWidget(
                  bannerPaths: bannerPaths,
                  currentBannerIndex: currentBannerIndex,
                  bannerAspectRatio: bannerAspectRatio,
                  navIconColor: navIconColor,
                  borderRadius: 16,
                  margin: const EdgeInsets.only(bottom: 22),
                ),
                const _ComingSoonCard(
                  title: 'Discover for Tablet/Desktop Is In Progress',
                  description:
                      'The mobile banner experience is already in place. This layout is a prepared area for the new Discover structure.',
                ),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: isExpanded ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: isExpanded ? 2.0 : 1.8,
                  children: const [
                    _ComingSoonCard(
                      title: 'Section A',
                      description: 'Reserved space for curated content.',
                    ),
                    _ComingSoonCard(
                      title: 'Section B',
                      description: 'Reserved space for recommendations.',
                    ),
                    _ComingSoonCard(
                      title: 'Section C',
                      description:
                          'Reserved space for campaigns and highlights.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BannerCarouselWidget extends StatelessWidget {
  const _BannerCarouselWidget({
    required this.bannerPaths,
    required this.currentBannerIndex,
    required this.bannerAspectRatio,
    required this.navIconColor,
    required this.borderRadius,
    required this.margin,
  });

  final List<String> bannerPaths;
  final int currentBannerIndex;
  final double bannerAspectRatio;
  final Color navIconColor;
  final double borderRadius;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < bannerPaths.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(borderRadius),
                    child: AspectRatio(
                      aspectRatio: bannerAspectRatio,
                      child: Image.asset(
                        bannerPaths[i],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < bannerPaths.length; i++)
                Transform.rotate(
                  angle: 0.7, // diagonal bar (bottom-left to top-right)
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: i == currentBannerIndex
                          ? navIconColor
                          : navIconColor.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
