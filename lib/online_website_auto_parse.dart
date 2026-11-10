import 'dart:convert';

import 'online_website.dart';

const String onlineWebsiteListScript = r'''
(function () {
  function abs(href) {
    try { return new URL(href, location.href).href; } catch (e) { return ''; }
  }
  function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
  function sameSite(h1, h2) {
    var p1 = h1.split('.').slice(-2).join('.');
    var p2 = h2.split('.').slice(-2).join('.');
    return p1 !== '' && p1 === p2;
  }
  var navWords = /登录|注册|首页|更多|上一页|下一页|返回|搜索|下载|APP|客户端|关于我们|联系我们|友情链接|广告|充值|会员|签到|收藏|历史|设置|反馈|帮助|隐私|条款/;
  var detailHint = /\/(detail|video|play|movie|tv|show|drama|vod|view|watch|content|p|v)\//i;
  var out = [];
  var seen = {};
  var links = document.querySelectorAll('a[href]');
  var host = location.host;
  for (var i = 0; i < links.length; i++) {
    var a = links[i];
    var href = abs(a.getAttribute('href') || '');
    if (!href || href === location.href) continue;
    if (/^(javascript|mailto|tel):/i.test(href)) continue;
    var uri;
    try { uri = new URL(href); } catch (e) { continue; }
    if (uri.protocol !== 'http:' && uri.protocol !== 'https:') continue;
    var img = a.querySelector('img');
    var title = clean(a.getAttribute('title') || a.textContent || '');
    if (title.length < 2 || title.length > 60) continue;
    if (navWords.test(title)) continue;
    var cover = '';
    if (img) {
      cover = abs(img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-lazy-src') || img.src || '');
    }
    var score = 0;
    if (img) score += 2;
    if (sameSite(uri.host, host)) score += 1;
    if (detailHint.test(uri.pathname)) score += 1;
    if (score < 2) continue;
    if (seen[href]) continue;
    seen[href] = true;
    out.push({title: title, url: href, cover: cover, score: score});
  }
  out.sort(function (x, y) { return y.score - x.score; });
  var result = [];
  for (var j = 0; j < out.length && j < 60; j++) {
    result.push({title: out[j].title, url: out[j].url, cover: out[j].cover});
  }
  return JSON.stringify(result);
})()
''';

const String onlineWebsiteDetailScript = r'''
(function () {
  function abs(href) {
    try { return new URL(href, location.href).href; } catch (e) { return ''; }
  }
  function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
  var out = [];
  var seen = {};
  function push(title, href) {
    href = abs(href || '');
    title = clean(title);
    if (!href || !title) return;
    var key = href + '|' + title;
    if (seen[key]) return;
    seen[key] = true;
    out.push({title: title, url: href});
  }
  var epPattern = /第?\s*\d+\s*[集话話期]/;
  var nodes = document.querySelectorAll('a[href], button, [data-href], [data-url], [onclick]');
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i];
    var text = clean(n.textContent || '');
    if (!epPattern.test(text)) continue;
    var href = n.getAttribute('href') || n.getAttribute('data-href') || n.getAttribute('data-url') || '';
    if (!href) {
      var oc = n.getAttribute('onclick') || '';
      var m = oc.match(/['"]([^'"]+)['"]/);
      if (m) href = m[1];
    }
    if (!href) href = location.href;
    push(text.length > 24 ? text.slice(0, 24) : text, href);
  }
  var info = {title: '', cover: '', director: '', actors: '', description: ''};
  var h1 = document.querySelector('h1');
  if (h1) info.title = clean(h1.textContent);
  if (!info.title) info.title = clean(document.title);
  var ogImg = document.querySelector('meta[property="og:image"]');
  if (ogImg) info.cover = abs(ogImg.getAttribute('content') || '');
  if (!info.cover) {
    var big = document.querySelector('.poster img, .detail-pic img, .vod-pic img, [class*="poster"] img, [class*="cover"] img');
    if (big) info.cover = abs(big.getAttribute('data-src') || big.getAttribute('data-original') || big.src || '');
  }
  var bodyText = (document.body && document.body.innerText) || '';
  function labeled(label) {
    var m = bodyText.match(new RegExp(label + '\\s*[：:]\\s*([^\\n]{1,80})'));
    return m ? clean(m[1]) : '';
  }
  info.director = labeled('导演');
  info.actors = labeled('主演') || labeled('演员');
  var desc = document.querySelector('meta[name="description"]');
  if (desc) info.description = clean(desc.getAttribute('content') || '');
  return JSON.stringify({episodes: out.slice(0, 200), info: info});
})()
''';

const String onlineWebsiteShieldScript = r'''
(function () {
  var title = (document.title || '').toLowerCase();
  var text = (document.body ? document.body.innerText || '' : '').slice(0, 2000).toLowerCase();
  var challenged = title.indexOf('just a moment') >= 0 ||
    title.indexOf('attention required') >= 0 ||
    text.indexOf('checking your browser') >= 0 ||
    text.indexOf('verify you are human') >= 0 ||
    text.indexOf('confirm you are human') >= 0 ||
    text.indexOf('please verify') >= 0 ||
    !!document.querySelector('iframe[src*="challenges.cloudflare.com"]') ||
    !!document.querySelector('#cf-challenge, .cf-challenge, [data-sitekey]');
  return JSON.stringify({challenged: challenged, title: document.title || ''});
})()
''';

class OnlineWebsiteShieldResult {
  const OnlineWebsiteShieldResult({required this.challenged, this.title = ''});

  final bool challenged;
  final String title;

  factory OnlineWebsiteShieldResult.fromJson(Map<String, dynamic> json) =>
      OnlineWebsiteShieldResult(
        challenged: json['challenged'] == true,
        title: json['title'] as String? ?? '',
      );
}

OnlineWebsiteShieldResult parseOnlineWebsiteShield(Object? result) {
  final value = _unwrap(result);
  if (value is Map) {
    return OnlineWebsiteShieldResult.fromJson(Map<String, dynamic>.from(value));
  }
  return const OnlineWebsiteShieldResult(challenged: false);
}

Object? _unwrap(Object? result) {
  var value = result;
  for (var i = 0; i < 2; i++) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    } else {
      break;
    }
  }
  return value;
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is List) {
    return [
      for (final row in value)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }
  return const [];
}

List<OnlineWebsiteCard> parseOnlineWebsiteCards(Object? result) {
  final value = _unwrap(result);
  return [
    for (final row in _asMapList(value)) OnlineWebsiteCard.fromJson(row),
  ].where((card) => card.title.isNotEmpty && card.url.isNotEmpty).toList();
}

({List<OnlineWebsiteEpisode> episodes, OnlineWebsiteDetailInfo info})
parseOnlineWebsiteDetail(Object? result) {
  final value = _unwrap(result);
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final episodes =
        [
              for (final row in _asMapList(map['episodes']))
                OnlineWebsiteEpisode.fromJson(row),
            ]
            .where(
              (episode) => episode.title.isNotEmpty && episode.url.isNotEmpty,
            )
            .toList();
    final info = map['info'] is Map
        ? OnlineWebsiteDetailInfo.fromJson(
            Map<String, dynamic>.from(map['info'] as Map),
          )
        : const OnlineWebsiteDetailInfo();
    return (episodes: episodes, info: info);
  }
  return (episodes: const [], info: const OnlineWebsiteDetailInfo());
}
