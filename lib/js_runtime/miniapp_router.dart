import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'miniapp_local_service.dart';

class MiniAppPageKind {
  const MiniAppPageKind._(this.name);

  final String name;

  static const MiniAppPageKind index = MiniAppPageKind._('index');
  static const MiniAppPageKind manage = MiniAppPageKind._('manage');
  static const MiniAppPageKind parse = MiniAppPageKind._('parse');

  static const List<MiniAppPageKind> values = <MiniAppPageKind>[
    index,
    manage,
    parse,
  ];
}

class MiniAppRoute {
  const MiniAppRoute({
    required this.kind,
    required this.miniAppId,
    this.title,
    this.initialPath,
    this.initialUrl,
  });

  final MiniAppPageKind kind;
  final String miniAppId;
  final String? title;
  final String? initialPath;
  final String? initialUrl;

  String get name => '/miniapp/${kind.name}/$miniAppId';

  static MiniAppRoute? tryParse(String? name, {Object? arguments}) {
    if (name == null) return null;
    final uri = Uri.tryParse(name);
    if (uri == null) return null;
    if (uri.pathSegments.length != 3) return null;
    if (uri.pathSegments[0] != 'miniapp') return null;
    final kind = MiniAppPageKind.values.where(
      (value) => value.name == uri.pathSegments[1],
    );
    if (kind.isEmpty) return null;
    final miniAppId = uri.pathSegments[2];
    if (miniAppId.isEmpty ||
        miniAppId.contains('..') ||
        miniAppId.contains('/')) {
      return null;
    }
    String? initialUrl;
    String? initialPath;
    if (arguments is MiniAppRoute) {
      initialUrl = arguments.initialUrl;
      initialPath = arguments.initialPath;
    }
    initialPath ??= uri.queryParameters['path'];
    initialUrl ??= uri.queryParameters['url'];
    return MiniAppRoute(
      kind: kind.first,
      miniAppId: miniAppId,
      initialPath: initialPath,
      initialUrl: initialUrl,
    );
  }
}

class MiniAppRouter {
  static const Map<MiniAppPageKind, String> routeNames = {
    MiniAppPageKind.index: '/miniapp/index',
    MiniAppPageKind.manage: '/miniapp/manage',
    MiniAppPageKind.parse: '/miniapp/parse',
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final route = MiniAppRoute.tryParse(
      settings.name,
      arguments: settings.arguments,
    );
    if (route == null) return null;
    return MaterialPageRoute<void>(
      builder: (_) => MiniAppPageShell(route: route),
      settings: settings,
    );
  }

  static Future<void> push(BuildContext context, MiniAppRoute route) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiniAppPageShell(route: route),
        settings: RouteSettings(name: route.name, arguments: route),
      ),
    );
  }

  static Future<void> pushNamed(BuildContext context, MiniAppRoute route) {
    return Navigator.of(context).pushNamed(route.name, arguments: route);
  }
}

class MiniAppPageShell extends StatelessWidget {
  const MiniAppPageShell({super.key, required this.route});

  final MiniAppRoute route;

  String get _title =>
      route.title ?? '${route.kind.name} · ${route.miniAppId}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: MiniAppWebPage(route: route),
    );
  }
}

class MiniAppWebPage extends StatefulWidget {
  const MiniAppWebPage({super.key, required this.route});

  final MiniAppRoute route;

  @override
  State<MiniAppWebPage> createState() => _MiniAppWebPageState();
}

class _MiniAppWebPageState extends State<MiniAppWebPage> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.route.kind == MiniAppPageKind.parse) {
      final service = MiniAppLocalService.current;
      if (service != null) {
        final parseUri = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: service.port,
          path: '/parse',
          queryParameters: <String, String>{
            'url': widget.route.initialUrl ?? '',
            'services': '',
          },
        );
        _controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(parseUri);
      }
      return;
    }
    final initialUrl = widget.route.initialUrl;
    if (initialUrl != null && initialUrl.isNotEmpty) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(initialUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return WebViewWidget(controller: controller);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('小程序页面尚未接线：${widget.route.kind.name}'),
            const SizedBox(height: 8),
            Text('miniAppId：${widget.route.miniAppId}'),
            const SizedBox(height: 8),
            const Text('小程序执行接线等 P1 落地后再做，本页只提供路由与页面壳。'),
          ],
        ),
      ),
    );
  }
}
