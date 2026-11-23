"""Classical tafsir books from the Quranpedia dumps, as tafsir text packs.

Quranpedia («الموسوعة القرآنية», quranpedia.net) publishes one gzipped JSON
file per tafsir book (`tafsir-book-<id>.json.gz`, schema
/v1/ayah/{surah}/{ayah}/book/{id}) with a manifest that gives each file's
SHA-256. This script:

  fetch    downloads the books in BOOKS (one request every 2 s), checks
           each against the manifest's SHA-256, keeps the files as they are
           and writes SHA256SUMS beside them;
  build    writes one tafsir text pack per book (the format of
           tools/fetch_quranenc_extra.py: pack_index + verse), and
           packs.index.json with each pack's SHA-256 and size;
  dart     writes lib/features/content_extras/tafsir_library_specs.dart
           from packs.index.json.

The text of each verse is the book's passages for that verse exactly as
served (`content[].text`, HTML markup included), joined with a blank line
when there are several. Nothing is edited; the app only strips the markup
when it draws the text.

Runs on Python 3.8 (the mirror server) and later:
  python3 tools/build_quranpedia_tafsir_packs.py fetch DIR
  python3 tools/build_quranpedia_tafsir_packs.py build DIR OUT
  python3 tools/build_quranpedia_tafsir_packs.py dart OUT/packs.index.json
"""
import gzip
import hashlib
import json
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

DUMPS = 'https://quranpedia.net/dumps/'
USER_AGENT = 'TibyanDataFetch/1.0 (+https://altibyan.app)'
PACK_FORMAT = '1'
PACK_URL = 'https://altibyan.app/mirror/packs/tafsir/'

# The classical books chosen (authors who died by 1300 AH), one edition
# each: (Quranpedia book id, the author's death year AH, short name).
# Left out, with the reason, in docs/DATA_SOURCES.md: contemporary works,
# modern compilations, books whose author is not named, second editions,
# books already shipped (al-Muyassar, al-Mukhtasar, al-Jalalayn) and the
# three files over 30 MB (Ruh al-Ma'ani 301, al-Bahr al-Muhit 322,
# Ghara'ib al-Quran 337).
BOOKS = [
    (27755, 150, 'مقاتل بن سليمان'),
    (27758, 161, 'سفيان الثوري'),
    (269, 104, 'مجاهد'),
    (27766, 200, 'يحيى بن سلام'),
    (351, 207, 'الفراء'),
    (348, 209, 'أبو عبيدة'),
    (341, 276, 'ابن قتيبة'),
    (329, 283, 'التستري'),
    (27759, 303, 'النسائي'),
    (4, 310, 'الطبري'),
    (546, 311, 'الزجاج'),
    (295, 318, 'ابن المنذر'),
    (149, 327, 'ابن أبي حاتم'),
    (27760, 330, 'السجستاني'),
    (468, 333, 'الماتريدي'),
    (324, 373, 'السمرقندي'),
    (520, 399, 'ابن أبي زمنين'),
    (313, 427, 'الثعلبي'),
    (367, 437, 'مكي بن أبي طالب'),
    (542, 450, 'الماوردي'),
    (347, 465, 'القشيري'),
    (72, 468, 'الواحدي: الوجيز'),
    (475, 468, 'الواحدي: البسيط'),
    (134, 489, 'السمعاني'),
    (547, 502, 'الراغب الأصفهاني'),
    (2, 516, 'البغوي'),
    (346, 538, 'الزمخشري'),
    (350, 542, 'ابن عطية'),
    (323, 553, 'الغزنوي'),
    (340, 597, 'ابن الجوزي: زاد المسير'),
    (27761, 597, 'ابن الجوزي: تذكرة الأريب'),
    (352, 606, 'الرازي'),
    (108, 660, 'العز بن عبد السلام'),
    (319, 685, 'البيضاوي'),
    (26, 710, 'النسفي'),
    (345, 741, 'ابن جزي'),
    (507, 741, 'الخازن'),
    (27762, 745, 'أبو حيان: النهر الماد'),
    (162, 756, 'السمين الحلبي'),
    (136, 774, 'ابن كثير'),
    (169, 775, 'ابن عادل'),
    (555, 803, 'ابن عرفة'),
    (27784, 815, 'ابن الهائم'),
    (363, 817, 'الفيروزآبادي: تنوير المقباس'),
    (462, 830, 'البسيلي'),
    (339, 875, 'الثعالبي'),
    (168, 885, 'البقاعي'),
    (461, 893, 'الكوراني'),
    (273, 911, 'السيوطي: الدر المنثور'),
    (27763, 923, 'الكازروني'),
    (27786, 926, 'زكريا الأنصاري'),
    (557, 927, 'العليمي'),
    (27787, 977, 'الخطيب الشربيني'),
    (37, 982, 'أبو السعود'),
    (336, 1127, 'إسماعيل حقي'),
    (206, 1224, 'ابن عجيبة'),
    (284, 1225, 'المظهري'),
    (27757, 1241, 'الصاوي'),
    (343, 1250, 'الشوكاني'),
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def fetch(out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_bytes = get(DUMPS + 'manifest.json')
    (out_dir / 'manifest.json').write_bytes(manifest_bytes)
    (out_dir / 'LICENSE.md').write_bytes(get(DUMPS + 'LICENSE.md'))
    (out_dir / 'books.json.gz').write_bytes(get(DUMPS + 'books.json.gz'))
    manifest = json.loads(manifest_bytes)
    files = {f['name']: f for f in manifest['files']}
    for book_id, _, _ in BOOKS:
        name = 'tafsir-book-%d.json.gz' % book_id
        want = files[name]['sha256']
        path = out_dir / name
        if path.exists() and sha256_file(path) == want:
            continue
        path.write_bytes(get(DUMPS + name))
        got = sha256_file(path)
        if got != want:
            raise SystemExit('%s: sha256 %s, manifest says %s' % (name, got, want))
        print('fetched', name, path.stat().st_size, flush=True)
        time.sleep(2)
    names = ['manifest.json', 'LICENSE.md', 'books.json.gz'] + [
        'tafsir-book-%d.json.gz' % b for b, _, _ in BOOKS]
    (out_dir / 'SHA256SUMS').write_text(''.join(
        '%s  %s\n' % (sha256_file(out_dir / n), n) for n in names))
    print('version', manifest['version'])


def verses(payload):
    """(surah, ayah, text) for each verse with text, passages joined."""
    rows = {}
    for a in payload['ayahs']:
        texts = [c['text'] for c in a.get('content') or []
                 if isinstance(c.get('text'), str) and c['text'].strip()]
        if not texts:
            continue
        key = (int(a['surah']), int(a['ayah']))
        if key in rows:
            raise ValueError('verse %s twice' % (key,))
        rows[key] = '\n\n'.join(texts)
    return [(s, a, t) for (s, a), t in sorted(rows.items())]


def build(src_dir, out_dir):
    src_dir, out_dir = Path(src_dir), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((src_dir / 'manifest.json').read_text(encoding='utf-8'))
    files = {f['name']: f for f in manifest['files']}
    index = []
    for book_id, died, short in BOOKS:
        name = 'tafsir-book-%d.json.gz' % book_id
        src = src_dir / name
        with gzip.open(src) as f:
            payload = json.load(f)
        book = payload['book']
        rows = verses(payload)
        author = (book.get('author') or {}).get('full_name') or ''
        version = payload['license'].get('version') or manifest['version']
        meta = {
            'format': PACK_FORMAT, 'kind': 'tafsir_text', 'source': 'quranpedia',
            'key': 'quranpedia-%d' % book_id, 'lang': 'ar', 'direction': 'rtl',
            'markup': 'html', 'title': book['name'], 'author': author,
            'author_short': short, 'died_ah': str(died),
            'edition': book.get('edition') or '', 'publisher': book.get('nasher') or '',
            'tahqiq': book.get('mohaqeq') or '',
            'url': 'https://quranpedia.net/book/%d' % book_id,
            'dump': DUMPS + name, 'dump_sha256': sha256_file(src),
            'dump_built_at': files[name]['built_at'],
            'version': version, 'verses': str(len(rows)),
        }
        pack_id = 'tafsir-qp-%d' % book_id
        out = out_dir / (pack_id + '.pack.db')
        if out.exists():
            out.unlink()
        db = sqlite3.connect(str(out))
        try:
            db.executescript(
                'CREATE TABLE pack_index (key TEXT PRIMARY KEY, value TEXT NOT NULL);'
                'CREATE TABLE verse (surah INTEGER NOT NULL, ayah INTEGER NOT NULL, '
                'text TEXT NOT NULL, footnotes TEXT, PRIMARY KEY (surah, ayah)) WITHOUT ROWID;')
            db.executemany('INSERT INTO pack_index VALUES (?, ?)', sorted(meta.items()))
            db.executemany('INSERT INTO verse VALUES (?, ?, ?, NULL)', rows)
            db.commit()
            db.execute('VACUUM')
        finally:
            db.close()
        entry = dict(meta, id=pack_id, file=out.name,
                     pack_sha256=sha256_file(out), bytes=out.stat().st_size)
        index.append(entry)
        print(pack_id, len(rows), entry['bytes'], flush=True)
    (out_dir / 'packs.index.json').write_text(
        json.dumps({'manifest_version': manifest['version'], 'packs': index},
                   ensure_ascii=False, indent=1), encoding='utf-8')
    (out_dir / 'SHA256SUMS').write_text(''.join(
        '%s  %s\n' % (p['pack_sha256'], p['file']) for p in index))


def dart_string(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


# Ahmed's rule (2026-11-23): the library lists only books that cover at
# least 90% of the Quran (5613 of 6236 verses); the others stay on the
# mirror but are not offered (docs/DATA_SOURCES.md).
MIN_VERSES = 5301

# Kept below the rule, by Ahmed's choice: al-Tustari (4492) and al-Durr
# al-Manthur (4427).
LOW_COVERAGE_ALLOWED = {'tafsir-qp-329', 'tafsir-qp-273'}


def dart(index_path):
    index = json.loads(Path(index_path).read_text(encoding='utf-8'))
    lines = [
        '// GENERATED by tools/build_quranpedia_tafsir_packs.py dart: do not edit.',
        '//',
        '// Classical tafsir books from the Quranpedia dumps (version %s),'
        % index['manifest_version'],
        '// each a tafsir text pack on Tibyan\'s mirror (docs/DATA_SOURCES.md).',
        '',
        "import 'english_tafsir.dart';",
        '',
        'const quranpediaTafsirPacks = <TafsirTextPackSpec>[',
    ]
    for p in index['packs']:
        if int(p['verses']) < MIN_VERSES and p['id'] not in LOW_COVERAGE_ALLOWED:
            continue
        lines += [
            '  TafsirTextPackSpec(',
            '    id: %s,' % dart_string(p['id']),
            "    url: '%s%s'," % (PACK_URL, p['file']),
            "    sha256: '%s'," % p['pack_sha256'],
            '    bytes: %d,' % p['bytes'],
            '    title: %s,' % dart_string(p['title']),
            '    author: %s,' % dart_string(p['author_short']),
            '    diedAh: %s,' % p['died_ah'],
            '    verses: %s,' % p['verses'],
            '  ),',
        ]
    lines += ['];', '']
    out = Path(__file__).resolve().parents[1] / 'lib/features/content_extras/tafsir_library_specs.dart'
    out.write_text('\n'.join(lines), encoding='utf-8')
    print('wrote', out)


if __name__ == '__main__':
    cmd = sys.argv[1:2]
    if cmd == ['fetch']:
        fetch(sys.argv[2])
    elif cmd == ['build']:
        build(sys.argv[2], sys.argv[3])
    elif cmd == ['dart']:
        dart(sys.argv[2])
    else:
        raise SystemExit(__doc__)
