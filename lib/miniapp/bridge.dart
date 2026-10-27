import 'dart:convert';
import 'dart:io';

import '../app_build.dart';
import 'manifest.dart';
import 'permissions.dart';
import 'storage.dart';

class MiniAppHttpResponse {
  const MiniAppHttpResponse({required this.status, required this.bytes});
  final int status;
  final List<int> bytes;
}

typedef MiniAppFetch = Future<MiniAppHttpResponse> Function(Uri uri);

class MiniAppBridge {
  MiniAppBridge({
    required this.manifest,
    required this.storage,
    this.fetch,
    this.onReply,
    this.onEmit,
  });

  final MiniAppManifest manifest;
  final MiniAppStorage storage;
  final MiniAppFetch? fetch;
  final void Function(int id, Object? result, String? error)? onReply;
  final void Function(String event, String dataJson)? onEmit;

  MiniAppPermissions get permissions =>
      MiniAppPermissions(manifest.permissions.toSet());

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
        return _fetchUrl(
          _paramString(params, 'url'),
          responseType == 'json'
              ? 'network.json'
              : responseType == 'bytes' || responseType == 'base64'
              ? 'network.bytes'
              : 'network.text',
        );
      case 'getSystemInfo':
        return {
          'platform': Platform.operatingSystem,
          'appName': appName,
          'appSlug': appSlug,
          'appBuild': appBuild,
        };
      case 'network.text':
      case 'network.bytes':
      case 'network.json':
        return _fetchUrl(_paramString(params, 'url'), api);
      default:
        if (api.startsWith('player.') || api.startsWith('source.')) {
          throw const MiniAppDenied(
            'player and source calls are not available in v1',
          );
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
      final result = await invoke(
        api,
        params is Map<String, Object?> ? params : const {},
      );
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

  Future<Object?> _fetchUrl(String raw, String api) async {
    permissions.require(MiniAppPermissions.network);
    final uri = _allowedUri(raw);
    final fetch = this.fetch;
    if (fetch == null) {
      throw const MiniAppDenied('network fetch is not available');
    }
    final response = await fetch(uri);
    if (api == 'network.bytes') {
      return base64Encode(response.bytes);
    }
    final text = utf8.decode(response.bytes, allowMalformed: true);
    if (api == 'network.json') {
      return jsonDecode(text);
    }
    return text;
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
  if (window.jhminiapp) return;
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
  window.jhminiapp = {
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
  window.jhminiapp.request = function(params){
    return window.jhminiapp.invoke('request', params || {});
  };
  window.jhminiapp.storage = {
    get: function(key){ return window.jhminiapp.invoke('storage.get', {key: key}); },
    set: function(key, value){ return window.jhminiapp.invoke('storage.set', {key: key, value: value}); },
    remove: function(key){ return window.jhminiapp.invoke('storage.remove', {key: key}); }
  };
  window.jhminiapp.getSystemInfo = function(){
    return window.jhminiapp.invoke('getSystemInfo', {});
  };
  window.jhminiapp.tv = {
    onKey: function(cb){ window.jhminiapp.on('tv.key', cb); }
  };
})();
''';
}
