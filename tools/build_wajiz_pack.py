"""«الجامع الوجيز في تفسير آي الكتاب العزيز» (Dr. Ayman Fatih Al-Amer) as a
tafsir text pack (the format of tools/fetch_quranenc_extra.py).

Source: the author's repository github.com/yamanamr/quran-tafsir-jami-wajiz
(v1.0, CC BY-ND 4.0), at the commit in COMMIT. Each verse's text is the
record's `tafsir_text` exactly as published; nothing is edited (BY-ND).

  python3 tools/build_wajiz_pack.py fetch DIR   # the files, checked by SHA-256
  python3 tools/build_wajiz_pack.py build DIR OUT.pack.db
"""
import hashlib
import json
import sqlite3
import sys
import urllib.request
from pathlib import Path

REPO = 'yamanamr/quran-tafsir-jami-wajiz'
COMMIT = '9ebcb53f813f538aa0d5ed483d67ac7cc7f67660'
RAW = 'https://raw.githubusercontent.com/%s/%s/' % (REPO, COMMIT)
FILES = {
    'LICENSE': 'cda98e1197c27698339037a42f1a8b9380fee7d11d6163a4df6a8310dae22e77',
    'README.md': '895b94281d3191a536323ad529b4ddc60b3fb26da04abba941b4e9dc51f17ce2',
    'ayah_tafsir_db_surah_001-020.json': 'f4d677cfb1830cc4fed27b86267fcf34b101bd99c6aa7d05471cff31a4a648ba',
    'ayah_tafsir_db_surah_021-060.json': '547b97c85fc02f989b17141223c61f01efd552341685d5594ab78ebf4e62fdde',
    'ayah_tafsir_db_surah_061-114.json': '5ae8534e84b20713bf7c43f38f75d0ed42c00fe9b19cfb6bb6a621f2f3a97897',
}
PACK_ID = 'tafsir-jami-wajiz-v1'


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fetch(out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, want in FILES.items():
        path = out_dir / name
        if not path.exists() or sha256_file(path) != want:
            req = urllib.request.Request(RAW + name, headers={'User-Agent': 'tibyan-tools/0.1'})
            with urllib.request.urlopen(req, timeout=300) as r:
                path.write_bytes(r.read())
        got = sha256_file(path)
        if got != want:
            raise SystemExit('%s: sha256 %s, expected %s' % (name, got, want))
    (out_dir / 'SHA256SUMS').write_text(''.join('%s  %s\n' % (h, n) for n, h in FILES.items()))


def build(src_dir, out):
    src_dir, out = Path(src_dir), Path(out)
    rows = {}
    for name in FILES:
        if not name.endswith('.json'):
            continue
        if sha256_file(src_dir / name) != FILES[name]:
            raise SystemExit('%s changed' % name)
        for r in json.loads((src_dir / name).read_text(encoding='utf-8')):
            key = (int(r['surah_number']), int(r['ayah_number']))
            text = r['tafsir_text']
            if key in rows or not isinstance(text, str) or not text.strip():
                raise SystemExit('bad record %s' % (key,))
            rows[key] = text
    assert len(rows) == 6236, len(rows)
    meta = {
        'format': '1', 'kind': 'tafsir_text', 'source': 'jami_wajiz',
        'key': 'jami-wajiz', 'lang': 'ar', 'direction': 'rtl',
        'title': 'الجامع الوجيز في تفسير آي الكتاب العزيز',
        'author': 'الشيخ الدكتور أيمن فاتح آل عامر', 'version': '1.0',
        'commit': COMMIT, 'license': 'CC BY-ND 4.0',
        'url': 'https://github.com/' + REPO, 'verses': str(len(rows)),
    }
    if out.exists():
        out.unlink()
    db = sqlite3.connect(str(out))
    try:
        db.executescript(
            'CREATE TABLE pack_index (key TEXT PRIMARY KEY, value TEXT NOT NULL);'
            'CREATE TABLE verse (surah INTEGER NOT NULL, ayah INTEGER NOT NULL, '
            'text TEXT NOT NULL, footnotes TEXT, PRIMARY KEY (surah, ayah)) WITHOUT ROWID;')
        db.executemany('INSERT INTO pack_index VALUES (?, ?)', sorted(meta.items()))
        db.executemany('INSERT INTO verse VALUES (?, ?, ?, NULL)',
                       [(s, a, t) for (s, a), t in sorted(rows.items())])
        db.commit()
        db.execute('VACUUM')
    finally:
        db.close()
    print(PACK_ID, sha256_file(out), out.stat().st_size)


if __name__ == '__main__':
    if sys.argv[1:2] == ['fetch']:
        fetch(sys.argv[2])
    elif sys.argv[1:2] == ['build']:
        build(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)
