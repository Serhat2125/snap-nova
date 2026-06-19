const fs=require('fs'), vm=require('vm'), path=require('path');
const BQ='C:/Users/TUNA MUHENDISLIK/snap_nova/tools/_bq';
const AS='C:/Users/TUNA MUHENDISLIK/snap_nova/assets';

function loadBank(file){ const ctx={globalThis:{}}; ctx.globalThis=ctx; vm.createContext(ctx); vm.runInContext(fs.readFileSync(BQ+'/'+file,'utf8'),ctx); return ctx.__BQ; }
function mergeInfo(files){ const out={}; files.forEach(f=>Object.assign(out,loadBank(f))); return out; }

// ENGINE_BODY'yi integrate.js'ten al (template literal escape'leri düzelt: \\ → \)
const intSrc=fs.readFileSync(path.join(__dirname,'integrate.js'),'utf8');
const ENGINE_BODY=intSrc.match(/const ENGINE_BODY = `([\s\S]*?)`;/)[1].replace(/\\\\/g,'\\');

const NEW_BASE=[[5,10,15],[10,15,20],[10,20,30],[10,20,30],[10,20,30]];

const LESSONS=[
  {html:'elektrik.html', name:'Elektrik', test:'elektrik_test.js', info:['elektrik_info_a.js','elektrik_info_b.js','elektrik_info_c.js'], base:NEW_BASE},
  {html:'akiskanlar-mekanigi.html', name:'Akışkanlar Mekaniği', test:'akiskanlar_test.js', info:['akiskanlar_info_a.js','akiskanlar_info_b.js','akiskanlar_info_c.js'], base:NEW_BASE},
];

LESSONS.forEach(L=>{
  const testBank=loadBank(L.test);
  const infoBank=mergeInfo(L.info);
  const header='\n<script>\n/* Test Soruları + Bilgi Paneli Sistemi (bq) — '+L.name+' */\n(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    +'  var LESSON='+JSON.stringify(L.name)+';\n'
    +'  var BQ_BASE='+JSON.stringify(L.base||NEW_BASE)+';\n'
    +'  var Q={};\n'
    +'  var EXTRA={_all:'+JSON.stringify(testBank)+'};\n'
    +'  var TQ='+JSON.stringify(infoBank)+';\n';
  const engineScript=header+ENGINE_BODY+'\n})();\n</'+'script>\n';

  const innerCode='(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    +'  var LESSON='+JSON.stringify(L.name)+';\n  var BQ_BASE='+JSON.stringify(L.base||NEW_BASE)+';\n  var Q={};\n  var EXTRA={_all:'+JSON.stringify(testBank)+'};\n  var TQ='+JSON.stringify(infoBank)+';\n'
    +ENGINE_BODY+'\n})();';
  try{ new vm.Script(innerCode); }
  catch(e){ console.log('✗ '+L.html+' JS HATA: '+e.message.split('\n')[0]); return; }

  let h=fs.readFileSync(AS+'/'+L.html,'utf8');
  const log=[];
  h=h.replace('>Test Soruları Oluştur</span>','>Test Soruları</span>');
  h=h.replace(/document\.getElementById\('cpArcExam'\)\.onclick=function\(\)\{closeAll\(\);var b=document\.getElementById\('btnExam'\);if\(b\)b\.click\(\);\};/,"document.getElementById('cpArcExam').onclick=function(){closeAll();if(window.bqOpenMix)window.bqOpenMix();};");
  h=h.replace(/delegate\('cpArcExam','btnExam'\);[^\n]*/,"(function(){ var s=$('cpArcExam'); if(s) s.onclick=function(){ var ap=$('araclarComboP'); if(ap) ap.classList.remove('show'); var pbb=$('_popBlur'); if(pbb) pbb.style.display='none'; if(window.bqOpenMix) window.bqOpenMix(); }; })();");
  if(h.includes('if(window.bqOpenMix)')) log.push('cpArcExam→mix');
  const reEngine=/\n<script>\n\/\* Test Soruları \+ Bilgi Paneli Sistemi \(bq\)[\s\S]*?<\/script>\n(?=<\/body>)/;
  if(reEngine.test(h)){ h=h.replace(reEngine, engineScript); log.push('engine↻'); }
  else { h=h.replace('</body>\n</html>', engineScript+'</body>\n</html>'); log.push('engine+'); }

  fs.writeFileSync(AS+'/'+L.html,h,'utf8');
  let infoCnt=0; for(const k in infoBank){ for(const lv in infoBank[k]){ for(const d in infoBank[k][lv]) infoCnt+=infoBank[k][lv][d].length; } }
  let testCnt=0; for(const lv in testBank){ for(const d in testBank[lv]) testCnt+=testBank[lv][d].length; }
  console.log('✓ '+L.html+' | test:'+testCnt+' bilgi:'+infoCnt+' altKonu:'+Object.keys(infoBank).length+' | ['+log.join(', ')+']');
});
