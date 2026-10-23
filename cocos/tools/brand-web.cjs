const fs = require('node:fs');
const path = require('node:path');

module.exports = function brandWeb(output) {
 const source = path.resolve(__dirname, '../data/branding/intro_splash.png');
 fs.copyFileSync(source, path.join(output, 'frankfromfuture.png'));
 const settingsFile = fs.readdirSync(path.join(output, 'src')).find(n => /^settings(?:\.[^.]+)?\.json$/.test(n));
 const settingsPath = path.join(output, 'src', settingsFile), settings = JSON.parse(fs.readFileSync(settingsPath));
 settings.splashScreen = { ...settings.splashScreen, totalTime: 0, logo: { type: 'none' } };
 fs.writeFileSync(settingsPath, JSON.stringify(settings));
 const index = path.join(output, 'index.html');
 let html = fs.readFileSync(index, 'utf8').replace(/<title>.*?<\/title>/, '<title>StartX</title>');
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
