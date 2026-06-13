const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const GROUP_A = ['denetleyici-duzenleyici-sistem','destek-hareket-sistemi','bosaltim-sistemi','dolasim-sistemi','sindirim-sistemi','ureme-sistemi','dna-replikasyon','hucre-organeller','mitoz-mayoz'];
const GROUP_B = ['ekosistem-besin-zinciri','fotosentez','kalitim-genotip-fenotip','bitki-anatomisi','atom-periyodik','atom-teorisi-orbitaller','kimyasal-baglar','kimyasal-tepkimeler','maddenin-yapisi','molekul-geometrisi','mol-stokiyometri','organik-kimya','karisimlar-cozeltiler','elektrik','dalgalar','optik-mercekler','basit-makineler','bileske-kuvvet-vektorler','akiskanlar-mekanigi','golge-olusumu-isik-yayilmasi','dunya-cografyasi','atmosfer-iklim','yer-sekilleri-izohipsler','yerin-ic-yapisi-levha-tektonigi','dunyanin-hareketleri'];
const ALL = [...GROUP_A, ...GROUP_B];

// Etiketleri dar + çok satıra sarılabilir yap → ekrana sığar, üst üste binmez
const CSS = `
<style id="labelFitFix">
.label3d, .organ-label{
  max-width:42vw !important;
  white-space:normal !important;
  font-size:10px !important;
  line-height:1.2 !important;
  text-align:center !important;
  padding:3px 7px !important;
  word-break:break-word !important;
}
</style>`;

let css=0, dec=0, upd=0;

ALL.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  if(!h.includes('id="labelFitFix"')) h=h.replace('</body>', CSS+'\n</body>');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); css++; }
});

// Group B declutter: dikey ayrımı artır (+18) + iter 16->24
GROUP_B.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  h=h.replace('var minX=(A.w+B.w)/2, minY=(A.h+B.h)/2;','var minX=(A.w+B.w)/2, minY=(A.h+B.h)/2+18;');
  h=h.replace('for(var it=0; it<16; it++)','for(var it=0; it<24; it++)');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); dec++; }
});

// Group A updateLabels: iter 16->24
GROUP_A.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  h=h.replace('for(let it=0;it<16;it++)','for(let it=0;it<24;it++)');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); upd++; }
});

console.log('CSS labelFit: '+css+'/'+ALL.length);
console.log('Group B declutter (dikey+iter): '+dec+'/'+GROUP_B.length);
console.log('Group A updateLabels iter: '+upd+'/'+GROUP_A.length);
