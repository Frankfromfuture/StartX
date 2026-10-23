const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { syncContent } = require('./sync-content.cjs');
const root = path.resolve(__dirname, '..');
const platform = process.argv[2];
if (!['web-mobile', 'wechatgame'].includes(platform)) throw new Error('Choose web-mobile or wechatgame');
const creator = process.env.COCOS_CREATOR || path.join(os.homedir(), 'Applications/CocosCreator-3.8.8/CocosCreator.app/Contents/MacOS/CocosCreator');
if (!fs.existsSync(creator)) throw new Error('Set COCOS_CREATOR to the Cocos Creator 3.8.8 executable.');
const config = JSON.parse(fs.readFileSync(path.join(root, 'config', platform + '.json')));
if (platform === 'wechatgame' && process.env.WECHAT_APPID) config.packages.wechatgame.appid = process.env.WECHAT_APPID;
fs.mkdirSync(path.join(root, 'temp'), { recursive: true });
const configPath = path.join(root, 'temp', `build-${platform}.json`);
fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
async function build() {
    const synced = await syncContent();
    // A data or artwork edit requires importing assets, even when a script-only build was requested.
    const scriptsOnly = process.argv.includes('--scripts-only') && synced.changed.length === 0;
    const child = spawn(creator, ['--project', root, '--build', `configPath=${configPath}${scriptsOnly ? ';buildMode=script' : ''}`], { stdio: 'inherit' });
    child.on('error', e => { console.error(e); process.exitCode = 1; });
    child.on('exit', code => {
      // Creator documents 36 as its successful CLI-build exit code.
      if (code !== 0 && code !== 36) { process.exitCode = code || 1; return; }
      const output = path.join(root, 'build', platform);
      const entry = path.join(output, platform === 'wechatgame' ? 'game.js' : 'index.html');
      if (!fs.existsSync(entry)) { console.error('Missing build entry:', entry); process.exitCode = 1; return; }
      for (const [name, required] of [['sample', 'prefabs/Hud'], ['content', 'faces/founder']]) {
        const bundle = [path.join(output, 'assets', name), path.join(output, 'subpackages', name)].find(p => fs.existsSync(p));
        const file = bundle && fs.readdirSync(bundle).find(n => /^config(?:\.[^.]+)?\.json$/.test(n));
        const config = file && JSON.parse(fs.readFileSync(path.join(bundle, file)));
        if (!config || !Object.values(config.paths || {}).some(p => p[0] === required)) {
          console.error('Incomplete built bundle:', name, 'missing', required); process.exitCode = 1; return;
        }
      }
      if (fs.existsSync(path.join(root, 'licenses'))) fs.cpSync(path.join(root, 'licenses'), path.join(output, 'licenses'), { recursive: true });
      if (platform === 'web-mobile') require('./brand-web.cjs')(output);
      if (platform === 'wechatgame') {
        try { console.log(require('./package-wechat.cjs').packageWechat(output)); }
        catch (error) { console.error(error); process.exitCode = 1; return; }
      }
      console.log(`Built ${platform}: ${output}`);
    });
}
build().catch(error => { console.error(error.message); process.exitCode = 1; });
