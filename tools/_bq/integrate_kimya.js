// Kimya 3D sahnelerine bq (Soru Bankası) motorunu + verilerini enjekte eder.
// Motor gövdesi (ENGINE_BODY) integrate.js'ten BİREBİR okunur (sapma olmasın).
// Kimya sahneleri seviye/konu için farklı çapalar kullanır (blueprint).
const fs=require('fs'), vm=require('vm');
const BQ='C:/Users/TUNA MUHENDISLIK/snap_nova/tools/_bq';
const AS='C:/Users/TUNA MUHENDISLIK/snap_nova/assets';

function loadBank(file){ const ctx={globalThis:{}}; ctx.globalThis=ctx; vm.createContext(ctx); vm.runInContext(fs.readFileSync(BQ+'/'+file,'utf8'),ctx); return ctx.__BQ; }
function mergeInfo(files){ const out={}; files.forEach(f=>Object.assign(out,loadBank(f))); return out; }

// ── bq motor gövdesini integrate.js'ten al ──
const intSrc=fs.readFileSync(BQ+'/integrate.js','utf8');
const em=intSrc.match(/const ENGINE_BODY = `([\s\S]*?)`;/);
if(!em){ console.error('ENGINE_BODY bulunamadı (integrate.js)'); process.exit(1); }
// Ham kaynak metni değil, template literal'in ÇALIŞMA-ZAMANI değeri gerekli
// (kaçışlar: \\ → \, vb.). ENGINE_BODY içinde ${...} interpolasyonu yok.
const ENGINE_BODY=eval('`'+em[1]+'`');

const NEW_BASE=[[5,10,15],[10,15,20],[10,20,30],[10,20,30],[10,20,30]];

// variant: 'A' = const lv = item.dataset.level (sinav modlu, default lise)
//          'B' = currentLevel = item.dataset.level (maddenin, default ilkokul)
const LESSONS=[
  {html:'atom-periyodik.html', name:'Atom ve Periyodik Sistem', test:'atomperiyodik_test.js', info:['atomperiyodik_info.js'], base:NEW_BASE, variant:'A'},
  {html:'atom-teorisi-orbitaller.html', name:'Atom Teorisi ve Orbitaller', test:'atomteori_test.js', info:['atomteori_info.js'], base:NEW_BASE, variant:'A'},
  {html:'kimyasal-baglar.html', name:'Kimyasal Bağlar', test:'kimyasalbaglar_test.js', info:['kimyasalbaglar_info.js'], base:NEW_BASE, variant:'A'},
  {html:'kimyasal-tepkimeler.html', name:'Kimyasal Tepkimeler', test:'kimyasaltepkimeler_test.js', info:['kimyasaltepkimeler_info.js'], base:NEW_BASE, variant:'A'},
  {html:'mol-stokiyometri.html', name:'Mol ve Stokiyometri', test:'molstokiyometri_test.js', info:['molstokiyometri_info.js'], base:NEW_BASE, variant:'A'},
];

LESSONS.forEach(L=>{
  let testBank, infoBank;
  try{ testBank=loadBank(L.test); infoBank=mergeInfo(L.info); }
  catch(e){ console.log('✗ '+L.html+' veri yüklenemedi: '+e.message.split('\n')[0]); return; }

  const header='\n<script>\n/* Test Soruları + Bilgi Paneli Sistemi (bq) — '+L.name+' */\n(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    +'  var LESSON='+JSON.stringify(L.name)+';\n'
    +'  var BQ_BASE='+JSON.stringify(L.base||NEW_BASE)+';\n'
    +'  var Q={};\n'
    +'  var EXTRA={_all:'+JSON.stringify(testBank)+'};\n'
    +'  var TQ='+JSON.stringify(infoBank)+';\n';
  const engineScript=header+ENGINE_BODY+'\n})();\n</'+'script>\n';

  // JS doğrulama — enjekte edilecek gövdeyi parse et
  const innerCode='(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    +'  var LESSON='+JSON.stringify(L.name)+';\n  var BQ_BASE='+JSON.stringify(L.base||NEW_BASE)+';\n  var Q={};\n  var EXTRA={_all:'+JSON.stringify(testBank)+'};\n  var TQ='+JSON.stringify(infoBank)+';\n'
    + ENGINE_BODY + '\n})();';
  try{ new vm.Script(innerCode); }
  catch(e){ console.log('✗ '+L.html+' JS HATA: '+e.message.split('\n')[0]); return; }

  let h=fs.readFileSync(AS+'/'+L.html,'utf8');
  const log=[];

  // 1) ✎ butonu — navPrev'den ÖNCE ekle (kimya: title="Önceki")
  const navRe=/(<button class="nav-mini-btn" id="navPrev"[^>]*>◀<\/button>)/;
  if(navRe.test(h) && !h.includes('id="bqOpen"')){
    h=h.replace(navRe,'<button class="nav-mini-btn" id="bqOpen" title="Sorular">✎</button>\n          $1'); log.push('bqOpen');
  }

  // 2) seviye → window.__bqLevel (varyanta göre)
  if(!h.includes('window.__bqLevel')){
    if(L.variant==='A' && h.includes('const lv = item.dataset.level;')){
      h=h.replace('const lv = item.dataset.level;', "const lv = item.dataset.level;\n      window.__bqLevel = ({ilkokul:0,ortaokul:1,lise:2,sinav:3}[lv]) ?? 2;");
      log.push('levelA');
    } else if(L.variant==='B' && h.includes('currentLevel = item.dataset.level;')){
      h=h.replace('currentLevel = item.dataset.level;', "currentLevel = item.dataset.level;\n      window.__bqLevel = ({ilkokul:0,ortaokul:1,lise:2}[item.dataset.level]) ?? 0;");
      log.push('levelB');
    }
  }

  // 3) konu → window.__bqTopic (selectSub ilk satırı, 8/8 ortak)
  if(h.includes('currentSub = subKey;') && !h.includes('window.__bqTopic')){
    h=h.replace('currentSub = subKey;', "currentSub = subKey;\n  window.__bqTopic = subKey;"); log.push('topic');
  }

  // 4) cpArcExam → bqOpenMix (mevcut btnExam köprüsünü değiştir)
  h=h.replace('>Test Soruları Oluştur</span>','>Test Soruları</span>');
  h=h.replace(/document\.getElementById\('cpArcExam'\)\.onclick=function\(\)\{closeAll\(\);var b=document\.getElementById\('btnExam'\);if\(b\)b\.click\(\);\};/, "document.getElementById('cpArcExam').onclick=function(){closeAll();if(window.bqOpenMix)window.bqOpenMix();};");
  h=h.replace(/delegate\('cpArcExam','btnExam'\);[^\n]*/, "(function(){ var s=document.getElementById('cpArcExam'); if(s) s.onclick=function(){ if(window.bqOpenMix) window.bqOpenMix(); }; })();");
  if(h.includes('if(window.bqOpenMix)')) log.push('cpArcExam→mix');

  // 5) motoru enjekte et (varsa eski bloğu DEĞİŞTİR)
  const reEngine=/\n<script>\n\/\* Test Soruları \+ Bilgi Paneli Sistemi \(bq\)[\s\S]*?<\/script>\n(?=<\/body>)/;
  if(reEngine.test(h)){ h=h.replace(reEngine, engineScript); log.push('engine↻'); }
  else { h=h.replace('</body>\n</html>', engineScript+'</body>\n</html>'); log.push('engine+'); }

  fs.writeFileSync(AS+'/'+L.html,h,'utf8');
  let infoCnt=0; for(const k in infoBank){ for(const lv in infoBank[k]){ for(const d in infoBank[k][lv]) infoCnt+=infoBank[k][lv][d].length; } }
  let testCnt=0; for(const lv in testBank){ for(const d in testBank[lv]) testCnt+=testBank[lv][d].length; }
  console.log('✓ '+L.html+' | test:'+testCnt+' bilgi:'+infoCnt+' altKonu:'+Object.keys(infoBank).length+' | ['+log.join(', ')+']');
});
