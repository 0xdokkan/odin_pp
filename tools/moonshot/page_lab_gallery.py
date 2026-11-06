#!/usr/bin/env python3
"""Copia le catture originali del cartoncino e crea una galleria HTML locale."""

import argparse
import html
import json
from pathlib import Path
import shutil
import struct
import sys
import zlib


BASE_STILLS = (
    ("panorama", "La pagina intera"), ("piede", "La cerniera del piede"),
    ("passo", "Il passo"), ("passo_dettaglio", "Il passo, da vicino"),
    ("curva", "La rotazione"), ("salita", "La salita"),
    ("salita_dettaglio", "La salita, da vicino"), ("montata", "La montata"),
    ("morte_piega", "La figura si ripiega"), ("morte_pagina", "Il ritorno alla pagina"),
    ("freccia", "La freccia"), ("bomba", "La bomba"), ("volo", "Il volo"),
    ("arco", "L'arco"), ("ponte", "Il ponte"), ("tetto", "Il tetto chiuso"),
    ("tetto_aperto", "Il tetto aperto"), ("ombra", "Con le ombre"),
    ("senza_ombra", "Senza le ombre"), ("occhi", "Nei suoi occhi"),
)
LAB_STILL = (("laboratorio", "Il laboratorio e i suoi comandi"),)
LEGACY_STILLS = BASE_STILLS + LAB_STILL
STILLS = BASE_STILLS + (
    ("stampa_idle_a", "La stampa a riposo: posa A"),
    ("stampa_idle_b", "La stampa a riposo: posa B"),
    ("cartoncino_senza_stampa", "Il cartoncino senza stampa"),
    ("retro_cartoncino", "Il retro del cartoncino"),
) + LAB_STILL
LEGACY_PREFIX = "odin_pp_page"
CARDBOARD_PREFIX = "odin_pp_page_cardboard"
SEQUENCES = (("Walk", "Camminata"), ("Turn", "Rotazione"), ("Death", "Ritorno alla pagina"))
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_END = b"\x00\x00\x00\x00IEND\xaeB`\x82"


def capture_set(legacy=False):
    return (LEGACY_PREFIX, LEGACY_STILLS) if legacy else (CARDBOARD_PREFIX, STILLS)


def expected_names(legacy=False):
    prefix, stills = capture_set(legacy)
    names = [f"{prefix}_{index:02d}_{name}.png" for index, (name, _) in enumerate(stills)]
    names += [f"{prefix}_seq_{act}_{frame:02d}.png" for act, _ in SEQUENCES for frame in range(1, 13)]
    return names


def png_dimensions(path):
    # Lightweight integrity check, not a full image decode. Checking IEND also
    # prevents copying a capture whose writer has not finished yet.
    with path.open("rb") as source:
        header = source.read(33)
        if len(header) != 33 or header[:8] != PNG_SIGNATURE or header[8:16] != b"\x00\x00\x00\rIHDR":
            raise ValueError(f"{path.name}: intestazione PNG/IHDR non valida")
        if zlib.crc32(header[12:29]) != struct.unpack(">I", header[29:33])[0]:
            raise ValueError(f"{path.name}: checksum IHDR non valido")
        width, height = struct.unpack(">II", header[16:24])
        if not (0 < width < 2**31 and 0 < height < 2**31):
            raise ValueError(f"{path.name}: dimensioni PNG non valide")
        source.seek(-12, 2)
        if source.read(12) != PNG_END:
            raise ValueError(f"{path.name}: PNG incompleto, manca IEND")
    return width, height


def validate_captures(folder, legacy=False):
    expected = expected_names(legacy)
    prefix, _ = capture_set(legacy)
    # The old prefix is also the beginning of the new one. A mixed capture
    # directory must neither reject nor silently include the other version.
    present = {path.name for path in folder.glob(f"{prefix}_*.png")
               if not (legacy and path.name.startswith(CARDBOARD_PREFIX + "_"))}
    missing, extra = set(expected) - present, present - set(expected)
    if missing or extra:
        messages = []
        if missing:
            messages.append("catture mancanti: " + ", ".join(sorted(missing)))
        if extra:
            messages.append("catture inattese: " + ", ".join(sorted(extra)))
        raise ValueError("; ".join(messages))
    return {name: png_dimensions(folder / name) for name in expected}


def image_button(name, caption, dimensions, extra_class=""):
    width, height = dimensions
    return (
        f'<button type="button" class="preview {extra_class}" data-src="captures/{name}" '
        f'data-caption="{html.escape(caption, quote=True)}" aria-label="Ingrandisci: {html.escape(caption, quote=True)}">'
        f'<img src="captures/{name}" width="{width}" height="{height}" '
        f'alt="{html.escape(caption, quote=True)}" loading="lazy"></button>'
    )


STYLE = """
:root { color-scheme: dark; --paper: #eee5d6; --muted: #aeb9bd; --line: #35454c; --accent: #afd9cd; }
* { box-sizing: border-box; }
body { margin: 0; color: var(--paper); background: #111c22; font: 16px/1.6 system-ui, sans-serif; }
main { max-width: 1460px; padding: 48px 28px 64px; margin: auto; }
header { max-width: 820px; margin-bottom: 40px; }
.eyebrow { color: var(--accent); letter-spacing: .15em; font-size: .76rem; text-transform: uppercase; }
h1 { font-family: Georgia, serif; font-weight: 400; font-size: clamp(2.2rem, 5vw, 4rem); line-height: 1.12; margin: 12px 0 18px; }
h2 { font-weight: 500; margin: 44px 0 10px; font-size: 1.5rem; }
h3 { font-weight: 500; margin: 0 0 14px; }
p { color: var(--muted); }
nav { display: flex; gap: 20px; flex-wrap: wrap; margin-top: 24px; }
a { color: var(--accent); text-underline-offset: 4px; }
button, input { font: inherit; }
button { color: var(--paper); border: 1px solid var(--line); background: #203039; border-radius: 5px; padding: 7px 13px; cursor: pointer; }
button:hover { border-color: var(--accent); }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 4px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 310px), 1fr)); gap: 24px; }
figure { margin: 0; min-width: 0; }
.preview { display: block; width: 100%; padding: 0; aspect-ratio: 16/9; overflow: hidden; background: #0b1217; cursor: zoom-in; }
.preview img { display: block; width: 100%; height: 100%; object-fit: contain; }
figcaption { padding: 12px 0; }
.filename { color: var(--muted); font-size: .75rem; overflow-wrap: anywhere; }
.download { font-size: .8rem; }
.sequence { border-top: 1px solid var(--line); padding-top: 24px; margin-top: 32px; }
.sequence .preview { max-height: 65vh; aspect-ratio: 16/9; }
.controls { display: flex; align-items: center; flex-wrap: wrap; gap: 14px; margin: 16px 0 8px; }
.controls input { flex: 1; min-width: 160px; accent-color: var(--accent); }
.counter { min-width: 150px; font-variant-numeric: tabular-nums; }
.note { font-size: .85rem; }
dialog { width: min(96vw, 1800px); max-width: 96vw; max-height: 96vh; padding: 20px; color: var(--paper); border: 1px solid var(--line); border-radius: 8px; background: #111c22; }
dialog::backdrop { background: #000d; }
.dialog-header { display: flex; justify-content: space-between; align-items: center; gap: 16px; }
.dialog-header h2 { margin: 0; font-size: 1.1rem; }
.zoom-view { height: 68vh; overflow: auto; margin: 16px 0; background: #0b1217; }
.zoom-view img { display: block; height: auto; max-width: none; object-fit: contain; margin: auto; }
footer { margin-top: 48px; border-top: 1px solid var(--line); padding-top: 20px; color: var(--muted); font-size: .85rem; }
@media (max-width: 600px) { main { padding: 28px 18px; } .controls { gap: 10px; } dialog { padding: 12px; } }
"""


SCRIPT = """
const dialog = document.querySelector('#zoom');
const zoomImage = dialog.querySelector('img');
const zoomView = dialog.querySelector('.zoom-view');
const zoomRange = dialog.querySelector('input');
const zoomValue = dialog.querySelector('output');
const stopPlayers = [];
function fitZoom() {
  if (!zoomImage.naturalWidth) return;
  const fitted = Math.min(zoomImage.naturalWidth, zoomView.clientWidth,
    zoomView.clientHeight * zoomImage.naturalWidth / zoomImage.naturalHeight);
  zoomImage.style.width = `${fitted * Number(zoomRange.value) / 100}px`;
  zoomValue.value = `${zoomRange.value}% della vista`;
}
document.querySelectorAll('.preview').forEach(button => {
  button.addEventListener('click', () => {
    stopPlayers.forEach(stop => stop());
    dialog.querySelector('h2').textContent = button.dataset.caption;
    zoomImage.alt = button.dataset.caption;
    zoomRange.value = '100';
    dialog.querySelector('.download').href = button.dataset.src;
    dialog.querySelector('.download').download = button.dataset.src.split('/').pop();
    zoomImage.onload = fitZoom;
    zoomImage.src = button.dataset.src;
    dialog.showModal();
    fitZoom();
  });
});
dialog.querySelector('.close').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
zoomRange.addEventListener('input', fitZoom);
dialog.querySelector('.native').addEventListener('click', () => {
  zoomImage.style.width = `${zoomImage.naturalWidth}px`;
  zoomValue.value = '1 pixel immagine = 1 pixel CSS';
});
window.addEventListener('resize', () => { if (dialog.open) fitZoom(); });
document.querySelectorAll('.sequence').forEach(section => {
  const frames = JSON.parse(section.dataset.frames);
  const range = section.querySelector('input');
  const play = section.querySelector('.play');
  const preview = section.querySelector('.preview');
  const download = section.querySelector('.download');
  let timer = null;
  function show(index) {
    range.value = String(index + 1);
    preview.dataset.src = `captures/${frames[index]}`;
    preview.dataset.caption = `${section.dataset.title}, fotogramma ${index + 1} di 12`;
    preview.querySelector('img').src = preview.dataset.src;
    preview.querySelector('img').alt = preview.dataset.caption;
    preview.setAttribute('aria-label', `Ingrandisci: ${preview.dataset.caption}`);
    download.href = preview.dataset.src;
    download.download = frames[index];
    section.querySelector('.filename').textContent = frames[index];
    section.querySelector('output').value = `Fotogramma ${index + 1} / 12`;
  }
  function stop() {
    clearInterval(timer); timer = null;
    play.textContent = 'Riproduci a 3 fps';
    play.setAttribute('aria-pressed', 'false');
  }
  stopPlayers.push(stop);
  play.addEventListener('click', () => {
    if (timer !== null) { stop(); return; }
    stopPlayers.forEach(stopOther => stopOther());
    play.textContent = 'Pausa';
    play.setAttribute('aria-pressed', 'true');
    timer = setInterval(() => show(Number(range.value) % frames.length), 1000 / 3);
  });
  range.addEventListener('input', () => { stop(); show(Number(range.value) - 1); });
});
document.addEventListener('visibilitychange', () => { if (document.hidden) stopPlayers.forEach(stop => stop()); });
"""


def gallery_html(dimensions, legacy=False):
    prefix, stills = capture_set(legacy)
    total = len(stills) + 36
    edition = "Prima versione" if legacy else "Cartoncino stampato"
    parts = [
        '<!doctype html><html lang="it"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        '<title>Odin PP — La pagina prende vita</title>',
        f'<style>{STYLE}</style></head><body><main>',
        f'<header><div class="eyebrow">Odin PP · Moonshot · {edition}</div>',
        '<h1>La pagina prende vita</h1>',
        f'<p>Un mondo che si apre dal foglio. {len(stills)} viste e tre sequenze per osservare '
        'pieghe, movimento, architetture e ombre del prototipo.</p>',
        f'<p class="note">{total} catture native. I PNG sono copie inalterate: nessun ritocco '
        'o ridimensionamento dei file. Seleziona una vista per ingrandirla oppure scarica l’originale.</p>',
        f'<nav><a href="#viste">Le {len(stills)} viste</a><a href="#sequenze">Le tre sequenze</a></nav></header>',
        '<section id="viste"><h2>Le viste del laboratorio</h2><div class="grid">',
    ]
    for index, (stem, caption) in enumerate(stills):
        name = f"{prefix}_{index:02d}_{stem}.png"
        width, height = dimensions[name]
        parts += [
            '<figure>', image_button(name, caption, dimensions[name]),
            f'<figcaption>{html.escape(caption)}<div class="filename">{name}<br>{width} × {height} px</div>',
            f'<a class="download" href="captures/{name}" download="{name}">Scarica il PNG originale</a></figcaption></figure>',
        ]
    parts += ['</div></section><section id="sequenze"><h2>Il movimento, un fotogramma alla volta</h2>',
              '<p>Ogni sequenza contiene 12 catture. La riproduzione locale è ciclica, a 3 fotogrammi al secondo; '
              'il cursore permette di fermarsi su ogni posa. Non è una misura degli FPS del gioco.</p>']
    for act, title in SEQUENCES:
        names = [f"{prefix}_seq_{act}_{frame:02d}.png" for frame in range(1, 13)]
        name = names[0]
        parts += [
            f'<section class="sequence" data-title="{title}" data-frames="{html.escape(json.dumps(names), quote=True)}">',
            f'<h3>{title}</h3>', image_button(name, f"{title}, fotogramma 1 di 12", dimensions[name]),
            '<div class="controls"><button type="button" class="play" aria-pressed="false">Riproduci a 3 fps</button>',
            f'<input type="range" min="1" max="12" step="1" value="1" aria-label="Fotogramma: {title}">',
            '<output class="counter">Fotogramma 1 / 12</output></div>',
            f'<div class="filename">{name}</div>',
            f'<a class="download" href="captures/{name}" download="{name}">Scarica questo PNG originale</a></section>',
        ]
    parts += [
        '</section><footer>Galleria locale, senza connessioni esterne. '
        f'Intestazioni PNG e completezza delle {total} catture verificate dal generatore. '
        'Il ridimensionamento della sola vista nel browser lascia intatti i file originali.</footer></main>',
        '<dialog id="zoom" aria-labelledby="zoom-title"><div class="dialog-header">',
        '<h2 id="zoom-title">Vista ingrandita</h2><button type="button" class="close">Chiudi</button></div>',
        '<div class="zoom-view"><img alt=""></div><div class="controls">',
        '<label for="zoom-range">Ingrandimento</label><input id="zoom-range" type="range" min="100" max="400" step="25" value="100">',
        '<output>100% della vista</output><button type="button" class="native">Dimensioni originali</button></div>',
        '<a class="download" href="#" download>Scarica il PNG originale</a></dialog>',
        f'<script>{SCRIPT}</script></body></html>\n',
    ]
    return "\n".join(parts)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--legacy", action="store_true", help="usa le precedenti 57 catture odin_pp_page, senza cartoncino stampato")
    args = parser.parse_args(argv)
    source, output = args.captures.resolve(), args.output_dir.resolve()
    destination = output / "captures"
    if source == destination.resolve():
        parser.error("la cartella di destinazione delle catture deve essere distinta dall'origine")
    try:
        dimensions = validate_captures(source, args.legacy)
        destination.mkdir(parents=True, exist_ok=True)
        for name in dimensions:
            shutil.copy2(source / name, destination / name)
        (output / "index.html").write_text(gallery_html(dimensions, args.legacy), encoding="utf-8")
    except (OSError, ValueError) as error:
        print(f"Galleria non generata: {error}", file=sys.stderr)
        return 2
    print(f"Galleria: {output / 'index.html'}")
    _, stills = capture_set(args.legacy)
    print(f"{len(dimensions)} PNG originali copiati: {len(stills)} viste + 12 Walk + 12 Turn + 12 Death.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
