const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

// All biology lessons EXCEPT the gold standard (denetleyici already correct).
const FILES = [
  'destek-hareket-sistemi.html','bosaltim-sistemi.html','dolasim-sistemi.html',
  'sindirim-sistemi.html','ureme-sistemi.html','dna-replikasyon.html',
  'hucre-organeller.html','mitoz-mayoz.html',
  'ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

// Runs ~700ms after load — AFTER apply_bio_standard Combo IIFE, DOCK FIX and BIO-MODE-FIX.
// Definitively (re)binds every feature the user reported broken, defensively (if exists).
const MASTER = `
<script>
/* == BIO-MASTER-FIX == */
(function(){
  function $(id){ return document.getElementById(id); }
  function run(){
    // ---- 1. RENK PALETİ: X ve blur ile kesin kapanma (display !important ezilir) ----
    function killPalette(){
      var pp=$('palettePop');
      if(pp){ pp.style.setProperty('display','none','important'); pp.classList.remove('show'); }
      var pb=$('_popBlur'); if(pb) pb.style.display='none';
    }
    var pc=$('paletteClose');
    if(pc) pc.onclick=function(e){ if(e){e.stopPropagation();e.preventDefault();} killPalette(); if(window._haptic)window._haptic(8); };
    var pb=$('_popBlur');
    if(pb && !pb.__killWired){ pb.__killWired=1; pb.addEventListener('click',killPalette); }

    // ---- 2. BİLGİ PANELİ X: tam kapanma DEĞİL, küçülüp altta chip olarak kalsın ----
    var icb=$('infoCloseBtn');
    if(icb) icb.onclick=function(){
      var bp=$('bottomPanel'); if(!bp) return;
      bp.classList.remove('hidden');     // eski yanlış davranışı temizle
      bp.classList.add('info-mini');
      var lbl=$('infoMiniLbl');
      if(lbl){ var t=$('infoTitle'); if(t&&t.textContent) lbl.textContent=t.textContent+' konusunu aç'; }
    };
    var mc=$('infoMiniChip');
    if(mc) mc.onclick=function(){ var bp=$('bottomPanel'); if(bp){ bp.classList.remove('info-mini'); bp.classList.remove('hidden'); } };

    // ---- 3. ARAÇLAR sekmesi tam ortada (3 eşit kolon) ----
    var tr=$('toolsRow');
    if(tr){
      tr.style.display='grid';
      tr.style.gridTemplateColumns='1fr 1fr 1fr';
      tr.style.justifyItems='center';
      tr.style.alignItems='center';
      tr.style.padding='0 8px';
      tr.style.gap='4px';
    }

    // ---- 4. SADE/DETAYLI toggle: panelMode'daki pasif item'a tıkla → modül re-render eder ----
    window._toggleMode=function(){
      var items=document.querySelectorAll('#panelMode .dropdown-item[data-mode]');
      if(!items.length) return;
      var target=null;
      items.forEach(function(it){ if(!it.classList.contains('active')) target=it; });
      if(!target) target=items[0];
      target.click(); // modül handler'ı: currentMode değişir + loadOverviewTopic()/selectSub()
      var mode=target.dataset.mode;
      var bt=$('btnModTab');
      if(bt) bt.innerHTML = (mode==='sade')
        ? '<span class="dtb-ico">📖</span><span class="dtb-lbl">sade</span>'
        : '<span class="dtb-ico">📚</span><span class="dtb-lbl">detaylı</span>';
      if(window._haptic)window._haptic(10);
    };
    var bmt=$('btnModTab');
    if(bmt) bmt.onclick=function(e){ if(e)e.stopPropagation(); window._toggleMode(); };

    // ---- 5. ARAÇLAR popup öğeleri: Test Soruları + AI Destek kesin bağlı ----
    function delegate(srcId, dstId){
      var s=$(srcId); if(!s) return;
      s.onclick=function(){
        // araçlar popup'ı kapat
        var ap=$('araclarComboP'); if(ap) ap.classList.remove('show');
        var pbb=$('_popBlur'); if(pbb) pbb.style.display='none';
        var d=$(dstId); if(d) d.click();
      };
    }
    delegate('cpArcExam','btnExam');   // Test Soruları Oluştur → sınav sayfası (_bridge action:exam)
    delegate('cpArcAi','btnAsk');      // AI Destek → AI sheet (_bridge action:ai)
    delegate('cpArcKarsi','btnCompare');
    delegate('cpArcBilgi','btnTable');
    delegate('cpArcTts','btnTts');

    // ---- 6. Bilgi panelindeki bölüm başlıklarının başındaki emojiyi kaldır ----
    function stripIcons(){
      var bp=$('bottomPanel'); if(!bp) return;
      bp.querySelectorAll('.info-list li.subhead').forEach(function(el){
        var t=el.textContent; if(!t) return;
        var cp=t.codePointAt(0);
        if(cp>0xFFFF) el.textContent=t.slice(2).replace(/^\\s+/,'');
        else if(cp>=0x2190 && cp<=0x2BFF) el.textContent=t.slice(1).replace(/^\\s+/,'');
      });
    }
    var bp2=$('bottomPanel');
    if(bp2 && !bp2.__stripWired){
      bp2.__stripWired=1;
      new MutationObserver(stripIcons).observe(bp2,{childList:true,subtree:true});
    }
    stripIcons();
  }
  var tries=0;
  (function spin(){ try{ run(); }catch(e){} if(++tries<6) setTimeout(spin, tries*250); })();
})();
</script>`;

let passed=0, skipped=0, failed=0;
for (const fname of FILES){
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    let notes=[];

    // Module-level: nudge scene a bit higher (panel overlap). 0.20 -> 0.24 where present.
    const c20=(html.match(/innerHeight\*0\.20\)\s*-\s*_sh\.cur/g)||[]).length;
    if(c20>0){
      html=html.replace(/innerHeight\*0\.20\)(\s*-\s*_sh\.cur)/g,'innerHeight*0.24)$1');
      notes.push('scene+'+c20);
    }

    if (html.includes('BIO-MASTER-FIX')){
      // re-apply scene tweak only, skip duplicate master block
      if(notes.length) fs.writeFileSync(fpath, html, 'utf8');
      console.log('SKIP master (present): '+fname+(notes.length?' ['+notes.join(',')+']':''));
      skipped++; continue;
    }
    html = html.replace('</body>', MASTER + '\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: '+fname.padEnd(32)+' [master'+(notes.length?', '+notes.join(','):'')+']');
    passed++;
  } catch(e){
    console.log('ERROR: '+fname+' - '+e.message);
    failed++;
  }
}
console.log('\n'+passed+' done, '+skipped+' skipped, '+failed+' failed');
