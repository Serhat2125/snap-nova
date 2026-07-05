// Motorsuz 3 kimya dersine (karisimlar, molekul, organik) bq motorunu FİZİK
// deseniyle enjekte eder: engine + selectSub seviye/konu exposure + ✎ buton +
// cpArcExam→bqOpenMix. Bu dersler currentLevel string kullanır (integrate_kimya
// numeric curLevel=idx bekler → uymaz). lise=üniversite motor lvKey ile gelir.
const fs = require('fs'), vm = require('vm'), path = require('path');
const BQ = path.resolve(__dirname);
const AS = path.resolve(__dirname, '..', '..', 'assets');

function loadBank(file) { const ctx = { globalThis: {} }; ctx.globalThis = ctx; vm.createContext(ctx); vm.runInContext(fs.readFileSync(BQ + '/' + file, 'utf8'), ctx); return ctx.__BQ; }
function mergeInfo(files) { const out = {}; files.forEach(f => Object.assign(out, loadBank(f))); return out; }

const intSrc = fs.readFileSync(path.join(__dirname, 'integrate.js'), 'utf8');
const ENGINE_BODY = intSrc.match(/const ENGINE_BODY = `([\s\S]*?)`;/)[1].replace(/\\\\/g, '\\');
const NEW_BASE = [[5, 10, 15], [10, 15, 20], [10, 20, 30], [10, 20, 30], [10, 20, 30]];

// Sadece test+info bankası HAZIR olan dersleri işler (dosya yoksa atlar).
const LESSONS = [
  { html: 'karisimlar-cozeltiler.html', name: 'Karışımlar ve Çözeltiler', test: 'karisimlar_test.js', info: ['karisimlar_info.js'] },
  { html: 'molekul-geometrisi.html', name: 'Molekül Geometrisi', test: 'molekul_test.js', info: ['molekul_info.js'] },
  { html: 'organik-kimya.html', name: 'Organik Kimya', test: 'organik_test.js', info: ['organik_info.js'] },
];

const ONLY = process.argv.slice(2); // opsiyonel: slug filtre

LESSONS.forEach(L => {
  if (ONLY.length && !ONLY.some(s => L.html.includes(s))) return;
  if (!fs.existsSync(BQ + '/' + L.test)) { console.log('⏭  ' + L.html + ' — test bankası yok, atlandı'); return; }
  const testBank = loadBank(L.test);
  const infoBank = mergeInfo(L.info.filter(f => fs.existsSync(BQ + '/' + f)));

  const header = '\n<script>\n/* Test Soruları + Bilgi Paneli Sistemi (bq) — ' + L.name + ' */\n(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    + '  var LESSON=' + JSON.stringify(L.name) + ';\n'
    + '  var BQ_BASE=' + JSON.stringify(NEW_BASE) + ';\n'
    + '  var Q={};\n'
    + '  var EXTRA={_all:' + JSON.stringify(testBank) + '};\n'
    + '  var TQ=' + JSON.stringify(infoBank) + ';\n';
  const engineScript = header + ENGINE_BODY + '\n})();\n</' + 'script>\n';

  // JS doğrulama
  const innerCode = '(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    + '  var LESSON=' + JSON.stringify(L.name) + ';\n  var BQ_BASE=' + JSON.stringify(NEW_BASE) + ';\n  var Q={};\n  var EXTRA={_all:' + JSON.stringify(testBank) + '};\n  var TQ=' + JSON.stringify(infoBank) + ';\n'
    + ENGINE_BODY + '\n})();';
  try { new vm.Script(innerCode); }
  catch (e) { console.log('✗ ' + L.html + ' JS HATA: ' + e.message.split('\n')[0]); return; }

  let h = fs.readFileSync(AS + '/' + L.html, 'utf8');
  const log = [];

  // 1) selectSub seviye/konu exposure (currentSub = subKey; sonrası) — idempotent
  if (!h.includes('window.__bqTopic = subKey')) {
    h = h.replace('function selectSub(subKey) {\n  currentSub = subKey;',
      'function selectSub(subKey) {\n  currentSub = subKey;\n  window.__bqTopic = subKey;\n  var _bqLvMap = { ilkokul:0, ortaokul:1, lise:2, tyt_ayt:3, universite:4 };\n  window.__bqLevel = (_bqLvMap[currentLevel] != null) ? _bqLvMap[currentLevel] : 2;');
    if (h.includes('window.__bqTopic = subKey')) log.push('selectSub-expose');
  } else log.push('expose-var');

  // 2) ✎ butonu (navPrev soluna) — idempotent
  if (!h.includes('id="bqOpen"')) {
    h = h.replace('<button class="nav-mini-btn" id="navPrev" title="Önceki">◀</button>',
      '<button class="nav-mini-btn" id="bqOpen" title="Sorular">✎</button>\n          <button class="nav-mini-btn" id="navPrev" title="Önceki">◀</button>');
    if (h.includes('id="bqOpen"')) log.push('bqOpen');
  } else log.push('bqOpen-var');

  // 3) cpArcExam → bqOpenMix
  h = h.replace('>Test Soruları Oluştur</span>', '>Test Soruları</span>');
  h = h.replace(/document\.getElementById\('cpArcExam'\)\.onclick=function\(\)\{closeAll\(\);var b=document\.getElementById\('btnExam'\);if\(b\)b\.click\(\);\};/, "document.getElementById('cpArcExam').onclick=function(){closeAll();if(window.bqOpenMix)window.bqOpenMix();};");
  h = h.replace(/delegate\('cpArcExam','btnExam'\);[^\n]*/, "(function(){ var s=$('cpArcExam'); if(s) s.onclick=function(){ var ap=$('araclarComboP'); if(ap) ap.classList.remove('show'); var pbb=$('_popBlur'); if(pbb) pbb.style.display='none'; if(window.bqOpenMix) window.bqOpenMix(); }; })();");
  if (h.includes('if(window.bqOpenMix)')) log.push('cpArcExam→mix');

  // 4) motor enjeksiyonu
  const reEngine = /\n<script>\n\/\* Test Soruları \+ Bilgi Paneli Sistemi \(bq\)[\s\S]*?<\/script>\n(?=<\/body>)/;
  if (reEngine.test(h)) { h = h.replace(reEngine, engineScript); log.push('engine↻'); }
  else { h = h.replace('</body>\n</html>', engineScript + '</body>\n</html>'); log.push('engine+'); }

  fs.writeFileSync(AS + '/' + L.html, h, 'utf8');
  let testCnt = 0; for (const lv in testBank) for (const d in testBank[lv]) testCnt += testBank[lv][d].length;
  let infoCnt = 0; for (const k in infoBank) for (const lv in infoBank[k]) for (const d in infoBank[k][lv]) infoCnt += infoBank[k][lv][d].length;
  console.log('✓ ' + L.html + ' | test:' + testCnt + ' bilgi:' + infoCnt + ' konu:' + Object.keys(infoBank).length + ' | [' + log.join(', ') + ']');
});
