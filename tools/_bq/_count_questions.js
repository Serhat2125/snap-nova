// Her ders HTML'inden bq motorunun EXTRA._all (test) ve TQ (info/✎) veri
// bloklarını çıkarıp soru sayılarını raporlar. Konu sayısı = TQ anahtar sayısı.
const fs = require('fs'), path = require('path');
const AS = path.join(__dirname, '..', '..', 'assets');

function extractJson(src, varName) {
  // "var EXTRA={_all:" veya "var TQ=" sonrası dengeli süslü parantez tara
  const marker = varName === 'EXTRA' ? 'var EXTRA={_all:' : 'var TQ=';
  const i = src.indexOf(marker);
  if (i === -1) return null;
  let j = i + marker.length;
  // EXTRA için _all: sonrası { ile başlar; TQ için doğrudan {
  while (j < src.length && src[j] !== '{') j++;
  let depth = 0, inStr = false, esc = false, start = j;
  for (; j < src.length; j++) {
    const c = src[j];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
    } else {
      if (c === '"') inStr = true;
      else if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) { j++; break; } }
    }
  }
  let blob = src.slice(start, j);
  if (varName === 'EXTRA') blob = '{"_all":' + blob + '}'; // sarmala
  try { return JSON.parse(blob); } catch (e) { return { __err: e.message }; }
}

function countTest(extra) {
  // extra._all: level -> difficulty -> [q]
  if (!extra || extra.__err) return { total: 0, err: extra && extra.__err };
  const all = extra._all || {};
  let total = 0;
  for (const lv in all) for (const d in all[lv]) total += (all[lv][d] || []).length;
  return { total };
}
function countInfo(tq) {
  // tq: topic -> level -> difficulty -> [q]
  if (!tq || tq.__err) return { total: 0, topics: 0, err: tq && tq.__err };
  let total = 0; const topics = Object.keys(tq);
  for (const t of topics) for (const lv in tq[t]) for (const d in tq[t][lv]) total += (tq[t][lv][d] || []).length;
  return { total, topics: topics.length };
}

const rows = [];
for (const f of fs.readdirSync(AS)) {
  if (!f.endsWith('.html')) continue;
  const src = fs.readFileSync(path.join(AS, f), 'utf8');
  if (!src.includes('__bqInit')) continue;
  const extra = extractJson(src, 'EXTRA');
  const tq = extractJson(src, 'TQ');
  const t = countTest(extra), inf = countInfo(tq);
  rows.push({ f, test: t.total, info: inf.total, topics: inf.topics,
    testPerTopic: inf.topics ? Math.round(t.total / inf.topics) : 0,
    infoPerTopic: inf.topics ? Math.round(inf.total / inf.topics) : 0,
    err: t.err || inf.err });
}
rows.sort((a, b) => a.info - b.info);
console.log('ders'.padEnd(38), 'test', 'info', 'konu', 't/konu', 'i/konu', 'hata');
for (const r of rows) {
  console.log(r.f.padEnd(38), String(r.test).padStart(4), String(r.info).padStart(4),
    String(r.topics).padStart(4), String(r.testPerTopic).padStart(6),
    String(r.infoPerTopic).padStart(6), r.err || '');
}
const byInfo = rows.filter(r => !r.err);
const minInfo = byInfo.reduce((m, r) => r.info < m.info ? r : m, byInfo[0]);
const minTest = byInfo.reduce((m, r) => r.test < m.test ? r : m, byInfo[0]);
console.log('\nEN AZ INFO (✎):', minInfo.f, '→', minInfo.info, 'soru,', minInfo.topics, 'konu,', minInfo.infoPerTopic, '/konu');
console.log('EN AZ TEST     :', minTest.f, '→', minTest.test, 'soru,', minTest.testPerTopic, '/konu');
