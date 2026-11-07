import ast
import importlib.util
import io
import json
import re
import sys
import tokenize
from pathlib import Path

SPIDER_PATH = Path(__file__).resolve().parent.parent / 'assets' / 'py_spiders' / 'tgdrama.py'


def load_spider():
    spec = importlib.util.spec_from_file_location('tgdrama_spider', SPIDER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(name, cond):
    print(('PASS ' if cond else 'FAIL ') + name)
    if not cond:
        sys.exit(1)


def main():
    text = SPIDER_PATH.read_text(encoding='utf-8')
    kept = []
    for tok in tokenize.generate_tokens(io.StringIO(text).readline):
        if tok.type != tokenize.STRING:
            kept.append(tok.string)
    check('no Chinese comments', not re.search(r'[\u4e00-\u9fff]', ''.join(kept)))
    check('no hash comments', not any(line.strip().startswith('#') for line in text.splitlines()))
    check('no RE header', 'RE_' not in text)
    tree = ast.parse(text)
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef)):
            if node.body and isinstance(node.body[0], ast.Expr):
                value = node.body[0].value
                check('no docstring', not (isinstance(value, ast.Constant) and isinstance(value.value, str)))
    spider = load_spider()
    methods = [
        'getName', 'getDependence', 'init', 'destroy', 'homeContent',
        'homeVideoContent', 'categoryContent', 'detailContent',
        'searchContent', 'playerContent', 'localProxy', 'isVideoFormat',
        'manualVideoCheck', 'action',
    ]
    for method in methods:
        check('method ' + method, callable(getattr(spider.Spider, method, None)))
    check('name is tgdrama', spider.Spider().getName() == 'tgdrama')

    tags = spider._parse_tags([{'name': '测试', 'count': 2}, '短剧'])
    check('parse tags', tags == [('测试', 2), ('短剧', 0)])
    check('parse tags dict', spider._parse_tags({'tags': [{'name': '国产', 'count': 1}]}) == [('国产', 1)])
    check('parse tags empty', spider._parse_tags({}) == [])

    base = 'http://127.0.0.1:5278'
    show = spider.TgdramaMapper.show_vod(
        {'id': '1', 'name': '剧A', 'cover_path': '/api/covers/1', 'ep_count': 12}, base)
    check('show vod name', show['vod_name'] == '剧A')
    check('show vod cover', show['vod_pic'] == base + '/api/covers/1')
    check('show vod remark', show['vod_remarks'] == '共12集')
    show2 = spider.TgdramaMapper.show_vod(
        {'id': '2', 'name': '剧B', 'cover_path': '', 'ep_latest': 5}, base)
    check('show vod no cover', show2['vod_pic'] == '')
    check('show vod latest remark', show2['vod_remarks'] == '更新至5集')

    pack = spider.TgdramaMapper.pack('show', {'id': 2})
    ref = spider.TgdramaMapper.unpack(pack)
    check('pack round trip', ref == {'kind': 'show', 'data': {'id': 2}})
    ep_pack = spider.TgdramaMapper.pack('ep', {'id': 4})
    check('pack ep kind', spider.TgdramaMapper.unpack(ep_pack)['kind'] == 'ep')
    check('unpack bad', spider.TgdramaMapper.unpack('plain-id') is None)

    detail = spider.Spider()._build_detail({'show': {
        'id': 2, 'name': '剧A', 'cover_path': '/api/covers/1', 'intro': '简介',
        'ep_latest': 2,
    }, 'episodes': [
        {'id': 'e2', 'episode_no': 2, 'title': '第二集'},
        {'id': 'e1', 'episode_no': 1},
    ], 'progress': []}, None)
    check('build detail', detail is not None and detail['vod_name'] == '剧A')
    tokens = detail['vod_play_url'].split('#')
    order = [spider.TgdramaMapper.unpack(token.split('$', 1)[1])['data']['id'] for token in tokens]
    check('build detail episodes sorted', order == ['e1', 'e2'])
    check('build detail default title', '第1集' in detail['vod_play_url'])
    check('build detail no episodes',
          spider.Spider()._build_detail({'show': {'id': 9, 'name': '空剧'}, 'episodes': []}, None) is None)

    check('hardcoded count', len(spider.HARDCODED_CHANNELS) == 52)
    check('hardcoded unique', len({row[0] for row in spider.HARDCODED_CHANNELS}) == 52)
    check('hardcoded full id', spider.Spider._full_tg_id(2753266064) == -1002753266064)
    row = spider.Spider._hardcoded_row('jav_all')
    check('hardcoded row', row is not None and row['name'] == '日本精品av|中文字幕|Jav')
    bare = spider.Spider._hardcoded_row('2753266064')
    check('hardcoded row bare id', bare is not None and bare['name'] == '日本精品av|中文字幕|Jav')

    dead = spider.Spider()
    dead.init(json.dumps({'base_url': 'http://127.0.0.1:9'}))
    ids = [entry['type_id'] for entry in dead.homeContent(False)['class']]
    check('offline hardcoded classes', len(ids) == 58)
    check('offline hardcoded first', ids[0] == 'jav_all')
    check('offline hardcoded bare ids', '3761040325' in ids)
    page = dead.categoryContent('jav_all', 1)
    check('offline service down page honest',
          len(page['list']) == 1 and page['list'][0]['vod_name'] == 'TG影视库服务未启动')
    play = dead.playerContent('TG影视库', ep_pack)
    check('player parse 0', play['parse'] == 0)
    check('player header is dict', isinstance(play['header'], dict))
    check('player offline empty', play['url'] == '')
    check('localProxy 404', spider.Spider().localProxy(None)[0] == 404)
    check('isVideoFormat stream', spider.Spider().isVideoFormat('http://127.0.0.1:5278/api/stream/4') is True)
    check('isVideoFormat false', spider.Spider().isVideoFormat('http://x/page') is False)
    print('ALL PASS')


if __name__ == '__main__':
    main()
