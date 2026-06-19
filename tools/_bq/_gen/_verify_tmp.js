require("./kb_test_orta.js");
const O = globalThis.__OUT.ortaokul;
const k = O.kolay, z = O.zor;
console.log("kolay:", k.length, "zor:", z.length);
let err=0;
function check(arr,label){
  const qs = new Set();
  arr.forEach((it,i)=>{
    if(!it.q||!it.steps||!it.ans||!it.o){console.log(label,i,"missing field");err++;}
    if(it.o.length!==4){console.log(label,i,"o length",it.o.length);err++;}
    if(it.o.includes(it.ans)){console.log(label,i,"ans in o");err++;}
    if(qs.has(it.q)){console.log(label,i,"DUP q");err++;}
    qs.add(it.q);
    const blob=JSON.stringify(it);
    if(/[$]|\\\(|[*][*]/.test(blob)){console.log(label,i,"latex/md artifact");err++;}
    if(it.fig){
      if(!it.fig.startsWith("<svg")||!it.fig.endsWith("</svg>")){console.log(label,i,"bad svg bounds");err++;}
      if(it.fig.indexOf('"')>=0||it.fig.indexOf("href")>=0||it.fig.indexOf("<script")>=0){console.log(label,i,"svg illegal");err++;}
    }
  });
}
check(k,"kolay"); check(z,"zor");
const figK=k.filter(x=>x.fig).length, figZ=z.filter(x=>x.fig).length;
const total=k.length+z.length, figs=figK+figZ;
console.log("fig kolay:",figK,"fig zor:",figZ,"toplam fig:",figs,"oran %",Math.round(figs/total*100));
console.log("errors:",err);
