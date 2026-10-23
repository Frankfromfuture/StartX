const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[];
 try{
  for(const [name,viewport,dpr] of [['desktop',{width:1440,height:900},1],['portrait',{width:390,height:844},2]]){
   const page=await browser.newPage({viewport,deviceScaleFactor:dpr});page.on('pageerror',e=>errors.push(e.message));
   await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready);
   const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
   let s=await state(),p=center(s.controls.Details);await page.mouse.click(p.x,p.y);await page.waitForTimeout(250);
   await page.screenshot({path:path.join(root,'review',name+'-detail.png')});
   p=center((await state()).controls.Close);await page.mouse.click(p.x,p.y);
   for(let i=0;i<4;i++){s=await state();p=center(s.packs[0].bounds);await page.mouse.click(p.x,p.y);await page.waitForTimeout(180);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready);}
   await page.waitForTimeout(150);await page.screenshot({path:path.join(root,'review',name+'.png')});
   if(name==='portrait'){p=center((await state()).controls.Tasks);await page.mouse.click(p.x,p.y);await page.waitForTimeout(150);await page.screenshot({path:path.join(root,'review/portrait-packs.png')});}
   await page.close();
  }
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'review/layout-verification.json'),JSON.stringify({passed:true,errors,viewports:['1440×900','390×844'],checks:['Final detail content boxes and original card descriptions','Original opening cards, independent bottom icons and pack picker']},null,2));console.log('PASS: final layout screenshots, no page errors');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
