# -*- coding: utf-8 -*-
"""PPT 全库提取器：E:\\赞美诗\\赞美诗--投影\\*.ppt → hymn_ppt / hymn_ppt_line。
用法：python tools/extract_ppt.py [--apply]
默认 dry-run 输出 tools/_ppt_extract_report.json + 控制台摘要；--apply 时先备份 DB 再写库。
解析规则（2026-09-21 取证定案）：
  - 文本原子 0x0FA0/0x0FA8，payload 按 UTF-16LE 解码（失败回退 GBK）；
  - 跳过母版占位原子（含"单击此处编辑"或长度<100）；
  - 页内行序：[头行(仅首页: 编号、标题、调号、拍号、速度)] + (简谱行, 歌词行)* + 页码行 N/M；
  - 简谱行 = 纯 ASCII 可打印且含数字/谱符；歌词行 = 含 CJK；页码行 = ^\\d+/\\d+$；
  - 简谱字符必须 ⊆ 简谱字体 cmap（94 码位），否则记 unknown_chars 警告。
"""
import struct, os, re, sys, json, sqlite3, shutil, time, io, zlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PPT_DIR = r'E:\赞美诗\赞美诗--投影'
FONT = r'C:\Users\小蔡爱金雪\Downloads\简谱字体\简谱字体.ttf'
DB = r'e:\EchoHymn\data\tjc_hymn.db'
REPORT = r'e:\EchoHymn\tools\_ppt_extract_report.json'
APPLY = '--apply' in sys.argv

def font_cmap(path):
    data = open(path, 'rb').read()
    n = struct.unpack('>H', data[4:6])[0]
    tables = {}
    for i in range(n):
        off = 12 + 16 * i
        tag = data[off:off+4].decode('latin1')
        toff, tlen = struct.unpack('>II', data[off+8:off+16])
        tables[tag] = toff
    toff = tables['cmap']
    ver, cnt = struct.unpack('>HH', data[toff:toff+4])
    best = {}
    for i in range(cnt):
        pid, eid, off = struct.unpack('>HHI', data[toff+4+8*i:toff+12+8*i])
        sub = toff + off
        fmt = struct.unpack('>H', data[sub:sub+2])[0]
        if fmt != 4:
            continue
        b = data[sub:]
        segX2 = struct.unpack('>H', b[6:8])[0]; seg = segX2 // 2
        ends = struct.unpack('>%dH' % seg, b[14:14+segX2])
        so = 16 + segX2
        starts = struct.unpack('>%dH' % seg, b[so:so+segX2])
        do = so + segX2
        deltas = struct.unpack('>%dh' % seg, b[do:do+segX2])
        ro = do + segX2
        ranges = struct.unpack('>%dH' % seg, b[ro:ro+segX2])
        m = {}
        for k in range(seg):
            for c in range(starts[k], ends[k]+1):
                if ranges[k] == 0:
                    g = (c + deltas[k]) & 0xFFFF
                else:
                    gi = ro + 2*k + ranges[k] + 2*(c - starts[k])
                    g = struct.unpack('>H', b[gi:gi+2])[0]
                    if g:
                        g = (g + deltas[k]) & 0xFFFF
                if g:
                    m[c] = g
        if len(m) > len(best):
            best = m
    return set(best)

ALLOWED = font_cmap(FONT)
PAGE_RE = re.compile(r'^\s*(\d+)\s*/\s*(\d+)\s*$')
CJK_RE = re.compile('[\u3000-\u30ff\u4e00-\u9fff\uff00-\uffef]')
SCORE_RE = re.compile(r'^[ -~]*$')

def decomp_chunks(c):
    """MS-PPT CompressionContainer 内容：4 字节头 + 若干 2 字节块头 chunk。"""
    out = bytearray()
    pos = 4
    while pos + 2 <= len(c):
        hdr = struct.unpack('<H', c[pos:pos+2])[0]
        size = (hdr & 0x0FFF) + 3
        flag = hdr >> 15
        chunk = c[pos+2:pos+2+size]
        if flag:
            try:
                out += zlib.decompressobj(-15).decompress(chunk)
            except Exception:
                out += chunk
        else:
            out += chunk
        pos += 2 + size
    return bytes(out)

def walk(data, out):
    """正规记录树遍历：容器递归、0x0FBA 解压后递归、文本原子收集。"""
    i = 0
    n = len(data)
    while i + 8 <= n:
        vi, rt, rl = struct.unpack('<HHI', data[i:i+8])
        ver = vi & 0xF
        if rl > n - i - 8:
            break
        body = data[i+8:i+8+rl]
        if rt == 0x0FBA and ver == 0xF:
            walk(decomp_chunks(body), out)
        elif ver == 0xF:
            walk(body, out)
        elif rt in (0x0FA0, 0x0FA8):
            out.append(body)
        i += 8 + rl
    return out

def read_ppt_stream(path):
    """迷你 CFB 读取器：提取 'PowerPoint Document' 流。"""
    d = open(path, 'rb').read()
    ss = 1 << struct.unpack('<H', d[30:32])[0]
    ms = 1 << struct.unpack('<H', d[32:34])[0]
    nfat = struct.unpack('<I', d[44:48])[0]
    dir0 = struct.unpack('<I', d[48:52])[0]
    cutoff = struct.unpack('<I', d[56:60])[0]
    mfat0 = struct.unpack('<I', d[60:64])[0]
    difat = list(struct.unpack('<109I', d[76:76+436]))
    ndif = struct.unpack('<I', d[72:76])[0]
    pos = 76 + 436
    for _ in range(ndif):
        sec = struct.unpack('<I', d[pos:pos+4])[0]; pos += 4
        if sec < 0xFFFFFFFE:
            blk = d[512+sec*ss:512+sec*ss+ss]
            difat += list(struct.unpack('<%dI' % (ss//4), blk))
    fat = []
    for sec in difat[:nfat]:
        if sec < 0xFFFFFFFE:
            fat += list(struct.unpack('<%dI' % (ss//4), d[512+sec*ss:512+sec*ss+ss]))
    def chain(start):
        out, cur = [], start
        while cur < 0xFFFFFFFE and len(out) < 100000:
            out.append(cur)
            cur = fat[cur] if cur < len(fat) else 0xFFFFFFFE
        return out
    def secdata(sec):
        return d[512+sec*ss:512+sec*ss+ss]
    dirents = b''.join(secdata(s) for s in chain(dir0))
    entries = []
    for i in range(len(dirents)//128):
        e = dirents[i*128:(i+1)*128]
        nlen = struct.unpack('<H', e[64:66])[0]
        name = e[:max(0, nlen-2)].decode('utf-16-le', 'replace')
        etype = e[66]
        start = struct.unpack('<I', e[116:120])[0]
        size = struct.unpack('<Q', e[120:128])[0]
        entries.append((name, etype, start, size))
    root = [e for e in entries if e[1] == 5]
    mini = b''
    mfat = []
    if root:
        mini = b''.join(secdata(s) for s in chain(root[0][2]))
        mfat = []
        for s in chain(mfat0):
            mfat += list(struct.unpack('<%dI' % (ss//4), secdata(s)))
    def minichain(start):
        out, cur = [], start
        while cur < 0xFFFFFFFE and len(out) < 100000:
            out.append(cur)
            cur = mfat[cur] if cur < len(mfat) else 0xFFFFFFFE
        return out
    def miniread(start, size):
        buf = bytearray()
        for s in minichain(start):
            buf += mini[s*ms:s*ms+ms]
        return bytes(buf[:size])
    for name, etype, start, size in entries:
        if name == 'PowerPoint Document':
            if size < cutoff:
                return miniread(start, size)
            return b''.join(secdata(s) for s in chain(start))[:size]
    return b''

def atoms(path):
    return walk(read_ppt_stream(path), [])

NORM = {'︱': '\\', '｜': '|', '‖': '?', '︲': '|',
        '–': '/', '—': '/', '―': '/', '‐': '-', '−': '-'}
def norm_line(ln):
    for k, v in NORM.items():
        ln = ln.replace(k, v)
    return ln


def decode(payload):
    u = payload.decode('utf-16-le', 'replace')
    if u.count('\ufffd') <= len(u) // 20:
        return u
    return payload.decode('gbk', 'replace')

def map_name(b):
    b = b.lower()
    if b[-1].isalpha():
        return str(int(b[:-1])) + '_' + b[-1]
    return str(int(b))

report = {'hymns': {}, 'warnings': [], 'unknown_chars': {}}
total_slides = total_pairs = 0

for fn in sorted(os.listdir(PPT_DIR)):
    if not fn.lower().endswith('.ppt'):
        continue
    hn = map_name(os.path.splitext(fn)[0])
    slides = []
    for payload in atoms(os.path.join(PPT_DIR, fn)):
        if len(payload) < 100:
            continue
        txt = decode(payload)
        if '单击此处编辑' in txt[:40]:
            continue
        lines = txt.replace('\r', '\n').replace('\x0b', '\n').replace('\x0c', '\n').split('\n')
        while lines and lines[-1].strip() == '':
            lines.pop()
        if not lines:
            continue
        slide = {'header': None, 'page': None, 'pairs': [], 'warn': []}
        for ln in lines:
            ln = norm_line(ln).expandtabs(8)
            s = ln.strip()
            if s == '':
                continue
            m = PAGE_RE.match(s)
            if m and not CJK_RE.search(s):
                slide['page'] = s
                continue
            if CJK_RE.search(s):
                if slide['pairs'] and slide['pairs'][-1]['lyric'] is None:
                    slide['pairs'][-1]['lyric'] = ln
                elif slide['header'] is None and not slide['pairs']:
                    slide['header'] = ln
                else:
                    slide['warn'].append('lyric_without_score: ' + s[:30])
                    slide['pairs'].append({'score': '', 'lyric': ln})
                continue
            if SCORE_RE.match(ln) and re.search(r'[0-7`!#$%&@A-Z_a-z]', s):
                bad = set(ord(c) for c in s) - ALLOWED
                if bad:
                    rep = report['unknown_chars'].setdefault(hn, {})
                    for c in sorted(bad):
                        rep[c] = rep.get(c, 0) + 1
                slide['pairs'].append({'score': ln, 'lyric': None})
            else:
                slide['warn'].append('unclassified: ' + repr(s[:40]))
        slide['pairs'] = [p for p in slide['pairs']
                          if p['score'].strip() or (p['lyric'] or '').strip()]
        for p in slide['pairs']:
            if p['lyric'] is None and p['score']:
                slide['warn'].append('score_without_lyric: ' + p['score'][:30])
        if slide['pairs']:
            slides.append(slide)
    if not slides:
        report['warnings'].append('%s: 无有效 slide' % hn)
        continue
    total_slides += len(slides)
    total_pairs += sum(len(s['pairs']) for s in slides)
    report['hymns'][hn] = {'slides': [{
        'header': s['header'], 'page': s['page'], 'warn': s['warn'],
        'pairs': [{'score': p['score'], 'lyric': p['lyric']} for p in s['pairs']],
    } for s in slides]}
    for s in slides:
        for w in s['warn']:
            report['warnings'].append('%s: %s' % (hn, w))

json.dump(report, open(REPORT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('PPT 解析完成: hymns=%d slides=%d pairs=%d warnings=%d unknown_char_hymns=%d'
      % (len(report['hymns']), total_slides, total_pairs, len(report['warnings']), len(report['unknown_chars'])))
for w in report['warnings'][:30]:
    print('  W:', w)
for k in list(report['unknown_chars'])[:10]:
    print('  U:', k, report['unknown_chars'][k])



if APPLY:
    bak = DB.replace('.db', '.bak-%s-pre-ppt.db' % time.strftime('%Y%m%d_%H%M%S'))
    shutil.copy2(DB, bak)
    print('备份:', bak)
    db = sqlite3.connect(DB)
    db.execute('''CREATE TABLE IF NOT EXISTS hymn_ppt (
        hymn_number TEXT NOT NULL, slide_no INTEGER NOT NULL,
        header TEXT, page_mark TEXT,
        PRIMARY KEY (hymn_number, slide_no))''')
    db.execute('''CREATE TABLE IF NOT EXISTS hymn_ppt_line (
        hymn_number TEXT NOT NULL, slide_no INTEGER NOT NULL, pair_no INTEGER NOT NULL,
        score_enc TEXT NOT NULL, lyric TEXT,
        PRIMARY KEY (hymn_number, slide_no, pair_no))''')
    db.execute('DELETE FROM hymn_ppt')
    db.execute('DELETE FROM hymn_ppt_line')
    for hn, info in report['hymns'].items():
        for si, s in enumerate(info['slides'], 1):
            db.execute('INSERT INTO hymn_ppt VALUES (?,?,?,?)', (hn, si, s['header'], s['page']))
            for pi, p in enumerate(s['pairs'], 1):
                db.execute('INSERT INTO hymn_ppt_line VALUES (?,?,?,?,?)',
                           (hn, si, pi, p['score'], p['lyric']))
    db.commit()
    print('入库: hymn_ppt=%d hymn_ppt_line=%d' % db.execute(
        'SELECT (SELECT COUNT(*) FROM hymn_ppt), (SELECT COUNT(*) FROM hymn_ppt_line)').fetchone())
    db.close()
