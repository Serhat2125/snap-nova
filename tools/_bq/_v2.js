require('./bosaltim_info_a.js');
const b=globalThis.__BQ;
// find any straight apostrophe or double quote in any string value
let found=[];
function walk(x,path){
  if(typeof x==='string'){
    for(const ch of [''','"']){ if(x.includes(ch)) found.push([path,ch.charCodeAt(0),x]); }
  } else if(Array.isArray(x)){ x.forEach((v,i)=>walk(v,path+'['+i+']')); }
  else if(x&&typeof x==='object'){ for(const k in x) walk(x[k],path+'.'+k); }
}
walk(b,'BQ');
console.log('straight-quote hits:',found.length);
found.slice(0,5).forEach(f=>console.log(f[1],f[0],f[2]));
