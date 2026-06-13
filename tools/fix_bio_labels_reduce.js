const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';
const MAX = 7; // sahnede gösterilecek azami etiket (ana yapılar — ekleme sırası önce)

const GROUP_A = [ // updateLabels (radial + collision)
  'denetleyici-duzenleyici-sistem.html','destek-hareket-sistemi.html','bosaltim-sistemi.html',
  'dolasim-sistemi.html','sindirim-sistemi.html','ureme-sistemi.html',
  'dna-replikasyon.html','hucre-organeller.html','mitoz-mayoz.html'
];
const GROUP_B = [ // CSS2D declutter shim
  'ekosistem-besin-zinciri.html','fotosentez.html','kalitim-genotip-fenotip.html','bitki-anatomisi.html',
  'atom-periyodik.html','atom-teorisi-orbitaller.html','kimyasal-baglar.html','kimyasal-tepkimeler.html',
  'maddenin-yapisi.html','molekul-geometrisi.html','mol-stokiyometri.html','organik-kimya.html','karisimlar-cozeltiler.html',
  'elektrik.html','dalgalar.html','optik-mercekler.html','basit-makineler.html','bileske-kuvvet-vektorler.html',
  'akiskanlar-mekanigi.html','golge-olusumu-isik-yayilmasi.html',
  'dunya-cografyasi.html','atmosfer-iklim.html','yer-sekilleri-izohipsler.html','yerin-ic-yapisi-levha-tektonigi.html',
  'dunyanin-hareketleri.html'
];

let a=0, b=0, warn=[];

// GROUP A: DIST 62->38 (etikete model yakın) + sayı sınırı
GROUP_A.forEach(f=>{
  const p=BASE+f; let h=fs.readFileSync(p,'utf8'); const before=h;
  h=h.replace('const DIST=62;','const DIST=38;');
  if(!h.includes('items.length>='+MAX)){
    h=h.replace('items.push({a,ax,ay,lx,ly,elW,opa});',
      'if(items.length>='+MAX+'){hide();return;}items.push({a,ax,ay,lx,ly,elW,opa});');
  }
  if(h!==before){ fs.writeFileSync(p,h,'utf8'); a++; } else warn.push('A:'+f);
});

// GROUP B: declutter — fazla etiketleri her frame gizle (ilk MAX kalır)
GROUP_B.forEach(f=>{
  const p=BASE+f; let h=fs.readFileSync(p,'utf8'); const before=h;
  if(!h.includes('_cap'+MAX)){
    h=h.replace('if(els.length<2) return;',
      'if(els.length>'+MAX+'){for(var _cap'+MAX+'='+MAX+';_cap'+MAX+'<els.length;_cap'+MAX+'++)els[_cap'+MAX+'].style.display=\"none\";els.length='+MAX+';}\n    if(els.length<2) return;');
  }
  if(h!==before){ fs.writeFileSync(p,h,'utf8'); b++; } else warn.push('B:'+f);
});

console.log('Group A (DIST+limit): '+a+'/'+GROUP_A.length);
console.log('Group B (limit): '+b+'/'+GROUP_B.length);
if(warn.length){ console.log('UYARI (degismedi): '+warn.join(', ')); }
