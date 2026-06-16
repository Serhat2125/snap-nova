const fs=require('fs'),vm=require('vm');
const BQ=__dirname, AS='C:/Users/TUNA MUHENDISLIK/snap_nova/assets';
function load(f){const c={};c.globalThis=c;vm.createContext(c);vm.runInContext(fs.readFileSync(BQ+'/'+f,'utf8'),c);return c.__OUT;}
const tab=load('_den_test_ab.js'), tc=load('_den_test_c.js');
const ia=load('_den_info_a.js'), ib=load('_den_info_b.js');

// TEST → EXTRA._all (seviye bazlı)
const EXTRA_all={ ilkokul:tab.ilkokul, ortaokul:tab.ortaokul, lise:tc.lise };
// BİLGİ → Q (konu bazlı)
const Q=Object.assign({}, ia, ib);

// sayaç
function cTest(){let n=0;for(const lv in EXTRA_all)for(const d in EXTRA_all[lv])n+=EXTRA_all[lv][d].length;return n;}
function cInfo(){let n=0;for(const k in Q)for(const lv in Q[k])for(const d in Q[k][lv])n+=Q[k][lv][d].length;return n;}
console.log('TEST toplam='+cTest()+' | ilkokul '+EXTRA_all.ilkokul.kolay.length+'/'+EXTRA_all.ilkokul.zor.length+' ortaokul '+EXTRA_all.ortaokul.kolay.length+'/'+EXTRA_all.ortaokul.zor.length+' lise '+EXTRA_all.lise.kolay.length+'/'+EXTRA_all.lise.zor.length);
console.log('BİLGİ toplam='+cInfo()+' | konular: '+Object.keys(Q).join(', '));

// HTML'e göm
let h=fs.readFileSync(AS+'/denetleyici-duzenleyici-sistem.html','utf8');
const Q_START='  var Q={', Q_END='  /* ═══════════ DİĞER ALT KONULAR';
const E_START='  var EXTRA={', E_END='  function shuffle(a)';
let s=h.indexOf(Q_START), e=h.indexOf(Q_END);
if(s<0||e<0||e<s){console.error('Q anchor bulunamadı',s,e);process.exit(1);}
h=h.slice(0,s)+'  var Q='+JSON.stringify(Q)+';\n'+h.slice(e);
s=h.indexOf(E_START); e=h.indexOf(E_END);
if(s<0||e<0||e<s){console.error('EXTRA anchor bulunamadı',s,e);process.exit(1);}
h=h.slice(0,s)+'  var EXTRA={_all:'+JSON.stringify(EXTRA_all)+'};\n'+h.slice(e);
fs.writeFileSync(AS+'/denetleyici-duzenleyici-sistem.html',h,'utf8');

// DOĞRULAMA: gömülü Q & EXTRA tekrar parse + script JS geçerliliği
let h2=fs.readFileSync(AS+'/denetleyici-duzenleyici-sistem.html','utf8');
const qstr=h2.slice(h2.indexOf('  var Q='), h2.indexOf(';\n  /* ═══════════ DİĞER ALT KONULAR')+1);
const estr=h2.slice(h2.indexOf('  var EXTRA={_all:'), h2.indexOf('};\n  function shuffle(a)')+2);
try{ new vm.Script('('+qstr.replace(/^\s*var Q=/,'').replace(/;$/,'')+')'); new vm.Script('('+estr.replace(/^\s*var EXTRA=/,'').replace(/;$/,'')+')'); console.log('✓ Gömülü Q & EXTRA geçerli JS'); }
catch(err){ console.error('✗ JS parse hatası:',err.message); process.exit(1); }
console.log('✓ denetleyici-duzenleyici-sistem.html güncellendi');
