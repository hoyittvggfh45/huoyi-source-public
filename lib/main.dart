import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core_bridge.dart';
import 'app_update.dart';
import 'app_layout.dart';
import 'app_orientation.dart';
import 'app_theme.dart';
import 'playback_foreground.dart';
import 'tv_theme.dart';
import 'home_screen.dart';
import 'hongguo_account.dart';
import 'local_store.dart';
import 'profiles_screen.dart';
import 'media_library.dart';
import 'package_smoke.dart';
import 'lan_controller.dart';
import 'player_picker.dart';
import 'proxy_kernel_service.dart';
import 'signature_check.dart';
import 'video_enhancement_assets.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(PlaybackForeground.clearStaleFlag());
  runApp(const BootSplash());
  await Future<void>.delayed(const Duration(seconds: 4));
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(AppTheme.systemBars(Brightness.dark));
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  MediaKit.ensureInitialized();
  VideoEnhancementAssets.registerLicenses();
  if (Platform.isWindows && arguments.firstOrNull == '--package-smoke') {
    await runPackageSmoke(arguments);
    return;
  }
  final device = await AppDevice.detect();
  runApp(AppBootstrap(device: device));
}

class BootSplash extends StatefulWidget {
  const BootSplash({super.key});

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _stage(Interval interval) => interval.transform(_controller.value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final iconOpacity = _stage(const Interval(0.0, 0.55));
        return Scaffold(
          backgroundColor: const Color(0xFF131619),
          body: Center(
            child: Opacity(
              opacity: iconOpacity,
              child: Image.asset(
                'assets/splash/hongyi_tv.png',
                width: 260,
                height: 260,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    ),
  );
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.device = const AppDevice()});
  final AppDevice device;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  final repository = NativeRepository();
  final navigator = GlobalKey<NavigatorState>();
  LocalStore? store;
  Object? error;
  late AppDevice device = widget.device;
  bool? _signatureOk;
  Timer? _hongguoRenewalTimer;

  @override
  void dispose() {
    _hongguoRenewalTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    LanController.current?.dispose();
    LanController.current = null;
    MediaLibrary.current?.dispose();
    MediaLibrary.current = null;
    store?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hongguoRenewalTimer = Timer.periodic(const Duration(minutes: 60), (_) {
      unawaited(repository.refreshHongguoDevice());
    });
    if (signatureCheckEnforced) {
      unawaited(_checkSignature());
    }
    _initialize();
  }

  Future<void> _checkSignature() async {
    final ok = await checkReleaseSignature();
    if (mounted) setState(() => _signatureOk = ok);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(repository.refreshHongguoDevice());
    }
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      unawaited(_refreshDevice());
    }
    if (!Platform.isIOS) return;
    final library = MediaLibrary.current;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (library != null) {
        library.suspended = true;
        unawaited(library.cancel());
      }
      unawaited(
        NativeRepository(
          background: true,
        ).controlDownloads('pauseAll').catchError((Object _) {}),
      );
    } else if (state == AppLifecycleState.resumed) {
      if (library != null) library.suspended = false;
    }
  }

  Future<void> _refreshDevice() async {
    final detected = await AppDevice.detect(fallback: device);
    if (!mounted ||
        (device.television == detected.television &&
            device.version == detected.version)) {
      return;
    }
    setState(() => device = detected);
  }

  Future<void> _initialize() async {
    setState(() {
      error = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      unawaited(ensureHongguoAccountLoaded());
      await _refreshDevice();
      await repository.initialize();
      unawaited(AppUpdateChecker.maybeCheckSilently());
      unawaited(ProxyKernelService.maybeAutostart());
      if (mounted) {
        setState(() {
          store = LocalStore(preferences);
          repository.access = store;
          MediaLibrary.attach(repository, store!);
          LanController.current?.dispose();
          final link = LanController(
            repository,
            store!,
            kind: device.television
                ? 'tv'
                : Platform.isWindows
                ? 'computer'
                : 'phone',
          );
          LanController.current = link;
          link.openPlayback = (request) async {
            final epoch = request.profileEpoch;
            if (request.cancelled ||
                !mounted ||
                store!.locked ||
                !link.receiving ||
                store!.profileEpoch != epoch ||
                !store!.allowsSource(request.detail.drama.source)) {
              throw StateError('当前用户不能接收播放');
            }
            await link.playbackHost?.stop();
            if (request.cancelled ||
                !mounted ||
                store!.locked ||
                store!.profileEpoch != epoch ||
                !link.receiving) {
              throw StateError('播放接收已取消');
            }
            final navigation = navigator.currentState;
            if (navigation == null) throw StateError('接收设备界面尚未就绪');
            unawaited(
              navigation.pushAndRemoveUntil<void>(
                buildPlayerRoute<void>(
                  navigation.context,
                  detail: request.detail,
                  initialIndex: request.index,
                  initialPosition: request.position,
                  repository: repository,
                  store: store!,
                  handoff: request,
                ),
                (route) => route.isFirst,
              ),
            );
          };
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (signatureCheckEnforced && _signatureOk == false) {
      return MaterialApp(
        theme: AppTheme.platformLight,
        home: const TamperScreen(),
      );
    }
    return DuanjuApp(
      repository: repository,
      store: store,
      bootstrapError: error?.toString(),
      onRetry: _initialize,
      television: device.television,
      version: device.version,
      navigatorKey: navigator,
    );
  }
}

class DuanjuApp extends StatelessWidget {
  const DuanjuApp({
    super.key,
    required this.repository,
    this.store,
    this.bootstrapError,
    this.onRetry,
    this.television = false,
    this.version = appVersion,
    this.navigatorKey,
  });
  final AppRepository repository;
  final LocalStore? store;
  final String? bootstrapError;
  final VoidCallback? onRetry;
  final bool television;
  final String version;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([store]),
    builder: (_, _) => _application(),
  );

  Widget _application() => MaterialApp(
    navigatorKey: navigatorKey,
    title: appName,
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.platformLight,
    darkTheme: AppTheme.platformDark,
    themeMode: AppTheme.mode(store?.themeMode ?? 'system'),
    builder: (context, child) {
      final mode = store?.displayMode ?? 'auto';
      final tv = mode == 'television' || mode == 'auto' && television;
      final theme = Theme.of(context);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(theme.brightness),
        child: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: AppOrientationScope(
            television: tv,
            child: AppLayout(
              television: tv,
              version: version,
              child: Theme(
                data: tv
                    ? televisionTheme(
                        theme.brightness == Brightness.dark
                            ? AppTheme.dark
                            : AppTheme.light,
                      )
                    : theme,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(
                      LogicalKeyboardKey.select,
                      includeRepeats: false,
                    ): ActivateIntent(),
                    SingleActivator(
                      LogicalKeyboardKey.gameButtonA,
                      includeRepeats: false,
                    ): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
                  },
                  child: FocusTraversalGroup(child: child!),
                ),
              ),
            ),
          ),
        ),
      );
    },
    home: store != null
        ? store!.locked
              ? ProfilesScreen(store: store!, locked: true)
              : HomeScreen(
                  key: ValueKey(
                    'profile-${store!.profile.id}-${store!.profileEpoch}',
                  ),
                  repository: repository,
                  store: store!,
                )
        : Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Color(0xFFFF765F),
                      size: 72,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      bootstrapError ?? '正在打开$appName',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 24),
                    if (bootstrapError == null)
                      const CircularProgressIndicator.adaptive()
                    else
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('重新打开'),
                      ),
                  ],
                ),
              ),
            ),
          ),
  );
}
