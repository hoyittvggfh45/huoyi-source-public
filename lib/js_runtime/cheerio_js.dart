import 'dart:convert';

class CheerioJs {
  static String buildInstallScript(String cheerioSource) {
    return _head + jsonEncode(cheerioSource) + _tail;
  }

  static const String _head = r'''
(function () {
var module = {exports: {}};
var exports = module.exports;
var source = ''';

  static const String _tail = r''';
var match = source.match(/export\s*\{([^}]*)\}\s*;?\s*$/);
if (match) {
  var parts = match[1].split(',');
  var entries = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim();
    if (!part) {
      continue;
    }
    var kv = part.split(' as ');
    var name = kv[0].trim();
    var key = kv.length > 1 ? kv[1].trim() : name;
    entries.push(key + ':' + name);
  }
  source = source.slice(0, match.index) + 'module.exports={' + entries.join(',') + '};';
}
eval(source);
var cheerio = module.exports;
var load = cheerio.load;
var tags = {a: 1, div: 1, span: 1, p: 1, li: 1, ul: 1, ol: 1, img: 1, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, section: 1, article: 1, header: 1, footer: 1, nav: 1, main: 1, table: 1, tr: 1, td: 1, th: 1, form: 1, input: 1, button: 1, video: 1, source: 1, script: 1, style: 1, title: 1, head: 1, body: 1, html: 1, em: 1, strong: 1, i: 1, b: 1, small: 1, label: 1, select: 1, option: 1, textarea: 1, figure: 1, figcaption: 1, dl: 1, dt: 1, dd: 1, pre: 1, code: 1, blockquote: 1, iframe: 1, canvas: 1, svg: 1, path: 1};
function isField(segment) {
  if (segment === 'Text' || segment === 'Html') {
    return true;
  }
  if (segment.indexOf('data-') === 0) {
    return true;
  }
  if (tags[segment]) {
    return false;
  }
  var c = segment.charAt(0);
  if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c === '_')) {
    return false;
  }
  for (var i = 1; i < segment.length; i++) {
    var ch = segment.charAt(i);
    if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch === '_' || ch === '-')) {
      return false;
    }
  }
  return true;
}
function parseRule(rule) {
  var parts = String(rule).split('&&');
  var cleaned = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim();
    if (part) {
      cleaned.push(part);
    }
  }
  if (cleaned.length === 0) {
    return {selectors: [], field: null};
  }
  var last = cleaned[cleaned.length - 1];
  if (isField(last)) {
    return {selectors: cleaned.slice(0, cleaned.length - 1), field: last};
  }
  return {selectors: cleaned, field: null};
}
function unquote(value) {
  var v = value.trim();
  if (v.length >= 2 && ((v.charAt(0) === '"' && v.charAt(v.length - 1) === '"') || (v.charAt(0) === "'" && v.charAt(v.length - 1) === "'"))) {
    return v.slice(1, v.length - 1);
  }
  return v;
}
function stripPseudos(segment) {
  var pseudos = [];
  var out = '';
  var i = 0;
  while (i < segment.length) {
    if (segment.charAt(i) === ':') {
      var rest = segment.slice(i);
      var name = null;
      if (rest.indexOf(':matches(') === 0) {
        name = 'matches';
      } else if (rest.indexOf(':contains(') === 0) {
        name = 'contains';
      } else if (rest.indexOf(':not(') === 0) {
        name = 'not';
      }
      if (name) {
        var start = i + name.length + 2;
        var depth = 1;
        var j = start;
        while (j < segment.length && depth > 0) {
          if (segment.charAt(j) === '(') {
            depth++;
          } else if (segment.charAt(j) === ')') {
            depth--;
          }
          j++;
        }
        pseudos.push({name: name, arg: segment.slice(start, j - 1)});
        i = j;
        continue;
      }
    }
    out += segment.charAt(i);
    i++;
  }
  var base = out.trim();
  if (!base) {
    base = '*';
  }
  return {base: base, pseudos: pseudos};
}
function applySegment(root, current, segment) {
  var parsed = stripPseudos(segment);
  var found;
  if (current === null) {
    found = root(parsed.base);
  } else {
    found = current.find(parsed.base);
  }
  if (parsed.pseudos.length === 0) {
    return found;
  }
  return found.filter(function (index, element) {
    var wrapped = root(element);
    for (var i = 0; i < parsed.pseudos.length; i++) {
      var pseudo = parsed.pseudos[i];
      if (pseudo.name === 'matches' || pseudo.name === 'contains') {
        if (wrapped.text().indexOf(unquote(pseudo.arg)) === -1) {
          return false;
        }
      } else if (pseudo.name === 'not') {
        var arg = pseudo.arg.trim();
        if (arg.indexOf(':matches(') !== -1 || arg.indexOf(':contains(') !== -1) {
          var inner = stripPseudos(arg);
          var textArg = '';
          for (var k = 0; k < inner.pseudos.length; k++) {
            if (inner.pseudos[k].name === 'matches' || inner.pseudos[k].name === 'contains') {
              textArg = unquote(inner.pseudos[k].arg);
            }
          }
          if (textArg && wrapped.text().indexOf(textArg) !== -1) {
            return false;
          }
        } else if (wrapped.is(arg)) {
          return false;
        }
      }
    }
    return true;
  });
}
function selectElements(root, selectors) {
  var current = null;
  for (var i = 0; i < selectors.length; i++) {
    current = applySegment(root, current, selectors[i]);
    if (current.length === 0) {
      break;
    }
  }
  return current;
}
function fieldValue(wrapped, field) {
  if (field === 'Text') {
    return wrapped.text();
  }
  if (field === 'Html') {
    var inner = wrapped.html();
    return inner === null || inner === undefined ? '' : inner;
  }
  var value = wrapped.attr(field);
  return value === null || value === undefined ? '' : value;
}
function pdfh(html, rule) {
  try {
    var root = load(html || '');
    var parsed = parseRule(rule);
    var current = selectElements(root, parsed.selectors);
    if (current === null || current.length === 0) {
      return '';
    }
    var first = current.first();
    if (parsed.field) {
      return fieldValue(first, parsed.field);
    }
    var outer = root.html(first[0]);
    return outer === null || outer === undefined ? '' : outer;
  } catch (e) {
    return '';
  }
}
function pdfa(html, rule) {
  try {
    var root = load(html || '');
    var parsed = parseRule(rule);
    var current = selectElements(root, parsed.selectors);
    if (current === null || current.length === 0) {
      return [];
    }
    if (parsed.field) {
      return current.map(function (index, element) {
        return fieldValue(root(element), parsed.field);
      }).get();
    }
    return current.map(function (index, element) {
      var outer = root.html(element);
      return outer === null || outer === undefined ? '' : outer;
    }).get();
  } catch (e) {
    return [];
  }
}
globalThis.pdfh = pdfh;
globalThis.pdfa = pdfa;
})();
''';
}
