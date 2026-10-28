import 'dart:convert';

enum HikerChainExtractor { selector, text, html, attribute }

class HikerChainStep {
  const HikerChainStep({
    required this.raw,
    required this.extractor,
    this.attribute = '',
  });

  final String raw;
  final HikerChainExtractor extractor;
  final String attribute;
}

const Set<String> hikerChainAttributes = {
  'title',
  'href',
  'src',
  'data-original',
  'realsrc',
  'alt',
  'data-src',
  'value',
  'content',
  'id',
  'class',
  'name',
  'data-url',
  'data-href',
  'data-title',
  'data-id',
};

List<HikerChainStep> parseHikerChain(String rule) {
  final trimmed = rule.trim();
  if (trimmed.isEmpty || trimmed.startsWith('js:')) return [];
  final steps = <HikerChainStep>[];
  for (final part in trimmed.split('&&')) {
    final segment = part.trim();
    if (segment.isEmpty) continue;
    if (segment == 'Text') {
      steps.add(
        const HikerChainStep(raw: 'Text', extractor: HikerChainExtractor.text),
      );
    } else if (segment == 'Html') {
      steps.add(
        const HikerChainStep(raw: 'Html', extractor: HikerChainExtractor.html),
      );
    } else if (hikerChainAttributes.contains(segment)) {
      steps.add(
        HikerChainStep(
          raw: segment,
          extractor: HikerChainExtractor.attribute,
          attribute: segment,
        ),
      );
    } else {
      steps.add(
        HikerChainStep(raw: segment, extractor: HikerChainExtractor.selector),
      );
    }
  }
  return steps;
}

enum HikerLinkKind { empty, http, hiker, relative, other }

HikerLinkKind classifyHikerLink(String url) {
  final value = url.trim();
  if (value == 'hiker://empty') return HikerLinkKind.empty;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return HikerLinkKind.http;
  }
  if (value.startsWith('hiker://')) return HikerLinkKind.hiker;
  if (value.isEmpty ||
      value.contains('://') ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value)) {
    return HikerLinkKind.other;
  }
  return HikerLinkKind.relative;
}

bool isHikerEmptyLink(String url) =>
    classifyHikerLink(url) == HikerLinkKind.empty;

bool isPlayableHikerUrl(String url) =>
    classifyHikerLink(url) == HikerLinkKind.http;

String hikerPageUrl(String template, int page) =>
    template.replaceAll('fypage', page.toString());

String resolveHikerUrl(String base, String ref) {
  final value = ref.trim();
  if (value.isEmpty || !value.startsWith('/')) return ref;
  final baseUri = Uri.tryParse(base.trim());
  if (baseUri == null ||
      !(baseUri.scheme == 'http' || baseUri.scheme == 'https')) {
    return ref;
  }
  return baseUri.resolve(value).toString();
}

const _hikerUrlKeys = {
  'url',
  'href',
  'pic',
  'pic_url',
  'img',
  'src',
  'cover',
  'image',
  'playUrl',
  'play_url',
  'videoUrl',
};

dynamic resolveHikerResultUrls(dynamic raw, String base) {
  if (raw is String) {
    try {
      return resolveHikerResultUrls(jsonDecode(raw), base);
    } catch (_) {
      return raw;
    }
  }
  if (raw is Map) {
    final map = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is String && _hikerUrlKeys.contains(key)) {
        map[key] = resolveHikerUrl(base, value);
      } else {
        map[key] = resolveHikerResultUrls(value, base);
      }
    }
    return map;
  }
  if (raw is List) {
    return [for (final item in raw) resolveHikerResultUrls(item, base)];
  }
  return raw;
}
