// Kimya + Fizik + Coğrafya'ya biyoloji pipeline'ını uygular.
// Mevcut script'lerin FILES dizisini geçici TARGET ile değiştirip çalıştırır (orijinallere dokunmaz).
const fs = require('fs');
const cp = require('child_process');
const TBASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/tools/';

const TARGET = [
  // Kimya (9)
  'atom-periyodik.html','atom-teorisi-orbitaller.html','kimyasal-baglar.html',
  'kimyasal-tepkimeler.html','maddenin-yapisi.html','molekul-geometrisi.html',
  'mol-stokiyometri.html','organik-kimya.html','karisimlar-cozeltiler.html',
  // Fizik (7)
  'elektrik.html','dalgalar.html','optik-mercekler.html','basit-makineler.html',
  'bileske-kuvvet-vektorler.html','akiskanlar-mekanigi.html','golge-olusumu-isik-yayilmasi.html',
  // Coğrafya (5) — dunyanin-hareketleri farklı mimari (FOV45, cam.radius, CSS2D yok) ama butonları var; pipeline defansif
  'dunya-cografyasi.html','atmosfer-iklim.html','yer-sekilleri-izohipsler.html','yerin-ic-yapisi-levha-tektonigi.html',
  'dunyanin-hareketleri.html'
];

// Biyolojide uygulanan sırayla
const SCRIPTS = [
  'apply_bio_standard.js',   // Combo IIFE + CSS + infoMiniChip
  'fix_bio_dock.js',         // 3-buton dock
  'fix_bio_mode.js',         // sade/detaylı toggle + grid + subhead observer
  'fix_bio_labels_groupB.js',// CSS2D declutter shim
  'fix_bio_master.js',       // palette/info-mini/mode/exam-ai/grid master override
  'fix_bio_table_colors.js', // tablo renkleri (mavi/yeşil)
  'fix_bio_style_v2.js'      // dock bar + panel renkleri + 🌿 ikon + palet + blur
];

for (const s of SCRIPTS) {
  let code = fs.readFileSync(TBASE + s, 'utf8');
  // İlk `const FILES = [ ... ];` literalini TARGET ile değiştir
  const replaced = code.replace(/const FILES\s*=\s*\[[\s\S]*?\];/,
    'const FILES = ' + JSON.stringify(TARGET) + ';');
  if (replaced === code) { console.log('!! '+s+': FILES bulunamadi, atlandi'); continue; }
  const tmp = TBASE + '_tmp_' + s;
  fs.writeFileSync(tmp, replaced, 'utf8');
  console.log('===== ' + s + ' =====');
  try {
    console.log(cp.execSync('node "' + tmp + '"', { encoding: 'utf8' }));
  } catch(e) {
    console.log('HATA: ' + (e.stdout||'') + (e.stderr||e.message));
  }
  fs.unlinkSync(tmp);
}
console.log('PIPELINE BITTI');
