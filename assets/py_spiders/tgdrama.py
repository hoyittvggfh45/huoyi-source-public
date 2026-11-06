import json
import urllib.parse
import urllib.request

try:
    from base.spider import BaseSpider
except Exception:
    try:
        from base import BaseSpider
    except Exception:
        class BaseSpider:
            pass

BASE = 'http://127.0.0.1:5278'


def _http_json(path, params=None, timeout=10):
    url = BASE + path
    if params:
        url += '?' + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={'Accept': 'application/json'})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status != 200:
                return None
            return json.loads(resp.read().decode('utf-8', 'replace'))
    except Exception:
        return None


def _str(value):
    if value is None:
        return ''
    return str(value).strip()


def _int(value):
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    try:
        return int(str(value).strip())
    except Exception:
        return 0


def _as_map(value):
    if isinstance(value, dict):
        return value
    return {}


def _cover_of(node):
    raw = _str(node.get('cover_path') or node.get('cover') or node.get('poster'))
    if not raw:
        return ''
    if raw.startswith('http://') or raw.startswith('https://'):
        return raw
    if raw.startswith('/'):
        return BASE + raw
    return BASE + '/' + raw


def _remark_of(node):
    count = _int(node.get('total'))
    if count <= 0:
        count = _int(node.get('episode_count'))
    if count <= 0:
        eps = node.get('episodes')
        if isinstance(eps, list):
            count = len(eps)
    return '共%d集' % count if count > 0 else ''


def _parse_tags(decoded):
    rows = decoded
    if isinstance(rows, dict):
        for key in ('tags', 'list', 'data', 'items'):
            if isinstance(rows.get(key), list):
                rows = rows[key]
                break
    if not isinstance(rows, list):
        return [('all', '全部')]
    seen = set()
    out = []
    for entry in rows:
        if isinstance(entry, str):
            tag_id = entry.strip()
            name = tag_id
        else:
            node = _as_map(entry)
            name = _str(node.get('name') or node.get('tag') or node.get('title') or node.get('label'))
            tag_id = _str(node.get('tag') or node.get('name') or node.get('id'))
            if not name:
                name = tag_id
        if not tag_id or not name or tag_id in seen:
            continue
        seen.add(tag_id)
        out.append((tag_id, name))
    return out if out else [('all', '全部')]


def _show_rows(decoded):
    if isinstance(decoded, list):
        return decoded
    if not isinstance(decoded, dict):
        return []
    for key in ('list', 'shows', 'items'):
        if isinstance(decoded.get(key), list):
            return decoded[key]
    data = _as_map(decoded.get('data'))
    for key in ('list', 'shows', 'items'):
        if isinstance(data.get(key), list):
            return data[key]
    return []


def _parse_shows(decoded):
    out = []
    seen = set()
    for entry in _show_rows(decoded):
        node = _as_map(entry)
        show_id = _str(node.get('id') or node.get('show_id'))
        if not show_id or show_id in seen:
            continue
        title = _str(node.get('name') or node.get('title'))
        if not title:
            continue
        seen.add(show_id)
        out.append({
            'vod_id': show_id,
            'vod_name': title,
            'vod_pic': _cover_of(node),
            'vod_remarks': _remark_of(node),
        })
    return out


def _parse_episodes(raw, series_id):
    if not isinstance(raw, list):
        return []
    indexed = []
    for i, entry in enumerate(raw):
        node = _as_map(entry)
        ep_id = _str(node.get('id') or node.get('episode_id'))
        if not ep_id:
            continue
        number = _int(node.get('episode_no') or node.get('episodeNo'))
        if number <= 0:
            number = i + 1
        name = _str(node.get('name') or node.get('title'))
        indexed.append((number, ep_id, name if name else '第%d集' % number))
    indexed.sort(key=lambda item: item[0])
    return indexed


def _parse_detail(decoded, series_id):
    node = _as_map(decoded)
    for key in ('show', 'data'):
        inner = _as_map(node.get(key))
        if inner and (isinstance(inner.get('episodes'), list) or inner.get('name') is not None or inner.get('title') is not None):
            node = inner
            break
    episodes = _parse_episodes(node.get('episodes'), series_id)
    if not episodes:
        return None
    return {
        'vod_id': series_id,
        'vod_name': _str(node.get('name') or node.get('title')),
        'vod_pic': _cover_of(node),
        'vod_content': _str(node.get('synopsis') or node.get('description') or node.get('introduction')),
        'type_name': '',
        'episodes': episodes,
    }


def _norm_id(ids):
    if isinstance(ids, (list, tuple)):
        return str(ids[0]) if ids else ''
    return str(ids)


def _norm_pg(pg):
    try:
        return int(pg)
    except Exception:
        try:
            return int(str(pg).strip())
        except Exception:
            return 1


class Spider(BaseSpider):

    def getName(self):
        return 'tgdrama'

    def getDependence(self):
        return []

    def init(self, extend=None):
        pass

    def destroy(self):
        pass

    def homeContent(self, filter=False):
        tags = _parse_tags(_http_json('/api/tags'))
        return {'class': [{'type_id': tid, 'type_name': name} for tid, name in tags], 'filters': {}}

    def homeVideoContent(self):
        items = _parse_shows(_http_json('/api/shows', {'page': 1}))
        return {'list': items, 'page': 1, 'pagecount': 0, 'total': 0}

    def categoryContent(self, tid, pg, filter=False, extend=None):
        tid = _norm_id(tid)
        pg = _norm_pg(pg)
        if pg < 1:
            pg = 1
        params = {'page': pg}
        if tid and tid != 'all':
            params['tag'] = tid
        items = _parse_shows(_http_json('/api/shows', params))
        return {'list': items, 'page': pg, 'pagecount': 0, 'total': 0}

    def detailContent(self, ids):
        vid = _norm_id(ids)
        d = _parse_detail(_http_json('/api/shows/' + urllib.parse.quote(vid)), vid)
        if d is None:
            raise Exception('show has no episodes')
        play_url = '#'.join('%s$tgdrama:%s' % (title, ep_id) for _, ep_id, title in d['episodes'])
        return {'list': [{
            'vod_id': vid,
            'vod_name': d['vod_name'] or ('剧集 ' + vid),
            'vod_pic': d['vod_pic'],
            'vod_actor': '',
            'vod_remarks': '',
            'vod_year': '',
            'vod_area': '',
            'vod_content': d['vod_content'],
            'type_name': d['type_name'],
            'vod_play_from': 'TG影视库',
            'vod_play_url': play_url,
        }]}

    def searchContent(self, key, quick=False, pg=1):
        pg = _norm_pg(pg)
        if pg < 1:
            pg = 1
        items = _parse_shows(_http_json('/api/search', {'q': str(key).strip()}))
        return {'list': items, 'page': pg, 'pagecount': 0, 'total': 0}

    def playerContent(self, flag, id, vipFlags=None):
        raw = str(id or '')
        if '$' in raw:
            raw = raw.split('$', 1)[1]
        if raw.startswith('tgdrama:'):
            raw = raw.split(':', 1)[1].strip()
        if raw.startswith('http'):
            return {'parse': 0, 'playUrl': raw, 'url': raw, 'header': {}}
        if not raw:
            return {'parse': 0, 'playUrl': '', 'url': '', 'header': {}}
        url = BASE + '/api/episodes/' + urllib.parse.quote(raw) + '/hls/index.m3u8'
        return {'parse': 0, 'playUrl': url, 'url': url, 'header': {}}

    def localProxy(self, param):
        return [404, 'text/plain', b'', {}]

    def isVideoFormat(self, url):
        return False

    def manualVideoCheck(self):
        return True

    def action(self, action, params=None):
        return {'code': 0, 'msg': 'ok'}
