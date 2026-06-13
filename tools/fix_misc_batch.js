const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const ALL = [
  'denetleyici-duzenleyici-sistem','destek-hareket-sistemi','bosaltim-sistemi','dolasim-sistemi','sindirim-sistemi','ureme-sistemi','dna-replikasyon','hucre-organeller','mitoz-mayoz','ekosistem-besin-zinciri','fotosentez','kalitim-genotip-fenotip','bitki-anatomisi',
  'atom-periyodik','atom-teorisi-orbitaller','kimyasal-baglar','kimyasal-tepkimeler','maddenin-yapisi','molekul-geometrisi','mol-stokiyometri','organik-kimya','karisimlar-cozeltiler',
  'elektrik','dalgalar','optik-mercekler','basit-makineler','bileske-kuvvet-vektorler','akiskanlar-mekanigi','golge-olusumu-isik-yayilmasi',
  'dunya-cografyasi','atmosfer-iklim','yer-sekilleri-izohipsler','yerin-ic-yapisi-levha-tektonigi','dunyanin-hareketleri'
].map(n=>n+'.html');

// Menü (Ders Ayarları) açılınca arka plan flu — tüm dosyalara
const MENU_BLUR = `
<script>
/* == MENU-BLUR-FIX == */
(function(){
  function wire(){
    var mp=document.getElementById('menuPop'), pb=document.getElementById('_popBlur');
    if(!pb) return false;
    if(!mp) return false;
    if(mp.__menuBlurWired) return true;
    mp.__menuBlurWired=1;
    new MutationObserver(function(){
      var open=mp.classList.contains('show');
      if(open){ pb.style.display='block'; }
      else {
        var arc=document.getElementById('araclarComboP');
        if(!(arc&&arc.classList.contains('show'))) pb.style.display='none';
      }
    }).observe(mp,{attributes:true,attributeFilter:['class']});
    return true;
  }
  var n=0;(function s(){ if(wire()||n++>25) return; setTimeout(s,200); })();
})();
</script>`;

// bitki-anatomisi: başlık yanı ikon kaldır + nav butonları büyüt & sağ üst köşe
const BITKI = `
<style id="bitkiPanelFix">
#infoEmoji{ display:none!important; }
#bottomPanel .nav-buttons{ position:absolute!important; top:7px!important; right:9px!important; gap:6px!important; z-index:6!important; }
#bottomPanel .nav-mini-btn{ width:30px!important; height:30px!important; font-size:15px!important; border-width:2px!important; border-radius:8px!important; }
#bottomPanel .info-title{ padding-right:104px!important; }
</style>`;

let done=[];
ALL.forEach(f=>{
  const p=BASE+f; let h=fs.readFileSync(p,'utf8'); const before=h; const ch=[];

  // 1. DNA + mitoz: %15 daha uzak (1.2 -> 1.38)
  if(f==='dna-replikasyon.html' || f==='mitoz-mayoz.html'){
    if(h.includes('const r=cam.radius*1.2;')){ h=h.replace('const r=cam.radius*1.2;','const r=cam.radius*1.38;'); ch.push('uzak+15%'); }
  }

  // 2. bitki-anatomisi panel düzeltmeleri
  if(f==='bitki-anatomisi.html' && !h.includes('id="bitkiPanelFix"')){
    h=h.replace('</body>', BITKI+'\n</body>'); ch.push('bitkiPanel');
  }

  // 3. menü blur (tümü)
  if(!h.includes('MENU-BLUR-FIX')){ h=h.replace('</body>', MENU_BLUR+'\n</body>'); ch.push('menuBlur'); }

  if(h!==before){ fs.writeFileSync(p,h,'utf8'); done.push(f+' ['+ch.join(',')+']'); }
});
console.log('Degisen ('+done.length+'):');
done.forEach(d=>console.log('  '+d));
