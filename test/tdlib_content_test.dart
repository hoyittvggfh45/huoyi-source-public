import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/tdlib_content.dart';
import 'package:duanju_app/tdlib_service.dart';

TdlibVideoMessage msg({
  required int messageId,
  required int chatId,
  required int fileId,
  int thumbFileId = 0,
  String caption = '',
  String fileName = 'video.mp4',
  int date = 1700000000,
}) => TdlibVideoMessage(
  messageId: messageId,
  chatId: chatId,
  date: date + messageId,
  duration: 600,
  width: 1280,
  height: 720,
  fileName: fileName,
  mimeType: 'video/mp4',
  supportsStreaming: true,
  fileId: fileId,
  fileSize: 1000,
  thumbFileId: thumbFileId,
  thumbWidth: 320,
  thumbHeight: 180,
  caption: caption,
);

TdlibFile localFile(int fileId, String path) => TdlibFile(
  id: fileId,
  size: 3,
  expectedSize: 3,
  localPath: path,
  downloadedPrefixSize: 3,
  downloadOffset: 0,
  isDownloadingCompleted: true,
  isDownloadingActive: false,
);

class FakeTdlibService extends TdlibService {
  FakeTdlibService({this.thumbPath = ''});

  final String thumbPath;
  var manyShows = false;
  var flipped = false;

  final _pages = <int, List<List<TdlibVideoMessage>>>{
    100: [
      [
        msg(
          messageId: 1,
          chatId: 100,
          fileId: 11,
          thumbFileId: 5,
          caption: '#剧A 第1集',
          fileName: '剧A 第1集.mp4',
        ),
        msg(
          messageId: 2,
          chatId: 100,
          fileId: 12,
          thumbFileId: 6,
          caption: '#剧A 第2集',
          fileName: '剧A 第2集.mp4',
        ),
      ],
      [
        msg(
          messageId: 3,
          chatId: 100,
          fileId: 13,
          caption: '#剧B 第1集',
          fileName: '剧B 第1集.mp4',
        ),
        msg(
          messageId: 4,
          chatId: 100,
          fileId: 14,
          thumbFileId: 7,
          caption: '无标签视频',
          fileName: 'random.mp4',
        ),
      ],
    ],
    101: [
      [
        msg(
          messageId: 5,
          chatId: 101,
          fileId: 15,
          thumbFileId: 8,
          caption: '#剧A 第1集',
          fileName: '剧A 第1集.mp4',
        ),
        msg(
          messageId: 6,
          chatId: 101,
          fileId: 16,
          thumbFileId: 9,
          caption: '#剧C EP 3',
          fileName: '剧C EP3.mp4',
        ),
      ],
    ],
  };

  @override
  Future<List<TdlibChat>> chats({int limit = 40}) async => const [
    TdlibChat(id: 100, title: '频道A', type: 'channel'),
    TdlibChat(id: 101, title: '频道B', type: 'channel'),
    TdlibChat(id: 102, title: '私聊C', type: 'private'),
  ];

  @override
  Future<({List<TdlibVideoMessage> messages, int nextFromMessageId})>
  chatHistory({
    required int chatId,
    int fromMessageId = 0,
    int limit = 100,
  }) async {
    if (manyShows) {
      if (fromMessageId != 0) {
        return (messages: const <TdlibVideoMessage>[], nextFromMessageId: 0);
      }
      return (
        messages: [
          for (var i = 0; i < 35; i++)
            msg(
              messageId: 100 + i,
              chatId: chatId,
              fileId: 200 + i,
              thumbFileId: 300 + i,
              caption: '#批量剧$i 第1集',
              fileName: '批量剧$i.mp4',
            ),
        ],
        nextFromMessageId: 0,
      );
    }
    final pages = _pages[chatId] ?? const [];
    final index = fromMessageId == 0 ? 0 : 1;
    if (index >= pages.length) {
      return (messages: const <TdlibVideoMessage>[], nextFromMessageId: 0);
    }
    return (
      messages: pages[index],
      nextFromMessageId: index + 1 < pages.length ? 99 : 0,
    );
  }

  @override
  Future<List<TdlibVideoMessage>> searchMessages({
    required String query,
    int limit = 50,
  }) async {
    if (flipped) return const [];
    if (query.contains('剧A')) {
      return [
        msg(
          messageId: 1,
          chatId: 100,
          fileId: 11,
          thumbFileId: 5,
          caption: '#剧A 第1集',
          fileName: '剧A 第1集.mp4',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<({List<TdlibVideoMessage> messages, int nextFromMessageId})>
  searchChatMessages({
    required int chatId,
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    if (chatId == 101 && query.contains('剧C')) {
      return (
        messages: [
          msg(
            messageId: 6,
            chatId: 101,
            fileId: 16,
            thumbFileId: 9,
            caption: '#剧C EP 3',
            fileName: '剧C EP3.mp4',
          ),
        ],
        nextFromMessageId: 0,
      );
    }
    return (messages: const <TdlibVideoMessage>[], nextFromMessageId: 0);
  }

  @override
  Future<TdlibFile> downloadFileAndWait(
    int fileId, {
    int priority = 32,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (fileId == 5 || fileId == 6 || fileId == 7 || fileId == 8 || fileId == 9) {
      return localFile(fileId, thumbPath);
    }
    return localFile(fileId, '/tmp/tdlib/$fileId.mp4');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTdlibService fake;
  late TdlibContent content;

  setUp(() {
    fake = FakeTdlibService();
    content = TdlibContent(service: fake);
  });

  test('分类：固定“全部”在首位，只列频道与超级群', () async {
    final categories = await content.categories();
    expect(categories.map((c) => c.name).toList(), ['全部', '频道A', '频道B']);
    expect(categories.first.id, '');
    expect(categories[1].id, '100');
  });

  test('列表按 #标签聚合，集号按第N集/EP 排，单集无封面不显示', () async {
    final page = await content.catalog(category: '', page: 1);
    final titles = page.items.map((d) => d.title).toList();
    expect(titles, containsAll(['剧A', 'random']));
    expect(titles, isNot(contains('剧B')));
    expect(page.items.where((d) => d.title == '剧A').length, 2);

    final showA = page.items.firstWhere(
      (d) => d.title == '剧A' && d.category == '频道A',
    );
    expect(showA.episodes, 2);
    expect(showA.cover, startsWith('http://127.0.0.1:'));

    final detail = await content.detail(showA);
    expect(detail.episodes.length, 2);
    expect(detail.episodes[0].title, '第1集');
    expect(detail.episodes[0].id, 'tgdrama:100:1:11');
    expect(detail.episodes[1].id, 'tgdrama:100:2:12');
    expect(detail.episodes[0].raw['flag'], 'TG影视库');
  });

  test('同一剧名在不同频道是两部剧，不混', () async {
    final pageA = await content.catalog(category: '100', page: 1);
    final pageB = await content.catalog(category: '101', page: 1);
    expect(pageA.items.map((d) => d.title).toSet(), {'剧A', 'random'});
    expect(pageB.items.map((d) => d.title).toSet(), {'剧A', '剧C'});
    final showC = pageB.items.firstWhere((d) => d.title == '剧C');
    expect(showC.episodes, 1);
    final detailC = await content.detail(showC);
    expect(detailC.episodes.first.id, 'tgdrama:101:6:16');
  });

  test('翻页：30 条一页，hasMore 与越界空页', () async {
    fake.manyShows = true;
    final first = await content.catalog(category: '100', page: 1);
    expect(first.items.length, 30);
    expect(first.hasMore, isTrue);
    final second = await content.catalog(category: '100', page: 2);
    expect(second.items.length, 5);
    expect(second.hasMore, isFalse);
    final beyond = await content.catalog(category: '100', page: 3);
    expect(beyond.items, isEmpty);
    expect(beyond.hasMore, isFalse);
  });

  test('详情找不到剧时给提示不抛错', () async {
    final drama = Drama(
      id: 'tdlib:100:不存在的剧',
      source: 'tgdrama',
      sourceId: 'tdlib:100:不存在的剧',
      title: '不存在的剧',
    );
    final detail = await content.detail(drama);
    expect(detail.episodes, isEmpty);
    expect(detail.warning, isNotEmpty);
  });

  test('搜索：全局有结果直接用，全局无结果退回逐频道搜', () async {
    final hit = await content.search('剧A');
    expect(hit.items.map((d) => d.title).toList(), ['剧A']);

    fake.flipped = true;
    final fallback = await content.search('剧C');
    expect(fallback.items.map((d) => d.title).toList(), ['剧C']);
  });

  test('取流：集 id 解析出文件号，下完回本地路径；坏 id 报错', () async {
    final plan = await content.resolvePlan('TG影视库', 'tgdrama:100:1:11');
    expect(plan.url, '/tmp/tdlib/11.mp4');
    expect(plan.local, isTrue);

    await expectLater(
      content.resolvePlan('TG影视库', 'not-a-play-id'),
      throwsA(isA<AppFailure>()),
    );
  });

  test('封面服务：未启动回空，启动后回环地址能下到缩略图', () async {
    final thumb = File('${Directory.systemTemp.path}/tdlib_test_thumb.jpg');
    await thumb.writeAsBytes([1, 2, 3]);
    final serverFake = FakeTdlibService(thumbPath: thumb.path);
    final server = TdlibFileServer(service: serverFake);
    expect(server.urlFor(5), isEmpty);
    await server.ensureStarted();
    final url = server.urlFor(5);
    expect(url, startsWith('http://127.0.0.1:'));
    try {
      final ok = await _rawGet(Uri.parse(url));
      expect(ok.$1, 200);
      expect(ok.$2, [1, 2, 3]);
      final bad = await _rawGet(
        Uri.parse('${url.split('/file').first}/nope'),
      );
      expect(bad.$1, 404);
    } finally {
      await server.close();
      await thumb.delete();
    }
  });

  test('封面服务：文件拿不到本地路径时回 404', () async {
    final server = TdlibFileServer(service: FakeTdlibService(thumbPath: ''));
    await server.ensureStarted();
    try {
      final missing = await _rawGet(Uri.parse(server.urlFor(5)));
      expect(missing.$1, 404);
    } finally {
      await server.close();
    }
  });
}

Future<(int, List<int>)> _rawGet(Uri uri) async {
  final socket = await Socket.connect(uri.host, uri.port);
  socket.write(
    'GET ${uri.path}?${uri.query} HTTP/1.1\r\n'
    'Host: ${uri.host}\r\n'
    'Connection: close\r\n\r\n',
  );
  final bytes = await socket.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  await socket.close();
  final text = latin1.decode(bytes);
  final headEnd = text.indexOf('\r\n\r\n');
  final head = text.substring(0, headEnd);
  final status = int.parse(head.split(' ')[1]);
  return (status, bytes.sublist(headEnd + 4));
}
