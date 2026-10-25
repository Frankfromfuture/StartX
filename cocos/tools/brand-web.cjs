const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

module.exports = function brandWeb(output) {
 const source = path.resolve(__dirname, '../data/branding/intro_splash.png');
 fs.copyFileSync(source, path.join(output, 'frankfromfuture.png'));
 const icon = fs.readFileSync(path.resolve(__dirname, '../assets/content/ui/card-back.png'));
 const iconName = 'startx-icon-' + crypto.createHash('sha256').update(icon).digest('hex').slice(0, 12) + '.png';
 fs.writeFileSync(path.join(output, iconName), icon);
 const settingsFile = fs.readdirSync(path.join(output, 'src')).find(n => /^settings(?:\.[^.]+)?\.json$/.test(n));
 const settingsPath = path.join(output, 'src', settingsFile), settings = JSON.parse(fs.readFileSync(settingsPath));
 settings.splashScreen = { ...settings.splashScreen, totalTime: 0, logo: { type: 'none' } };
 // The frame owns its logical dimensions when a player selects landscape or portrait.
 settings.screen = { ...settings.screen, exactFitScreen: false };
 fs.writeFileSync(settingsPath, JSON.stringify(settings));
 const index = path.join(output, 'index.html');
 let html = fs.readFileSync(index, 'utf8').replace(/<title>.*?<\/title>/, '<title>StartX</title>');
 html = html.replace(/<link\b[^>]*\brel=["'](?:icon|shortcut icon|apple-touch-icon)["'][^>]*>\s*/gi, '');
 html = html.replace('</head>', `<link rel="icon" type="image/png" href="${iconName}">\n<link rel="apple-touch-icon" href="${iconName}">\n</head>`);
 if (!html.includes('id="startx-loading"')) {
  html = html.replace('</head>', '<link rel="preload" as="image" href="frankfromfuture.png">\n</head>');
  html = html.replace('<body>', `<body>
  <div id="startx-loading" aria-label="FrankFromFuture Studio">
    <img src="frankfromfuture.png" alt="FrankFromFuture Studio 猫咪 Logo" fetchpriority="high">
  </div>
  <style>
    html, body { background: #171512; }
    #startx-loading { position: fixed; inset: 0; z-index: 9999; display: flex; align-items: center; justify-content: center; overflow: hidden; background: #171512; }
    #startx-loading img { height: min(100vh, 190vw); width: auto; max-width: none; flex: none; }
  </style>`);
 }
 fs.writeFileSync(index, html);
 console.log('Branded web startup with original FrankFromFuture cat logo.');
};
