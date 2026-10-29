import 'dart:convert';
import 'dart:io';

/// MiniApp local service skeleton: page driving is pending a later batch.
class MiniAppLocalService {
  MiniAppLocalService._(this._server);

  static MiniAppLocalService? _current;

  static MiniAppLocalService? get current => _current;

  static Future<MiniAppLocalService> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final service = MiniAppLocalService._(server);
    _current = service;
    server.listen(service._handle);
    return service;
  }

  final HttpServer _server;

  int get port => _server.port;

  Future<void> close() async {
    if (identical(_current, this)) {
      _current = null;
    }
    await _server.close(force: true);
  }

  /// Substitutes a parse template in order: the first %s takes the service
  /// addresses joined with ';', the second %s takes the target url.
  static String substituteParseTemplate(
    String template,
    List<String> services,
    String targetUrl,
  ) {
    final withServices = template.replaceFirst('%s', services.join(';'));
    return withServices.replaceFirst('%s', targetUrl);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/parse') {
        final servicesParam = request.uri.queryParameters['services'] ?? '';
        final services = servicesParam.isEmpty
            ? <String>[]
            : servicesParam.split(';');
        final targetUrl = request.uri.queryParameters['url'] ?? '';
        final body = substituteParseTemplate(
          _parseTemplate,
          services,
          targetUrl,
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(body);
      } else if (path == '/action' ||
          path == '/manage' ||
          path.startsWith('/manage/') ||
          path == '/upload' ||
          path.startsWith('/file')) {
        request.response
          ..statusCode = HttpStatus.notImplemented
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'not implemented',
          }));
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'not found',
          }));
      }
    } catch (_) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'not implemented',
        }));
    } finally {
      await request.response.close();
    }
  }
}

const String _parseTemplate =
    '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
    '<body><div id="frames"></div><script>(function(){'
    'var services="%s".split(";");'
    'var target="%s";'
    'var root=document.getElementById("frames");'
    'services.forEach(function(service){'
    'if(!service){return;}'
    'var frame=document.createElement("iframe");'
    'frame.setAttribute("sandbox","allow-scripts");'
    'frame.setAttribute("src",service);'
    'frame.setAttribute("data-target",target);'
    'root.appendChild(frame);'
    '});})();</script></body></html>';
