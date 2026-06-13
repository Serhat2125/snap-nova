const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const GROUP_A = [
  'denetleyici-duzenleyici-sistem.html','destek-hareket-sistemi.html','bosaltim-sistemi.html',
  'dolasim-sistemi.html','sindirim-sistemi.html','ureme-sistemi.html',
  'dna-replikasyon.html','hucre-organeller.html','mitoz-mayoz.html'
];
const GROUP_B = [
  'ekosistem-besin-zinciri.html','fotosentez.html','kalitim-genotip-fenotip.html','bitki-anatomisi.html',
  'atom-periyodik.html','atom-teorisi-orbitaller.html','kimyasal-baglar.html','kimyasal-tepkimeler.html',
  'maddenin-yapisi.html','molekul-geometrisi.html','mol-stokiyometri.html','organik-kimya.html','karisimlar-cozeltiler.html',
  'elektrik.html','dalgalar.html','optik-mercekler.html','basit-makineler.html','bileske-kuvvet-vektorler.html',
  'akiskanlar-mekanigi.html','golge-olusumu-isik-yayilmasi.html',
  'dunya-cografyasi.html','atmosfer-iklim.html','yer-sekilleri-izohipsler.html','yerin-ic-yapisi-levha-tektonigi.html'
];

const NEW_COLORMAP = "const colorMap = {'xylem':'#ffd166','phloem':'#5fd99a','chloro':'#2ecc40','epi':'#a8d0b0','endo':'#f4c542','warn':'#5fd99a'}";

const OLD_COL_A = "const col=getComputedStyle(el).borderTopColor||'#ffd166';";
const NEW_COL_A = "const col=(colorClass==='accent'||!colorClass)?'#ffd166':'#5fd99a';";

const CLAMP = "const _leaderRaw = ref.color || colorMap[ref.className] || '#ffd166'; const _leaderSafe={'#d97043':'#ffd166','#e69138':'#f4c542','#e74c3c':'#5fd99a','#ff7b54':'#ffd166','#ffa07a':'#ffd166','#c0392b':'#5fd99a','#ef4444':'#5fd99a','#d32f2f':'#5fd99a','#e07a5f':'#ffd166','#c45d5d':'#5fd99a','#ff6f00':'#ffd166','#ff6b9d':'#5fd99a','#5fb8e8':'#5fd99a','#5fc8e0':'#5fd99a'}; const color = _leaderSafe[(_leaderRaw||'').toLowerCase()] || _leaderRaw;";

let a=0,b=0,warn=[];

GROUP_A.forEach(f=>{
  const p=BASE+f; let h=fs.readFileSync(p,'utf8'); const before=h;
  h=h.replace(OLD_COL_A, NEW_COL_A);
  if(h!==before){ fs.writeFileSync(p,h,'utf8'); a++; } else warn.push('A:'+f);
});

GROUP_B.forEach(f=>{
  const p=BASE+f; let h=fs.readFileSync(p,'utf8'); const before=h;
  h=h.replace(/const colorMap\s*=\s*\{[^}]*\}/, NEW_COLORMAP);
  if(!h.includes('_leaderSafe')){
    h=h.replace(/const color = ref\.color \|\| colorMap\[ref\.className\] \|\| '#[0-9a-fA-F]{3,6}';/, CLAMP);
  }
  if(h!==before){ fs.writeFileSync(p,h,'utf8'); b++; } else warn.push('B:'+f);
});

console.log('Group A (ok yesil/sari): '+a+'/'+GROUP_A.length);
console.log('Group B (colorMap+clamp): '+b+'/'+GROUP_B.length);
if(warn.length) console.log('UYARI: '+warn.join(', '));
