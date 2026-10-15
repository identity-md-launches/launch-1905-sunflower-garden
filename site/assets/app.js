// @ts-check
import {rangeModel, TIERS, normalizeCoin, formatUsd, SHARE_TEXTS, SITE_URL} from './model.js';
/** @template {Element} T @param {string} selector @returns {T} */
function need(selector) {
  const element = document.querySelector(selector);
  if (!element) throw new Error(`Missing interface element: ${selector}`);
  return /** @type {T} */ (element);
}
const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
let paused = false;
const canAnimate = () => !reduced.matches && !paused;
const slider = /** @type {HTMLInputElement} */ (need('#range-width'));
const toast = /** @type {HTMLElement} */ (need('#toast'));
let toastTimeout = 0;
/** @param {string} message */
function announce(message) {
  clearTimeout(toastTimeout);
  toast.textContent = message;
  toast.classList.add('visible');
  toastTimeout = window.setTimeout(() => toast.classList.remove('visible'), 4500);
}
/** @param {number} value */
function renderRange(value) {
  const model = rangeModel(value);
  slider.value = String(model.width);
  slider.style.setProperty('--range-progress', `${model.progress * 100}%`);
  slider.setAttribute('aria-valuetext', `Plus or minus ${model.width} percent. ${model.explanation.title}.`);
  need('#range-value').textContent = `±${model.width}%`;
  need('#chart-width').textContent = `±${model.width}%`;
  need('#range-bounds').textContent = `${model.lower.toFixed(2)}–${model.upper.toFixed(2)}×`;
  need('#risk-tier').textContent = model.explanation.title;
  need('#range-risk').textContent = `${model.explanation.title}. ${model.explanation.description}`;
  need('#bee-tip-title').textContent = model.explanation.tagline;
  need('#bee-tip-copy').textContent = model.explanation.description;
  for (const [name, ratio] of [['main', 1], ['side', .6], ['small', .47]]) {
    const plant = /** @type {SVGElement} */ (need(`[data-plant="${name}"]`));
    plant.style.transform = `scale(${model.flowerScale * Number(ratio)})`;
    plant.querySelector("use")?.setAttribute("href", model.width <= 7 ? "#seed-art" : model.width < 20 ? "#sprout-art" : "#plant-art");
  }
  const fill = need('#honey-fill');
  fill.setAttribute('y', String(290 - model.progress * 52));
  fill.setAttribute('height', String(10 + model.progress * 52));
  document.querySelectorAll('.bee').forEach((element) => {
    /** @type {SVGElement} */ (element).style.animationDuration = `${1.8 + model.progress * 5}s`;
  });
  need('#chart-selection').setAttribute('x', String(280 - model.chartHalf));
  need('#chart-selection').setAttribute('width', String(model.chartHalf * 2));
  need('#chart-handle-left').setAttribute('transform', `translate(${280-model.chartHalf} 60)`);
  need('#chart-handle-right').setAttribute('transform', `translate(${280+model.chartHalf} 60)`);
  document.querySelectorAll('[data-tier]').forEach((element) => element.setAttribute('aria-pressed', String(/** @type {HTMLElement} */ (element).dataset.tier === model.tier)));
}
slider.addEventListener('input', () => renderRange(Number(slider.value)));
renderRange(Number(slider.value));
const chart = /** @type {SVGSVGElement} */ (need('#range-chart'));
let dragging = false;
/** @param {PointerEvent} event */
function dragRange(event) {
  if (!dragging) return;
  const rect = chart.getBoundingClientRect();
  renderRange(Math.abs((event.clientX - rect.left) / rect.width * 560 - 280) / 3);
}
chart.addEventListener('pointerdown', (event) => {dragging=true;chart.setPointerCapture(event.pointerId);dragRange(event);});
chart.addEventListener('pointermove', dragRange);
chart.addEventListener('pointerup', () => {dragging=false;});
chart.addEventListener('pointercancel', () => {dragging=false;});
document.querySelectorAll('[data-tier]').forEach((element) => element.addEventListener('click', () => {
  const tier = /** @type {keyof typeof TIERS} */ (/** @type {HTMLElement} */ (element).dataset.tier);
  renderRange(TIERS[tier].width);
}));
const beeButton = /** @type {HTMLButtonElement} */ (need('#bee-tip'));
const beePopover = /** @type {HTMLElement} */ (need('#bee-popover'));
function closeBee() {beeButton.setAttribute('aria-expanded','false');beePopover.hidden=true;}
beeButton.addEventListener('click', () => {const open=beePopover.hidden;beePopover.hidden=!open;beeButton.setAttribute('aria-expanded',String(open));});
need('#close-bee').addEventListener('click', () => {closeBee();beeButton.focus();});
const menuButton = /** @type {HTMLButtonElement} */ (need('#menu-toggle'));
const mobileMenu = /** @type {HTMLElement} */ (need('#mobile-nav'));
function closeMenu() {mobileMenu.hidden=true;menuButton.setAttribute('aria-expanded','false');menuButton.setAttribute('aria-label','Open menu');}
menuButton.addEventListener('click', () => {const open=mobileMenu.hidden;mobileMenu.hidden=!open;menuButton.setAttribute('aria-expanded',String(open));menuButton.setAttribute('aria-label',open?'Close menu':'Open menu');});
mobileMenu.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => closeMenu()));
window.matchMedia('(min-width: 761px)').addEventListener('change', (event) => {if(event.matches)closeMenu();});
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (!beePopover.hidden) {closeBee();beeButton.focus();}
  if (!mobileMenu.hidden) {closeMenu();menuButton.focus();}
});
const motionButton=/** @type {HTMLButtonElement} */ (need('#motion-toggle'));
function motionLabel() {
  motionButton.setAttribute('aria-label', paused ? 'Resume garden motion' : 'Pause garden motion');
  motionButton.setAttribute('aria-pressed',String(paused));
}
motionButton.addEventListener('click', () => {paused=!paused;document.documentElement.classList.toggle('motion-paused',paused);motionLabel();announce(paused?'Garden motion paused.':'Garden motion follows your device preference.');});
if ('IntersectionObserver' in window) {
  const observer=new IntersectionObserver(entries => entries.forEach(entry => {if(entry.isIntersecting){entry.target.classList.add('entered');observer.unobserve(entry.target);}}),{threshold:.08});
  document.querySelectorAll('.reveal').forEach((element,index) => {/** @type {HTMLElement} */(element).style.animationDelay=`${index%2*100}ms`;observer.observe(element);});
}
document.querySelectorAll('.magnetic').forEach(element => {
  const el=/** @type {HTMLElement} */(element);
  el.addEventListener('pointermove',event=>{if(!canAnimate()||event.pointerType!=='mouse')return;const r=el.getBoundingClientRect();el.style.transform=`translate(${(event.clientX-r.left-r.width/2)*.035}px,${(event.clientY-r.top-r.height/2)*.08}px)`;});
  el.addEventListener('pointerleave',()=>{el.style.transform='';});
});
const tabs=Array.from(document.querySelectorAll('[role=tab]'));
/** @param {number} index @param {boolean} [focus] */
function selectStep(index,focus=false) {
  tabs.forEach((tab,i)=>{tab.setAttribute('aria-selected',String(i===index));tab.setAttribute('tabindex',i===index?'0':'-1');/** @type {HTMLElement} */(need(`#buy-panel-${i+1}`)).hidden=i!==index;});
  if(focus)/** @type {HTMLButtonElement} */(tabs[index]).focus();
}
tabs.forEach((tab,index)=>{
  tab.addEventListener('click',()=>selectStep(index));
  tab.addEventListener('keydown',event=>{const e=/** @type {KeyboardEvent} */(event);let next=index;if(e.key==='ArrowRight'||e.key==='ArrowDown')next=(index+1)%3;else if(e.key==='ArrowLeft'||e.key==='ArrowUp')next=(index+2)%3;else if(e.key==='Home')next=0;else if(e.key==='End')next=2;else return;e.preventDefault();selectStep(next,true);});
});
document.querySelectorAll('[data-next-step]').forEach(el=>el.addEventListener('click',()=>selectStep(Number(/** @type {HTMLElement} */(el).dataset.nextStep)-1,true)));
/** @param {string} value */
async function copy(value) {
  try {await navigator.clipboard.writeText(value);announce('Copied to clipboard.');}
  catch {announce('Copy is unavailable. Select the full address or page URL and copy it manually.');}
}
document.querySelectorAll('[data-copy]').forEach(el=>el.addEventListener('click',()=>copy(/** @type {HTMLElement} */(el).dataset.copy||'')));
need('#copy-link').addEventListener('click',()=>copy(SITE_URL));
for(const el of document.querySelectorAll('[data-share]')) {
  const link=/** @type {HTMLAnchorElement} */(el);
  const key=/** @type {keyof typeof SHARE_TEXTS} */(link.dataset.share);
  link.href=`https://x.com/intent/post?${new URLSearchParams({text:SHARE_TEXTS[key],url:SITE_URL})}`;
}
/** @type {string|null} */let token=null;
need('#copy-sun').addEventListener('click',()=>{if(token)copy(token);});
/** @type {AbortController|null} */let activeRequest=null;
/** @type {Date|null} */let lastUpdated=null;
const statKeys=/** @type {const} */(['priceUsd','marketCap','volume24h']);
const statIds={priceUsd:'#price-value',marketCap:'#cap-value',volume24h:'#volume-value'};
/** @type {Map<Element,number>} */const valueFrames=new Map();
/** @param {HTMLElement} element @param {number} value @param {boolean} price */
function animateValue(element,value,price) {
  cancelAnimationFrame(valueFrames.get(element)||0);
  const previous=element.dataset.value === undefined ? value : Number(element.dataset.value);
  element.dataset.value=String(value);
  if(!canAnimate()||previous===value){element.textContent=formatUsd(value,price);return;}
  const start=performance.now();
  /** @param {number} now */const frame=now=>{const t=Math.min(1,(now-start)/450);element.textContent=formatUsd(previous+(value-previous)*(1-(1-t)**3),price);if(t<1)valueFrames.set(element,requestAnimationFrame(frame));};
  valueFrames.set(element,requestAnimationFrame(frame));
}
/** @param {unknown} data */
function applyCoin(data) {
  const coin=normalizeCoin(data,location.origin);
  token=coin.token;
  need('#sun-address').textContent=token||'launching…';
  /** @type {HTMLButtonElement} */(need('#copy-sun')).disabled=!token;
  document.querySelectorAll('[data-live-link]').forEach(el=>{
    const link=/** @type {HTMLAnchorElement} */(el);
    const value=link.dataset.liveLink==='coinUrl'?coin.coinUrl:coin.chartUrl;
    link.hidden=!value;
    if(value)link.href=value;else link.removeAttribute('href');
  });
  document.querySelectorAll('.launch-wait').forEach(el=>{/** @type {HTMLElement} */(el).hidden=!!coin.coinUrl;});
  document.querySelectorAll('[data-logo]').forEach(el=>{
    const image=/** @type {HTMLImageElement} */(el);
    const fallback=new URL('./assets/logo-1.png',document.baseURI).href;
    const next=coin.logo||fallback;
    image.onerror=()=>{image.onerror=null;image.src=fallback;};
    if(image.src!==next)image.src=next;
  });
  let count=0;
  for(const key of statKeys){
    const value=coin.market[key];
    /** @type {HTMLElement} */(need(`[data-stat="${key}"]`)).hidden=value===null;
    if(value!==null){count++;animateValue(need(statIds[key]),value,key==='priceUsd');}
  }
  /** @type {HTMLElement} */(need('#market-values')).hidden=count===0;
  lastUpdated=new Date();
  need('#market-status').textContent=count?`Updated ${lastUpdated.toLocaleTimeString('en-US',{hour:'2-digit',minute:'2-digit'})} · every 30 seconds`:token?'Token launched · market data unavailable':'Waiting for launch data';
}
async function refreshMarket() {
  if(activeRequest)return;
  activeRequest=new AbortController();
  const controller=activeRequest;
  const timeout=window.setTimeout(()=>controller.abort(),8000);
  const refresh=/** @type {HTMLButtonElement} */(need('#refresh-market'));
  refresh.disabled=true;
  refresh.setAttribute('aria-busy','true');
  try {
    const response=await fetch('/simd-coin.json',{cache:'no-store',signal:controller.signal,credentials:'omit'});
    if(!response.ok)throw new Error('Launch data unavailable');
    const data=await response.json();
    if(!data||typeof data!=='object'||Array.isArray(data))throw new Error('Invalid launch data');
    applyCoin(data);
  } catch {
    need('#market-status').textContent=lastUpdated?'Refresh failed · last received data shown':'Launch data unavailable · try Refresh';
  } finally {
    clearTimeout(timeout);activeRequest=null;refresh.disabled=false;refresh.removeAttribute('aria-busy');
  }
}
need('#refresh-market').addEventListener('click',()=>refreshMarket());
refreshMarket();
window.setInterval(()=>{if(!document.hidden)refreshMarket();},30000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refreshMarket();});
