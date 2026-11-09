#!/usr/bin/env python3
"""Regenerates the Foyer launcher icons and the Fire TV banner (needs: pip install playwright)."""
import os, sys
from playwright.sync_api import sync_playwright

RES = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')

DEFS = '''
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#101746"/><stop offset="0.55" stop-color="#1B2670"/><stop offset="1" stop-color="#2A1B63"/>
  </linearGradient>
  <radialGradient id="glowA" cx="0.2" cy="0.15" r="0.7"><stop offset="0" stop-color="#4C6EF5" stop-opacity="0.55"/><stop offset="1" stop-color="#4C6EF5" stop-opacity="0"/></radialGradient>
  <radialGradient id="glowB" cx="0.9" cy="0.95" r="0.7"><stop offset="0" stop-color="#E64980" stop-opacity="0.45"/><stop offset="1" stop-color="#E64980" stop-opacity="0"/></radialGradient>
  <linearGradient id="glass" x1="0" y1="0" x2="0.4" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.50"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.16"/><stop offset="1" stop-color="#fff" stop-opacity="0.30"/>
  </linearGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.95"/><stop offset="1" stop-color="#fff" stop-opacity="0.25"/></linearGradient>
  <radialGradient id="warm" cx="0.5" cy="1" r="0.95">
    <stop offset="0" stop-color="#FFE8A3" stop-opacity="1"/><stop offset="0.45" stop-color="#FFB454" stop-opacity="0.85"/><stop offset="1" stop-color="#FF8A5B" stop-opacity="0.0"/>
  </radialGradient>
  <linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFD27A" stop-opacity="0.55"/><stop offset="1" stop-color="#FFD27A" stop-opacity="0"/></linearGradient>
  <clipPath id="door"><path d="M300 760 V450 A212 212 0 0 1 724 450 V760 Z"/></clipPath>
</defs>'''

# the doorway, drawn on a 1024 grid
DOOR = '''
<g>
  <path d="M300 760 V450 A212 212 0 0 1 724 450 V760 Z" fill="#0A0F33" fill-opacity="0.55"/>
  <g clip-path="url(#door)">
    <rect x="300" y="238" width="424" height="522" fill="url(#warm)"/>
    <ellipse cx="512" cy="760" rx="150" ry="46" fill="#FFF3C9" fill-opacity="0.85"/>
  </g>
  <path d="M300 760 V450 A212 212 0 0 1 724 450 V760 Z" fill="url(#glass)"/>
  <path d="M300 760 V450 A212 212 0 0 1 724 450 V760" fill="none" stroke="url(#rim)" stroke-width="10" stroke-linejoin="round"/>
  <path d="M250 760 H774" stroke="#fff" stroke-opacity="0.75" stroke-width="10" stroke-linecap="round"/>
  <path d="M330 790 H694 L736 900 H288 Z" fill="url(#floor)" opacity="0.7"/>
</g>'''

def icon_svg(n):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{n}" height="{n}" viewBox="0 0 1024 1024">{DEFS}
<rect width="1024" height="1024" rx="228" fill="url(#bg)"/>
<rect width="1024" height="1024" rx="228" fill="url(#glowA)"/>
<rect width="1024" height="1024" rx="228" fill="url(#glowB)"/>
{DOOR}
</svg>'''

def banner_svg(w, h):
    # 640x360 canvas: doorway icon on the left, wordmark on the right
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 640 360">{DEFS}
<rect width="640" height="360" fill="url(#bg)"/>
<rect width="640" height="360" fill="url(#glowA)"/>
<rect width="640" height="360" fill="url(#glowB)"/>
<g transform="translate(14 22) scale(0.3)">{DOOR}</g>
<text x="296" y="206" font-family="Helvetica Neue, Helvetica, Arial, DejaVu Sans, sans-serif" font-size="108" font-weight="600"
      letter-spacing="-3" fill="#fff">Foyer</text>
<text x="300" y="252" font-family="Helvetica Neue, Helvetica, Arial, DejaVu Sans, sans-serif" font-size="24" fill="#fff" fill-opacity="0.65"
      letter-spacing="2">YOUR HOME SCREEN</text>
</svg>'''

def shot(page, svg, w, h, out):
    page.set_viewport_size({'width': w, 'height': h})
    page.set_content(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    page.screenshot(path=out, omit_background=True, clip={'x': 0, 'y': 0, 'width': w, 'height': h})

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page()
    for d, n in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        shot(pg, icon_svg(n), n, n, os.path.join(RES, f'mipmap-{d}', 'ic_launcher.png'))
    shot(pg, banner_svg(640, 360), 640, 360, os.path.join(RES, 'drawable-xhdpi', 'foyer_banner.png'))
    # previews for humans
    prev = os.path.join(os.path.dirname(__file__), '..', 'docs')
    shot(pg, icon_svg(512), 512, 512, os.path.join(prev, 'icon.png'))
    shot(pg, banner_svg(640, 360), 640, 360, os.path.join(prev, 'banner.png'))
    b.close()
print('icons written')
