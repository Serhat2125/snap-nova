const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const FILES = [
  'bosaltim-sistemi.html','dna-replikasyon.html','dolasim-sistemi.html',
  'hucre-organeller.html','mitoz-mayoz.html','sindirim-sistemi.html',
  'ureme-sistemi.html','ekosistem-besin-zinciri.html','fotosentez.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

const CSS_BLOCK = `
  .dock-tab-btn{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px;background:var(--panel);border:2px solid var(--panel-line);border-radius:10px;cursor:pointer;min-width:46px;height:38px;padding:2px 7px;font-family:'Fredoka',sans-serif;color:var(--ink);box-shadow:0 3px 8px rgba(0,0,0,.25);transition:all .15s;flex:0 0 auto;}
  .dock-tab-btn .dtb-ico{font-size:15px;line-height:1;}
  .dock-tab-btn .dtb-lbl{font-size:9px;font-weight:700;line-height:1;opacity:.85;}
  .dock-tab-btn:hover{border-color:var(--accent);}
  .dock-tab-btn:active{transform:scale(.95);}
  .dock-tab-btn.araclar-btn{border-color:var(--accent,#3b82f6);}
  .combo-pop{position:absolute;z-index:62;background:var(--panel);border:2px solid var(--accent,#3b82f6);border-radius:14px;padding:8px;box-shadow:0 12px 32px rgba(0,0,0,.55);display:none;flex-direction:column;gap:5px;width:min(230px,82vw);}
  .combo-pop.show{display:flex;}
  .combo-pop-title{font-family:'Baloo 2',cursive;font-weight:800;font-size:11px;color:var(--accent,#3b82f6);text-transform:uppercase;letter-spacing:.4px;padding:2px 4px 7px;border-bottom:1px solid var(--panel-line);margin-bottom:2px;}
  .combo-pop-item{display:flex;align-items:center;gap:10px;background:var(--panel-soft,var(--panel));border:1.5px solid var(--panel-line);border-radius:10px;padding:9px 12px;cursor:pointer;font-family:'Fredoka',sans-serif;font-weight:600;font-size:13px;color:var(--ink);transition:all .12s;}
  .combo-pop-item:hover{border-color:var(--accent);background:var(--panel-line);}
  .combo-pop-item:active{transform:scale(.97);}
  .combo-pop-item .cpi-ico{font-size:18px;flex-shrink:0;}
  .combo-pop-item.tts-active{background:rgba(95,200,224,.15);border-color:var(--accent,#3b82f6);}
  @keyframes ttsPulse{0%,100%{box-shadow:0 2px 10px rgba(239,68,68,0.6);transform:scale(1);}50%{box-shadow:0 4px 18px rgba(239,68,68,0.9);transform:scale(1.06);}}
  #bottomPanel.info-mini{left:2px!important;right:auto!important;bottom:50px!important;padding:0!important;border:none!important;background:transparent!important;box-shadow:none!important;min-height:0!important;overflow:visible!important;}
  #bottomPanel.info-mini>*:not(.info-mini-chip){display:none!important;}
  .info-mini-chip{display:none;flex-direction:column;align-items:center;justify-content:center;gap:1px;background:var(--panel);border:2px solid #5fc8e0;border-radius:10px;cursor:pointer;min-width:46px;height:38px;padding:2px 7px;font-family:'Fredoka',sans-serif;color:#5fc8e0;box-shadow:0 3px 8px rgba(0,0,0,.35);transition:all .15s;pointer-events:all;}
  .info-mini-chip .dtb-ico{font-size:15px;line-height:1;}
  .info-mini-chip .dtb-lbl{font-size:9px;font-weight:700;line-height:1;opacity:.85;}
  .info-mini-chip:hover{background:var(--panel-soft,var(--panel));}
  .info-mini-chip:active{transform:scale(.95);}
  #bottomPanel.info-mini .info-mini-chip{display:flex;}
`;

const MINI_CHIP = '\n  <div class="info-mini-chip" id="infoMiniChip"><span class="dtb-ico">📋</span><span class="dtb-lbl" id="infoMiniLbl">bilgi</span></div>';

const COMBO_IIFE = `\n<script>\n/* == ARAÇLAR COMBO IIFE == */\n(function(){\n  var _pb=document.getElementById('_popBlur');\n  if(!_pb){ _pb=document.createElement('div'); _pb.id='_popBlur'; _pb.style.cssText='display:none;position:fixed;top:0;left:0;right:0;bottom:56px;background:rgba(0,0,0,0.55);z-index:58;'; document.body.appendChild(_pb); }\n  function _showBlur(){ if(_pb) _pb.style.display='block'; }\n  function _hideBlur(){ if(_pb) _pb.style.display='none'; }\n  var arcPop=document.createElement('div'); arcPop.id='araclarComboP'; arcPop.className='combo-pop'; arcPop.style.borderColor='var(--accent,#3b82f6)';\n  arcPop.innerHTML='<div class="combo-pop-title" style="color:var(--accent,#3b82f6)">\\u{1F9F0} Ara\\u00e7lar</div>'+\n    '<button class="combo-pop-item" id="cpArcKarsi" style="border-color:#f59e0b;"><span class="cpi-ico" style="background:rgba(245,158,11,.18);border-radius:8px;padding:3px 5px">\\u2696\\uFE0F</span><span style="color:#f59e0b">K\\u0131yaslama Tablosu</span></button>'+\n    '<button class="combo-pop-item" id="cpArcBilgi" style="border-color:#3b82f6;"><span class="cpi-ico" style="background:rgba(59,130,246,.18);border-radius:8px;padding:3px 5px">\\u{1F4CB}</span><span style="color:#3b82f6">Bilgi Tablosu</span></button>'+\n    '<button class="combo-pop-item" id="cpArcExam" style="border-color:#8b5cf6;"><span class="cpi-ico" style="background:rgba(139,92,246,.18);border-radius:8px;padding:3px 5px">\\u{1F4DD}</span><span style="color:#8b5cf6">Test Sorular\\u0131 Olu\\u015ftur</span></button>'+\n    '<button class="combo-pop-item" id="cpArcAi" style="border-color:#06b6d4;"><span class="cpi-ico" style="background:rgba(6,182,212,.18);border-radius:8px;padding:3px 5px">\\u{1F916}</span><span style="color:#06b6d4">AI Destek</span></button>'+\n    '<button class="combo-pop-item" id="cpArcTts" style="border-color:#22c55e;"><span class="cpi-ico" style="background:rgba(34,197,94,.18);border-radius:8px;padding:3px 5px">\\u{1F50A}</span><span style="color:#22c55e">Sesli Mod</span></button>'+\n    '<button class="combo-pop-item" id="cpArcPalette" style="border-color:#ec4899;"><span class="cpi-ico" style="background:rgba(236,72,153,.18);border-radius:8px;padding:3px 5px">\\u{1F3A8}</span><span style="color:#ec4899">Renk Paleti</span></button>'+\n    '<button class="combo-pop-item" id="cpArcGonder" style="border-color:#6366f1;"><span class="cpi-ico wa-send" style="background:rgba(99,102,241,.18);border-radius:8px;padding:3px 5px"><svg viewBox="0 0 24 24"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg></span><span style="color:#6366f1">G\\u00f6nder</span></button>';\n  document.body.appendChild(arcPop);\n  function posAbove(pop,anchor){ var r=anchor.getBoundingClientRect(),w=pop.offsetWidth||240; var l=Math.max(6,Math.min(Math.round(r.left+r.width/2-w/2),window.innerWidth-w-6)); pop.style.left=l+'px'; pop.style.right='auto'; pop.style.bottom=(window.innerHeight-r.top+8)+'px'; pop.style.top='auto'; }\n  function closeAll(){ arcPop.classList.remove('show'); _hideBlur(); }\n  document.addEventListener('click',function(e){ if(!e.target.closest('#araclarComboP')&&!e.target.closest('#btnAraclarCombo')) closeAll(); });\n  var tr=document.getElementById('toolsRow');\n  var bArc=document.createElement('button'); bArc.className='dock-tab-btn araclar-btn'; bArc.id='btnAraclarCombo'; bArc.title='Ara\\u00e7lar';\n  bArc.innerHTML='<span class="dtb-ico">\\u{1F9F0}</span><span class="dtb-lbl">Ara\\u00e7lar</span>';\n  if(tr) tr.insertBefore(bArc,tr.firstChild);\n  bArc.onclick=function(e){ e.stopPropagation(); var s=!arcPop.classList.contains('show'); closeAll(); if(s){arcPop.classList.add('show');_showBlur();setTimeout(function(){posAbove(arcPop,bArc);},0);} if(window._haptic)window._haptic(10); };\n  document.getElementById('cpArcKarsi').onclick=function(){closeAll();var b=document.getElementById('btnCompare');if(b)b.click();};\n  document.getElementById('cpArcBilgi').onclick=function(){closeAll();var b=document.getElementById('btnTable');if(b)b.click();};\n  document.getElementById('cpArcExam').onclick=function(){closeAll();var b=document.getElementById('btnExam');if(b)b.click();};\n  document.getElementById('cpArcAi').onclick=function(){closeAll();var b=document.getElementById('btnAsk');if(b)b.click();};\n  document.getElementById('cpArcTts').onclick=function(){closeAll();var b=document.getElementById('btnTts');if(b)b.click();};\n  document.getElementById('cpArcPalette').onclick=function(e){\n    e.stopPropagation(); e.preventDefault(); closeAll();\n    var pop=document.getElementById('palettePop'); if(!pop) return;\n    pop.style.cssText='display:block!important;position:fixed!important;z-index:80!important;';\n    setTimeout(function(){ var w=Math.min(pop.offsetWidth,window.innerWidth-12),h=pop.offsetHeight; pop.style.left=Math.max(6,Math.round((window.innerWidth-w)/2))+'px'; pop.style.top=Math.max(6,Math.round((window.innerHeight-h)/2))+'px'; pop.style.right='auto'; pop.style.bottom='auto'; },0);\n    _showBlur();\n  };\n  document.getElementById('cpArcGonder').onclick=function(){\n    closeAll(); var _pb4=document.getElementById('_popBlur'); if(_pb4) _pb4.style.display='none';\n    setTimeout(function(){ if(window.FlutterNativeShot) window.FlutterNativeShot.postMessage('1'); else { var b=document.getElementById('btnSend'); if(b) b.click(); } },350);\n  };\n  setTimeout(function(){ if(tr){ tr.style.justifyContent='space-between'; tr.style.padding='0 18px'; } },80);\n  var origTts=document.getElementById('btnTts');\n  var _ttsChip=(function(){\n    var ch=document.createElement('button'); ch.id='ttsActiveChip';\n    ch.innerHTML='<span style="font-size:15px">\\u{1F50A}</span><span style="font-size:10px;font-weight:800;letter-spacing:.3px">KES</span>';\n    ch.style.cssText='display:none;position:fixed;bottom:54px;right:8px;z-index:72;background:#ef4444;color:#fff;border:none;border-radius:20px;padding:6px 11px;gap:4px;align-items:center;cursor:pointer;box-shadow:0 2px 10px rgba(239,68,68,0.6);font-family:Fredoka,sans-serif;animation:ttsPulse 1.2s ease-in-out infinite;';\n    ch.onclick=function(){ var b=document.getElementById('btnTts'); if(b)b.click(); };\n    document.body.appendChild(ch); return ch;\n  })();\n  if(origTts){ new MutationObserver(function(){ var a=origTts.classList.contains('active'); var i=document.getElementById('cpArcTts'); if(i)i.classList.toggle('tts-active',a); if(_ttsChip)_ttsChip.style.display=a?'flex':'none'; }).observe(origTts,{attributes:true,attributeFilter:['class']}); }\n  var _icb=document.getElementById('infoCloseBtn');\n  if(_icb) _icb.onclick=function(){\n    var bp=document.getElementById('bottomPanel'); if(!bp) return;\n    bp.classList.add('info-mini');\n    var lbl=document.getElementById('infoMiniLbl');\n    if(lbl){ var t=document.getElementById('infoTitle'); if(t&&t.textContent) lbl.textContent=t.textContent+' konusunu a\\u00e7'; }\n  };\n  var _mc=document.getElementById('infoMiniChip');\n  if(_mc) _mc.onclick=function(){ var bp=document.getElementById('bottomPanel'); if(bp) bp.classList.remove('info-mini'); };\n  (function(){\n    var dock=document.getElementById('bottomDock');\n    if(dock) dock.addEventListener('click',function(e){\n      if(!window.bodyMapMode) return;\n      var btn=e.target.closest('button'); if(!btn||btn.id==='btnKonum') return;\n      if(typeof window.toggleBodyMap==='function') window.toggleBodyMap();\n      var bp=document.getElementById('bottomPanel'); if(bp){ bp.classList.remove('vars-hidden'); bp.classList.remove('info-mini'); }\n    });\n  })();\n  (function(){\n    function _cv(){ if(window._setSceneOpen){var vb=document.getElementById('sceneVarsBody');if(vb&&!vb.classList.contains('closed'))window._setSceneOpen(false);} }\n    ['btnAraclarCombo','btnMenu'].forEach(function(id){ var b=document.getElementById(id); if(b) b.addEventListener('click',_cv); });\n    var sr=document.getElementById('stackRow');\n    if(sr) sr.addEventListener('click',function(e){ if(!e.target.closest('#sceneToggle')) _cv(); });\n  })();\n  var _bm2=document.getElementById('btnMode');\n  if(_bm2) _bm2.onclick=function(){ if(window._toggleMode) window._toggleMode(); else { var pm=document.getElementById('panelMode'); if(pm) pm.classList.toggle('show'); } };\n})();\n</script>`;

let passed=0, skipped=0, failed=0;

for (const fname of FILES) {
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    if (html.includes('araclarComboP')) {
      console.log('SKIP: ' + fname);
      skipped++;
      continue;
    }
    // 1. CSS
    if (html.includes('id="dunyaPatchCss"')) {
      html = html.replace(/(<style[^>]*id="dunyaPatchCss"[^>]*>)([\s\S]*?)(<\/style>)/, (m,a,b,c) => a+b+CSS_BLOCK+c);
    } else {
      html = html.replace('</body>', '<style>\n'+CSS_BLOCK+'\n</style>\n</body>');
    }
    // 2. mini-chip after infoCloseBtn
    if (!html.includes('infoMiniChip')) {
      const idx = html.indexOf('id="infoCloseBtn"');
      if (idx >= 0) {
        const end = html.indexOf('</button>', idx);
        if (end >= 0) html = html.slice(0,end+9)+MINI_CHIP+html.slice(end+9);
      }
    }
    // 3. Combo IIFE
    html = html.replace('</body>', COMBO_IIFE+'\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: ' + fname);
    passed++;
  } catch(e) {
    console.log('ERROR: '+fname+' - '+e.message);
    failed++;
  }
}
console.log('\n'+passed+' done, '+skipped+' skipped, '+failed+' failed');
