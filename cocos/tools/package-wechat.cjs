/** Creator 3.8.8 CLI can ignore the old per-folder compression settings.
 * Normalize its completed output to the engine adapter's supported local subpackage layout.
 * No engine code or source assets are changed. Safe to run on the same output again.
 */
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
function packageWechat(output) {
 const names = ['content', 'sample'];
 const settingsFile = fs.readdirSync(path.join(output, 'src')).find(n => /^settings\.[^.]+\.json$/.test(n));
 if (!settingsFile) throw new Error('Missing Creator settings');
 const settings = JSON.parse(fs.readFileSync(path.join(output, 'src', settingsFile)));
 for (const name of names) {
  const from = path.join(output, 'assets', name), to = path.join(output, 'subpackages', name);
  if (fs.existsSync(from)) {
   if (fs.existsSync(to)) throw new Error('Duplicate bundle output: ' + name);
   fs.mkdirSync(path.dirname(to), { recursive: true }); fs.renameSync(from, to);
  }
  const version = settings.assets.bundleVers[name], index = 'index.' + version + '.js';
  for (const file of [index, 'config.' + version + '.json']) if (!fs.existsSync(path.join(to, file))) throw new Error('Missing subpackage entry: ' + name + '/' + file);
  fs.writeFileSync(path.join(to, 'game.js'), `require('./${index}');\n`);
 }
 settings.assets.subpackages = Array.from(new Set([...(settings.assets.subpackages || []), ...names]));
 const body = JSON.stringify(settings), hash = crypto.createHash('md5').update(body).digest('hex').slice(0, 5), next = `settings.${hash}.json`;
 fs.writeFileSync(path.join(output, 'src', next), body);
 if (next !== settingsFile) {
  for (const file of fs.readdirSync(output).filter(n => n.endsWith('.js'))) {
   const location = path.join(output, file), script = fs.readFileSync(location, 'utf8');
   if (script.includes(settingsFile)) fs.writeFileSync(location, script.split(settingsFile).join(next));
  }
  fs.unlinkSync(path.join(output, 'src', settingsFile));
 }
 const gamePath = path.join(output, 'game.json'), game = JSON.parse(fs.readFileSync(gamePath));
 const existing = (game.subpackages || []).filter(s => !names.includes(s.name));
 game.subpackages = existing.concat(names.map(name => ({ name, root: `subpackages/${name}/` })));
 fs.writeFileSync(gamePath, JSON.stringify(game, null, 2) + '\n');
 const files = folder => fs.readdirSync(folder, { withFileTypes: true }).flatMap(e => e.isDirectory() ? files(path.join(folder,e.name)) : [path.join(folder,e.name)]);
 const all = files(output), size = list => list.reduce((n, f) => n + fs.statSync(f).size, 0);
 const mainBytes = size(all.filter(f => !path.relative(output,f).startsWith('subpackages/')));
 if (mainBytes > 4 * 1024 * 1024) throw new Error('WeChat main package exceeds 4 MiB: ' + mainBytes);
 const subpackages = game.subpackages.map(s => ({ name:s.name, bytes:size(files(path.join(output,s.root))) }));
 const report = { passed:true, mainBytes, subpackages, runtimeVerified:false, appId:JSON.parse(fs.readFileSync(path.join(output,'project.config.json'))).appid };
 fs.writeFileSync(path.resolve(output,'../../review/wechat-package.json'),JSON.stringify(report,null,2)+'\n');
 return report;
}
module.exports = { packageWechat };
if (require.main === module) console.log(JSON.stringify(packageWechat(path.resolve(__dirname,'../build/wechatgame')),null,2));
