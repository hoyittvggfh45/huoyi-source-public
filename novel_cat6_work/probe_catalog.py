import importlib.util, json, sys
from pathlib import Path
ROOT = Path('/home/hatch/workspace/huoyi_new/tree_104')
HOST = ROOT / 'android/app/src/main/python/py_spider_host.py'
spec = importlib.util.spec_from_file_location('py_spider_host', HOST)
host = importlib.util.module_from_spec(spec)
sys.modules['py_spider_host'] = host
spec.loader.exec_module(host)
targets = {
 'nnhanman': ['all', 'completed', 'serialized'],
 'jywx2': ['DCCCCD', 'uCCCCD'],
 '55comics': ['hanman', 'riman'],
 'kmh001': ['', 'ongoing', 'complete'],
 'csmanhua': ['8', '9'],
 'kxmanhua': ['0', '2'],
}
for name, cats in targets.items():
    p = str(ROOT / 'assets/novel_spiders' / (name + '.py'))
    for c in cats:
        try:
            raw = host.handle(p, json.dumps({'action': 'catalog', 'category': c, 'page': 1}))
            r = json.loads(raw)
            if r.get('ok'):
                items = r['data'].get('list') or []
                first = items[0].get('vod_name') if items else None
                print(name, repr(c), 'OK n=%d' % len(items), 'first=', first)
            else:
                print(name, repr(c), 'FAIL', (r.get('error') or '')[:200])
        except Exception as e:
            print(name, repr(c), 'EXC', repr(e)[:200])
    host.dispose(p)
