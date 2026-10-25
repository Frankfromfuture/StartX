const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),ts=require('typescript');
const root=path.resolve(__dirname,'..'),api={};
class Vec3 {
 constructor(x=0,y=0,z=0){Object.assign(this,{x,y,z});}
 static lerp(out,a,b,t){for(const axis of ['x','y','z'])out[axis]=a[axis]+(b[axis]-a[axis])*t;return out;}
 static distance(a,b){return Math.hypot(a.x-b.x,a.y-b.y,a.z-b.z);}
}
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'assets/scripts/CardFrameVolume.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText+'\nexports.outline = packOutline;', {exports:api,require:()=>({Vec3}),Math,Set});
const {packThickness,PACK_DEPTH_RATIO,PACK_PROFILE_STOPS}=api;
assert.equal(PACK_DEPTH_RATIO,.12);assert.equal(PACK_PROFILE_STOPS.length,6);
const close=(a,b)=>assert(Math.abs(a-b)<1e-8,`${a} != ${b}`);
for(const size of [64,112,336]){
 const outline=api.outline(size);
 assert(outline.length>60);assert(outline.every(p=>Number.isFinite(p.x)&&Number.isFinite(p.y)));
 close(Math.max(...outline.map(p=>p.y))-Math.min(...outline.map(p=>p.y)),size);
 for(const stop of PACK_PROFILE_STOPS)assert(outline.some(p=>Math.abs(p.y-size*stop)<1e-8));
 close(packThickness(size,0),size*.12);close(packThickness(size,.34*size),size*.12);
 close(packThickness(size,.42*size),size*.12*.45);close(packThickness(size,.5*size),size*.12*.45);
 close(packThickness(size,.38*size),size*.12*(1+.45)/2);
 for(const y of [0,.2,.34,.38,.42,.5])close(packThickness(size,y*size),packThickness(size,-y*size));
}
console.log('Passed: symmetric flat body, linear shoulders, thin constant seals, identical profile at shelf/board/preview sizes.');
