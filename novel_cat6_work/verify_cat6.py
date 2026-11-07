import importlib.util, json, sys
from pathlib import Path
ROOT = Path('/home/hatch/workspace/huoyi_new/tree_104')
SP = ROOT / 'assets/novel_spiders'
WORK = ROOT / 'novel_cat6_work'
HOST = ROOT / 'android/app/src/main/python/py_spider_host.py'
spec = importlib.util.spec_from_file_location('py_spider_host', HOST)
host = importlib.util.module_from_spec(spec)
sys.modules['py_spider_host'] = host
spec.loader.exec_module(host)
fails = []
def check(cond, label):
    print(('PASS ' if cond else 'FAIL ') + label)
    if not cond:
        fails.append(label)

for name in ['nnhanman', 'jywx2', '55comics', 'kmh001', 'csmanhua', 'kxmanhua']:
    p = str(SP / (name + '.py'))
    ping = json.loads(host.handle(p, json.dumps({'action': 'ping'})))
    check(ping.get('ok') and ping['data'].get('name', '').startswith('\U0001f51e'), name + ' ping name has 18+ prefix: ' + str(ping.get('data', {}).get('name')))
    cats = json.loads(host.handle(p, json.dumps({'action': 'categories'})))
    cls = cats['data'].get('class') if cats.get('ok') else []
    ids = [c.get('type_id') for c in cls]
    check(cats.get('ok') and len(cls) > 0 and all(i for i in ids), name + ' categories=%d ids=%s' % (len(cls), ids))
    host.dispose(p)

def load_mod(name):
    s = importlib.util.spec_from_file_location(name, SP / (name + '.py'))
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    return m

kx = load_mod('kxmanhua')
lib_html = (WORK / 'kx_library.html').read_text(encoding='utf-8', errors='ignore')
items = kx._parse_list(lib_html)
check(len(items) == 24, 'kx list n=24 got %d' % len(items))
check(all(i['vod_pic'].startswith('https://img.imh99.top/webtoon/cover-image/') for i in items), 'kx list all 24 have cover-image pic, first=%s' % (items[0]['vod_pic'] if items else ''))
check(items[0]['vod_id'] == '3915' and items[0]['vod_name'] == '[3D]奸魔再世', 'kx list first id/name ok')
kx._fetch_orig = kx._fetch
kx._fetch = lambda url: (WORK / 'kx_detail.html').read_text(encoding='utf-8', errors='ignore')
d = kx.Spider().detailContent(['3915'])['list'][0]
check(d['vod_pic'] == 'https://img.imh99.top/webtoon/cover-image/2240_1749691562992.webp', 'kx detail cover=%s' % d['vod_pic'])
check(d['vod_name'].startswith('3D'), 'kx detail name=%s' % d['vod_name'])
kx._fetch = kx._fetch_orig

km = load_mod('kmh001')
api_json = json.dumps({'current': 1, 'total': 991, 'isEnd': False, 'records': [
    {'_id': '6aee4146889b396622bf6447', 'name': '优质女孩', 'cover': 'https://thumb-g1.toomics.com/upload/thumbnail/20251113121902/2026_01_06_17676681333506.jpg', 'lastChapter': {'subtitle': '第8话'}},
    {'_id': '6a7f43ea5a9ef7f6dacc5e7e', 'name': '衣冠禽兽', 'cover': 'https://img.kmh.pics/6KGj5Yag56a95YW9LWNvdmVy.jpg', 'lastChapter': {'subtitle': '第19话'}},
]}, ensure_ascii=False)
seen_urls = []
def fake_fetch(url):
    seen_urls.append(url)
    return api_json
km._fetch = fake_fetch
sp = km.Spider()
res = sp.categoryContent('all', 1)
check(len(res['list']) == 2 and all(i['vod_pic'].startswith('http') for i in res['list']), 'kmh001 all -> 2 items with covers: %s' % [(i['vod_name'], bool(i['vod_pic'])) for i in res['list']])
check('status=&' in seen_urls[0] or 'status=' in seen_urls[0] and 'status=all' not in seen_urls[0], 'kmh001 all maps to empty status, url=%s' % seen_urls[0])
res2 = sp.categoryContent('ongoing', 1)
check('status=ongoing' in seen_urls[1], 'kmh001 ongoing keeps status, url=%s' % seen_urls[1])
res3 = sp.categoryContent('', 1)
check('status=&' in seen_urls[2], 'kmh001 empty tid still works, url=%s' % seen_urls[2])

print('FAILURES: %d' % len(fails))
for f in fails:
    print(' - ' + f)
sys.exit(1 if fails else 0)
