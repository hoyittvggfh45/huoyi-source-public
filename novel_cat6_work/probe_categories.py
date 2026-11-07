import importlib.util, json, sys
from pathlib import Path
ROOT = Path('/home/hatch/workspace/huoyi_new/tree_104')
HOST = ROOT / 'android/app/src/main/python/py_spider_host.py'
spec = importlib.util.spec_from_file_location('py_spider_host', HOST)
host = importlib.util.module_from_spec(spec)
sys.modules['py_spider_host'] = host
spec.loader.exec_module(host)
for name in ['nnhanman', 'jywx2', '55comics', 'kmh001', 'csmanhua', 'kxmanhua']:
    p = str(ROOT / 'assets/novel_spiders' / (name + '.py'))
    try:
        raw = host.handle(p, json.dumps({'action': 'categories'}))
        r = json.loads(raw)
        if r.get('ok'):
            cls = r['data'].get('class') or []
            print(name, 'OK classes=%d' % len(cls), [(c.get('type_id'), c.get('type_name')) for c in cls][:20])
        else:
            print(name, 'FAIL', r.get('error'))
    except Exception as e:
        print(name, 'EXC', repr(e))
