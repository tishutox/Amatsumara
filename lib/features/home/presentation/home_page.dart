import 'dart:async';

import 'package:lumii_quest/core/responsive/breakpoints.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.navIconColor,
  });

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

  final PageController _pageController = PageController();
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
    final ratios = <double>[];
    for (final path in _bannerPaths) {
      ratios.add(await _readAssetAspectRatio(path));
    }
    if (!mounted) {
      return;
    }
    setState(() => _bannerAspectRatios = ratios);
  }

  Future<double> _readAssetAspectRatio(String assetPath) async {
    final completer = Completer<ImageInfo>();
    final image = AssetImage(assetPath);
    final stream = image.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(info);
        }
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    try {
      final info = await completer.future.timeout(const Duration(seconds: 2));
      return info.image.width / info.image.height;
    } catch (_) {
      return 3.0;
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_pageController.hasClients) {
        return;
      }

      final nextIndex = (_currentBannerIndex + 1) % _bannerPaths.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentAspectRatio =
        (_bannerAspectRatios != null && _bannerAspectRatios!.length == _bannerPaths.length)
            ? _bannerAspectRatios![_currentBannerIndex.clamp(0, _bannerPaths.length - 1)]
            : 3.0;

    final isMobile = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    if (isMobile) {
      return _MobileDiscoverContent(
        bannerPaths: _bannerPaths,
        pageController: _pageController,
        currentBannerIndex: _currentBannerIndex,
        bannerAspectRatio: currentAspectRatio,
        navIconColor: widget.navIconColor,
        onPageChanged: (index) {
          setState(() => _currentBannerIndex = index);
        },
        onManualSlide: _startBannerTimer,
      );
    }

    return _LargeDiscoverContent(
      bannerPaths: _bannerPaths,
      pageController: _pageController,
      currentBannerIndex: _currentBannerIndex,
      bannerAspectRatio: currentAspectRatio,
      navIconColor: widget.navIconColor,
      onPageChanged: (index) {
        setState(() => _currentBannerIndex = index);
      },
      onManualSlide: _startBannerTimer,
    );
  }
}

class _MobileDiscoverContent extends StatelessWidget {
  const _MobileDiscoverContent({
    required this.bannerPaths,
    required this.pageController,
    required this.currentBannerIndex,
    required this.bannerAspectRatio,
    required this.navIconColor,
    required this.onPageChanged,
    required this.onManualSlide,
  });

  final List<String> bannerPaths;
  final PageController pageController;
  final int currentBannerIndex;
  final double bannerAspectRatio;
  final Color navIconColor;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onManualSlide;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      children: [
        _BannerCarouselWidget(
          bannerPaths: bannerPaths,
          pageController: pageController,
          currentBannerIndex: currentBannerIndex,
          bannerAspectRatio: bannerAspectRatio,
          navIconColor: navIconColor,
          onPageChanged: onPageChanged,
          onManualSlide: onManualSlide,
          borderRadius: 22,
          margin: EdgeInsets.zero,
        ),
        const SizedBox(height: 18),
        const _ComingSoonCard(
          title: 'Discover Content Coming Soon',
          description:
              'This area is prepared as a placeholder. The final Discover content will be added next.',
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.only(bottom: 24),
          child: _ComingSoonCard(
            title: 'Additional Modules',
            description:
                'More Discover sections will appear below the banner here.',
          ),
        ),
      ],
    );
  }
}

class _LargeDiscoverContent extends StatelessWidget {
  const _LargeDiscoverContent({
    required this.bannerPaths,
    required this.pageController,
    required this.currentBannerIndex,
    required this.bannerAspectRatio,
    required this.navIconColor,
    required this.onPageChanged,
    required this.onManualSlide,
  });

  final List<String> bannerPaths;
  final PageController pageController;
  final int currentBannerIndex;
  final double bannerAspectRatio;
  final Color navIconColor;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onManualSlide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isExpanded = constraints.maxWidth >= Breakpoints.expanded;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BannerCarouselWidget(
                bannerPaths: bannerPaths,
                pageController: pageController,
                currentBannerIndex: currentBannerIndex,
                bannerAspectRatio: bannerAspectRatio,
                navIconColor: navIconColor,
                onPageChanged: onPageChanged,
                onManualSlide: onManualSlide,
                borderRadius: 28,
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
                    description: 'Reserved space for campaigns and highlights.',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BannerCarouselWidget extends StatelessWidget {
  const _BannerCarouselWidget({
    required this.bannerPaths,
    required this.pageController,
    required this.currentBannerIndex,
    required this.bannerAspectRatio,
    required this.navIconColor,
    required this.onPageChanged,
    required this.onManualSlide,
    required this.borderRadius,
    required this.margin,
  });

  final List<String> bannerPaths;
  final PageController pageController;
  final int currentBannerIndex;
  final double bannerAspectRatio;
  final Color navIconColor;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onManualSlide;
  final double borderRadius;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: bannerAspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: PageView.builder(
                controller: pageController,
                itemCount: bannerPaths.length,
                onPageChanged: (index) {
                  onPageChanged(index);
                  onManualSlide();
                },
                itemBuilder: (context, index) {
                  return Image.asset(
                    bannerPaths[index],
                    fit: BoxFit.contain,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(
              bannerPaths.length,
              (index) {
                final isActive = index == currentBannerIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? navIconColor
                        : navIconColor.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
