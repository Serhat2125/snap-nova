const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const FILES = [
  'destek-hareket-sistemi.html',
  'bosaltim-sistemi.html','dna-replikasyon.html','dolasim-sistemi.html',
  'hucre-organeller.html','mitoz-mayoz.html','sindirim-sistemi.html',
  'ureme-sistemi.html','ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

// Injected at end of <body>. Runs 300ms after page load so _bioDock + Combo IIFE have both finished.
const DOCK_FIX = `
<script>
/* == DOCK FIX == */
(function(){
  setTimeout(function(){
    var tr=document.getElementById('toolsRow');
    if(!tr||document.getElementById('btnModTab')) return;
    // Remove old tool buttons from toolsRow + hide them (they stay accessible for popup delegates)
    ['btnMode','btnStory','btnCompare','btnTable','btnSend','btnPalette','btnExam','btnAsk','btnTts'].forEach(function(id){
      var b=document.getElementById(id);
      if(b){ if(b.parentNode===tr) tr.removeChild(b); b.style.display='none'; if(b.parentNode!==document.body) document.body.appendChild(b); }
    });
    // Create 📖 sade button (dock-tab-btn)
    var btnMod=document.createElement('button');
    btnMod.className='dock-tab-btn mod-btn'; btnMod.id='btnModTab'; btnMod.title='Görünüm Modu';
    btnMod.innerHTML='<span class="dtb-ico">📖</span><span class="dtb-lbl">sade</span>';
    btnMod.onclick=function(){
      if(window._toggleMode) window._toggleMode();
      else { var bm=document.getElementById('btnMode'); if(bm) bm.click(); }
      if(window._haptic) window._haptic(10);
    };
    var bArc=document.getElementById('btnAraclarCombo');
    var menuBtn=document.getElementById('btnMenu');
    // Rebuild toolsRow in correct order: [sade] [araçlar] [☰menu]
    while(tr.firstChild) tr.removeChild(tr.firstChild);
    tr.appendChild(btnMod);
    if(bArc) tr.appendChild(bArc);
    if(menuBtn) tr.appendChild(menuBtn);
    tr.style.justifyContent='space-evenly';
    tr.style.padding='0 24px';
    // Hide scene title text (matches denetleyici behaviour)
    var title=document.getElementById('sceneMainTitle');
    if(title){ title.style.display='none'; title.textContent=''; }
    // Extra CSS for mod-btn accent colour
    if(!document.getElementById('dockFixCss')){
      var s=document.createElement('style'); s.id='dockFixCss';
      s.textContent='.dock-tab-btn.mod-btn{border-color:var(--joint,#5fc8e0);}';
      document.head.appendChild(s);
    }
  },300);
})();
</script>`;

let passed=0, skipped=0, failed=0;

for (const fname of FILES) {
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    if (html.includes('btnModTab')) {
      console.log('SKIP (already fixed): ' + fname);
      skipped++;
      continue;
    }
    html = html.replace('</body>', DOCK_FIX + '\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: ' + fname);
    passed++;
  } catch(e) {
    console.log('ERROR: ' + fname + ' - ' + e.message);
    failed++;
  }
}
console.log('\n' + passed + ' done, ' + skipped + ' skipped, ' + failed + ' failed');
