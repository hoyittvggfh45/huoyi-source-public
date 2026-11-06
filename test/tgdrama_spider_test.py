import importlib.util
import json
import re
import sys
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
    check('no Chinese comments', not re.search(r'[\u4e00-\u9fff]', re.sub(r"'[^']*'", '', text)))
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

    tags = spider._parse_tags({'tags': ['短剧', {'name': '国产', 'tag': 'cn'}]})
    check('parse tags', tags == [('短剧', '短剧'), ('cn', '国产')])
    check('parse tags fallback', spider._parse_tags({}) == [('all', '全部')])

    shows = spider._parse_shows({'list': [
        {'id': '1', 'name': '剧A', 'cover_path': '/api/covers/1', 'total': 12},
        {'id': '2', 'name': '剧B', 'cover': 'https://x.example/c.jpg'},
        {'id': '', 'name': '无id'},
        {'id': '3', 'name': ''},
    ]})
    check('parse shows count', len(shows) == 2)
    check('parse shows cover', shows[0]['vod_pic'] == 'http://127.0.0.1:5278/api/covers/1')
    check('parse shows remark', shows[0]['vod_remarks'] == '共12集')
    check('parse shows absolute cover', shows[1]['vod_pic'] == 'https://x.example/c.jpg')

    detail = spider._parse_detail({'show': {
        'name': '剧A', 'cover_path': '/api/covers/1', 'synopsis': '简介',
        'episodes': [
            {'id': 'e2', 'episode_no': 2, 'name': '第二集'},
            {'id': 'e1', 'episode_no': 1},
        ],
    }}, '1')
    check('parse detail', detail is not None and detail['vod_name'] == '剧A')
    check('parse detail episodes sorted',
          [ep[1] for ep in detail['episodes']] == ['e1', 'e2'])
    check('parse detail default title', detail['episodes'][0][2] == '第1集')
    check('parse detail no episodes', spider._parse_detail({'name': '空剧'}, '9') is None)

    play = spider.Spider().playerContent('TG影视库', 'tgdrama:e1')
    check('player url', play['playUrl'] == 'http://127.0.0.1:5278/api/episodes/e1/hls/index.m3u8')
    check('player parse 0', play['parse'] == 0)
    check('player header is dict', isinstance(play['header'], dict))
    check('player direct url', spider.Spider().playerContent('', 'http://127.0.0.1:5278/x.m3u8')['parse'] == 0)
    check('localProxy 404', spider.Spider().localProxy(None)[0] == 404)
    check('isVideoFormat false', spider.Spider().isVideoFormat('http://x/y.m3u8') is False)
    print('ALL PASS')


if __name__ == '__main__':
    main()
