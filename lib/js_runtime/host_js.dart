String buildHostPrelude({
  required String pageCacheJson,
  required String storageJson,
  required String storagePublicJson,
  required String filesDirJson,
}) {
  return md5Js +
      rsaJs +
      btoaPolyfillJs +
      r'''
globalThis.__pageCache = __PAGE_CACHE__;
globalThis.__storage = __STORAGE__;
globalThis.__storagePublic = __STORAGE_PUBLIC__;
globalThis.__filesDir = __FILES_DIR__;
globalThis.__pending = [];
globalThis.__fetchRegistry = {};
globalThis.__setResultValue = null;
globalThis.__ruleDone = false;
globalThis.__ruleError = null;
globalThis.__logs = [];
globalThis.window = globalThis;
globalThis.self = globalThis;
globalThis.global = globalThis;
function setResult(v) { globalThis.__setResultValue = v; }
function getPath(v) {
  if (typeof v !== 'string') return v;
  if (v.indexOf('hiker://assets/') === 0) return v.substring('hiker://assets/'.length);
  if (v.indexOf('hiker://files/') === 0) return __filesDir + '/' + v.substring('hiker://files/'.length);
  if (v.indexOf('hiker://page/') === 0) return '';
  if (v === 'hiker://empty') return '';
  return v;
}
function __deliver(id, ok, payload) {
  var e = __fetchRegistry[id];
  if (!e) return;
  delete __fetchRegistry[id];
  if (ok) e.resolve(payload);
  else e.reject(new Error(payload));
}
function __pushPending(kind, url, method, headers, body) {
  var id = 'p' + (__pending.length + 1) + '_' + Math.floor(Math.random() * 1000000000);
  __pending.push({id: id, kind: kind, url: url, method: method, headers: headers || {}, body: body || null});
  return new Promise(function(resolve, reject) { __fetchRegistry[id] = {resolve: resolve, reject: reject}; });
}
function fetch(url, options) {
  options = options || {};
  if (Object.prototype.hasOwnProperty.call(__pageCache, url)) return __pageCache[url];
  return __pushPending('http', url, options.method || 'GET', options.headers || {}, options.body || null);
}
function _http(url, options) {
  options = options || {};
  if (Object.prototype.hasOwnProperty.call(__pageCache, url)) return __pageCache[url];
  var p = __pushPending('http', url, options.method || 'GET', options.headers || {}, options.body || null);
  if (typeof options.complete === 'function') {
    p.then(function(t) { options.complete(t); }, function(e) { options.complete({ok: false, status: 500, url: url}); });
  }
  return p;
}
function __freejsRequest(method, url, opts) {
  var m = method || 'GET';
  if (Object.prototype.hasOwnProperty.call(__pageCache, url)) return JSON.stringify({status: 200, headers: {}, text: __pageCache[url]});
  return __pushPending('http', url, m, {}, null).then(function(t) { return JSON.stringify({status: 200, headers: {}, text: t}); });
}
function __lxRequest(url, opts) {
  if (Object.prototype.hasOwnProperty.call(__pageCache, url)) return JSON.stringify({resp: {status: 200, headers: {}, text: __pageCache[url]}});
  return __pushPending('http', url, 'GET', {}, null).then(function(t) { return JSON.stringify({resp: {status: 200, headers: {}, text: t}}); });
}
function __lxMd5(s) { return __md5(s); }
function __lxRandom(n) {
  var count = n || 16;
  var chars = '0123456789abcdef';
  var out = '';
  for (var i = 0; i < count; i++) out += chars[Math.floor(Math.random() * 16)];
  return out;
}
function __lxMeta() { return JSON.stringify({engine: 'quickjs', version: '2024-01-13'}); }
function __chain(method, url, data) {
  var c = {
    _method: method, _url: url, _data: data || null, _headers: {}, _ok: null, _err: null,
    headers: function(h) { this._headers = h; return this; },
    success: function(f) { this._ok = f; return this; },
    error: function(f) { this._err = f; return this; },
    func: function(f) { this._ok = f; return this; },
    start: function() {
      var self = this;
      var p = fetch(self._url, {method: self._method, headers: self._headers, body: self._data});
      if (typeof p === 'string') { if (self._ok) self._ok(p); }
      else { p.then(function(t) { if (self._ok) self._ok(t); }, function(e) { if (self._err) self._err(e); }); }
      return this;
    }
  };
  return c;
}
globalThis.windows = {
  getItem: function(k, d) { return Object.prototype.hasOwnProperty.call(__storage, k) ? __storage[k] : (d === undefined ? null : d); },
  setItem: function(k, v) { __storage[k] = v; },
  getPublicItem: function(k, d) { return Object.prototype.hasOwnProperty.call(__storagePublic, k) ? __storagePublic[k] : (d === undefined ? null : d); },
  setPublicItem: function(k, v) { __storagePublic[k] = v; },
  storage0: {
    getItem: function(k, d) {
      if (!Object.prototype.hasOwnProperty.call(__storage, k)) {
        if (d === undefined || d === null) return null;
        try { return JSON.parse(d); } catch (e) { return d; }
      }
      try { return JSON.parse(__storage[k]); } catch (e) { return __storage[k]; }
    },
    setItem: function(k, v) { __storage[k] = JSON.stringify(v); },
    getPublicItem: function(k, d) {
      if (!Object.prototype.hasOwnProperty.call(__storagePublic, k)) {
        if (d === undefined || d === null) return null;
        try { return JSON.parse(d); } catch (e) { return d; }
      }
      try { return JSON.parse(__storagePublic[k]); } catch (e) { return __storagePublic[k]; }
    },
    setPublicItem: function(k, v) { __storagePublic[k] = JSON.stringify(v); }
  },
  http: {
    fetch: function(url) { return __chain('GET', url, null); },
    post: function(url, data) { return __chain('POST', url, data); },
    request: function(url) { return __chain('GET', url, null); },
    postRequest: function(url, data) { return __chain('POST', url, data); },
    fetchCookie: function(url) { return __chain('GET', url, null); }
  },
  config: {},
  console: { log: function() { __logs.push(Array.prototype.slice.call(arguments).map(function(a) { return String(a); }).join(' ')); } },
  window0: {}
};
function downloadFile(url, virtualPath, headers) {
  return __pushPending('download', url, 'GET', headers || {}, virtualPath);
}
globalThis.fy_bridge_app = {
  fetch: function(url, json) { return __pushPending('file', getPath(url), 'GET', {}, null); },
  log: function() { __logs.push(Array.prototype.slice.call(arguments).map(function(a) { return String(a); }).join(' ')); }
};
globalThis._base64 = {
  encodeToString: function(input) {
    if (typeof input === 'string') return btoa(unescape(encodeURIComponent(input)));
    var s = '';
    for (var i = 0; i < input.length; i++) s += String.fromCharCode(input[i]);
    return btoa(s);
  },
  decodeToString: function(s) { return decodeURIComponent(escape(atob(s))); }
};
'''
      .replaceAll('__PAGE_CACHE__', pageCacheJson)
      .replaceAll('__STORAGE__', storageJson)
      .replaceAll('__STORAGE_PUBLIC__', storagePublicJson)
      .replaceAll('__FILES_DIR__', filesDirJson);
}

const String md5Js = r'''
function __md5(s) {
  s = unescape(encodeURIComponent(s));
  function rl(n, c) { return (n << c) | (n >>> (32 - c)); }
  function add(x, y) { var l = (x & 0xffff) + (y & 0xffff); var m = (x >> 16) + (y >> 16) + (l >> 16); return (m << 16) | (l & 0xffff); }
  function cmn(q, a, b, x, s, t) { a = add(add(a, q), add(x, t)); return add(rl(a, s), b); }
  function ff(a, b, c, d, x, s, t) { return cmn((b & c) | (~b & d), a, b, x, s, t); }
  function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & ~d), a, b, x, s, t); }
  function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | ~d), a, b, x, s, t); }
  function md5blk(s) {
    var md5blks = [];
    for (var i = 0; i < 64; i += 4) md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
    return md5blks;
  }
  function rhex(n) {
    var s = '';
    for (var j = 0; j < 4; j++) s += ('0' + ((n >> (j * 8 + 4)) & 0x0f).toString(16)).slice(-1) + ('0' + ((n >> (j * 8)) & 0x0f).toString(16)).slice(-1);
    return s;
  }
  function hex(x) { for (var i = 0; i < x.length; i++) x[i] = rhex(x[i]); return x.join(''); }
  function md5cycle(x, k) {
    var a = x[0], b = x[1], c = x[2], d = x[3];
    a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586); c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
    a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426); c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
    a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417); c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
    a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101); c = ff(c, d, a, b, k[14], 17, -1502002290); b = ff(b, c, d, a, k[15], 22, 1236535329);
    a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632); c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
    a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083); c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
    a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690); c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
    a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784); c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
    a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463); c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
    a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353); c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
    a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222); c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
    a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835); c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
    a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415); c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
    a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606); c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
    a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744); c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
    a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379); c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
    x[0] = add(a, x[0]); x[1] = add(b, x[1]); x[2] = add(c, x[2]); x[3] = add(d, x[3]);
  }
  function md51(s) {
    var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i;
    for (i = 64; i <= s.length; i += 64) md5cycle(state, md5blk(s.substring(i - 64, i)));
    s = s.substring(i - 64);
    var tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (i = 0; i < s.length; i++) tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
    tail[i >> 2] |= 0x80 << ((i % 4) << 3);
    if (i > 55) { md5cycle(state, tail); for (i = 0; i < 16; i++) tail[i] = 0; }
    tail[14] = n * 8;
    md5cycle(state, tail);
    return state;
  }
  return hex(md51(s));
}
''';

const String rsaJs = r'''
function __utf8Bytes(s) {
  var u = unescape(encodeURIComponent(s));
  var a = [];
  for (var i = 0; i < u.length; i++) a.push(u.charCodeAt(i));
  return a;
}
function __utf8Decode(a) {
  var s = '';
  for (var i = 0; i < a.length; i++) s += String.fromCharCode(a[i]);
  return decodeURIComponent(escape(s));
}
function __rsaModPow(base, exp, mod) {
  var r = 1n;
  base = base % mod;
  while (exp > 0n) {
    if (exp & 1n) r = (r * base) % mod;
    exp >>= 1n;
    base = (base * base) % mod;
  }
  return r;
}
function __rsaEncrypt(data, nHex, eHex) {
  var n = BigInt('0x' + nHex);
  var e = BigInt('0x' + eHex);
  var k = Math.ceil(n.toString(2).length / 8);
  var mBytes = __utf8Bytes(data);
  if (mBytes.length > k - 11) throw new Error('__lxRsa: data too long');
  var ps = [];
  while (ps.length < k - mBytes.length - 3) ps.push(Math.floor(Math.random() * 255) + 1);
  var em = [0, 2].concat(ps, [0], mBytes);
  var m = BigInt('0x' + em.map(function(x) { return ('0' + x.toString(16)).slice(-2); }).join(''));
  var c = __rsaModPow(m, e, n);
  var h = c.toString(16);
  while (h.length < k * 2) h = '0' + h;
  return h;
}
function __rsaDecrypt(hexData, nHex, dHex) {
  var n = BigInt('0x' + nHex);
  var d = BigInt('0x' + dHex);
  var k = Math.ceil(n.toString(2).length / 8);
  var c = BigInt('0x' + hexData);
  var m = __rsaModPow(c, d, n);
  var h = m.toString(16);
  while (h.length < k * 2) h = '0' + h;
  var bytes = [];
  for (var i = 0; i < h.length; i += 2) bytes.push(parseInt(h.substr(i, 2), 16));
  if (bytes[0] !== 0 || bytes[1] !== 2) throw new Error('__lxRsa: bad padding');
  var idx = bytes.indexOf(0, 2);
  if (idx < 0) throw new Error('__lxRsa: bad padding');
  return __utf8Decode(bytes.slice(idx + 1));
}
function __lxRsa(mode, data, nHex, eHex) {
  if (mode === 'decrypt') return __rsaDecrypt(data, nHex, eHex);
  return __rsaEncrypt(data, nHex, eHex);
}
''';

const String btoaPolyfillJs = r'''
if (typeof btoa === 'undefined') {
  globalThis.btoa = function(str) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    var out = '';
    for (var i = 0; i < str.length; i += 3) {
      var c1 = str.charCodeAt(i);
      var c2 = i + 1 < str.length ? str.charCodeAt(i + 1) : NaN;
      var c3 = i + 2 < str.length ? str.charCodeAt(i + 2) : NaN;
      var e1 = c1 >> 2;
      var e2 = ((c1 & 3) << 4) | (isNaN(c2) ? 0 : (c2 >> 4));
      var e3 = isNaN(c2) ? 64 : ((c2 & 15) << 2) | (isNaN(c3) ? 0 : (c3 >> 6));
      var e4 = isNaN(c3) ? 64 : (c3 & 63);
      out += chars.charAt(e1) + chars.charAt(e2) + chars.charAt(e3) + chars.charAt(e4);
    }
    return out;
  };
}
if (typeof atob === 'undefined') {
  globalThis.atob = function(str) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    var clean = str.replace(/[^A-Za-z0-9+/=]/g, '');
    var out = '';
    for (var i = 0; i < clean.length; i += 4) {
      var e1 = chars.indexOf(clean.charAt(i));
      var e2 = chars.indexOf(clean.charAt(i + 1));
      var e3 = chars.indexOf(clean.charAt(i + 2));
      var e4 = chars.indexOf(clean.charAt(i + 3));
      var b1 = (e1 << 2) | (e2 >> 4);
      var b2 = ((e2 & 15) << 4) | (e3 >> 2);
      var b3 = ((e3 & 3) << 6) | e4;
      out += String.fromCharCode(b1);
      if (e3 !== 64) out += String.fromCharCode(b2);
      if (e4 !== 64) out += String.fromCharCode(b3);
    }
    return out;
  };
}
''';

const String lxAesJs = r'''
function __lxAes(mode, data, key, iv) {
  if (typeof CryptoJS === 'undefined') throw new Error('__lxAes: crypto-js bundle not loaded');
  var k = CryptoJS.enc.Utf8.parse(key || '');
  var v = (iv === undefined || iv === null || iv === '') ? CryptoJS.enc.Hex.parse('00000000000000000000000000000000') : CryptoJS.enc.Utf8.parse(iv);
  if (mode === 'decrypt') {
    return CryptoJS.AES.decrypt(data, k, {iv: v, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7}).toString(CryptoJS.enc.Utf8);
  }
  return CryptoJS.AES.encrypt(data, k, {iv: v, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7}).toString();
}
''';
