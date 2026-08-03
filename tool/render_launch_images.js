// Renders the Notenra mark at the densities Android and iOS need for their
// native launch screens (the frame shown before Flutter boots).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = 'd:/notenra';
const MARK = fs.readFileSync(`${ROOT}/assets/images/notenra_mark.svg`, 'utf8');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'notenra-launch-'));

// 160dp mark, centred — big enough to read, small enough not to crop on a
// narrow device.
const targets = [
  { out: `${ROOT}/android/app/src/main/res/mipmap-mdpi/launch_image.png`, px: 160 },
  { out: `${ROOT}/android/app/src/main/res/mipmap-hdpi/launch_image.png`, px: 240 },
  { out: `${ROOT}/android/app/src/main/res/mipmap-xhdpi/launch_image.png`, px: 320 },
  { out: `${ROOT}/android/app/src/main/res/mipmap-xxhdpi/launch_image.png`, px: 480 },
  { out: `${ROOT}/android/app/src/main/res/mipmap-xxxhdpi/launch_image.png`, px: 640 },
  { out: `${ROOT}/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`, px: 160 },
  { out: `${ROOT}/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png`, px: 320 },
  { out: `${ROOT}/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png`, px: 480 },
];

for (const t of targets) {
  const svg = MARK.replace(/<\?xml[^>]*\?>/, '')
    .replace(/width="\d+"/, `width="${t.px}"`)
    .replace(/height="\d+"/, `height="${t.px}"`);
  const html = path.join(TMP, `${t.px}-${path.basename(t.out)}.html`);
  fs.writeFileSync(html, `<!doctype html><html><head><meta charset="utf-8">
    <style>html,body{margin:0;padding:0;background:transparent}
    div{width:${t.px}px;height:${t.px}px;display:flex;align-items:center;justify-content:center}
    svg{display:block}</style></head><body><div>${svg}</div></body></html>`);
  execFileSync(CHROME, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars',
    '--force-device-scale-factor=1', '--default-background-color=00000000',
    `--screenshot=${t.out}`, `--window-size=${t.px},${t.px}`,
    `file:///${html.replace(/\\/g, '/')}`,
  ], { stdio: 'ignore' });
  console.log(`${t.px}px -> ${t.out.replace(ROOT + '/', '')}`);
}

fs.rmSync(TMP, { recursive: true, force: true });
