from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "run-44945378464" / "iphone"
OUTPUT = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1206, 2622

# This treatment uses only the genuine Simulator captures. Decorative geometry
# and copy are outside the captured app screen; no screen pixels are redrawn.
SLIDES = [
    {
        "key": "home",
        "category_ja": "生産カウンター",
        "title_ja": ["生産数も残数も、", "ひと目でわかる。"],
        "sub_ja": "目標までの進み具合を、ホームで確認。",
        "category_en": "PRODUCTION COUNTER",
        "title_en": ["See output", "and what's left."],
        "sub_en": "Track progress against your production target.",
        "crop": 1840,
    },
    {
        "key": "counter-quick-add",
        "category_ja": "クイック追加",
        "title_ja": ["まとめて数えて、", "一度で加算。"],
        "sub_ja": "複数個の生産も、一度にカウンターへ。",
        "category_en": "QUICK ADD",
        "title_en": ["Add a batch.", "Keep moving."],
        "sub_en": "Enter a quantity and add it in one step.",
        "crop": 2250,
    },
    {
        "key": "counter-history",
        "category_ja": "カウント履歴",
        "title_ja": ["記録を残して、", "あとから確認。"],
        "sub_ja": "操作履歴を見返し、CSVに書き出し。",
        "category_en": "COUNT HISTORY",
        "title_en": ["Keep a record.", "Review it later."],
        "sub_en": "Review count changes and export them as CSV.",
        "crop": 2260,
    },
    {
        "key": "cycle-time",
        "category_ja": "サイクルタイム",
        "title_ja": ["1サイクルを測り、", "秒／個を算出。"],
        "sub_ja": "入力またはストップウォッチで計測。",
        "category_en": "CYCLE TIME",
        "title_en": ["Measure a cycle.", "See seconds per unit."],
        "sub_en": "Enter a time or use the built-in stopwatch.",
        "crop": 2290,
    },
    {
        "key": "takt-time",
        "category_ja": "タクトタイム",
        "title_ja": ["必要数から、", "タクトを計算。"],
        "sub_ja": "稼働時間と顧客需要から目安を算出。",
        "category_en": "TAKT TIME",
        "title_en": ["Calculate takt.", "Plan from demand."],
        "sub_en": "Use net production time and customer demand.",
        "crop": 2200,
    },
    {
        "key": "defect-counter",
        "category_ja": "不良カウンター",
        "title_ja": ["生産数と不良数を", "並べて確認。"],
        "sub_ja": "不良率も、その場で確認できます。",
        "category_en": "DEFECT COUNTER",
        "title_en": ["Track output", "and defects."],
        "sub_en": "See the defect rate as you count.",
        "crop": 1950,
    },
    {
        "key": "process-capability",
        "category_ja": "Proツール · 工程能力",
        "title_ja": ["工程能力を", "Cp・Cpkで確認。"],
        "sub_ja": "規格値と工程データから算出。",
        "category_en": "PRO TOOL · PROCESS CAPABILITY",
        "title_en": ["Calculate Cp", "and Cpk."],
        "sub_en": "Calculate from specification and process data.",
        "crop": 2240,
    },
]
SEQUENCE = [
    "home",
    "counter-quick-add",
    "cycle-time",
    "defect-counter",
    "counter-history",
    "takt-time",
    "process-capability",
]
SLIDES.sort(key=lambda slide: SEQUENCE.index(slide["key"]))

INK = (21, 28, 31)
INK_LIGHT = (34, 45, 50)
PAPER = (242, 243, 240)
PAPER_LINE = (222, 225, 220)
ORANGE = (255, 126, 32)
WHITE = (250, 249, 244)
MUTED = (190, 199, 198)


def font(size: int, *, bold: bool = False, japanese: bool = False) -> ImageFont.FreeTypeFont:
    if japanese:
        path = Path(r"C:\Windows\Fonts\meiryob.ttc" if bold else r"C:\Windows\Fonts\meiryo.ttc")
    else:
        path = Path(r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf")
    return ImageFont.truetype(str(path), size)


def fit(text: str, max_width: int, size: int, japanese: bool) -> ImageFont.FreeTypeFont:
    while size > 42 and ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox(
        (0, 0), text, font=font(size, bold=True, japanese=japanese)
    )[2] > max_width:
        size -= 2
    return font(size, bold=True, japanese=japanese)


def make_background() -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(image)
    # Subtle technical grid is a vector background detail, not app UI.
    for x in range(30, WIDTH, 72):
        draw.line((x, 570, x, HEIGHT), fill=PAPER_LINE, width=1)
    for y in range(590, HEIGHT, 72):
        draw.line((0, y, WIDTH, y), fill=PAPER_LINE, width=1)
    # Deep graphite header with a sharp safety-orange cut.
    draw.rectangle((0, 0, WIDTH, 594), fill=INK)
    draw.polygon(((900, 0), (WIDTH, 0), (WIDTH, 594), (780, 594)), fill=INK_LIGHT)
    draw.polygon(((1114, 0), (WIDTH, 0), (WIDTH, 298)), fill=ORANGE)
    return image


def compose(slide: dict, index: int, language: str) -> Path:
    english = language == "en"
    image = make_background()
    draw = ImageDraw.Draw(image)

    # Brand and sequence marker.
    brand = "FACTORY TOOLS" if english else "ラインギア"
    draw.text((68, 46), brand, font=font(33, bold=True, japanese=not english), fill=WHITE)
    draw.rounded_rectangle((68, 110, 224, 120), radius=5, fill=ORANGE)
    draw.text((1036, 50), f"{index:02d}", font=font(58, bold=True), fill=WHITE)
    draw.text((1110, 90), "/07", font=font(18, bold=True), fill=MUTED)

    category = slide["category_en" if english else "category_ja"]
    draw.text((68, 166), category, font=font(25, bold=True, japanese=not english), fill=ORANGE)
    title = slide["title_en" if english else "title_ja"]
    title_font_size = 76 if english else 78
    title_font = min(
        (fit(line, 1060, title_font_size, not english) for line in title),
        key=lambda f: f.size,
    )
    draw.text((68, 226), title[0], font=title_font, fill=WHITE)
    draw.text((68, 321), title[1], font=title_font, fill=WHITE)
    subtitle = slide["sub_en" if english else "sub_ja"]
    subtitle_font = fit(subtitle, 1040, 30, not english)
    draw.text((72, 446), subtitle, font=subtitle_font, fill=MUTED)

    # The screenshot remains genuine and unpainted. Only a shadow and a frame
    # are added around it; crop amounts match the approved source image plan.
    source = Image.open(SOURCE / f"iphone-{slide['key']}-{language}.jpg").convert("RGB")
    source = source.crop((0, 0, source.width, min(slide["crop"], source.height)))
    shot_width = 1040
    shot_height = round(source.height * shot_width / source.width)
    source = source.resize((shot_width, shot_height), Image.Resampling.LANCZOS)
    x = (WIDTH - shot_width) // 2
    y = 592
    frame = 12
    outer = (x - frame, y - frame, x + shot_width + frame, y + shot_height + frame)

    shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (outer[0] - 2, outer[1] + 4, outer[2] + 2, outer[3] + 20),
        radius=42,
        fill=(9, 15, 18, 92),
    )
    image = Image.alpha_composite(image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(24)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(outer, radius=42, fill=INK, outline=ORANGE, width=3)
    image.paste(source, (x, y))

    output = OUTPUT / f"{index:02d}-{slide['key']}-{language}.jpg"
    image.convert("RGB").save(output, quality=95, subsampling=0, optimize=True)
    return output


def contact_sheet(paths: list[Path]) -> None:
    thumb_w, thumb_h, gap, margin = 201, 437, 18, 28
    sheet_h = 55 + 483 + 64 + 483 + 56
    sheet = Image.new("RGB", (margin * 2 + 7 * thumb_w + 6 * gap, sheet_h), (231, 233, 228))
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 12), "JAPANESE", font=font(22, bold=True), fill=ORANGE)
    draw.text((margin, 602), "ENGLISH", font=font(22, bold=True), fill=ORANGE)
    for position, path in enumerate(paths):
        row = int(path.stem.endswith("-en"))
        x = margin + (position % 7) * (thumb_w + gap)
        y = 55 + row * 547
        thumb = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x, y))
        draw.text((x, y + thumb_h + 7), path.stem.upper(), font=font(12, bold=True), fill=INK)
    sheet.save(OUTPUT / "contact-sheet.jpg", quality=94, optimize=True)


if __name__ == "__main__":
    generated = [compose(slide, i, lang) for lang in ("ja", "en") for i, slide in enumerate(SLIDES, 1)]
    contact_sheet(generated)
    print(f"Created {len(generated)} private v5 layouts from genuine Simulator captures.")
