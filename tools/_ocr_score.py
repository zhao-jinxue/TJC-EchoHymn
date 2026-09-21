# 临时 OCR 试点脚本（校准任务用，勿提交；含 API key 读取但不落盘 key）
import os, sys, json, base64, re, time, sqlite3
from openai import OpenAI

KEY = os.environ['DASHSCOPE_API_KEY']
client = OpenAI(api_key=KEY, base_url='https://dashscope.aliyuncs.com/compatible-mode/v1')

PROMPT = """图片中有 {n} 行简谱（自上而下排列，每行是一个乐句的女高声部）。请逐行转录全部 {n} 行。

注意：这是艺术字体，请严格按字形区分数字——
- 3 = 圆润双弧形（左开口的两个半圆叠起），绝不是 2；
- 2 = 顶部弧线 + 斜下笔画 + 底部水平长横；
- 5 = 顶部一横 + 短竖 + 下半圆；6 = 下带圆圈的竖钩；7 = 横加斜竖；
- 数字正上方有小圆点 = 高音，写作数字后加 ^（带点的1是 1^，不是 i）；
- 数字正下方有小圆点 = 低音，写作数字后加 ,（如 5,）。

记谱转换规则（严格遵循）：
- 音符用数字 1-7，休止符用 0；
- 升号写在数字前如 #4，降号写在数字前如 b7（还原记号忽略）；
- 每个增时线短横单独作为一个 token 输出为 -（如 5 - 表示5延长一拍）；
- 忽略小节线、竖线、数字下划线(减时线)、数字右侧附点、连音弧线、括号、谱表左端的方括号；
- 每行的所有 token 用单个空格分隔。

只输出严格 JSON，不要其他文字：
{{"lines": ["……第1行……", "……共{n}行……"]}}"""

# 人工目视核对的标准答案（女高，按系统）
GROUND_TRUTH = {
    '1': ['1 1 3 3 5 - 5 - 6 - 6 6 5 - 3 -',
          '5 5 5 5 1^ - 7 5 2 5 6 5 5 - - -',
          '1 1 3 3 5 - 5 - 6 6 6 6 5 - 5 -',
          '1^ - 5 5 6 - 3 - 4 2 2 1 1 - - -'],
}

FW = str.maketrans('１２３４５６７８９０＃ｂ', '1234567890#b')

def clean_token(tok):
    tok = tok.translate(FW)
    tok = tok.replace('\u0307', '^')          # 组合上点 → ^
    if re.fullmatch(r'[iïīíìī̇]', tok):         # 模型把带点1写成 i
        tok = '1^'
    tok = re.sub(r'^([1-7])[,，]\^?$', r'\1,', tok)  # 全角逗号规整
    return tok

def normalize_line(s):
    toks = [clean_token(t) for t in re.sub(r'\s+', ' ', s or '').strip().split()]
    toks = [t for t in toks if t and t not in ('|', '||', '‖')]
    return ' '.join(toks)

def png_path(hn):
    db = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
    r = db.execute('SELECT numbered_png_path FROM tjc_hymn WHERE hymn_number=?', (hn,)).fetchone()
    return os.path.join(r'e:\EchoHymn\data', r[0])

def ocr(path, n_lines, high_res=False, model='qwen-vl-max'):
    b64 = base64.b64encode(open(path, 'rb').read()).decode()
    t0 = time.time()
    resp = client.chat.completions.create(
        model=model, temperature=0.0,
        messages=[{'role': 'user', 'content': [
            {'type': 'image_url', 'image_url': {'url': f'data:image/png;base64,{b64}'}},
            {'type': 'text', 'text': PROMPT.format(n=n_lines)},
        ]}],
        extra_body={'vl_high_resolution_images': True} if high_res else None,
    )
    usage = resp.usage
    out = resp.choices[0].message.content.strip()
    m = re.search(r'\{.*\}', out, re.S)
    data = [normalize_line(x) for x in (json.loads(m.group(0))['lines'] if m else [])]
    return data, usage, time.time() - t0

def score(a, b):
    ta, tb = a.split(), b.split()
    same = sum(1 for x, y in zip(ta, tb) if x == y)
    return f'{same}/{max(len(ta), len(tb))}', ta == tb

if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from _crop_bands import build_band_image
    hns = sys.argv[1:] or ['1']
    per_line = os.environ.get('PER_LINE') == '1'
    tot = {'pt': 0, 'ct': 0, 'it': 0}
    for hn in hns:
        band = rf'e:\EchoHymn\tools\_bands_{hn}.png'
        groups = build_band_image(hn, band)
        results = []
        if per_line:
            for i in range(len(groups)):
                bl = rf'e:\EchoHymn\tools\_band_{hn}_{i+1}.png'
                lines, usage, dt = ocr(bl, 1, high_res=True,
                                       model=os.environ.get('OCR_MODEL', 'qwen3-vl-plus'))
                results += lines
                tot['pt'] += usage.prompt_tokens; tot['ct'] += usage.completion_tokens
                it = getattr(usage.prompt_tokens_details, 'image_tokens', None) if usage.prompt_tokens_details else None
                tot['it'] += it or 0
                print(f'  hymn {hn} line {i+1}: {dt:.1f}s prompt={usage.prompt_tokens} image={it}')
        else:
            lines, usage, dt = ocr(band, len(groups), high_res=True,
                                   model=os.environ.get('OCR_MODEL', 'qwen-vl-max'))
            results = lines
            it = getattr(usage.prompt_tokens_details, 'image_tokens', None) if usage.prompt_tokens_details else None
            print(f'--- hymn {hn}  {dt:.1f}s  prompt={usage.prompt_tokens} completion={usage.completion_tokens} image={it}')
            tot['pt'] += usage.prompt_tokens; tot['ct'] += usage.completion_tokens; tot['it'] += it or 0
        gt = GROUND_TRUTH.get(hn)
        for i, ln in enumerate(results):
            tag = ''
            if gt and i < len(gt):
                acc, ok = score(gt[i], ln)
                tag = ('  ==OK==' if ok else f'  DIFF({acc})')
            print(f'  L{i+1}: {ln}{tag}')
        if gt:
            print(f'  行数: ocr={len(results)} gt={len(gt)}')
            for i, g in enumerate(gt):
                if i >= len(results): print(f'  MISS L{i+1}: {g}')
    print(f'== TOTAL prompt={tot["pt"]} completion={tot["ct"]} image={tot["it"]}')
