import 'dart:async';
import 'dart:io';

import 'builtin_py_sites.dart';
import 'core_bridge.dart';
import 'models.dart';
import 'tdlib_service.dart';

class TdlibShow {
  TdlibShow({
    required this.chatId,
    required this.chatTitle,
    required this.name,
    required this.episodes,
  });

  final int chatId;
  final String chatTitle;
  final String name;
  final List<TdlibVideoMessage> episodes;

  String get id => 'tdlib:$chatId:${Uri.encodeComponent(name)}';

  int get latestDate =>
      episodes.isEmpty ? 0 : episodes.map((e) => e.date).reduce((a, b) => a > b ? a : b);

  int get coverFileId {
    for (final episode in episodes) {
      if (episode.thumbFileId != 0) return episode.thumbFileId;
    }
    return 0;
  }
}

class TdlibFileServer {
  TdlibFileServer({TdlibService? service})
    : _service = service ?? TdlibService.instance;

  final TdlibService _service;
  HttpServer? _server;

  Future<void> ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    _server = server;
  }

  int get port => _server?.port ?? 0;

  String urlFor(int fileId) {
    if (_server == null || fileId == 0) return '';
    return 'http://127.0.0.1:${_server!.port}/file?fileId=$fileId';
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path != '/file') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final fileId = int.tryParse(request.uri.queryParameters['fileId'] ?? '');
      if (fileId == null || fileId == 0) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }
      final file = await _service.downloadFileAndWait(
        fileId,
        priority: 1,
        timeout: const Duration(seconds: 30),
      );
      final path = file.localPath;
      if (path.isEmpty) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final bytes = await File(path).readAsBytes();
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType('image', 'jpeg');
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}

class TdlibContent {
  TdlibContent({TdlibService? service, TdlibFileServer? fileServer})
    : _service = service ?? TdlibService.instance,
      _fileServer = fileServer ?? TdlibFileServer();

  static final TdlibContent _instance = TdlibContent();
  static TdlibContent get instance => _instance;

  static const pageSize = 30;
  static const maxScanMessages = 2000;

  final TdlibService _service;
  final TdlibFileServer _fileServer;
  final Map<String, List<TdlibShow>> _showsCache = {};

  void invalidate() {
    _showsCache.clear();
  }

  Future<List<CatalogCategory>> categories() async {
    final chats = await _service.chats(limit: 40);
    final items = <CatalogCategory>[CatalogCategory('', '全部')];
    for (final chat in chats) {
      if (!chat.isVideoChannel) continue;
      items.add(CatalogCategory(chat.id.toString(), chat.title));
    }
    return items;
  }

  Future<CatalogPage> catalog({
    required String category,
    required int page,
    String query = '',
    bool force = false,
  }) async {
    if (query.isNotEmpty) return search(query);
    if (force) _showsCache.remove(category);
    final shows = await _showsForCategory(category);
    final safePage = page < 1 ? 1 : page;
    final start = (safePage - 1) * pageSize;
    if (start >= shows.length) {
      return CatalogPage(const [], page: safePage, hasMore: false);
    }
    await _fileServer.ensureStarted();
    final slice = shows.skip(start).take(pageSize).toList();
    return CatalogPage(
      [for (final show in slice) _showToDrama(show)],
      page: safePage,
      hasMore: start + slice.length < shows.length,
    );
  }

  Future<CatalogPage> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return CatalogPage(const [], page: 1, hasMore: false);
    var messages = await _service.searchMessages(query: trimmed);
    final chatTitles = <int, String>{};
    if (messages.isEmpty) {
      final chats = await _service.chats(limit: 40);
      for (final chat in chats) {
        if (!chat.isVideoChannel) continue;
        chatTitles[chat.id] = chat.title;
        final found = await _service.searchChatMessages(
          chatId: chat.id,
          query: trimmed,
        );
        messages = [...messages, ...found.messages];
      }
    } else {
      final chats = await _service.chats(limit: 40);
      for (final chat in chats) {
        chatTitles[chat.id] = chat.title;
      }
    }
    await _fileServer.ensureStarted();
    final shows = _groupShows(messages, chatTitles: chatTitles);
    return CatalogPage(
      [for (final show in shows) _showToDrama(show)],
      page: 1,
      hasMore: false,
    );
  }

  Future<DramaDetail> detail(Drama drama) async {
    final parsed = _parseShowId(
      drama.sourceId.isNotEmpty ? drama.sourceId : drama.id,
    );
    if (parsed == null) {
      return DramaDetail(drama, const [], warning: '该剧无法在 TDLib 里定位');
    }
    final shows = await _showsForCategory(parsed.$1.toString());
    TdlibShow? show;
    for (final candidate in shows) {
      if (candidate.name == parsed.$2) {
        show = candidate;
        break;
      }
    }
    if (show == null) {
      return DramaDetail(drama, const [], warning: '该剧已不在频道里');
    }
    await _fileServer.ensureStarted();
    final cover = _fileServer.urlFor(show.coverFileId);
    final detailDrama = Drama(
      id: drama.id,
      source: BuiltinPySites.tgdramaSiteId,
      sourceId: show.id,
      title: show.name,
      cover: cover.isNotEmpty ? cover : drama.cover,
      episodes: show.episodes.length,
      category: show.chatTitle,
    );
    final episodes = <Episode>[];
    for (var i = 0; i < show.episodes.length; i++) {
      final message = show.episodes[i];
      episodes.add(
        Episode({
          'id':
              'tgdrama:${message.chatId}:${message.messageId}:${message.fileId}',
          'title': '第${i + 1}集',
          'currentEpisode': i + 1,
          'flag': 'TG影视库',
        }, i + 1),
      );
    }
    return DramaDetail(detailDrama, episodes);
  }

  Future<PlaybackPlan> resolvePlan(String flag, String playId) async {
    final parsed = _parsePlayId(playId);
    if (parsed == null) {
      throw AppFailure('播放地址格式错误');
    }
    final file = await _service.downloadFileAndWait(parsed.$3);
    if (file.localPath.isEmpty) {
      throw AppFailure('该集拿不到文件');
    }
    return PlaybackPlan(url: file.localPath, local: true);
  }

  Future<List<TdlibShow>> _showsForCategory(String category) async {
    final cached = _showsCache[category];
    if (cached != null) return cached;
    final chats = await _service.chats(limit: 40);
    final targets = <TdlibChat>[];
    if (category.isEmpty) {
      targets.addAll(chats.where((chat) => chat.isVideoChannel));
    } else {
      final wanted = int.tryParse(category);
      for (final chat in chats) {
        if (chat.id == wanted) targets.add(chat);
      }
    }
    final messages = <TdlibVideoMessage>[];
    final chatTitles = <int, String>{};
    for (final chat in targets) {
      chatTitles[chat.id] = chat.title;
      messages.addAll(await _allChannelMessages(chat.id));
    }
    final shows = _groupShows(messages, chatTitles: chatTitles);
    _showsCache[category] = shows;
    return shows;
  }

  Future<List<TdlibVideoMessage>> _allChannelMessages(int chatId) async {
    final out = <TdlibVideoMessage>[];
    var fromMessageId = 0;
    while (out.length < maxScanMessages) {
      final page = await _service.chatHistory(
        chatId: chatId,
        fromMessageId: fromMessageId,
        limit: 100,
      );
      out.addAll(page.messages);
      if (page.nextFromMessageId == 0 || page.messages.isEmpty) break;
      fromMessageId = page.nextFromMessageId;
    }
    return out;
  }

  List<TdlibShow> _groupShows(
    List<TdlibVideoMessage> messages, {
    Map<int, String> chatTitles = const {},
  }) {
    final byKey = <String, List<TdlibVideoMessage>>{};
    final titles = <String, String>{};
    for (final message in messages) {
      final name = _showNameOf(message);
      final key = '${message.chatId}|$name';
      (byKey[key] ??= []).add(message);
      titles[key] = name;
    }
    final shows = <TdlibShow>[];
    for (final entry in byKey.entries) {
      final episodes = _sortEpisodes(entry.value);
      final cover = episodes.any((e) => e.thumbFileId != 0);
      if (episodes.length == 1 && !cover) continue;
      final parts = entry.key.split('|');
      final chatId = int.tryParse(parts.first) ?? 0;
      shows.add(
        TdlibShow(
          chatId: chatId,
          chatTitle: chatTitles[chatId] ?? '',
          name: titles[entry.key] ?? '',
          episodes: episodes,
        ),
      );
    }
    shows.sort((a, b) => b.latestDate.compareTo(a.latestDate));
    return shows;
  }

  List<TdlibVideoMessage> _sortEpisodes(List<TdlibVideoMessage> messages) {
    final numbered = <({TdlibVideoMessage message, int number})>[];
    for (var i = 0; i < messages.length; i++) {
      numbered.add((
        message: messages[i],
        number: _episodeNumberOf(messages[i], i + 1),
      ));
    }
    numbered.sort((a, b) {
      final byNumber = a.number.compareTo(b.number);
      if (byNumber != 0) return byNumber;
      return a.message.date.compareTo(b.message.date);
    });
    return [for (final row in numbered) row.message];
  }

  Drama _showToDrama(TdlibShow show) {
    return Drama(
      id: show.id,
      source: BuiltinPySites.tgdramaSiteId,
      sourceId: show.id,
      title: show.name,
      cover: _fileServer.urlFor(show.coverFileId),
      episodes: show.episodes.length,
      category: show.chatTitle,
    );
  }

  static final _tagPattern = RegExp(r'#([^\s#]+)');

  static final _episodePatterns = <RegExp>[
    RegExp(r'第\s*(\d+)\s*集'),
    RegExp(r'\bEP?\s*(\d+)\b', caseSensitive: false),
    RegExp(r'\bE(\d+)\b'),
    RegExp(r'[第集]\s*(\d+)\s*[集话话]'),
    RegExp(r'[-_](\d+)\s*(?:\.\w+)?$'),
  ];

  static String _showNameOf(TdlibVideoMessage message) {
    final text = '${message.caption} ${message.fileName}'.trim();
    final tag = _tagPattern.firstMatch(text);
    if (tag != null) return tag.group(1)!.trim();
    var name = message.fileName.trim();
    name = name.replaceAll(RegExp(r'\.\w+$'), '');
    name = name.replaceAll(RegExp(r'第\s*\d+\s*集'), '');
    name = name.replaceAll(RegExp(r'\bEP?\s*\d+\b', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[-_]\d+$'), '');
    name = name.replaceAll('_', ' ').trim();
    if (name.isNotEmpty) return name;
    return '未命名';
  }

  static int _episodeNumberOf(TdlibVideoMessage message, int fallback) {
    final text = '${message.caption} ${message.fileName}';
    for (final pattern in _episodePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final number = int.tryParse(match.group(1) ?? '');
        if (number != null && number > 0) return number;
      }
    }
    return fallback;
  }

  static (int, String)? _parseShowId(String raw) {
    if (!raw.startsWith('tdlib:')) return null;
    final rest = raw.substring('tdlib:'.length);
    final colon = rest.indexOf(':');
    if (colon <= 0) return null;
    final chatId = int.tryParse(rest.substring(0, colon));
    if (chatId == null) return null;
    final encoded = rest.substring(colon + 1);
    if (encoded.isEmpty) return null;
    var name = encoded;
    if (encoded.contains('%')) {
      try {
        name = Uri.decodeComponent(encoded);
      } catch (_) {
        return null;
      }
    }
    return (chatId, name);
  }

  static (int, int, int)? _parsePlayId(String raw) {
    var value = raw.trim();
    if (value.startsWith('tgdrama:')) value = value.substring('tgdrama:'.length);
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final chatId = int.tryParse(parts[0]);
    final messageId = int.tryParse(parts[1]);
    final fileId = int.tryParse(parts[2]);
    if (chatId == null || messageId == null || fileId == null) return null;
    return (chatId, messageId, fileId);
  }
}
