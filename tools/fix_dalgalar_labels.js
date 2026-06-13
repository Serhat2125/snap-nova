const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const GROUP_A = ['denetleyici-duzenleyici-sistem','destek-hareket-sistemi','bosaltim-sistemi','dolasim-sistemi','sindirim-sistemi','ureme-sistemi','dna-replikasyon','hucre-organeller','mitoz-mayoz'];
const GROUP_B = ['ekosistem-besin-zinciri','fotosentez','kalitim-genotip-fenotip','bitki-anatomisi','atom-periyodik','atom-teorisi-orbitaller','kimyasal-baglar','kimyasal-tepkimeler','maddenin-yapisi','molekul-geometrisi','mol-stokiyometri','organik-kimya','karisimlar-cozeltiler','elektrik','dalgalar','optik-mercekler','basit-makineler','bileske-kuvvet-vektorler','akiskanlar-mekanigi','golge-olusumu-isik-yayilmasi','dunya-cografyasi','atmosfer-iklim','yer-sekilleri-izohipsler','yerin-ic-yapisi-levha-tektonigi','dunyanin-hareketleri'];

let log=[];

// ===== DALGALAR: %15 uzak + %20 yukarı + değişken sabit =====
(function(){
  const p=BASE+'dalgalar.html'; let h=fs.readFileSync(p,'utf8'); const b=h; const ch=[];
  // 1) %15 daha uzak: FOV 55 -> 63
  if(h.includes('PerspectiveCamera(55,')){ h=h.replace('PerspectiveCamera(55,','PerspectiveCamera(63,'); ch.push('FOV55->63 (%15 uzak)'); }
  // 2) sahne %20 yukarı: _sh bloğu koşulsuz setViewOffset (+20% - _sh.cur)
  const re=/if \(_sh\.cur > 0\.4\) \{[\s\S]*?camera\.clearViewOffset\(\);\s*\}/;
  if(re.test(h) && !h.includes('innerHeight*0.20)-_sh.cur')){
    h=h.replace(re, '{ camera.setViewOffset(window.innerWidth, window.innerHeight, 0, Math.round(window.innerHeight*0.20)-_sh.cur, window.innerWidth, window.innerHeight); }');
    ch.push('sahne+20%yukari');
  }
  // 3) değişken açılınca sabit (target -10% -> 0)
  h=h.replace(/(add\('vars-hidden'\);\s*window\._sceneShift\.target = )-window\.innerHeight\*0\.10;/, '\$10;');
  if(/add\('vars-hidden'\);\s*window\._sceneShift\.target = 0;/.test(h)) ch.push('değişken sabit');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); log.push('dalgalar ['+ch.join(', ')+']'); }
  else log.push('dalgalar [degisiklik yok]');
})();

// ===== TÜM DERSLER: etiket sayısı 5 -> 4 (daha az kalabalık, daha az binme) =====
let ga=0, gb=0;
GROUP_A.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  h=h.replace('if(items.length>=5){hide();return;}','if(items.length>=4){hide();return;}');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); ga++; }
});
GROUP_B.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  h=h.replace('if(els.length>5){for(var _cap5=5;_cap5<els.length;_cap5++)els[_cap5].style.display="none";els.length=5;}',
              'if(els.length>4){for(var _cap4=4;_cap4<els.length;_cap4++)els[_cap4].style.display="none";els.length=4;}');
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); gb++; }
});
log.push('Group A max 5->4: '+ga+'/'+GROUP_A.length);
log.push('Group B max 5->4: '+gb+'/'+GROUP_B.length);

log.forEach(l=>console.log(l));
