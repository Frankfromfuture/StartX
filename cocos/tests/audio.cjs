const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2}),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const resources=JSON.parse(fs.readFileSync(path.join(root,'review/audio-resources.json')));
for(const r of resources){
 assert.equal(hash(fs.readFileSync(path.join(root,'..',r.source))),r.sourceSha256);
 const wav=fs.readFileSync(path.join(root,'assets/content/audio',r.name+'.wav'));let pcm;
 for(let i=12;i+8<=wav.length;){const n=wav.readUInt32LE(i+4);if(wav.toString('ascii',i,i+4)==='data')pcm=wav.subarray(i+8,i+8+n);i+=8+n+n%2;}
 assert(pcm&&pcm.some(v=>v!==0));assert.equal(hash(pcm),r.pcmSha256);
}
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[],checks=[];
 try{
  const ctx=await browser.newContext({viewport:{width:1440,height:900}}),page=await ctx.newPage();
  const watch=p=>{p.on('pageerror',e=>errors.push(e.message));p.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text());});};watch(page);
  const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
  const count=(s,name,type='request')=>s.audio.events.filter(e=>e.name===name&&e.type===type).length;
  const waitSound=async(name,n,type='started')=>page.waitForFunction(({name,n,type})=>window.__STARTX_SAMPLE__().audio.events.filter(e=>e.name===name&&e.type===type).length===n,{name,n,type});
  await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready&&window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));
  let s=await state();assert.equal(s.audio.loaded,7);assert.deepEqual(s.audio.events,[]);
  const drag=async(uid,target,sound)=>{
   let s=await state(),a=center(s.cards.find(c=>c.uid===uid).bounds),b=typeof target==='number'?center(s.cards.find(c=>c.uid===target).bounds):target;
   const grabs=count(s,'grab'),drops=count(s,sound);
   await page.mouse.move(a.x,a.y);await page.mouse.down();await page.mouse.move(b.x,b.y,{steps:14});
   await waitSound('grab',grabs+1);await page.mouse.up();await waitSound(sound,drops+1);
   s=await state();assert.equal(count(s,'grab'),grabs+1);assert.equal(count(s,sound),drops+1);
  };
  let founder=s.cards.find(c=>c.id==='founder');let p=center(founder.bounds);await drag(founder.uid,{x:p.x+45,y:p.y},'founder');
  for(let i=0;i<4;i++){
   s=await state();const n=count(s,'unpack'),p=center(s.packs[0].bounds);await page.mouse.click(p.x,p.y);await waitSound('unpack',n+1);
   await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready&&window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));
  }
  s=await state();assert.equal(s.packs.length,0);assert.equal(count(s,'unpack'),4);assert.equal(count(s,'resource_down'),0,'Original pack resource release has no extra landing sound');
  const office=s.cards.find(c=>c.id==='p1_office');p=center(office.bounds);await drag(office.uid,{x:p.x-20,y:p.y+20},'resource_down');
  s=await state();const cash=s.cards.filter(c=>c.id==='cash').at(-1);p=center(cash.bounds);await drag(cash.uid,{x:p.x+25,y:p.y+15},'cash_down');
  s=await state();const before=count(s,'down');
  await drag(s.cards.find(c=>c.id==='founder').uid,s.cards.find(c=>c.id==='p1_neighborhood').uid,'founder');
  await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cards.some(c=>c.id==='p1_youth'),null,{timeout:12000});
  s=await state();const born=Date.now();assert.equal(count(s,'down'),before,'Production landing sound waits for flight');
  await waitSound('down',before+1);s=await state();
  assert(s.audio.events.findLast(e=>e.name==='down'&&e.type==='request').time-born>=180);
  assert(s.audio.events.some(e=>e.name==='aha'&&e.type==='started'),'Original task completion prompt');
  assert(s.audio.events.every(e=>Math.abs(e.volume-.8)<.0001));
  checks.push('Desktop: seven original PCM sources, actual AudioSource playback, one grab/drop per gesture, founder/resource/cash/human variants, four unpack sounds and production landing timing');
  await ctx.close();
  const touch=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true}),tp=await touch.newPage();watch(tp);
  await tp.goto('http://127.0.0.1:4173/?review=1');await tp.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready&&window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));
  const ts=()=>tp.evaluate(()=>window.__STARTX_SAMPLE__());s=await ts();const original=s.position;
  await tp.touchscreen.tap(s.viewport.x+s.viewport.width*.7,s.viewport.y+s.viewport.height*.9);
  s=await ts();p=center(s.card);const cdp=await touch.newCDPSession(tp);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{...p,id:1}]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:p.x+35,y:p.y+45,id:1}]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchCancel',touchPoints:[]});
  await tp.waitForFunction(()=>['grab','founder'].every(name=>window.__STARTX_SAMPLE__().audio.events.some(e=>e.type==='started'&&e.name===name)));
  s=await ts();assert.deepEqual(s.position,original);assert.equal(count(s,'grab'),1);assert.equal(count(s,'founder'),1);
  await tp.evaluate(()=>window.dispatchEvent(new Event('blur')));
  await tp.waitForFunction(()=>!window.__STARTX_SAMPLE__().audio.active&&window.__STARTX_SAMPLE__().audio.voices.every(v=>!v.playing));
  await tp.evaluate(()=>window.dispatchEvent(new Event('focus')));s=await ts();p=center(s.packs[0].bounds);await tp.touchscreen.tap(p.x,p.y);
  await tp.waitForFunction(()=>window.__STARTX_SAMPLE__().audio.events.some(e=>e.type==='started'&&e.name==='unpack'));
  checks.push('Portrait touch: audio after user gesture, one grab and drop on touch cancellation, stopped voices on blur and working unpack sound after focus');
  await touch.close();assert.deepEqual(errors,[]);
  const report={passed:true,resources:resources.length,checks,errors};fs.writeFileSync(path.join(root,'review/audio-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
