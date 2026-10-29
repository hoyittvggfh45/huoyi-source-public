import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_drawer.dart';
import '../content_models.dart';
import '../content_zone_binding.dart';
import '../content_zone_screen.dart';
import '../core_bridge.dart';
import '../home_screen.dart';
import '../legado_screen.dart';
import '../local_store.dart';
import '../midnight_zone.dart';
import 'kotv_page.dart';
import 'kotv_settings_screen.dart';
import 'kotv_shell_controller.dart';
import 'kotv_theme.dart';

class KotvShellScreen extends ConsumerStatefulWidget {
  const KotvShellScreen({
    super.key,
    required this.repository,
    required this.store,
    this.midnightActivated = false,
  });

  final AppRepository repository;
  final LocalStore store;
  final bool midnightActivated;

  @override
  ConsumerState<KotvShellScreen> createState() => _KotvShellScreenState();
}

class _KotvShellScreenState extends ConsumerState<KotvShellScreen> {
  final _dramaZoneSync = ValueNotifier<HomeZone>(HomeZone.drama);
  final _vodZoneSync = ValueNotifier<HomeZone>(HomeZone.vod);
  final _midnightZoneSync = ValueNotifier<HomeZone>(HomeZone.midnight);
  final _liveZoneSync = ValueNotifier<HomeZone>(HomeZone.live);
  final _comicBinding = ContentZoneBinding();
  final _audioBinding = ContentZoneBinding();

  List<KotvPage> _pagesFor(bool midnightActivated) => [
    KotvPage.drama,
    KotvPage.vod,
    if (midnightActivated) KotvPage.midnight,
    KotvPage.live,
    KotvPage.novel,
    KotvPage.comic,
    KotvPage.audio,
    KotvPage.settings,
  ];

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(kotvShellControllerProvider.notifier);
    notifier.setMidnightActivated(widget.midnightActivated);
    if (!_pagesFor(
      widget.midnightActivated,
    ).contains(ref.read(kotvShellControllerProvider))) {
      notifier.select(KotvPage.vod);
    }
  }

  @override
  void didUpdateWidget(covariant KotvShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    ref.read(kotvShellControllerProvider.notifier).setMidnightActivated(
      widget.midnightActivated,
    );
  }

  @override
  void dispose() {
    _dramaZoneSync.dispose();
    _vodZoneSync.dispose();
    _midnightZoneSync.dispose();
    _liveZoneSync.dispose();
    super.dispose();
  }

  void _onSelect(KotvPage page) {
    ref.read(kotvShellControllerProvider.notifier).select(page);
    final zone = page.zone;
    if (zone == null) return;
    switch (zone) {
      case HomeZone.drama:
        _dramaZoneSync.value = zone;
      case HomeZone.vod:
        _vodZoneSync.value = zone;
      case HomeZone.midnight:
        _midnightZoneSync.value = zone;
      case HomeZone.live:
        _liveZoneSync.value = zone;
      default:
        break;
    }
  }

  void _hideMidnight() {
    unawaited(_hideMidnightAsync());
  }

  Future<void> _hideMidnightAsync() async {
    await saveMidnightActivated(false);
    if (!mounted) return;
    final notifier = ref.read(kotvShellControllerProvider.notifier);
    notifier.setMidnightActivated(false);
    notifier.select(KotvPage.vod);
  }

  Widget _pageBody(KotvPage page) {
    if (page == KotvPage.drama) {
      return HomeScreen(
        repository: widget.repository,
        store: widget.store,
        bare: true,
        zoneSync: _dramaZoneSync,
      );
    }
    if (page == KotvPage.vod) {
      return HomeScreen(
        repository: widget.repository,
        store: widget.store,
        bare: true,
        zoneSync: _vodZoneSync,
      );
    }
    if (page == KotvPage.midnight) {
      return HomeScreen(
        repository: widget.repository,
        store: widget.store,
        bare: true,
        zoneSync: _midnightZoneSync,
      );
    }
    if (page == KotvPage.live) {
      return HomeScreen(
        repository: widget.repository,
        store: widget.store,
        bare: true,
        zoneSync: _liveZoneSync,
      );
    }
    if (page == KotvPage.novel) {
      return LegadoScreen(repository: widget.repository);
    }
    if (page == KotvPage.comic) {
      return ContentZoneScreen(
        section: ContentSection.comic,
        binding: _comicBinding,
      );
    }
    if (page == KotvPage.audio) {
      return ContentZoneScreen(
        section: ContentSection.audio,
        binding: _audioBinding,
      );
    }
    return KotvSettingsScreen(
      repository: widget.repository,
      store: widget.store,
      onHideMidnight: _hideMidnight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(kotvShellControllerProvider);
    final controllerMidnightActivated = ref
        .read(kotvShellControllerProvider.notifier)
        .midnightActivated;
    final midnightActivated =
        widget.midnightActivated && controllerMidnightActivated;
    final pages = _pagesFor(midnightActivated);
    final effectiveCurrent = pages.contains(current)
        ? current
        : KotvPage.vod;
    final currentIndex = pages.indexOf(effectiveCurrent);
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: [
          for (int i = 0; i < pages.length; i++)
            (i - currentIndex).abs() <= 1
                ? _pageBody(pages[i])
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: KotvBottomBar(
        pages: pages,
        current: effectiveCurrent,
        onSelect: _onSelect,
      ),
    );
  }
}
