from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
W, H = 2880, 1800
SRC, OUT = "src", "out"
FONTS = {
  "en": ("/System/Library/Fonts/SFNS.ttf", None),
  "ko": ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6),
  "ja": ("/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc", None),
  "zh": ("/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc", None),
}
def font(loc, size, bold):
    path, idx = FONTS[loc]
    if loc == "en":
        f = ImageFont.truetype(path, size); f.set_variation_by_name("Bold" if bold else "Regular"); return f
    if loc == "ko":
        return ImageFont.truetype(path, size, index=6 if bold else 0)
    # PingFang.ttc: find SC Semibold / Regular by name
    for i in range(30):
        try: f = ImageFont.truetype(path, size, index=i)
        except Exception: break
        fam, sty = f.getname()
        if fam == "PingFang SC" and sty == ("Semibold" if bold else "Regular"): return f
    return ImageFont.truetype(path, size, index=0)

# (source image, headline, subline)
COPY = {
 "en": [
  ("app-md-en-light",   "Markdown, done lightly.",      "Syntax stays visible. Text gets easier to read."),
  ("app-reader-en-dark","Reader mode. One keystroke.",  "⌘⇧R renders the document. Esc brings the editor back."),
  ("app-txt-en-light",  "Just open the file.",          "One file, one window. No projects, no sidebars."),
  ("app-yaml-dark",     "Config files, quietly highlighted.", "Keys tinted in JSON, YAML and TOML. Nothing else touched."),
  ("app-md-en-dark",    "Light, dark, or system.",      "Native macOS colors. Behaves like a built-in app."),
  ("app-cjk-light",     "Beautiful in any language.",   "English, 한국어, 日本語, 简体中文 — following your Mac."),
 ],
 "ko": [
  ("app-md-ko-light",   "Markdown을 가볍게.",           "문법은 그대로 보이고, 글은 더 읽기 쉬워집니다."),
  ("app-reader-ko-dark","Reader 모드, 단축키 하나로.",  "⌘⇧R로 렌더링하고 Esc로 편집기로 돌아옵니다."),
  ("app-txt-ko-light",  "그냥 파일을 여세요.",          "파일 하나에 창 하나. 프로젝트도 사이드바도 없습니다."),
  ("app-yaml-dark",     "설정 파일은 조용하게.",        "JSON, YAML, TOML의 키만 살짝 색을 입힙니다."),
  ("app-md-ko-dark",    "라이트, 다크, 시스템.",        "macOS 기본 색상. 내장 앱처럼 동작합니다."),
  ("app-cjk-light",     "어떤 언어로도 아름답게.",      "한국어, English, 日本語, 简体中文 — Mac 언어 설정을 따릅니다."),
 ],
 "ja": [
  ("app-md-ja-light",   "Markdownを、軽やかに。",       "記法はそのまま見えて、文章はもっと読みやすく。"),
  ("app-reader-ja-dark","リーダーモードはキーひとつ。", "⌘⇧Rでレンダリング、Escでエディタに戻ります。"),
  ("app-txt-ja-light",  "ただ、ファイルを開くだけ。",   "1ファイル1ウインドウ。プロジェクトもサイドバーもなし。"),
  ("app-yaml-dark",     "設定ファイルは、静かに。",     "JSON・YAML・TOMLはキーだけを淡く色付け。"),
  ("app-md-ja-dark",    "ライト、ダーク、システム。",   "macOS標準の配色。純正アプリのように振る舞います。"),
  ("app-cjk-light",     "どの言語でも美しく。",         "日本語、English、한국어、简体中文 — Macの言語設定に従います。"),
 ],
 "zh": [
  ("app-md-zh-light",   "Markdown，轻描淡写。",         "语法保持可见，文字更易阅读。"),
  ("app-reader-zh-dark","阅读模式，一键切换。",         "⌘⇧R 渲染文档，Esc 返回编辑器。"),
  ("app-txt-zh-light",  "只需打开文件。",               "一个文件一个窗口。没有项目，没有侧边栏。"),
  ("app-yaml-dark",     "配置文件，安静高亮。",         "JSON、YAML、TOML 仅为键着色，其余保持原样。"),
  ("app-md-zh-dark",    "浅色、深色、跟随系统。",       "macOS 原生配色，表现如同自带应用。"),
  ("app-cjk-light",     "任何语言都很美。",             "简体中文、English、한국어、日本語 — 跟随 Mac 语言设置。"),
 ],
}

import unicodedata
def script_of(ch, loc):
    o = ord(ch)
    if 0x2300 <= o <= 0x23FF or 0x2190 <= o <= 0x21FF: return "en"
    if 0xAC00 <= o <= 0xD7A3 or 0x1100 <= o <= 0x11FF or 0x3130 <= o <= 0x318F: return "ko"
    if 0x3040 <= o <= 0x30FF: return "ja"
    if 0x4E00 <= o <= 0x9FFF or 0x3000 <= o <= 0x303F or 0xFF00 <= o <= 0xFFEF: return loc if loc in ("ja","zh") else "zh"
    return loc if loc in ("en","ko","ja","zh") else "en"
def draw_runs(d, text, y, size, bold, fill, loc):
    runs=[]; 
    for ch in text:
        sc = script_of(ch, loc)
        if ch in " ,.:;—-": sc = "en"   # spaces and ASCII punctuation always in the Latin font
        if runs and runs[-1][0]==sc: runs[-1][1]+=ch
        else: runs.append([sc,ch])
    fonts={sc:font(sc,size,bold) for sc,_ in runs}
    total=sum(d.textlength(t,font=fonts[sc]) for sc,t in runs)
    x=(W-total)/2
    for sc,t in runs:
        d.text((x,y),t,font=fonts[sc],fill=fill,anchor='ls'); x+=d.textlength(t,font=fonts[sc])

def gradient(dark):
    top, bot = ((28,28,30),(16,16,18)) if dark else ((246,244,240),(228,226,222))
    g = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H-1); g.putpixel((0,y), tuple(int(top[i]*(1-t)+bot[i]*t) for i in range(3)))
    return g.resize((W, H))

def compose(loc, src, head, sub, i):
    dark = src.endswith("dark")
    bg = gradient(dark).convert("RGBA")
    img = Image.open(f"{SRC}/{src}.png").convert("RGBA")
    sw = 2320; sh = round(img.height * sw / img.width)
    img = img.convert("RGBa").resize((sw, sh), Image.LANCZOS).convert("RGBA")  # premultiplied resize keeps edges clean
    sx, sy = (W - sw)//2, 600
    # shadow
    sh_layer = Image.new("RGBA", (W, H), (0,0,0,0))
    ImageDraw.Draw(sh_layer).rounded_rectangle([sx, sy+30, sx+sw, sy+sh+200], radius=30, fill=(0,0,0,110 if dark else 70))
    sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(60))
    bg.alpha_composite(sh_layer)
    # window: use the source's own alpha (already rounded) instead of a separate mask
    layer = Image.new("RGBA", (W, H), (0,0,0,0)); layer.paste(img, (sx, sy))
    bg.alpha_composite(layer)
    # text
    d = ImageDraw.Draw(bg)
    fg = (245,245,247) if dark else (28,28,30)
    fg2 = (160,160,168) if dark else (110,110,118)
    draw_runs(d, head, 320, 118, True, fg, loc)
    draw_runs(d, sub, 440, 50, False, fg2, loc)
    bg = bg.crop((0,0,W,H)).convert("RGB")
    os.makedirs(f"{OUT}/{loc}", exist_ok=True)
    bg.save(f"{OUT}/{loc}/{i:02d}-{src}.png", optimize=True)

for loc, items in COPY.items():
    for i, (src, head, sub) in enumerate(items, 1):
        compose(loc, src, head, sub, i)
print("done")
