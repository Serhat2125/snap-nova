const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';
const FILES = [
  'bosaltim-sistemi.html','dna-replikasyon.html','dolasim-sistemi.html',
  'hucre-organeller.html','mitoz-mayoz.html','sindirim-sistemi.html',
  'ureme-sistemi.html','ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

let allOk = true;
for (const fname of FILES) {
  const h = fs.readFileSync(BASE + fname, 'utf8');

  // CSS region
  const cs = h.indexOf('id="dunyaPatchCss"');
  const ce = h.indexOf('</style>', cs);
  const css = cs >= 0 ? h.slice(cs, ce) : '';

  // bottomPanel region (~800 chars)
  const bp = h.indexOf('id="bottomPanel"');
  const bpr = bp >= 0 ? h.slice(bp, bp + 800) : '';

  // Combo IIFE region (9000 chars from start of arcPop)
  const ci = h.indexOf('araclarComboP');
  const combo = ci >= 0 ? h.slice(ci, ci + 9000) : '';

  // Handler positions
  const newH = h.lastIndexOf('_icb.onclick');
  const oldH = h.indexOf("classList.add('hidden')");

  const checks = {
    'CSS dock-tab-btn':        css.includes('dock-tab-btn'),
    'CSS info-mini':           css.includes('info-mini'),
    'CSS ttsPulse':            css.includes('ttsPulse'),
    'HTML infoMiniChip':       bpr.includes('infoMiniChip'),
    'HTML chip after closeBtn':bpr.indexOf('infoCloseBtn') < bpr.indexOf('infoMiniChip'),
    'IIFE arcPop':             h.includes('araclarComboP'),
    'IIFE posAbove':           combo.includes('posAbove'),
    'IIFE closeAll':           combo.includes('closeAll'),
    'IIFE space-between':      combo.includes('space-between'),
    'IIFE ttsChip':            combo.includes('ttsActiveChip'),
    'IIFE KES':                combo.includes('KES'),
    'IIFE new handler after old': newH > oldH,
    'IIFE after head':         h.lastIndexOf('araclarComboP') > h.lastIndexOf('</head>'),
  };

  const fails = Object.entries(checks).filter(([, v]) => !v).map(([k]) => k);
  if (fails.length === 0) {
    console.log('OK: ' + fname);
  } else {
    console.log('FAIL: ' + fname + ' -> ' + fails.join(', '));
    allOk = false;
  }
}
console.log(allOk ? '\nTUMMU GECTI' : '\nHATALAR VAR');
