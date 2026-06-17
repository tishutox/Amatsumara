import 'dart:async';

import 'package:lumii_quest/core/responsive/breakpoints.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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

  @override
  void initState() {
    super.initState();
    _startBannerTimer();
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
    final isMobile = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    if (isMobile) {
      return _MobileDiscoverContent(
        bannerPaths: _bannerPaths,
        pageController: _pageController,
        currentBannerIndex: _currentBannerIndex,
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
    required this.onPageChanged,
    required this.onManualSlide,
  });

  final List<String> bannerPaths;
  final PageController pageController;
  final int currentBannerIndex;
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
          onPageChanged: onPageChanged,
          onManualSlide: onManualSlide,
          maxWidth: double.infinity,
          borderRadius: 22,
          margin: EdgeInsets.zero,
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _ComingSoonCard(
            title: 'Discover Content Coming Soon',
            description:
                'This area is prepared as a placeholder. The final Discover content will be added next.',
          ),
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
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
    required this.onPageChanged,
    required this.onManualSlide,
  });

  final List<String> bannerPaths;
  final PageController pageController;
  final int currentBannerIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onManualSlide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isExpanded = constraints.maxWidth >= Breakpoints.expanded;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isExpanded ? 1220 : 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BannerCarouselWidget(
                    bannerPaths: bannerPaths,
                    pageController: pageController,
                    currentBannerIndex: currentBannerIndex,
                    onPageChanged: onPageChanged,
                    onManualSlide: onManualSlide,
                    maxWidth: isExpanded ? 1160 : 920,
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
    required this.onPageChanged,
    required this.onManualSlide,
    required this.maxWidth,
    required this.borderRadius,
    required this.margin,
  });

  final List<String> bannerPaths;
  final PageController pageController;
  final int currentBannerIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onManualSlide;
  final double maxWidth;
  final double borderRadius;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bannerWidth = maxWidth == double.infinity
        ? width - margin.horizontal
        : maxWidth.clamp(0, width - margin.horizontal);
    final bannerHeight = bannerWidth * (500 / 1500);

    return Container(
      margin: margin,
      child: Column(
        children: [
          Container(
            height: bannerHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
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
                    fit: BoxFit.cover,
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
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.28),
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
