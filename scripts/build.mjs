import {cp, mkdir, readFile, rm, stat} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
// The website runs directly from site/. This is a deterministic copy/export, not a transpilation.
const html=await readFile(resolve(root,'site/index.html'),'utf8');
for(const required of ['og:title','og:image','twitter:card','rel="icon"','id="plot-interactive"']){
  if(!html.includes(required))throw new Error(`Missing required site feature: ${required}`);
}
await cp(resolve(root,'src/SUNToken.sol'),resolve(root,'site/assets/SUNToken.sol'));
await rm(resolve(root,'dist'),{recursive:true,force:true});
await mkdir(resolve(root,'dist'),{recursive:true});
await cp(resolve(root,'site'),resolve(root,'dist'),{recursive:true});
if(!(await stat(resolve(root,'dist/index.html'))).isFile())throw new Error('No static export');
console.log('Production export complete: site/ → dist/. No runtime dependencies or bundler.');
