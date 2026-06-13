const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const FILES = [
  'denetleyici-duzenleyici-sistem.html','destek-hareket-sistemi.html',
  'bosaltim-sistemi.html','dolasim-sistemi.html','sindirim-sistemi.html',
  'ureme-sistemi.html','dna-replikasyon.html','hucre-organeller.html','mitoz-mayoz.html',
  'ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

const BLOCK = `
<style id="bioStyleV2">
/* === ALT DOCK BAR: tam genişlik, gri-siyah, mavi çerçeve === */
#bottomDock{ padding-left:0 !important; padding-right:0 !important; }
#bottomDock #toolsRow{
  background:rgba(12,15,22,0.97) !important;
  border-top:2px solid #2f8fd0 !important;
  border-radius:0 !important;
  width:100% !important; box-sizing:border-box !important;
  padding:7px 12px 9px !important; margin:0 !important;
}
/* 3 sekmenin çerçeve çizgileri mavi */
#toolsRow .dock-tab-btn, #toolsRow #btnMenu, #toolsRow .tool-icon-btn.menu{
  border-color:#2f8fd0 !important;
}
#toolsRow #btnMenu, #toolsRow .tool-icon-btn.menu{ color:#5fc8e0 !important; }
#toolsRow #btnMenu:hover, #toolsRow .tool-icon-btn.menu:hover{ background:#2f8fd0 !important; color:#08121e !important; }
/* Araçlar sekmesi açık yeşil vurgu (ikon JS ile 🌿) */
#btnAraclarCombo{ border-color:#5fd99a !important; }
#btnAraclarCombo .dtb-lbl{ color:#7fe6a8 !important; }

/* === BİLGİ PANELİ renkleri === */
.bottom-panel{ border-color:#2f8fd0 !important; }
.info-title, #infoTitle{ color:#3b5bd9 !important; }                 /* başlık lacivert */
.info-list li.subhead, #infoList li.subhead, #infoList li.subhead2{ color:#5fd99a !important; }  /* alt başlık yeşil */
.info-list li b, #infoList li b{ color:#5fc8e0 !important; }          /* kırmızı/coral vurgu → mavi */
.info-list li, #infoList li{ color:#eef0ff !important; }
.info-list li::before, #infoList li::before{ color:#2f8fd0 !important; }   /* madde imi mavi */

/* === İLERİ / GERİ (◀ ▶) butonları yeşil çerçeve === */
.nav-mini-btn{ border-color:#5fd99a !important; color:#5fd99a !important; }
.nav-mini-btn:hover{ background:#5fd99a !important; color:#0a1420 !important; }
.nav-mini-btn:disabled{ opacity:.3 !important; }

/* === RENK PALETİ çerçevesi açık === */
.palette-pop{ border-color:#aee0f0 !important; }
.palette-title{ color:#aee0f0 !important; }

/* === BLUR güçlendir (3 sekme popup'larında belirgin flu) === */
#_popBlur{ background:rgba(0,0,0,0.5) !important; backdrop-filter:blur(3px) !important; -webkit-backdrop-filter:blur(3px) !important; }
</style>
<script>
/* == BIO-STYLE-V2 ICON == */
(function(){
  function setIcon(){
    var ico=document.querySelector('#btnAraclarCombo .dtb-ico');
    if(ico){ ico.textContent='🌿'; return true; }
    return false;
  }
  var n=0;
  (function spin(){ if(setIcon()||n++>8) return; setTimeout(spin,250); })();
})();
</script>`;

let passed=0, skipped=0, failed=0;
for (const fname of FILES){
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    if (html.includes('id="bioStyleV2"')){ console.log('SKIP (present): '+fname); skipped++; continue; }
    html = html.replace('</body>', BLOCK + '\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: '+fname);
    passed++;
  } catch(e){ console.log('ERROR: '+fname+' - '+e.message); failed++; }
}
console.log('\n'+passed+' done, '+skipped+' skipped, '+failed+' failed');
