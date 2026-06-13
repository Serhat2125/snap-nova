const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';
const GOLD = 'denetleyici-duzenleyici-sistem.html';

const FILES = [
  'destek-hareket-sistemi.html','bosaltim-sistemi.html','dolasim-sistemi.html',
  'sindirim-sistemi.html','ureme-sistemi.html','dna-replikasyon.html',
  'hucre-organeller.html','mitoz-mayoz.html'
];

// Extract a `function NAME(){ ... }` block by brace counting starting at the keyword.
function extractFn(html, marker){
  const i = html.indexOf(marker);
  if (i < 0) return null;
  let depth = 0, started = false, j = i;
  for (; j < html.length; j++){
    const c = html[j];
    if (c === '{'){ depth++; started = true; }
    else if (c === '}'){ depth--; if (started && depth === 0){ j++; break; } }
  }
  return { start: i, end: j, text: html.slice(i, j) };
}

// 1. Get gold-standard updateLabels body
const goldHtml = fs.readFileSync(BASE + GOLD, 'utf8');
const goldBlock = extractFn(goldHtml, 'function updateLabels');
if (!goldBlock){ console.error('GOLD updateLabels not found!'); process.exit(1); }
console.log('Gold updateLabels length: ' + goldBlock.text.length);

let passed=0, failed=0;

for (const fname of FILES){
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    let changes = [];

    // --- Replace updateLabels with gold version ---
    const cur = extractFn(html, 'function updateLabels');
    if (!cur){ console.log('SKIP (no updateLabels): ' + fname); failed++; continue; }
    if (cur.text === goldBlock.text){
      changes.push('updateLabels already gold');
    } else {
      html = html.slice(0, cur.start) + goldBlock.text + html.slice(cur.end);
      changes.push('updateLabels->gold');
    }

    // --- canvas max-width:100vw ---
    if (html.includes('canvas { display:block; cursor:grab; max-width:100vw; }') ||
        html.includes('canvas{display:block;cursor:grab;max-width:100vw;}')){
      changes.push('maxwidth already');
    } else if (html.includes('canvas { display:block; cursor:grab; }')){
      html = html.replace('canvas { display:block; cursor:grab; }',
                          'canvas { display:block; cursor:grab; max-width:100vw; }');
      changes.push('maxwidth+');
    } else {
      changes.push('maxwidth: canvas rule not matched');
    }

    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: ' + fname.padEnd(30) + ' [' + changes.join(', ') + ']');
    passed++;
  } catch(e){
    console.log('ERROR: ' + fname + ' - ' + e.message);
    failed++;
  }
}
console.log('\n' + passed + ' done, ' + failed + ' failed');
