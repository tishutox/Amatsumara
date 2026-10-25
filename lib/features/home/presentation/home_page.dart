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

  final PageController _pageController = PageController(viewportFraction: 0.92);
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
    final bannerAspectRatio = _bannerAspectRatios?[_currentBannerIndex] ?? 3;
    final isMobile = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    if (isMobile) {
      return _MobileDiscoverContent(
        bannerPaths: _bannerPaths,
        pageController: _pageController,
        currentBannerIndex: _currentBannerIndex,
        bannerAspectRatio: bannerAspectRatio,
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
      bannerAspectRatio: bannerAspectRatio,
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
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: _BannerCarouselWidget(
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
          padding: ContentLayout.pagePadding,
          child: ContentLayout.widthBox(
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
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: AspectRatio(
              aspectRatio: bannerAspectRatio,
              child: AnimatedBuilder(
                animation: pageController,
                builder: (context, _) {
                  final page = pageController.hasClients
                      ? (pageController.page ?? 0.0)
                      : 0.0;
                  return PageView(
                    controller: pageController,
                    padEnds: false,
                    onPageChanged: (index) {
                      onPageChanged(index);
                      onManualSlide();
                    },
                    children: [
                      for (var index = 0; index < bannerPaths.length; index++)
                        _buildBanner(index, page),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(bannerPaths.length, (index) {
              final isActive = index == currentBannerIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? navIconColor
                      : navIconColor.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(int index, double page) {
    final distance = (page - index).abs().clamp(0.0, 1.0);
    final opacity = (1.0 - distance * 0.55).clamp(0.4, 1.0);
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.asset(
            bannerPaths[index],
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
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
