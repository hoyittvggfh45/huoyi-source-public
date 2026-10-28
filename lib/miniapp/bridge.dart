import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_build.dart';
import 'manifest.dart';
import 'permissions.dart';
import 'storage.dart';

class MiniAppHttpResponse {
  const MiniAppHttpResponse({
    required this.status,
    required this.bytes,
    this.headers = const {},
  });
  final int status;
  final List<int> bytes;
  final Map<String, String> headers;
}

typedef MiniAppFetch =
    Future<MiniAppHttpResponse> Function(
      Uri uri, {
      Map<String, String> headers,
      Duration? timeout,
    });

typedef MiniAppSourceList = Future<List<Map<String, Object?>>> Function();
typedef MiniAppSourceCall =
    Future<Map<String, Object?>> Function(Map<String, Object?> params);
typedef MiniAppPlayerOpen =
    Future<Map<String, Object?>> Function(Map<String, Object?> params);

abstract class MiniAppHost {
  Future<List<Map<String, Object?>>> sourceList() =>
      throw const MiniAppDenied('source is not available');
  Future<Map<String, Object?>> sourceHome(Map<String, Object?> params) =>
      throw const MiniAppDenied('source is not available');
  Future<Map<String, Object?>> sourceDetail(Map<String, Object?> params) =>
      throw const MiniAppDenied('source is not available');
  Future<Map<String, Object?>> sourceCategory(Map<String, Object?> params) =>
      throw const MiniAppDenied('source is not available');
  Future<Map<String, Object?>> sourceSearch(Map<String, Object?> params) =>
      throw const MiniAppDenied('source is not available');
  Future<Map<String, Object?>> sourcePlay(Map<String, Object?> params) =>
      throw const MiniAppDenied('source is not available');
  Future<Map<String, Object?>> playerOpen(Map<String, Object?> params) =>
      throw const MiniAppDenied('player is not available');
  void toast(String message) =>
      throw const MiniAppDenied('ui is not available');
  void showLoading(String message) =>
      throw const MiniAppDenied('ui is not available');
  void hideLoading() => throw const MiniAppDenied('ui is not available');
  Future<int> actionSheet(List<String> options) =>
      throw const MiniAppDenied('ui is not available');
  Future<Object?> navigateTo(String url) =>
      throw const MiniAppDenied('navigation is not available');
  Future<bool> navigateBack() =>
      throw const MiniAppDenied('navigation is not available');
}

class MiniAppBridge {
  MiniAppBridge({
    required this.manifest,
    required this.storage,
    this.fetch,
    this.onReply,
    this.onEmit,
    this.host,
  });

  final MiniAppManifest manifest;
  final MiniAppStorage storage;
  final MiniAppFetch? fetch;
  final void Function(int id, Object? result, String? error)? onReply;
  final void Function(String event, String dataJson)? onEmit;
  final MiniAppHost? host;

  MiniAppPermissions get permissions =>
      MiniAppPermissions(manifest.permissions.toSet());

  MiniAppHost _requireHost(String feature) {
    final host = this.host;
    if (host == null) {
      throw MiniAppDenied('$feature is not available');
    }
    return host;
  }

  Future<Object?> invoke(String api, Map<String, Object?> params) async {
    switch (api) {
      case 'storage.get':
        permissions.require(MiniAppPermissions.storage);
        final raw = await storage.get(_paramString(params, 'key'));
        if (raw == null) return null;
        try {
          return jsonDecode(raw);
        } on FormatException {
          return raw;
        }
      case 'storage.set':
        permissions.require(MiniAppPermissions.storage);
        await storage.set(
          _paramString(params, 'key'),
          jsonEncode(params['value']),
        );
        return true;
      case 'storage.remove':
        permissions.require(MiniAppPermissions.storage);
        await storage.remove(_paramString(params, 'key'));
        return true;
      case 'storage.getJSON':
        permissions.require(MiniAppPermissions.storage);
        final raw = await storage.get(_paramString(params, 'key'));
        if (raw == null) return params['fallback'];
        try {
          return jsonDecode(raw);
        } on FormatException {
          return params['fallback'];
        }
      case 'storage.setJSON':
        permissions.require(MiniAppPermissions.storage);
        await storage.set(
          _paramString(params, 'key'),
          jsonEncode(params['value']),
        );
        return true;
      case 'ui.toast':
        permissions.require(MiniAppPermissions.ui);
        _requireHost('ui').toast(_paramMessage(params));
        return true;
      case 'ui.loading':
        permissions.require(MiniAppPermissions.ui);
        _requireHost('ui').showLoading(_paramMessage(params));
        return true;
      case 'ui.hideLoading':
        permissions.require(MiniAppPermissions.ui);
        _requireHost('ui').hideLoading();
        return true;
      case 'ui.actionSheet':
        permissions.require(MiniAppPermissions.ui);
        final options = _paramStringList(params, 'items', 'options');
        return _requireHost('ui').actionSheet(options);
      case 'navigateTo':
        permissions.require(MiniAppPermissions.navigation);
        return _requireHost(
          'navigation',
        ).navigateTo(_paramString(params, 'url'));
      case 'navigateBack':
        permissions.require(MiniAppPermissions.navigation);
        return {'moved': await _requireHost('navigation').navigateBack()};
      case 'log':
        debugPrint('[miniapp] ${_paramMessage(params)}');
        return true;
      case 'version':
        return 4;
      case 'getSystemInfo':
      case 'env.getSystemInfo':
        return {
          'platform': Platform.operatingSystem,
          'appName': appName,
          'appSlug': appSlug,
          'appBuild': appBuild,
          'appId': manifest.id,
          'permissions': manifest.permissions,
          'version': 4,
          'sdkVersion': 4,
        };
      case 'source.list':
        permissions.require(MiniAppPermissions.source);
        return _requireHost('source').sourceList();
      case 'source.home':
        permissions.require(MiniAppPermissions.source);
        return _requireHost('source').sourceHome(params);
      case 'source.detail':
        permissions.require(MiniAppPermissions.source);
        return _requireHost('source').sourceDetail(params);
      case 'source.category':
        permissions.require(MiniAppPermissions.source);
        return _requireHost('source').sourceCategory(params);
      case 'source.search':
        permissions.require(MiniAppPermissions.source);
        return _requireHost('source').sourceSearch(params);
      case 'source.play':
        permissions.require(MiniAppPermissions.source);
        return _requireHost('source').sourcePlay(params);
      case 'player.open':
        permissions.require(MiniAppPermissions.player);
        return _requireHost('player').playerOpen(params);
      case 'serve':
        permissions.require(MiniAppPermissions.service);
        throw const MiniAppDenied('本版未提供：miniapp 服务运行时');
      case 'miniApp.onOpen':
      case 'miniApp.getLaunchOptions':
      case 'miniApp.exitMiniApp':
        permissions.require(MiniAppPermissions.miniapp);
        throw const MiniAppDenied('本版未提供：跨小程序运行时');
      case 'player.getState':
      case 'player.onStateChange':
      case 'player.onClose':
        permissions.require(MiniAppPermissions.player);
        throw const MiniAppDenied('本版未提供：播放器状态事件');
      case 'clipboard.get':
      case 'clipboard.set':
        throw const MiniAppDenied('本版未提供：剪贴板');
      case 'requestBytes':
        permissions.require(MiniAppPermissions.network);
        throw const MiniAppDenied('本版未提供：字节请求');
      case 'bytesToBase64':
      case 'base64ToBytes':
        throw const MiniAppDenied('本版未提供：字节请求');
      case 'request':
        permissions.require(MiniAppPermissions.network);
        final method = params['method'];
        if (method != null && method != 'GET') {
          throw const MiniAppDenied('request only supports GET in v1');
        }
        final responseType = params['responseType'];
        if (responseType != null &&
            responseType != 'text' &&
            responseType != 'json' &&
            responseType != 'bytes' &&
            responseType != 'base64') {
          throw ArgumentError('unknown request responseType: $responseType');
        }
        final url = _paramString(params, 'url');
        final response = await _fetchRaw(
          url,
          headers: _requestHeaders(params['headers']),
          timeout: _requestTimeout(params['timeout']),
        );
        final type = responseType?.toString() ?? 'text';
        final text = utf8.decode(response.bytes, allowMalformed: true);
        final Object? data;
        if (type == 'json') {
          data = jsonDecode(text);
        } else if (type == 'bytes' || type == 'base64') {
          data = base64Encode(response.bytes);
        } else {
          data = text;
        }
        return {
          'statusCode': response.status,
          'headers': response.headers,
          'data': data,
          'responseType': type,
          'url': url,
          'byteLength': response.bytes.length,
        };
      case 'network.text':
      case 'network.bytes':
      case 'network.json':
        return _fetchUrl(_paramString(params, 'url'), api);
      default:
        if (api.startsWith('miniApp.')) {
          permissions.require(MiniAppPermissions.miniapp);
          throw const MiniAppDenied('本版未提供：跨小程序运行时');
        }
        if (api.startsWith('player.') || api.startsWith('source.')) {
          throw MiniAppDenied('本版未提供：$api');
        }
        throw ArgumentError('unknown miniapp api: $api');
    }
  }

  void emit(String event, Object? data) {
    onEmit?.call(event, jsonEncode(data));
  }

  Future<void> handleMessage(String message) async {
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, Object?>) return;
    if (decoded['type'] != 'invoke') return;
    final id = decoded['id'];
    final api = decoded['api'];
    if (id is! int || api is! String) return;
    final params = decoded['params'];
    try {
      final Map<String, Object?> normalized;
      if (params is String && api == 'source.home') {
        normalized = {'siteKey': params};
      } else if (params is Map<String, Object?>) {
        normalized = params;
      } else {
        normalized = const <String, Object?>{};
      }
      final result = await invoke(api, normalized);
      onReply?.call(id, result, null);
    } catch (error) {
      onReply?.call(id, null, error.toString());
    }
  }

  static String _paramString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('miniapp param $key must be a non-empty string');
    }
    return value;
  }

  static String _paramMessage(Map<String, Object?> params) {
    for (final key in ['message', 'text', 'content']) {
      final value = params[key];
      if (value is String) return value;
      if (value != null) return value.toString();
    }
    return '';
  }

  static List<String> _paramStringList(
    Map<String, Object?> params,
    String first,
    String second,
  ) {
    final value = params[first] ?? params[second];
    if (value is! List) {
      throw ArgumentError('miniapp param $first must be an array');
    }
    return [for (final item in value) item.toString()];
  }

  Future<Object?> _fetchUrl(String raw, String api) async {
    final response = await _fetchRaw(raw);
    if (api == 'network.bytes') {
      return base64Encode(response.bytes);
    }
    final text = utf8.decode(response.bytes, allowMalformed: true);
    if (api == 'network.json') {
      return jsonDecode(text);
    }
    return text;
  }

  Future<MiniAppHttpResponse> _fetchRaw(
    String raw, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    permissions.require(MiniAppPermissions.network);
    final scheme = Uri.tryParse(raw)?.scheme.toLowerCase();
    if (scheme == 'miniapp') {
      throw const MiniAppDenied('本版未提供：miniapp 服务运行时');
    }
    final uri = _allowedUri(raw);
    final fetch = this.fetch;
    if (fetch == null) {
      throw const MiniAppDenied('network fetch is not available');
    }
    return fetch(uri, headers: headers, timeout: timeout);
  }

  static Map<String, String> _requestHeaders(Object? raw) {
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    raw.forEach((key, value) {
      final name = key.toString().toLowerCase();
      if (name == 'host' || name == 'content-length' || name == 'connection') {
        return;
      }
      headers[key.toString()] = value.toString();
    });
    return headers;
  }

  static Duration? _requestTimeout(Object? raw) {
    final millis = raw is int
        ? raw
        : raw is String
        ? int.tryParse(raw)
        : null;
    if (millis == null || millis <= 0) return null;
    return Duration(milliseconds: millis > 30000 ? 30000 : millis);
  }

  Uri _allowedUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw MiniAppDenied('url is not an http(s) address: $raw');
    }
    if (manifest.networkAllowlist.isEmpty) return uri;
    final host = uri.host.toLowerCase();
    if (!manifest.networkAllowlist.contains(host)) {
      throw MiniAppDenied('host is not in the network allowlist: $host');
    }
    return uri;
  }

  static const injectionScript = '''
(function(){
  if (window.ant) return;
  var seq = 0;
  var pending = {};
  var listeners = {};
  var lastEmit = {};
  function post(obj){ JhMiniapp.postMessage(JSON.stringify(obj)); }
  function deliver(event, data){
    var arr = (listeners[event] || []).slice();
    listeners[event] = (listeners[event] || []).filter(function(l){ return !l.once; });
    arr.forEach(function(l){ try{ l.cb(data); }catch(e){} });
  }
  var core = {
    invoke: function(api, params){
      return new Promise(function(resolve, reject){
        var id = ++seq;
        pending[id] = {resolve: resolve, reject: reject};
        post({type: 'invoke', id: id, api: api, params: params || {}});
      });
    },
    on: function(event, cb){
      (listeners[event] = listeners[event] || []).push({cb: cb, once: false});
      if (event in lastEmit) { try{ cb(lastEmit[event]); }catch(e){} }
    },
    once: function(event, cb){
      if (event in lastEmit) { try{ cb(lastEmit[event]); }catch(e){} return; }
      (listeners[event] = listeners[event] || []).push({cb: cb, once: true});
    },
    off: function(event, cb){
      if (!listeners[event]) return;
      if (!cb) { listeners[event] = []; return; }
      listeners[event] = listeners[event].filter(function(l){ return l.cb !== cb; });
    },
    _resolve: function(id, result){
      var p = pending[id];
      if (p) { delete pending[id]; p.resolve(result); }
    },
    _reject: function(id, error){
      var p = pending[id];
      if (p) { delete pending[id]; p.reject(new Error(error)); }
    },
    _emit: function(event, data){
      lastEmit[event] = data;
      deliver(event, data);
    }
  };
  window.ant = core;
  window.jhminiapp = core;
  window.ant.request = function(params){
    return window.ant.invoke('request', params || {});
  };
  window.ant.storage = {
    get: function(key){ return window.ant.invoke('storage.get', {key: key}); },
    set: function(key, value){ return window.ant.invoke('storage.set', {key: key, value: value}); },
    remove: function(key){ return window.ant.invoke('storage.remove', {key: key}); },
    getJSON: function(key, fallback){ return window.ant.invoke('storage.getJSON', {key: key, fallback: fallback}); },
    setJSON: function(key, value){ return window.ant.invoke('storage.setJSON', {key: key, value: value}); }
  };
  window.ant.getSystemInfo = function(){
    return window.ant.invoke('getSystemInfo', {});
  };
  window.ant.env = {
    getSystemInfo: function(){ return window.ant.invoke('env.getSystemInfo', {}); }
  };
  window.ant.tv = {
    onKey: function(cb){ window.ant.on('tv.key', cb); }
  };
  window.ant.ui = {
    toast: function(message){ return window.ant.invoke('ui.toast', {message: message}); },
    loading: function(message){ return window.ant.invoke('ui.loading', {message: message}); },
    hideLoading: function(){ return window.ant.invoke('ui.hideLoading', {}); },
    actionSheet: function(items){ return window.ant.invoke('ui.actionSheet', {items: items}); }
  };
  window.ant.navigateTo = function(url){ return window.ant.invoke('navigateTo', {url: url}); };
  window.ant.navigateBack = function(){ return window.ant.invoke('navigateBack', {}); };
  window.ant.log = function(message){ return window.ant.invoke('log', {message: message}); };
  window.ant.version = 4;
  window.ant.onShow = function(cb){ return window.ant.on('show', cb); };
  window.ant.onHide = function(cb){ return window.ant.on('hide', cb); };
  window.ant.serve = function(){ return window.ant.invoke('serve', {}); };
  window.ant.miniApp = {
    onOpen: function(){ return window.ant.invoke('miniApp.onOpen', {}); },
    getLaunchOptions: function(){ return window.ant.invoke('miniApp.getLaunchOptions', {}); },
    exitMiniApp: function(){ return window.ant.invoke('miniApp.exitMiniApp', {}); }
  };
  window.ant.player = {
    open: function(options){ return window.ant.invoke('player.open', options || {}); },
    getState: function(){ return window.ant.invoke('player.getState', {}); },
    onStateChange: function(cb){ return window.ant.on('player.stateChange', cb); },
    onClose: function(cb){ return window.ant.on('player.close', cb); }
  };
  window.ant.source = {
    list: function(){ return window.ant.invoke('source.list', {}); },
    home: function(params){ if (typeof params === 'string') params = {siteKey: params}; return window.ant.invoke('source.home', params || {}); },
    detail: function(params){ return window.ant.invoke('source.detail', params || {}); },
    category: function(params){ return window.ant.invoke('source.category', params || {}); },
    search: function(params){ return window.ant.invoke('source.search', params || {}); },
    play: function(params){ return window.ant.invoke('source.play', params || {}); }
  };
  window.ant.clipboard = {
    get: function(){ return window.ant.invoke('clipboard.get', {}); },
    set: function(text){ return window.ant.invoke('clipboard.set', {text: text}); }
  };
  window.ant.requestBytes = function(params){ return window.ant.invoke('requestBytes', params || {}); };
})();
''';
}
