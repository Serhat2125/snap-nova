const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const PHYS = ['elektrik','dalgalar','optik-mercekler','basit-makineler','bileske-kuvvet-vektorler','akiskanlar-mekanigi','golge-olusumu-isik-yayilmasi'];
const GROUP_A = ['denetleyici-duzenleyici-sistem','destek-hareket-sistemi','bosaltim-sistemi','dolasim-sistemi','sindirim-sistemi','ureme-sistemi','dna-replikasyon','hucre-organeller','mitoz-mayoz'];
const GROUP_B = ['ekosistem-besin-zinciri','fotosentez','kalitim-genotip-fenotip','bitki-anatomisi','atom-periyodik','atom-teorisi-orbitaller','kimyasal-baglar','kimyasal-tepkimeler','maddenin-yapisi','molekul-geometrisi','mol-stokiyometri','organik-kimya','karisimlar-cozeltiler','elektrik','dalgalar','optik-mercekler','basit-makineler','bileske-kuvvet-vektorler','akiskanlar-mekanigi','golge-olusumu-isik-yayilmasi','dunya-cografyasi','atmosfer-iklim','yer-sekilleri-izohipsler','yerin-ic-yapisi-levha-tektonigi','dunyanin-hareketleri'];

const VARS_BG = `
<style id="varsBgFix">
.scene-vars-body{ background:rgba(13,18,32,0.75) !important; border-radius:10px !important; backdrop-filter:blur(3px) !important; -webkit-backdrop-filter:blur(3px) !important; padding:6px !important; }
</style>`;

let r={fov:0,up:0,bg:0,gb:0,ga:0};

// ===== FİZİK: FOV %10 uzak + değişken %10 yukarı + panel %75 opak =====
PHYS.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  // 1) yatay geniş model %10 uzak → FOV 50->55
  if(h.includes('PerspectiveCamera(50,')){ h=h.replace('PerspectiveCamera(50,','PerspectiveCamera(55,'); r.fov++; }
  // 2) değişken açılınca model %10 yukarı (open dalı target = -%10)
  h=h.replace(/(add\('vars-hidden'\);\s*window\._sceneShift\.target = )0;/, '\$1-window.innerHeight*0.10;');
  if(/target = -window\.innerHeight\*0\.10/.test(h)) r.up++;
  // 3) değişken paneli %75 opak
  if(!h.includes('id="varsBgFix"')){ h=h.replace('</body>', VARS_BG+'\n</body>'); r.bg++; }
  if(h!==b) fs.writeFileSync(p,h,'utf8');
});

// ===== TÜM ETİKETLER daha agresif ayrım =====
GROUP_B.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  h=h.replace('minY=(A.h+B.h)/2+18;','minY=(A.h+B.h)/2+30;');
  h=h.replace('for(var it=0; it<24; it++)','for(var it=0; it<30; it++)');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); r.gb++; }
});
GROUP_A.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  h=h.replace('for(let it=0;it<24;it++)','for(let it=0;it<30;it++)');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); r.ga++; }
});

console.log('Fizik FOV50->55: '+r.fov+'/7');
console.log('Fizik değişken %10 yukarı: '+r.up+'/7');
console.log('Fizik panel %75 opak: '+r.bg+'/7');
console.log('Group B declutter agresif (+30,iter30): '+r.gb+'/'+GROUP_B.length);
console.log('Group A updateLabels iter30: '+r.ga+'/'+GROUP_A.length);
