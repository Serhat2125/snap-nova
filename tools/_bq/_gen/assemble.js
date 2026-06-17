// Temp __OUT dosyalarını birleştirip kaynak bq dosyaları üretir.
// Kullanım: node assemble.js <prefix> <testOut.js> <infoOut.js>
//   <prefix>_test_*.js  → testOut (globalThis.__BQ = {ilkokul,ortaokul,lise})
//   <prefix>_info_*.js  → infoOut (globalThis.__BQ = {topicKey:{...}})
const fs = require('fs'), vm = require('vm'), path = require('path');
const GEN = __dirname;
const BQ = path.resolve(__dirname, '..');

const [prefix, testOut, infoOut] = process.argv.slice(2);
if (!prefix || !testOut || !infoOut) { console.error('args: <prefix> <testOut> <infoOut>'); process.exit(1); }

function loadOut(file) {
  const c = {}; c.globalThis = c; vm.createContext(c);
  vm.runInContext(fs.readFileSync(path.join(GEN, file), 'utf8'), c);
  return c.__OUT;
}
const files = fs.readdirSync(GEN).filter(f => f.endsWith('.js') && f !== 'assemble.js');

// ── TEST birleştir (level → diff → array) ──
const testFiles = files.filter(f => f.startsWith(prefix + '_test_'));
const test = {};
testFiles.forEach(f => {
  const o = loadOut(f);
  for (const lv in o) {
    test[lv] = test[lv] || {};
    for (const d in o[lv]) {
      test[lv][d] = (test[lv][d] || []).concat(o[lv][d]);
    }
  }
});
// dedup by q içinde her level/diff
for (const lv in test) for (const d in test[lv]) {
  const seen = new Set(); test[lv][d] = test[lv][d].filter(q => { const k = (q.q || '').trim(); if (seen.has(k)) return false; seen.add(k); return true; });
}

// ── INFO birleştir (topicKey → ...) ──
const infoFiles = files.filter(f => f.startsWith(prefix + '_info_'));
const info = {};
infoFiles.forEach(f => {
  const o = loadOut(f);
  for (const tk in o) {
    info[tk] = info[tk] || {};
    for (const lv in o[tk]) {
      info[tk][lv] = info[tk][lv] || {};
      for (const d in o[tk][lv]) {
        info[tk][lv][d] = (info[tk][lv][d] || []).concat(o[tk][lv][d]);
      }
    }
  }
});

fs.writeFileSync(path.join(BQ, testOut), 'globalThis.__BQ = ' + JSON.stringify(test) + ';\n', 'utf8');
fs.writeFileSync(path.join(BQ, infoOut), 'globalThis.__BQ = ' + JSON.stringify(info) + ';\n', 'utf8');

// rapor
console.log('TEST (' + testFiles.length + ' dosya):');
for (const lv in test) console.log('  ' + lv, Object.keys(test[lv]).map(d => d + ':' + test[lv][d].length).join(' '));
console.log('INFO (' + infoFiles.length + ' dosya, ' + Object.keys(info).length + ' altKonu):');
for (const tk in info) console.log('  ' + tk, Object.keys(info[tk]).map(lv => lv + '[' + Object.keys(info[tk][lv]).map(d => d + ':' + info[tk][lv][d].length).join('/') + ']').join(' '));
