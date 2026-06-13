const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const GROUP_A = [ // labelAnchors mimarisi — subhead: li.innerHTML=t.subhead
  'destek-hareket-sistemi.html','bosaltim-sistemi.html','dolasim-sistemi.html',
  'sindirim-sistemi.html','ureme-sistemi.html','dna-replikasyon.html',
  'hucre-organeller.html','mitoz-mayoz.html'
];
const GOLD = 'denetleyici-duzenleyici-sistem.html'; // subhead var; kamera zaten doğru
const GROUP_B = [ // CSS2D mimarisi — subhead: sub.textContent=el.textContent
  'ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html',
  // Coğrafya (CSS2D, strip'siz textContent) — kamera Group A'da değil, dokunulmaz
  'dunya-cografyasi.html','atmosfer-iklim.html',
  'yer-sekilleri-izohipsler.html','yerin-ic-yapisi-levha-tektonigi.html'
];

// Leading emoji/symbol stripper expression (kaynakta uygulanır → kesin, observer'sız)
const STRIP = "replace(/^[\\u{1F000}-\\u{1FAFF}\\u{2600}-\\u{27BF}\\u{2190}-\\u{2BFF}\\u{FE0F}\\u{200D}\\s]+/u,'')";

let done=[], warn=[];

function edit(fname, fn){
  const p = BASE + fname;
  let h = fs.readFileSync(p, 'utf8');
  const before = h;
  h = fn(h, fname);
  if (h !== before){ fs.writeFileSync(p, h, 'utf8'); done.push(fname); }
  else warn.push(fname+' (degisiklik yok)');
}

// ---- Group A + GOLD: subhead innerHTML kaynak strip ----
[...GROUP_A, GOLD].forEach(f=>{
  edit(f, (h)=>{
    if (h.includes("li.innerHTML=("+ "t.subhead||''" )) return h; // already stripped
    return h.replace(
      'li.innerHTML=t.subhead;',
      "li.innerHTML=(t.subhead||'')."+STRIP+";"
    );
  });
});

// ---- Group B: subhead textContent kaynak strip ----
GROUP_B.forEach(f=>{
  edit(f, (h)=>{
    if (h.includes("sub.textContent = (el.textContent")) return h;
    return h.replace(
      'sub.textContent = el.textContent;',
      "sub.textContent = (el.textContent||'')."+STRIP+";"
    );
  });
});

// ---- Group A: kamera — offset 0.24->0.20 (kirpmayi duzelt) + radius *1.2 (uzaklastir, tam ciksin) ----
GROUP_A.forEach(f=>{
  edit(f, (h)=>{
    let n=h;
    n=n.replace(/innerHeight\*0\.24\)/g,'innerHeight*0.20)');
    n=n.replace('const r=cam.radius;','const r=cam.radius*1.2;');
    return n;
  });
});

console.log('Degisen dosyalar ('+done.length+'):');
[...new Set(done)].forEach(f=>console.log('  '+f));
if(warn.length){ console.log('\nUYARI (eslesmedi):'); warn.forEach(w=>console.log('  '+w)); }
