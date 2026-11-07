import importlib.util, json, sys
from pathlib import Path
ROOT = Path('/home/hatch/workspace/huoyi_new/tree_104')
OUT = ROOT / 'novel_cat6_work' / 'probe_live.log'
HOST = ROOT / 'android/app/src/main/python/py_spider_host.py'
spec = importlib.util.spec_from_file_location('py_spider_host', HOST)
host = importlib.util.module_from_spec(spec)
sys.modules['py_spider_host'] = host
spec.loader.exec_module(host)
def log(s):
    with open(OUT, 'a', encoding='utf-8') as f:
        f.write(s + '\n')
    print(s, flush=True)
targets = {
 'nnhanman': ['all', 'completed'],
 'jywx2': ['DCCCCD', 'uCCCCD'],
 '55comics': ['hanman', 'riman'],
 'kxmanhua': ['0', '2'],
}
import sys
only = sys.argv[1:] or list(targets)
for name in only:
    cats = targets[name]
    p = str(ROOT / 'assets/novel_spiders' / (name + '.py'))
    for c in cats:
        try:
            raw = host.handle(p, json.dumps({'action': 'catalog', 'category': c, 'page': 1}))
            r = json.loads(raw)
            if r.get('ok'):
                items = r['data'].get('list') or []
                first = items[0] if items else None
                log('%s [%s] OK n=%d first_name=%s first_pic=%s first_id=%s' % (name, c, len(items), (first or {}).get('vod_name'), bool((first or {}).get('vod_pic')), (first or {}).get('vod_id')))
                if first:
                    try:
                        raw2 = host.handle(p, json.dumps({'action': 'detail', 'vodId': first.get('vod_id')}))
                        r2 = json.loads(raw2)
                        if r2.get('ok'):
                            d = (r2['data'].get('list') or [{}])[0]
                            log('%s [%s] DETAIL name=%s pic=%s play_from=%s' % (name, c, d.get('vod_name'), bool(d.get('vod_pic')), (d.get('vod_play_from') or '')[:40]))
                        else:
                            log('%s [%s] DETAIL FAIL %s' % (name, c, (r2.get('error') or '')[:150]))
                    except Exception as e:
                        log('%s [%s] DETAIL EXC %r' % (name, c, e))
            else:
                log('%s [%s] FAIL %s' % (name, c, (r.get('error') or '')[:200]))
        except Exception as e:
            log('%s [%s] EXC %r' % (name, c, e))
    host.dispose(p)
log('DONE ' + ' '.join(only))
