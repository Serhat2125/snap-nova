// Biyoloji dersleri: seviye bazında (ilkokul/ortaokul/lise) test ve info soru sayıları.
const fs = require('fs'), path = require('path');
const AS = path.join(__dirname, '..', '..', 'assets');
const BIO = ['bitki-anatomisi', 'fotosentez', 'ekosistem-besin-zinciri', 'kalitim-genotip-fenotip',
  'hucre-organeller', 'dna-replikasyon', 'mitoz-mayoz', 'sindirim-sistemi', 'dolasim-sistemi',
  'bosaltim-sistemi', 'ureme-sistemi', 'destek-hareket-sistemi', 'denetleyici-duzenleyici-sistem'];

function extract(src, varName) {
  const marker = varName === 'EXTRA' ? 'var EXTRA={_all:' : 'var TQ=';
  const i = src.indexOf(marker); if (i === -1) return null;
  let j = i + marker.length; while (j < src.length && src[j] !== '{') j++;
  let depth = 0, inStr = false, esc = false, start = j;
  for (; j < src.length; j++) {
    const c = src[j];
    if (inStr) { if (esc) esc = false; else if (c === '\\') esc = true; else if (c === '"') inStr = false; }
    else { if (c === '"') inStr = true; else if (c === '{') depth++; else if (c === '}') { depth--; if (depth === 0) { j++; break; } } }
  }
  let blob = src.slice(start, j); if (varName === 'EXTRA') blob = '{"_all":' + blob + '}';
  try { return JSON.parse(blob); } catch (e) { return null; }
}
function testByLevel(extra) { const all = (extra && extra._all) || {}; const r = {}; for (const lv in all) { let n = 0; for (const d in all[lv]) n += all[lv][d].length; r[lv] = n; } return r; }
function infoByLevel(tq) { const r = {}; if (!tq) return r; for (const t in tq) for (const lv in tq[t]) { let n = 0; for (const d in tq[t][lv]) n += tq[t][lv][d].length; r[lv] = (r[lv] || 0) + n; } return r; }

console.log('ders'.padEnd(32), '| TEST ilk/orta/lise'.padEnd(22), '| INFO ilk/orta/lise'.padEnd(22), '| lise durumu');
const fmt = o => ['ilkokul', 'ortaokul', 'lise'].map(k => o[k] || 0).join('/');
for (const f of BIO) {
  const src = fs.readFileSync(path.join(AS, f + '.html'), 'utf8');
  const tb = testByLevel(extract(src, 'EXTRA'));
  const ib = infoByLevel(extract(src, 'TQ'));
  const liseTest = tb.lise || 0, liseInfo = ib.lise || 0;
  const flag = (liseTest === 0 || liseInfo === 0) ? 'LİSE EKSİK ⚠' : 'tam';
  console.log(f.padEnd(32), '|', fmt(tb).padEnd(20), '|', fmt(ib).padEnd(20), '|', 'test:' + liseTest + ' info:' + liseInfo + ' ' + flag);
}
