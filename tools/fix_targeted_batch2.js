const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const KIMYA = ['atom-periyodik','atom-teorisi-orbitaller','kimyasal-baglar','kimyasal-tepkimeler','maddenin-yapisi','molekul-geometrisi','mol-stokiyometri','organik-kimya','karisimlar-cozeltiler'];

// Kimya: değişken paneli %75 opak (artık tam şeffaf değil)
const VARS_BG = `
<style id="varsBgFix">
.scene-vars-body{ background:rgba(13,18,32,0.75) !important; border-radius:10px !important; backdrop-filter:blur(3px) !important; -webkit-backdrop-filter:blur(3px) !important; padding:6px !important; }
</style>`;

let log=[];

// ===== 1 & 2: bileske-kuvvet-vektorler =====
(function(){
  const p=BASE+'bileske-kuvvet-vektorler.html'; let h=fs.readFileSync(p,'utf8'); const b=h; const ch=[];
  // 1) Sahneyi %20 yukarı: _sh bloğunu koşulsuz setViewOffset (+20% - _sh.cur) yap
  const re=/if \(_sh\.cur > 0\.4\) \{[\s\S]*?camera\.clearViewOffset\(\);\s*\}/;
  if(re.test(h) && !h.includes('innerHeight*0.20)-_sh.cur')){
    h=h.replace(re, '{ camera.setViewOffset(window.innerWidth, window.innerHeight, 0, Math.round(window.innerHeight*0.20)-_sh.cur, window.innerWidth, window.innerHeight); }');
    ch.push('sahne+20%yukari');
  }
  // 2) buildAyniZitYon modelini %10 küçült (ekrana sığsın): sc 0.55 -> 0.495
  if(h.includes('const sc = 0.55;')){ h=h.replace('const sc = 0.55;','const sc = 0.495;'); ch.push('ayniZit -%10'); }
  if(h!==b){ fs.writeFileSync(p,h,'utf8'); log.push('bileske ['+ch.join(', ')+']'); }
  else log.push('bileske [degisiklik yok]');
})();

// ===== 3 & 4: KİMYA =====
let v=0, bg=0;
KIMYA.forEach(n=>{
  const p=BASE+n+'.html'; let h=fs.readFileSync(p,'utf8'); const b=h;
  // 3) değişken paneli açılınca model sabit (fizikteki gibi)
  h=h.replace(/(add\('vars-hidden'\);\s*)updateSceneShiftTarget\(\);/, '\$1window._sceneShift.target = 0;');
  if(h!==b) v++;
  // 4) değişken paneli %75 opak
  if(!h.includes('id="varsBgFix"')){ h=h.replace('</body>', VARS_BG+'\n</body>'); bg++; }
  if(h!==b) fs.writeFileSync(p,h,'utf8');
});
log.push('kimya değişken sabit: '+v+'/9');
log.push('kimya panel %75 opak: '+bg+'/9');

log.forEach(l=>console.log(l));
