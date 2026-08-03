// Rasterizes the Notenra brand SVGs into the PNG assets the app ships.
//
//   assets/images/notenra_logo.svg   -> notenra_logo.png       (full lockup)
//                                       notenra_logo_white.png (reversed)
//   assets/images/notenra_mark.svg   -> notenra_mark.png       (mark only)
//                                       notenra_mark_white.png (reversed)
//                                       notenra_icon.png       (1024 launcher source)
//
// The SVGs are the source of truth; edit those, then run:
//   node tool/render_brand.js
//   dart run flutter_launcher_icons     # regenerate platform launcher icons
//
// Uses headless Chrome as the renderer so there's no native SVG toolchain to
// install. Set CHROME to override the browser path.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const ASSETS = path.join(ROOT, 'assets', 'images');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'notenra-brand-'));

const CHROME_CANDIDATES = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);

const chrome = CHROME_CANDIDATES.find((p) => fs.existsSync(p));
if (!chrome) {
  console.error('No Chrome/Chromium found. Set CHROME=/path/to/chrome.');
  process.exit(1);
}

// The lockup artwork sits at x 32..947, y 25..215 inside the 970x257 canvas;
// crop to it so the exported PNG carries no dead transparent margin.
const LOGO_BOX = '24 17 932 206';
const LW = 1864;
const LH = 412; // keeps the cropped 932:206 ratio

const logo = fs.readFileSync(path.join(ASSETS, 'notenra_logo.svg'), 'utf8');
const mark = fs.readFileSync(path.join(ASSETS, 'notenra_mark.svg'), 'utf8');

function prep(svg, { w, h, viewBox, white }) {
  let s = svg
    .replace(/<\?xml[^>]*\?>/, '')
    .replace(/width="\d+"/, `width="${w}"`)
    .replace(/height="\d+"/, `height="${h}"`);
  if (viewBox) s = s.replace(/viewBox="[^"]*"/, `viewBox="${viewBox}"`);
  // Reversed lockup: flatten every fill (solid + gradient) to white.
  if (white) s = s.replace(/fill="(#[0-9A-Fa-f]{6}|url\(#[^)]*\))"/g, 'fill="#FFFFFF"');
  return s;
}

function page(inner, { w, h, bg = 'transparent' }) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent}
    .stage{width:${w}px;height:${h}px;display:flex;align-items:center;
      justify-content:center;background:${bg};box-sizing:border-box}
    svg{display:block}
  </style></head><body><div class="stage">${inner}</div></body></html>`;
}

const jobs = [
  { out: 'notenra_logo.png', w: LW, h: LH,
    inner: prep(logo, { w: LW, h: LH, viewBox: LOGO_BOX }) },
  { out: 'notenra_logo_white.png', w: LW, h: LH,
    inner: prep(logo, { w: LW, h: LH, viewBox: LOGO_BOX, white: true }) },
  { out: 'notenra_mark.png', w: 512, h: 512,
    inner: prep(mark, { w: 512, h: 512 }) },
  { out: 'notenra_mark_white.png', w: 512, h: 512,
    inner: prep(mark, { w: 512, h: 512, white: true }) },
  // 1024 white square with the mark at 60% — the launcher-icon source.
  { out: 'notenra_icon.png', w: 1024, h: 1024, bg: '#FFFFFF',
    inner: prep(mark, { w: 614, h: 614 }) },
];

for (const j of jobs) {
  const html = path.join(TMP, j.out.replace('.png', '.html'));
  const png = path.join(ASSETS, j.out);
  fs.writeFileSync(html, page(j.inner, { w: j.w, h: j.h, bg: j.bg }));
  execFileSync(chrome, [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--force-device-scale-factor=1',
    '--default-background-color=00000000',
    `--screenshot=${png}`,
    `--window-size=${j.w},${j.h}`,
    `file:///${html.replace(/\\/g, '/')}`,
  ], { stdio: 'ignore' });
  console.log(`${j.out}  ${j.w}x${j.h}`);
}

fs.rmSync(TMP, { recursive: true, force: true });
