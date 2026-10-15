import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {createPreview} from './preview.mjs';
const argument=name=>process.argv.find(value=>value.startsWith(name+'='))?.slice(name.length+1);
const modulePath=argument('--playwright');
const axePath=argument('--axe');
const {chromium,webkit}=await import(modulePath?pathToFileURL(resolve(modulePath)).href:'playwright');
const axeModule=await import(axePath?pathToFileURL(resolve(axePath)).href:'@axe-core/playwright');
const AxeBuilder=axeModule.AxeBuilder||axeModule.default;
await mkdir('test/scratch/browser-check',{recursive:true});
await mkdir('artifacts',{recursive:true});
const report={pages:[],interactions:[],accessibility:[],limitations:[]};
const server=createPreview();
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${server.address().port}`;
const pass=name=>{report.interactions.push(name);console.log('PASS',name);};
let browser;
try{
 browser=await chromium.launch({headless:true});
 const context=await browser.newContext({viewport:{width:390,height:844},reducedMotion:'reduce'});
 await context.grantPermissions(['clipboard-read','clipboard-write']);
 const page=await context.newPage();
 const errors=[];const failed=[];
 page.on('pageerror',error=>errors.push(error.message));
 page.on('console',msg=>{if(msg.type()==='error')errors.push(msg.text());});
 page.on('requestfailed',req=>failed.push(new URL(req.url()).pathname));
 page.on('response',response=>{if(response.status()>=400)failed.push(new URL(response.url()).pathname);});
 for(const name of ['index.html','404.html']){
  for(const width of [320,375,390,768,1440,1920]){
   await page.setViewportSize({width,height:844});
   await page.goto(`${base}/preview/${name}`);await page.waitForLoadState('networkidle');
   await page.evaluate(async()=>{await document.fonts.ready;for(const img of document.images)img.loading='eager';await Promise.all([...document.images].map(img=>img.decode().catch(()=>{})));});
   const layout=await page.evaluate(()=>({width:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth,broken:[...document.images].filter(i=>!i.complete||i.naturalWidth===0).map(i=>i.getAttribute('src'))}));
   assert.ok(layout.scroll<=layout.width,`${name}: overflow at ${width}`);
   assert.deepEqual(layout.broken,[],`${name}: broken images`);
   report.pages.push({page:name,width,overflow:false,brokenImages:0});
   if(name==='index.html'&&width<=390){
    await page.locator('#bee-tip').click();
    const tip=await page.locator('#bee-popover').boundingBox();
    const control=await page.locator('.range-label').boundingBox();
    assert.ok(tip.y+tip.height<=control.y,`Bee explanation covers the range control at ${width}`);
    await page.locator('#close-bee').click();await page.evaluate(()=>window.scrollTo(0,0));
   }
   if(name==='index.html'&&width===390){
    const box=await page.locator('#range-width').boundingBox();assert.ok(box.y+box.height<=844,'slider is below first screen');
    await page.screenshot({path:'artifacts/mobile.jpg',type:'jpeg',quality:75});
    report.firstScreen={width:390,height:844,sliderBottom:box.y+box.height};
   }
   if(name==='index.html'&&width===1440)await page.screenshot({path:'artifacts/desktop.jpg',type:'jpeg',quality:78,fullPage:true});
   if(width===375||width===1440){
    const scan=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze();
    report.accessibility.push({page:name,width,violations:scan.violations.map(v=>({id:v.id,impact:v.impact,nodes:v.nodes.map(n=>n.target)}))});
    assert.equal(scan.violations.length,0,`${name} ${width}: axe violations ${JSON.stringify(scan.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)})))}`);
   }
  }
 }
 await page.setViewportSize({width:390,height:844});await page.goto(`${base}/preview/`);await page.waitForLoadState('networkidle');
 assert.equal(await page.locator('#sun-address').textContent(),'launching…');
 assert.ok(await page.locator('#copy-sun').isDisabled());assert.ok(await page.locator('#market-values').isHidden());
 pass('Empty launch data: no invented address, prices or Buy links');
 const slider=page.locator('#range-width');await slider.focus();await slider.press('Home');assert.equal(await slider.inputValue(),'5');assert.equal(await page.locator('#risk-tier').textContent(),'Narrow range');
 assert.equal(await page.locator('[data-plant=main] use').getAttribute('href'),'#seed-art');
 const narrow=await page.locator('[data-plant=main]').getAttribute('style');
 await slider.press('End');assert.equal(await slider.inputValue(),'80');assert.equal(await page.locator('#risk-tier').textContent(),'Wide range');
 assert.notEqual(await page.locator('[data-plant=main]').getAttribute('style'),narrow);
 assert.equal(await page.locator('[data-plant=main] use').getAttribute('href'),'#plant-art');
 const focus=await slider.evaluate(el=>({color:getComputedStyle(el).outlineColor,width:getComputedStyle(el).outlineWidth}));assert.notEqual(focus.width,'0px');
 pass('Keyboard range endpoints update flowers, risk, chart bounds and visible focus');
 await page.locator('#bee-tip').click();assert.ok(await page.locator('#bee-popover').isVisible());await page.keyboard.press('Escape');assert.ok(await page.locator('#bee-popover').isHidden());
 pass('Bee explanation opens and Escape restores focus');
 await page.locator('[data-tier=narrow]').click();assert.equal(await slider.inputValue(),'10');
 pass('Risk-tier buttons synchronize the range');
 const chart=page.locator('#range-chart');await chart.scrollIntoViewIfNeeded();const c=await chart.boundingBox();
 await page.mouse.move(c.x+c.width*.7,c.y+c.height/2);await page.mouse.down();await page.mouse.move(c.x+c.width*.88,c.y+c.height/2,{steps:5});await page.mouse.up();assert.ok(Number(await slider.inputValue())>60);
 pass('Pointer drag adjusts the chart selection and range model');
 await page.locator('#menu-toggle').click();assert.ok(await page.locator('#mobile-nav').isVisible());await page.keyboard.press('Escape');assert.ok(await page.locator('#mobile-nav').isHidden());
 await page.locator('#menu-toggle').click();await page.locator('#mobile-nav a[href="#tokenomics"]').click();assert.ok(await page.locator('#mobile-nav').isHidden());
 pass('Mobile navigation opens, closes on Escape and follows anchors');
 await page.locator('#buy-tab-1').focus();await page.keyboard.press('ArrowRight');assert.ok(await page.locator('#buy-panel-2').isVisible());await page.keyboard.press('End');assert.ok(await page.locator('#buy-panel-3').isVisible());await page.keyboard.press('Home');assert.ok(await page.locator('#buy-panel-1').isVisible());await page.locator('[data-next-step="2"]').click();assert.ok(await page.locator('#buy-panel-2').isVisible());
 pass('Buying guide supports click, next buttons, arrows, Home and End');
 await page.locator('[data-copy]').first().click();assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127');
 await page.locator('#copy-link').click();assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'https://sunflowergardensun.si-md.xyz/');
 for(const link of await page.locator('[data-share]').all()){const url=new URL(await link.getAttribute('href'));assert.equal(url.hostname,'x.com');assert.ok(url.searchParams.get('text'));assert.equal(url.searchParams.get('url'),'https://sunflowergardensun.si-md.xyz/');}
 const downloadPromise=page.waitForEvent('download');await page.locator('.meme-download').first().click();const download=await downloadPromise;assert.equal(download.suggestedFilename(),'sunflower-garden-1.png');
 for(const link of await page.locator('.meme-download').all()){const response=await page.request.get(new URL(await link.getAttribute('href'),`${base}/preview/`).href);assert.ok(response.ok());assert.equal(response.headers()['content-type'],'image/png');}
 pass('Address and page copying, three X share intents, six PNG downloads');
 // Synthetic responses are test-only and never written to site/ or dist/.
 const sample={token:'0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127',coinUrl:'https://example.test/coin',chartUrl:'https://example.test/chart',logo:`${base}/preview/assets/logo.svg`,market:{priceUsd:0.00025,marketCap:2500,volume24h:0}};
 await page.route('**/simd-coin.json',route=>route.fulfill({json:sample}));
 await page.locator('#refresh-market').click();await page.waitForFunction(()=>document.querySelector('#sun-address').textContent!=='launching…');
 assert.equal(await page.locator('#sun-address').textContent(),sample.token);assert.equal(await page.locator('[data-live-link=coinUrl]').getAttribute('href'),sample.coinUrl);assert.equal(await page.locator('[data-live-link=chartUrl]').getAttribute('href'),sample.chartUrl);
 assert.equal(await page.locator('#volume-value').textContent(),'$0');assert.ok(await page.locator('#market-values').isVisible());assert.ok((await page.locator('[data-logo]').first().getAttribute('src')).endsWith('logo.svg'));
 await page.locator('#copy-sun').click();assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),sample.token);
 pass('Live feed populates complete address, valid zero volume, dynamic Buy/Chart and preferred logo');
 await page.unroute('**/simd-coin.json');await page.route('**/simd-coin.json',route=>route.fulfill({json:{token:'bad',coinUrl:'javascript:alert(1)',market:{priceUsd:-2,volume24h:'bad'}}}));
 await page.locator('#refresh-market').click();await page.waitForFunction(()=>document.querySelector('#sun-address').textContent==='launching…');assert.ok(await page.locator('#market-values').isHidden());assert.ok(await page.locator('[data-live-link=coinUrl]').isHidden());
 pass('Malformed data removes stale addresses and rejects unsafe links and invalid prices');
 await page.unroute('**/simd-coin.json');await page.route('**/simd-coin.json',route=>route.fulfill({status:200,contentType:'application/json',body:'not json'}));await page.locator('#refresh-market').click();await page.waitForFunction(()=>document.querySelector('#market-status').textContent.includes('Refresh failed'));
 pass('Invalid JSON yields a recoverable refresh state');
 await page.unroute('**/simd-coin.json');await page.route('**/simd-coin.json',route=>route.fulfill({json:sample}));await page.locator('#refresh-market').click();await page.waitForFunction(()=>document.querySelector('#market-status').textContent.includes('Updated'));
 pass('Refresh recovers after failure');
 let refreshes=0;await page.unroute('**/simd-coin.json');await page.route('**/simd-coin.json',route=>{refreshes++;return route.fulfill({json:sample});});
 await page.clock.install();await page.goto(`${base}/preview/`);await page.waitForLoadState('networkidle');const before=refreshes;await page.clock.fastForward(30001);await page.waitForTimeout(100);assert.ok(refreshes>before);await page.clock.uninstall?.();
 pass('Live data automatically refreshes at 30 seconds (virtual clock)');
 const animations=await page.evaluate(()=>document.getAnimations().filter(a=>a.playState==='running').length);assert.equal(animations,0);
 pass('Reduced-motion preference disables all running animations');
 // Test the manual control in a fresh context with normal motion.
 const motionContext=await browser.newContext({reducedMotion:'no-preference'});const motionPage=await motionContext.newPage();await motionPage.goto(`${base}/preview/`);await motionPage.locator('#motion-toggle').click();assert.equal(await motionPage.evaluate(()=>document.getAnimations().filter(a=>a.playState==='running').length),0);await motionContext.close();
 pass('Pause motion control stops decorative animation');
 // Validate every local static link independently of anchor scrolling.
 const localLinks=await page.locator('a[href]').evaluateAll(links=>links.map(a=>a.getAttribute('href')).filter(href=>href&&!href.startsWith('#')&&!/^(https?:|mailto:)/.test(href)));
 for(const link of localLinks){const response=await page.request.get(new URL(link,`${base}/preview/`).href);assert.ok(response.ok(),`Broken link ${link}`);}
 assert.deepEqual(errors,[],'Unexpected page/console errors');assert.deepEqual(failed,[],'Unexpected failed requests');
 report.consoleErrors=0;report.failedRequests=0;
 pass('All local links resolve; no console errors or failed resources in checked states');
 await context.close();await browser.close();browser=null;
 try{
  const safari=await webkit.launch({headless:true});
  try{const p=await safari.newPage({viewport:{width:390,height:844},reducedMotion:'reduce'});await p.goto(`${base}/preview/`);await p.locator('#range-width').focus();await p.keyboard.press('End');assert.equal(await p.locator('#range-width').inputValue(),'80');await p.locator('#bee-tip').click();assert.ok(await p.locator('#bee-popover').isVisible());report.webkit='Range and bee interactions passed';}finally{await safari.close();}
 }catch{report.webkit='Not run: WebKit runtime could not launch in the available environment';report.limitations.push('WebKit and physical-device behavior remain unverified.');}
 report.limitations.push('No manual screen-reader session or browser-native zoom; automated reflow checked at 320px.','No live transaction, wallet connection or deployed market feed; runtime integration exercised with clearly isolated fixtures.');
 await writeFile('artifacts/browser-validation.json',JSON.stringify(report,null,2)+'\n');
 console.log('Browser validation complete.');
}finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
