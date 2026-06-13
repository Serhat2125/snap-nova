const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

// ALL biology lessons including the gold standard (its override left border/text red).
const FILES = [
  'denetleyici-duzenleyici-sistem.html','destek-hareket-sistemi.html',
  'bosaltim-sistemi.html','dolasim-sistemi.html','sindirim-sistemi.html',
  'ureme-sistemi.html','dna-replikasyon.html','hucre-organeller.html','mitoz-mayoz.html',
  'ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

// Targets ONLY the comparison/info table overlays — leaves the lesson's --accent theme
// (labels, buttons, scrollbars) untouched. Blue (#5fc8e0 / #2f8fd0 / #1a6b8a) + green
// (#5fd99a / #1f7a5e) only; no red/orange. Placed last + !important so it wins the cascade.
const CSS = `
<style id="tableColorFix">
/* Bilgi & Karşılaştırma tabloları: kırmızı yok — sadece mavi + yeşil */
#compareOverlay .cmp-table, #tableOverlay .cmp-table{ border-color:#2f8fd0 !important; }
#compareOverlay .cmp-table th, #tableOverlay .cmp-table th{
  background:linear-gradient(135deg,#1a6b8a 0%,#1f7a5e 100%) !important;
  color:#eafaff !important; border-color:#2f8fd0 !important;
}
#compareOverlay .cmp-table td, #tableOverlay .cmp-table td{ border-color:rgba(95,200,224,.22) !important; }
#compareOverlay .cmp-table td:first-child, #tableOverlay .cmp-table td:first-child{ color:#5fd99a !important; }
#compareOverlay .cmp-table tbody tr:nth-child(odd) td, #tableOverlay .cmp-table tbody tr:nth-child(odd) td{ background:rgba(95,200,224,.06) !important; }
#compareOverlay .cmp-table tbody tr:nth-child(even) td, #tableOverlay .cmp-table tbody tr:nth-child(even) td{ background:rgba(95,217,154,.10) !important; }
#compareOverlay .cmp-table tr:hover td, #tableOverlay .cmp-table tr:hover td{ background:rgba(95,200,224,.20) !important; }
/* Başlık + gezinme + çerçeve */
#compareTitle, #tableTitle{ color:#5fc8e0 !important; }
#compareNav button, #tableNav button{ border-color:#2f8fd0 !important; color:#5fc8e0 !important; }
#compareOverlay .cmp-overlay-box, #tableOverlay .cmp-overlay-box,
#compareOverlay .overlay-box, #tableOverlay .overlay-box{ border-color:#2f8fd0 !important; }
/* İçerikte kırmızımsı vurgu metinleri → yeşil (✗/farklılık işaretleri vb.) */
#compareOverlay .cmp-table td [style*="color:#e74c3c"], #tableOverlay .cmp-table td [style*="color:#e74c3c"],
#compareOverlay .cmp-table td [style*="color:#ef4444"], #tableOverlay .cmp-table td [style*="color:#ef4444"],
#compareOverlay .cmp-table td [style*="color:#ff6f00"], #tableOverlay .cmp-table td [style*="color:#ff6f00"]{ color:#5fd99a !important; }
</style>`;

let passed=0, skipped=0, failed=0;
for (const fname of FILES){
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    if (html.includes('id="tableColorFix"')){
      console.log('SKIP (present): ' + fname); skipped++; continue;
    }
    html = html.replace('</body>', CSS + '\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: ' + fname);
    passed++;
  } catch(e){
    console.log('ERROR: ' + fname + ' - ' + e.message);
    failed++;
  }
}
console.log('\n' + passed + ' done, ' + skipped + ' skipped, ' + failed + ' failed');
