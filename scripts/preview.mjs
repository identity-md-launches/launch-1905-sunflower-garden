import {createServer} from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {pathToFileURL} from 'node:url';
const mime={'.html':'text/html; charset=utf-8','.css':'text/css','.js':'text/javascript','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2','.json':'application/json','.sol':'text/plain'};
/** Serve only the export and an explicitly empty local data response, never workspace files. */
export function createPreview(dir=resolve('dist')) {
  const root=resolve(dir);
  return createServer(async(req,res)=>{
    const path=new URL(req.url,'http://localhost').pathname;
    // Local preview has no deployment feed. Empty data exercises the real launching state.
    if(path==='/simd-coin.json'){res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end('{}');return;}
    try{
      let requested=decodeURIComponent(path).replace(/^\/preview(?=\/|$)/,'');
      let file=resolve(root,'.'+requested);
      if(file!==root&&!file.startsWith(root+sep))throw new Error('Outside export');
      if((await stat(file)).isDirectory())file=resolve(file,'index.html');
      const data=await readFile(file);
      res.writeHead(200,{'Content-Type':mime[extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(data);
    }catch{res.writeHead(404,{'Content-Type':'text/html; charset=utf-8'});res.end(await readFile(resolve(root,'404.html')));}
  });
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){const server=createPreview();server.listen(4173,'127.0.0.1',()=>console.log('Preview ready at http://127.0.0.1:4173/preview/ (Ctrl+C stops it).'));}
