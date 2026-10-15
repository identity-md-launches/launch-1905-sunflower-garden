import {readdir,lstat,readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const forbidden=new Set(['node_modules','.npm','.cache','.parcel-cache','.vite','__pycache__','.playwright-mcp']);
const groups={};let bytes=0,files=0;
async function walk(dir='.'){
 for(const entry of await readdir(dir,{withFileTypes:true})){
  const relative=join(dir,entry.name).replace(/^\.\//,'');
  // Never access repository metadata, supplied inputs or scratch verification outputs.
  if(['.git','.github','.imd','test/scratch'].includes(relative)||entry.name.startsWith('.env'))continue;
  if(forbidden.has(entry.name))throw new Error(`Generated directory must not ship: ${relative}`);
  if(entry.isSymbolicLink())throw new Error(`Symlink must not ship: ${relative}`);
  if(entry.isDirectory()){await walk(relative);continue;}
  if(/\.(tgz|zip|tar|gz)$/.test(entry.name))throw new Error(`Unnecessary archive: ${relative}`);
  const size=(await lstat(relative)).size;
  bytes+=size;files++;const group=relative.includes('/')?relative.split('/')[0]:'root';groups[group]=(groups[group]||0)+size;
 }
}
await walk();
const maxBytes=8388608;
// Raw bytes are a conservative budget proxy; this does not inspect .git or create a Git bundle.
const result={files,rawBytes:bytes,maxBundleBytes:maxBytes,rawHeadroomBytes:maxBytes-bytes,groups,method:'All deliverable file bytes, excluding supplied inputs and scratch. Git metadata was not accessed. Raw payload held below 7 MiB to leave bundle overhead.'};
if(bytes>7*1024*1024)throw new Error(`Raw deliverables ${bytes} exceed the conservative 7 MiB payload budget`);
await writeFile('artifacts/size-budget.json',JSON.stringify(result,null,2)+'\n');
console.log(`${files} deliverable files; ${bytes} raw bytes; ${maxBytes-bytes} bytes below the 8 MiB bundle cap (before Git overhead).`);
