const fs=require('fs'), vm=require('vm'), path=require('path');
const BQ='C:/Users/TUNA MUHENDISLIK/snap_nova/tools/_bq';
const AS='C:/Users/TUNA MUHENDISLIK/snap_nova/assets';

function loadBank(file){ const ctx={globalThis:{}}; ctx.globalThis=ctx; vm.createContext(ctx); vm.runInContext(fs.readFileSync(BQ+'/'+file,'utf8'),ctx); return ctx.__BQ; }
function mergeInfo(files){ const out={}; files.forEach(f=>Object.assign(out,loadBank(f))); return out; }

// ── bq motor gövdesi (veri tanımları header'da enjekte edilir) ──────────────
const ENGINE_BODY = `
  function lvIdx(){ return (typeof window.__bqLevel==='number')?window.__bqLevel:2; }
  function lvKey(){ return ['ilkokul','ortaokul','lise','lise','lise'][lvIdx()]||'lise'; }
  var LV_NAMES=['İlkokul','Ortaokul','Lise','Sınavlara Hazırlık','Üniversite'];
  function lvName(){ return LV_NAMES[lvIdx()]||'Lise'; }
  function topicName(){ return LESSON; }
  function topicKey(){ return window.__bqTopic||Object.keys(TQ)[0]; }
  function curTopicName(){ try{return document.getElementById('infoTitle').textContent.trim()||'Konu';}catch(e){return 'Konu';} }
  function baseCounts(){ var i=lvIdx(); return (typeof BQ_BASE!=='undefined' && BQ_BASE[i])?BQ_BASE[i]:[10,20,30,40]; }
  function capCounts(len){ var base=baseCounts(); if(len<=0) return base; var r=base.filter(function(n){return n<=len;}); if(!r.length) r=[len]; return r; }
  function stepCounts(len){ var base=[5,10]; if(len<=0) return base; var r=base.filter(function(n){return n<=len;}); if(!r.length) r=[len]; return r; }
  function nOpt(){ return lvIdx()===0?3:(lvIdx()===1?4:5); }
  function isTimed(){ return lvIdx()>=2; }
  var CNT_LBL={5:'Kısa Tur',10:'Standart',15:'Uzun Tur',20:'Tam Çalışma',25:'Geniş Set',30:'Derinlemesine',40:'İleri Set',50:'Sınav Modu'};
  function shuffle(a){ for(var i=a.length-1;i>0;i--){ var j=Math.floor(Math.random()*(i+1)); var t=a[i];a[i]=a[j];a[j]=t; } return a; }
  function pool(diff){ var lv=lvKey(); var out=[]; [Q,EXTRA].forEach(function(B){ for(var k in B){ var L=B[k][lv]||B[k].lise||{}; if(L[diff]) out=out.concat(L[diff]); } }); return shuffle(out); }
  function poolStep(diff){ var t=TQ[topicKey()]; if(!t) return null; var L=t[lvKey()]||t.lise||{}; var a=(L[diff]||[]).slice(); return shuffle(a); }
  var css=''
   +'#bqBack{position:fixed;inset:0;background:rgba(4,10,22,.66);backdrop-filter:blur(3px);z-index:998;display:none}#bqBack.on{display:block}'
   +'#bqPick{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:min(92vw,470px);max-height:88vh;overflow:auto;background:#101a2c;border:1px solid #28415f;border-radius:18px;padding:16px;z-index:999;display:none;box-shadow:0 24px 70px #000b}#bqPick.on{display:block}'
   +'.bq-ph{font:800 17px "Bricolage Grotesque",system-ui;color:#eaf2ff;text-align:center}.bq-ph b{color:#ffb24e}'
   +'.bq-psub{font:500 12px system-ui;color:#8aa0c4;margin:3px 0 12px;text-align:center}'
   +'.bq-cols{display:grid;grid-template-columns:1fr 1fr;gap:10px}'
   +'.bq-colh{border-radius:9px;padding:6px;text-align:center;font:800 12.5px system-ui;margin-bottom:6px}'
   +'.bq-colh.easy{background:#34d39922;color:#34d399}.bq-colh.hard{background:#ff7a4d22;color:#ff8a5c}'
   +'.bq-col{display:flex;flex-direction:column;gap:8px}'
   +'.bq-go{border-radius:13px;padding:11px 6px;cursor:pointer;background:linear-gradient(160deg,rgba(255,255,255,.04),rgba(255,255,255,.01));width:100%;text-align:center;transition:.15s}'
   +'.bq-go b{font:800 18px "Bricolage Grotesque",system-ui}.bq-go small{display:block;font:600 10px system-ui;opacity:.72;margin-top:1px}.bq-go:hover{filter:brightness(1.3)}'
   +'.bq-desc{font:500 10.5px system-ui;color:#8aa0c4;text-align:center;margin-bottom:6px;line-height:1.35;min-height:26px}'
   +'#bqPickClose{margin-top:14px;width:100%;border:1px solid #2b405d;background:transparent;color:#aebbd6;border-radius:12px;padding:10px;font:700 13px system-ui;cursor:pointer}'
   +'#bqOverlay{position:fixed;inset:0;background:#34373d;z-index:1000;display:none;flex-direction:column}#bqOverlay.on{display:flex}'
   +'.bq-oh{display:flex;align-items:center;gap:10px;padding:13px 16px;border-bottom:1px solid #2b2e34;background:#26282d}'
   +'.bq-oh #bqTitle{font:800 14.5px "Bricolage Grotesque",system-ui;color:#eaf2ff;flex:1;line-height:1.2}'
   +'.bq-oh #bqTitle small{display:block;font:600 11px system-ui;color:#7e95bf;margin-top:2px}'
   +'#bqTimer{font:700 12.5px "DM Mono",monospace;color:#ffb24e}'
   +'.bq-cevap{font:700 11.5px "DM Mono",monospace;color:#ffb24e;border:1px solid #ffb24e66;border-radius:20px;padding:4px 11px;white-space:nowrap}'
   +'#bqClose{border:none;background:#16294a;color:#cdd9f0;width:34px;height:34px;border-radius:9px;font-size:16px;cursor:pointer}'
   +'#bqScroll{flex:1;overflow:auto;padding:16px 14px 48px;-webkit-overflow-scrolling:touch}'
   +'.bq-q{background:linear-gradient(162deg,#52565f,#42454c);border:1px solid #6a6f79;border-radius:16px;padding:15px 16px;margin:0 auto 14px;max-width:680px;box-shadow:0 6px 20px rgba(0,0,0,.28)}'
   +'.bq-qn{font:800 11px "DM Mono",monospace;color:#9fd0ff;letter-spacing:.5px}'
   +'.bq-qt{font:600 15px system-ui;color:#f1f6ff;margin:7px 0 10px;line-height:1.5}'
   +'.bq-opts{display:flex;flex-wrap:wrap;gap:8px}'
   +'.bq-opt{display:flex;gap:8px;align-items:center;text-align:left;border:1.5px solid #6b7079;background:rgba(255,255,255,.07);color:#f0f2f6;border-radius:11px;padding:9px 12px;font:600 13.5px system-ui;cursor:pointer}'
   +'.bq-opt .ql{width:22px;height:22px;flex:none;border-radius:6px;background:#5a5e67;color:#eef1f5;font:800 11px "DM Mono",monospace;display:flex;align-items:center;justify-content:center}'
   +'.bq-opt.ok{border-color:#27a567;background:rgba(39,165,103,.22);color:#7ef0b4}.bq-opt.ok .ql{background:#27a567;color:#06210d}'
   +'.bq-opt.no{border-color:#d2546a;background:rgba(210,84,106,.2);color:#ff9fae}.bq-opt.no .ql{background:#d2546a}'
   +'.bq-fb{font:700 12.5px system-ui;margin-top:10px}.bq-fb.ok{color:#7ef0b4}.bq-fb.no{color:#ff9fae}'
   +'.bq-soltgl{display:block;margin-left:auto;margin-top:11px;border:1px solid #ffcf6b66;background:transparent;color:#ffcf6b;border-radius:9px;padding:6px 12px;font:700 12px system-ui;cursor:pointer}'
   +'.bq-sol{display:none;margin-top:11px;border-top:1px dashed #ffffff2e;padding-top:11px}.bq-sol.on{display:block}'
   +'.bq-stp{border-left:3px solid #34d399;padding:4px 0 4px 11px;margin:8px 0}'
   +'.bq-stp .sn{font:800 10px "DM Mono",monospace;color:#34d399;letter-spacing:.5px}'
   +'.bq-stp .so{font:500 14px system-ui;color:#eaf2ff;margin-top:2px}'
   +'.bq-stp .sa{font:700 13px system-ui;color:#ffd27a;margin-top:2px}'
   +'.bq-dtg{display:block;margin-left:auto;width:fit-content;margin-top:5px;border:1px solid #ffffff33;background:rgba(255,255,255,.05);color:#ffd27a;font:600 11px system-ui;cursor:pointer;padding:4px 9px;border-radius:7px}'
   +'.bq-dd{display:none;font:500 12.5px system-ui;color:#cfe0ff;background:rgba(255,255,255,.06);border-radius:8px;padding:8px 10px;margin-top:5px;line-height:1.45}.bq-dd.on{display:block}'
   +'.bq-ans{margin-top:11px;background:rgba(39,165,103,.18);border:1px solid #27a567;border-radius:10px;padding:9px 12px;font:700 13.5px system-ui;color:#7ef0b4}'
   +'.bq-empty{max-width:520px;margin:50px auto;text-align:center;color:#8aa0c4;font:500 14px system-ui;line-height:1.7}';
  var st=document.createElement('style'); st.textContent=css; document.head.appendChild(st);
  var wrap=document.createElement('div');
  wrap.innerHTML=''
   +'<div id="bqBack"></div>'
   +'<div id="bqPick"><div class="bq-ph" id="bqPickTopic"></div><div class="bq-psub" id="bqPickSub"></div>'
   +'<div class="bq-cols"><div><div class="bq-colh easy">😊 KOLAY</div><div class="bq-col" id="bqEasy"></div></div>'
   +'<div><div class="bq-colh hard">🔥 ZOR</div><div class="bq-col" id="bqHard"></div></div></div>'
   +'<button id="bqPickClose">İptal</button></div>'
   +'<div id="bqOverlay"><div class="bq-oh"><span id="bqTitle"></span><span id="bqTimer"></span><span class="bq-cevap" id="bqCevap"></span><button id="bqClose">✕</button></div><div id="bqScroll"></div></div>';
  document.body.appendChild(wrap);
  var bqMode='mix';
  function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
  function rich(s){return esc(s).replace(/&lt;b&gt;/g,'<b>').replace(/&lt;\\/b&gt;/g,'</b>');}
  function descFor(diff){ if(diff==='kolay') return bqMode==='step'?'Bu konudan tanıma ve temel sorular':'Tüm konulardan tanıma ve temel sorular'; return bqMode==='step'?'Bu konudan yorum ve detay soruları':'Tüm konulardan yorum ve detay soruları'; }
  function mkGo(n,diff,col){ var b=document.createElement('button'); b.className='bq-go'; b.style.border='1.5px solid '+col; b.style.color=col; b.innerHTML='<b>'+n+'</b><small>'+(CNT_LBL[n]||(n+' Soru'))+'</small>'; b.onclick=function(){ closePick(); start(bqMode,diff,n); }; return b; }
  function buildCols(){ var isStep=(bqMode==='step');
    var ec=document.getElementById('bqEasy'); ec.innerHTML=''; var ed=document.createElement('div'); ed.className='bq-desc'; ed.textContent=descFor('kolay'); ec.appendChild(ed);
    var pk=isStep?poolStep('kolay'):pool('kolay'); var ck=isStep?stepCounts(pk===null?-1:pk.length):capCounts(pk.length); ck.forEach(function(n){ ec.appendChild(mkGo(n,'kolay','#34d399')); });
    var hc=document.getElementById('bqHard'); hc.innerHTML=''; var hd=document.createElement('div'); hd.className='bq-desc'; hd.textContent=descFor('zor'); hc.appendChild(hd);
    var pz=isStep?poolStep('zor'):pool('zor'); var cz=isStep?stepCounts(pz===null?-1:pz.length):capCounts(pz.length); cz.forEach(function(n){ hc.appendChild(mkGo(n,'zor','#ff8a5c')); }); }
  function openPickStep(){ bqMode='step'; document.getElementById('bqPickTopic').innerHTML='<b>'+curTopicName()+'</b> · '+lvName(); document.getElementById('bqPickSub').textContent='Bu konu — adım adım çözümlü sorular'; buildCols(); document.getElementById('bqBack').classList.add('on'); document.getElementById('bqPick').classList.add('on'); }
  function openPickMix(){ bqMode='mix'; document.getElementById('bqPickTopic').innerHTML='<b>Test Soruları</b> · '+lvName(); document.getElementById('bqPickSub').textContent='Tüm konular · '+nOpt()+' şıklı çoktan seçmeli'; buildCols(); document.getElementById('bqBack').classList.add('on'); document.getElementById('bqPick').classList.add('on'); }
  function closePick(){ document.getElementById('bqBack').classList.remove('on'); document.getElementById('bqPick').classList.remove('on'); }
  function openOverlay(t){ document.getElementById('bqTitle').innerHTML=t; document.getElementById('bqOverlay').classList.add('on'); }
  function closeOverlay(){ document.getElementById('bqOverlay').classList.remove('on'); if(window.__bqTimer){clearInterval(window.__bqTimer);window.__bqTimer=null;} }
  function stepsHtml(steps){ return steps.map(function(s,i){ var d=s.d||(s.a?('Bu adımda: '+s.a):''); return '<div class="bq-stp"><div class="sn">'+(i+1)+'. ADIM</div><div class="so">'+rich(s.t)+'</div>'+(s.a?'<div class="sa">→ '+rich(s.a)+'</div>':'')+(d?'<button class="bq-dtg" type="button">detaya bak ▸</button><div class="bq-dd">'+rich(d)+'</div>':'')+'</div>'; }).join(''); }
  function start(mode,diff,n){ var dn=diff==='zor'?'Zor':'Kolay';
    if(mode==='step'){ var ps=poolStep(diff); if(ps===null){ openOverlay('📝 '+curTopicName()); document.getElementById('bqScroll').innerHTML='<div class="bq-empty">Bu alt konunun soruları henüz hazırlanıyor.</div>'; document.getElementById('bqTimer').textContent=''; document.getElementById('bqCevap').textContent=''; return; } renderBoard(ps.slice(0,n),dn); return; }
    renderQuiz(pool(diff).slice(0,n),dn); }
  function renderBoard(qs,dn){ openOverlay('📝 '+curTopicName()+' <small>'+lvName()+' · '+dn+' · '+qs.length+' soru · adım adım</small>'); var sc=document.getElementById('bqScroll'); sc.innerHTML=''; document.getElementById('bqTimer').textContent=''; document.getElementById('bqCevap').textContent=qs.length+' soru';
    if(!qs.length){ sc.innerHTML='<div class="bq-empty">Bu seviye/zorlukta soru bulunamadı.</div>'; document.getElementById('bqCevap').textContent=''; return; }
    qs.forEach(function(q,i){ var blk=document.createElement('div'); blk.className='bq-q'; blk.innerHTML='<div class="bq-qn">SORU '+(i+1)+'</div><div class="bq-qt">'+rich(q.q)+'</div><button class="bq-soltgl" type="button">çözümü göster ▸</button><div class="bq-sol">'+stepsHtml(q.steps)+'<div class="bq-ans">✓ Sonuç: '+rich(q.ans)+'</div></div>'; sc.appendChild(blk); });
    bindToggles(sc); sc.scrollTop=0; }
  function renderQuiz(qs,dn){ var no=nOpt(); openOverlay('🎲 Test Soruları <small>'+lvName()+' · '+dn+' · '+qs.length+' soru · '+no+' şıklı</small>'); var sc=document.getElementById('bqScroll'); sc.innerHTML=''; var tEl=document.getElementById('bqTimer'),cEl=document.getElementById('bqCevap');
    if(!qs.length){ sc.innerHTML='<div class="bq-empty">Bu seviye/zorlukta soru bulunamadı.</div>'; tEl.textContent=''; cEl.textContent=''; return; }
    var answered=0,correct=0,LET=['A','B','C','D','E']; cEl.textContent='0 cevap'; var t0=Date.now();
    if(window.__bqTimer){clearInterval(window.__bqTimer);window.__bqTimer=null;} tEl.textContent='';
    if(isTimed()){ window.__bqTimer=setInterval(function(){ var s=Math.floor((Date.now()-t0)/1000); tEl.textContent='⏱ '+(Math.floor(s/60)?Math.floor(s/60)+'d ':'')+(s%60)+'s'; },1000); }
    qs.forEach(function(q,i){ var blk=document.createElement('div'); blk.className='bq-q'; var head='<div class="bq-qn">SORU '+(i+1)+' / '+qs.length+'</div><div class="bq-qt">'+rich(q.q)+'</div>';
      var dist=(q.o||[]).slice(0,no-1); var pos=i%no; var opts=dist.slice(); opts.splice(pos,0,q.ans);
      var ow=document.createElement('div'); ow.className='bq-opts'; blk.innerHTML=head; blk.appendChild(ow);
      var fb=document.createElement('div'); fb.className='bq-fb';
      var solBtn=document.createElement('button'); solBtn.type='button'; solBtn.className='bq-soltgl'; solBtn.textContent='çözümü göster ▸';
      var sol=document.createElement('div'); sol.className='bq-sol'; sol.innerHTML=stepsHtml(q.steps)+'<div class="bq-ans">✓ Cevap: '+LET[pos]+') '+rich(q.ans)+'</div>';
      opts.forEach(function(opt,oi){ var b=document.createElement('button'); b.type='button'; b.className='bq-opt'; b.innerHTML='<span class="ql">'+LET[oi]+'</span><span>'+rich(opt)+'</span>';
        b.onclick=function(){ if(blk.dataset.done)return; blk.dataset.done='1'; answered++; var ok=(oi===pos); if(ok)correct++; b.classList.add(ok?'ok':'no'); if(!ok){ var bs=ow.children[pos]; if(bs)bs.classList.add('ok'); }
          fb.className='bq-fb '+(ok?'ok':'no'); fb.textContent=ok?'Doğru ✓':('Yanlış ✗ · Doğru: '+LET[pos]+') '+q.ans); cEl.textContent=answered+' cevap';
          if(answered>=qs.length){ var fin=Math.round(correct/qs.length*100); if(window.__bqTimer){clearInterval(window.__bqTimer);window.__bqTimer=null;} setTimeout(function(){ cEl.textContent='Bitti · %'+fin+(fin>=80?' 🏆':fin>=60?' 👍':' 📚'); },250); } };
        ow.appendChild(b); });
      blk.appendChild(fb); blk.appendChild(solBtn); blk.appendChild(sol); sc.appendChild(blk); });
    bindToggles(sc); sc.scrollTop=0; }
  function bindToggles(sc){ sc.querySelectorAll('.bq-soltgl').forEach(function(btn){ btn.onclick=function(){ var sol=btn.parentElement.querySelector('.bq-sol'); if(!sol)return; var on=sol.classList.toggle('on'); btn.textContent=on?'çözümü gizle ▾':'çözümü göster ▸'; }; });
    sc.querySelectorAll('.bq-dtg').forEach(function(btn){ btn.onclick=function(){ var dd=btn.nextElementSibling; if(!dd)return; var on=dd.classList.toggle('on'); btn.textContent=on?'gizle ▾':'detaya bak ▸'; }; }); }
  var _ob=document.getElementById('bqOpen'); if(_ob) _ob.addEventListener('click',openPickStep);
  document.getElementById('bqPickClose').addEventListener('click',closePick);
  document.getElementById('bqBack').addEventListener('click',closePick);
  document.getElementById('bqClose').addEventListener('click',closeOverlay);
  window.bqOpenStep=openPickStep; window.bqOpenMix=openPickMix;
`;

// Test adet butonları (seviye sırası: ilkokul, ortaokul, lise, sınav, üniversite)
const OLD_BASE=[[5,10,15,20],[10,15,20,25],[10,20,30,40],[10,20,30,40],[10,20,30,40]]; // eski sistemler (havuz 50/70/100)
const NEW_BASE=[[5,10,15],[10,15,20],[10,20,30],[10,20,30],[10,20,30]];                 // yeni sistemler (havuz 30/45/60)

const LESSONS=[
  {html:'sindirim-sistemi.html', name:'Sindirim Sistemi', test:'sindirim_test.js', info:['sindirim_info_a.js','sindirim_info_b.js','sindirim_info_c.js'], base:OLD_BASE},
  {html:'dolasim-sistemi.html', name:'Dolaşım Sistemi', test:'dolasim_test.js', info:['dolasim_info_a.js','dolasim_info_b.js','dolasim_info_c.js'], base:OLD_BASE},
  {html:'bosaltim-sistemi.html', name:'Boşaltım Sistemi', test:'bosaltim_test.js', info:['bosaltim_info_a.js','bosaltim_info_b.js','bosaltim_info_c.js'], base:OLD_BASE},
  {html:'ureme-sistemi.html', name:'Üreme Sistemi', test:'ureme_test.js', info:['ureme_info_a.js','ureme_info_b.js','ureme_info_c.js'], base:OLD_BASE},
  {html:'hucre-organeller.html', name:'Hücre ve Organeller', test:'hucre_test.js', info:['hucre_info_a.js','hucre_info_b.js','hucre_info_c.js'], base:NEW_BASE},
  {html:'dna-replikasyon.html', name:'DNA ve Replikasyon', test:'dna_test.js', info:['dna_info_a.js','dna_info_b.js','dna_info_c.js'], base:NEW_BASE},
  {html:'mitoz-mayoz.html', name:'Mitoz ve Mayoz', test:'mm_test.js', info:['mm_info_a.js','mm_info_b.js','mm_info_c.js'], base:NEW_BASE},
  {html:'bitki-anatomisi.html', name:'Bitki Anatomisi', test:'bitki_test.js', info:['bitki_info_a.js','bitki_info_b.js','bitki_info_c.js','bitki_info_d.js'], base:NEW_BASE},
];

LESSONS.forEach(L=>{
  const testBank=loadBank(L.test);
  const infoBank=mergeInfo(L.info);
  const header='\n<script>\n/* Test Soruları + Bilgi Paneli Sistemi (bq) — '+L.name+' */\n(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    +'  var LESSON='+JSON.stringify(L.name)+';\n'
    +'  var BQ_BASE='+JSON.stringify(L.base||OLD_BASE)+';\n'
    +'  var Q={};\n'
    +'  var EXTRA={_all:'+JSON.stringify(testBank)+'};\n'
    +'  var TQ='+JSON.stringify(infoBank)+';\n';
  const engineScript=header+ENGINE_BODY+'\n})();\n</'+'script>\n';

  // JS doğrulama — enjekte edilecek script gövdesini (yorumsuz) parse et
  const innerCode = '(function(){ if(window.__bqInit) return; window.__bqInit=true;\n'
    +'  var LESSON='+JSON.stringify(L.name)+';\n  var BQ_BASE='+JSON.stringify(L.base||OLD_BASE)+';\n  var Q={};\n  var EXTRA={_all:'+JSON.stringify(testBank)+'};\n  var TQ='+JSON.stringify(infoBank)+';\n'
    + ENGINE_BODY + '\n})();';
  try{ new vm.Script(innerCode); }
  catch(e){ console.log('✗ '+L.html+' JS HATA: '+e.message.split('\n')[0]); return; }

  let h=fs.readFileSync(AS+'/'+L.html,'utf8');
  const log=[];
  // 1) ✎ butonu
  const navOld='<button class="nav-mini-btn" id="navPrev" title="Önceki konu">◀</button>';
  if(h.includes(navOld) && !h.includes('id="bqOpen"')){ h=h.replace(navOld,'<button class="nav-mini-btn" id="bqOpen" title="Sorular">✎</button>\n          '+navOld); log.push('bqOpen'); }
  // 2) seviye/konu window'a aç
  if(h.includes('curLevel=idx;') && !h.includes('window.__bqLevel=idx')){ h=h.replace('curLevel=idx;','curLevel=idx;\n  window.__bqLevel=idx;'); log.push('levelExpose'); }
  if(h.includes('curKey=key;') && !h.includes('window.__bqTopic=key')){ h=h.replace('curKey=key;','curKey=key;\n  window.__bqTopic=key;'); log.push('topicExpose'); }
  // 3) cpArcExam adı + onclick + delegate
  h=h.replace('>Test Soruları Oluştur</span>','>Test Soruları</span>');
  h=h.replace(/document\.getElementById\('cpArcExam'\)\.onclick=function\(\)\{closeAll\(\);var b=document\.getElementById\('btnExam'\);if\(b\)b\.click\(\);\};/,"document.getElementById('cpArcExam').onclick=function(){closeAll();if(window.bqOpenMix)window.bqOpenMix();};");
  h=h.replace(/delegate\('cpArcExam','btnExam'\);[^\n]*/, "(function(){ var s=$('cpArcExam'); if(s) s.onclick=function(){ var ap=$('araclarComboP'); if(ap) ap.classList.remove('show'); var pbb=$('_popBlur'); if(pbb) pbb.style.display='none'; if(window.bqOpenMix) window.bqOpenMix(); }; })();");
  if(h.includes('if(window.bqOpenMix)')) log.push('cpArcExam→mix');
  // 4) motoru enjekte et (varsa eski bloğu yenisiyle DEĞİŞTİR — veri tazelensin)
  const reEngine=/\n<script>\n\/\* Test Soruları \+ Bilgi Paneli Sistemi \(bq\)[\s\S]*?<\/script>\n(?=<\/body>)/;
  if(reEngine.test(h)){ h=h.replace(reEngine, engineScript); log.push('engine↻'); }
  else { h=h.replace('</body>\n</html>', engineScript+'</body>\n</html>'); log.push('engine+'); }

  fs.writeFileSync(AS+'/'+L.html,h,'utf8');
  let infoCnt=0; for(const k in infoBank){ for(const lv in infoBank[k]){ for(const d in infoBank[k][lv]) infoCnt+=infoBank[k][lv][d].length; } }
  let testCnt=0; for(const lv in testBank){ for(const d in testBank[lv]) testCnt+=testBank[lv][d].length; }
  console.log('✓ '+L.html+' | test:'+testCnt+' bilgi:'+infoCnt+' altKonu:'+Object.keys(infoBank).length+' | ['+log.join(', ')+']');
});
