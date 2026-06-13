const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const FILES = [
  'denetleyici-duzenleyici-sistem.html',
  'destek-hareket-sistemi.html',
  'bosaltim-sistemi.html','dna-replikasyon.html','dolasim-sistemi.html',
  'hucre-organeller.html','mitoz-mayoz.html','sindirim-sistemi.html',
  'ureme-sistemi.html','ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

// Three fixes in one injected script:
// 1. _toggleMode: click the non-active panelMode item → existing module handler fires
//    (changes currentMode + calls loadOverviewTopic() → structureLines() uses new mode)
// 2. Araçlar centering: CSS Grid 3 equal columns so araçlar is always at 50%
// 3. Icon strip: remove leading emoji from li.subhead elements in info panel
const MODE_FIX = `
<script>
/* == BIO-MODE-FIX == */
(function(){
  // 1. _toggleMode — only if the module script didn't already define it (denetleyici has its own)
  setTimeout(function(){
    if(!window._toggleMode){
      window._toggleMode=function(){
        var items=document.querySelectorAll('#panelMode .dropdown-item[data-mode]');
        var toClick=null;
        items.forEach(function(item){ if(!item.classList.contains('active')) toClick=item; });
        if(!toClick) return;
        toClick.click(); // triggers module-level handler: currentMode change + loadOverviewTopic()
        setTimeout(function(){
          var mode=toClick.dataset.mode;
          var btn=document.getElementById('btnModTab');
          if(btn) btn.innerHTML=mode==='sade'
            ?'<span class="dtb-ico">📖</span><span class="dtb-lbl">sade</span>'
            :'<span class="dtb-ico">📚</span><span class="dtb-lbl">detaylı</span>';
        },30);
      };
    }
  },500);

  // 2. Araçlar centering — 3 equal-width grid columns (overrides space-evenly from DOCK FIX)
  setTimeout(function(){
    var tr=document.getElementById('toolsRow');
    if(!tr) return;
    tr.style.display='grid';
    tr.style.gridTemplateColumns='1fr 1fr 1fr';
    tr.style.justifyItems='center';
    tr.style.alignItems='center';
    tr.style.padding='0 8px';
    tr.style.gap='4px';
  },500);

  // 3. Strip leading emoji from li.subhead section headings in info panel
  function stripSubheadIcons(root){
    if(!root) return;
    root.querySelectorAll('.info-list li.subhead').forEach(function(el){
      var t=el.textContent;
      if(!t) return;
      var code=t.codePointAt(0);
      // Above BMP emoji (surrogate pair, e.g. 🧩🫃👄): skip 2 UTF-16 chars
      if(code>0xFFFF){
        el.textContent=t.slice(2).replace(/^\s+/,'');
      // Basic plane emoji block (☀✈♦ etc U+2600-U+2BFF):
      } else if(code>=0x2600 && code<=0x2BFF){
        el.textContent=t.slice(1).replace(/^\s+/,'');
      }
    });
  }
  var bp=document.getElementById('bottomPanel');
  if(bp){
    new MutationObserver(function(){ stripSubheadIcons(bp); })
      .observe(bp,{childList:true,subtree:true});
    stripSubheadIcons(bp);
  }
})();
</script>`;

let passed=0, skipped=0, failed=0;

for (const fname of FILES) {
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    if (html.includes('BIO-MODE-FIX')) {
      console.log('SKIP (already fixed): ' + fname);
      skipped++;
      continue;
    }
    html = html.replace('</body>', MODE_FIX + '\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: ' + fname);
    passed++;
  } catch(e) {
    console.log('ERROR: ' + fname + ' - ' + e.message);
    failed++;
  }
}
console.log('\n' + passed + ' done, ' + skipped + ' skipped, ' + failed + ' failed');
