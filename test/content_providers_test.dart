import 'dart:convert';

import 'package:duanju_app/content_cms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MacCMS 通用引擎解析', () {
    test('分类与列表', () {
      final cats = parseMacCmsCategories(
        jsonDecode(
          '{"class":[{"type_id":1,"type_name":"有声小说"}],'
          '"pagecount":3,"total":42,'
          '"list":[{"vod_id":9,"vod_name":"书","vod_pic":"p.jpg",'
          '"vod_remarks":"更新至10集"}]}',
        ) as Map<String, dynamic>,
      );
      expect(cats, hasLength(2));
      expect(cats.last.name, '有声小说');
      final page = parseMacCmsListPage(
        jsonDecode(
          '{"pagecount":3,"total":42,"list":[{"vod_id":9,'
          '"vod_name":"书","vod_pic":"p.jpg","vod_remarks":"更新至10集"}]}',
        ) as Map<String, dynamic>,
        1,
      );
      expect(page.items.first.title, '书');
      expect(page.hasMore, isTrue);
    });

    test('分集解析与音频过滤', () {
      final chapters = parseMacCmsEpisodes({
        'vod_play_url':
            '第1集\$https://a.example/1.mp3#第2集\$https://a.example/2.mp4'
            '\$\$\$第1集\$https://b.example/1.mp3',
      }, onlyAudio: true);
      expect(chapters, hasLength(1));
      expect(chapters.first.title, '第1集');
      expect(chapters.first.id, 'https://a.example/1.mp3');
      expect(MacCmsAudioSource.isAudioUrl('https://a/1.MP3?x=1'), isTrue);
      expect(MacCmsAudioSource.isAudioUrl('https://a/1.mp4'), isFalse);
    });
  });
}
