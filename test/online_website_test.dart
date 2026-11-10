import 'dart:convert';

import 'package:duanju_app/online_website.dart';
import 'package:duanju_app/online_website_auto_parse.dart';
import 'package:duanju_app/online_website_clearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('online website keeps fields and defaults auto and pure on', () {
    final site = OnlineWebsite.fromJson({
      'id': '1',
      'name': '',
      'url': 'https://www.example.com/list',
    });
    expect(site.autoMode, isTrue);
    expect(site.pureMode, isTrue);
    expect(site.displayName, 'www.example.com');
    expect(site.hostLabel, 'www.example.com');
    final restored = OnlineWebsite.fromJson(site.toJson());
    expect(restored.id, '1');
    expect(restored.url, 'https://www.example.com/list');
    expect(restored.autoMode, isTrue);
    expect(restored.pureMode, isTrue);
  });

  test('online website store saves and loads the list', () async {
    SharedPreferences.setMockInitialValues({});
    await OnlineWebsiteStore.save([
      const OnlineWebsite(
        id: 'a',
        name: 'A站',
        url: 'https://a.example.com',
        autoMode: false,
        pureMode: true,
      ),
      const OnlineWebsite(id: 'b', name: '', url: 'https://b.example.com'),
    ]);
    final loaded = await OnlineWebsiteStore.load();
    expect(loaded.length, 2);
    expect(loaded.first.autoMode, isFalse);
    expect(loaded.last.displayName, 'b.example.com');
  });

  test('card parse accepts a json string and drops empty rows', () {
    final cards = parseOnlineWebsiteCards(
      jsonEncode([
        {
          'title': '剧一',
          'url': 'https://x.example.com/1',
          'cover': 'https://x.example.com/1.jpg',
        },
        {'title': '', 'url': 'https://x.example.com/2'},
        {'title': '剧三', 'url': ''},
      ]),
    );
    expect(cards.length, 1);
    expect(cards.first.title, '剧一');
    expect(cards.first.cover, 'https://x.example.com/1.jpg');
  });

  test('card parse accepts a double encoded string and bad input', () {
    final doubleEncoded = jsonEncode(
      jsonEncode([
        {'title': '剧一', 'url': 'https://x.example.com/1'},
      ]),
    );
    expect(parseOnlineWebsiteCards(doubleEncoded).length, 1);
    expect(parseOnlineWebsiteCards('not json'), isEmpty);
    expect(parseOnlineWebsiteCards(null), isEmpty);
  });

  test('detail parse returns episodes and info with defaults', () {
    final parsed = parseOnlineWebsiteDetail(
      jsonEncode({
        'episodes': [
          {'title': '第1集', 'url': 'https://x.example.com/play/1'},
          {'title': '第2集', 'url': 'https://x.example.com/play/2'},
        ],
        'info': {
          'title': '剧一',
          'cover': 'https://x.example.com/cover.jpg',
          'director': '',
          'actors': '甲，乙',
          'description': '简介',
        },
      }),
    );
    expect(parsed.episodes.length, 2);
    expect(parsed.episodes.first.title, '第1集');
    expect(parsed.info.title, '剧一');
    expect(parsed.info.director, isEmpty);
    expect(parsed.info.actors, '甲，乙');
  });

  test('detail parse tolerates missing info', () {
    final parsed = parseOnlineWebsiteDetail(jsonEncode({'episodes': []}));
    expect(parsed.episodes, isEmpty);
    expect(parsed.info.title, isEmpty);
  });

  test('synthetic detail carries the episode page url and stable id', () {
    const site = OnlineWebsite(
      id: 's1',
      name: 'S',
      url: 'https://s.example.com',
    );
    const episodes = [
      OnlineWebsiteEpisode(title: '第1集', url: 'https://s.example.com/play/1'),
      OnlineWebsiteEpisode(title: '第2集', url: 'https://s.example.com/play/2'),
    ];
    final first = onlineWebsiteDetail(
      site: site,
      pageUrl: 'https://s.example.com/detail/9',
      title: '剧一',
      cover: '',
      episodes: episodes,
    );
    final second = onlineWebsiteDetail(
      site: site,
      pageUrl: 'https://s.example.com/detail/9',
      title: '剧一',
      cover: '',
      episodes: episodes,
    );
    expect(first.drama.source, onlineWebsiteSourceId);
    expect(first.drama.id, second.drama.id);
    expect(first.episodes.length, 2);
    expect(first.episodes.first.raw['url'], 'https://s.example.com/play/1');
    expect(first.episodes.first.title, '第1集');
    expect(first.episodes[1].number, 2);
  });

  test('synthetic detail falls back to the site name when title is empty', () {
    const site = OnlineWebsite(
      id: 's1',
      name: 'S站',
      url: 'https://s.example.com',
    );
    final detail = onlineWebsiteDetail(
      site: site,
      pageUrl: 'https://s.example.com/detail/9',
      title: '',
      cover: '',
      episodes: const [
        OnlineWebsiteEpisode(title: '正片', url: 'https://s.example.com/play/9'),
      ],
    );
    expect(detail.drama.title, 'S站');
  });

  test('shield parse flags a challenge page and clears on real content', () {
    final challenged = parseOnlineWebsiteShield(
      jsonEncode({'challenged': true, 'title': 'Just a moment...'}),
    );
    expect(challenged.challenged, isTrue);
    expect(challenged.title, 'Just a moment...');
    final clear = parseOnlineWebsiteShield(
      jsonEncode({'challenged': false, 'title': '首页'}),
    );
    expect(clear.challenged, isFalse);
    expect(parseOnlineWebsiteShield('not json').challenged, isFalse);
    expect(parseOnlineWebsiteShield(null).challenged, isFalse);
  });

  test(
    'clearance store saves and loads by host with subdomain fallback',
    () async {
      SharedPreferences.setMockInitialValues({});
      await OnlineWebsiteClearanceStore.save(
        OnlineWebsiteClearance(
          host: 'example.com',
          clearance: 'abc123',
          userAgent: 'UA-Test',
          updatedAt: DateTime.now(),
        ),
      );
      final exact = await OnlineWebsiteClearanceStore.loadForHost(
        'example.com',
      );
      expect(exact?.clearance, 'abc123');
      final sub = await OnlineWebsiteClearanceStore.loadForHost(
        'www.example.com',
      );
      expect(sub?.clearance, 'abc123');
      expect(
        await OnlineWebsiteClearanceStore.loadForHost('other.com'),
        isNull,
      );
    },
  );

  test(
    'clearance store marks entries older than thirty minutes stale',
    () async {
      SharedPreferences.setMockInitialValues({});
      await OnlineWebsiteClearanceStore.save(
        OnlineWebsiteClearance(
          host: 'old.example.com',
          clearance: 'old',
          userAgent: '',
          updatedAt: DateTime.now().subtract(const Duration(minutes: 31)),
        ),
      );
      await OnlineWebsiteClearanceStore.save(
        OnlineWebsiteClearance(
          host: 'fresh.example.com',
          clearance: 'fresh',
          userAgent: '',
          updatedAt: DateTime.now(),
        ),
      );
      final old = await OnlineWebsiteClearanceStore.loadForHost(
        'old.example.com',
      );
      expect(old?.isStale, isTrue);
      final fresh = await OnlineWebsiteClearanceStore.loadForHost(
        'fresh.example.com',
      );
      expect(fresh?.isStale, isFalse);
    },
  );

  test('clearance store removes one host and keeps the others', () async {
    SharedPreferences.setMockInitialValues({});
    await OnlineWebsiteClearanceStore.save(
      OnlineWebsiteClearance(
        host: 'a.example.com',
        clearance: 'a',
        userAgent: '',
        updatedAt: DateTime.now(),
      ),
    );
    await OnlineWebsiteClearanceStore.save(
      OnlineWebsiteClearance(
        host: 'b.example.com',
        clearance: 'b',
        userAgent: '',
        updatedAt: DateTime.now(),
      ),
    );
    await OnlineWebsiteClearanceStore.removeForHost('a.example.com');
    expect(
      await OnlineWebsiteClearanceStore.loadForHost('a.example.com'),
      isNull,
    );
    expect(
      (await OnlineWebsiteClearanceStore.loadForHost(
        'b.example.com',
      ))?.clearance,
      'b',
    );
  });
}
