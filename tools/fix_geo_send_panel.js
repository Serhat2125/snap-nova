const fs = require('fs');
const p = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/geometrik-cisimler.html';
let h = fs.readFileSync(p, 'utf8');
const log = [];

// 1) Gönder ikonu → WhatsApp gönderme butonu (kâğıt uçak SVG)
const svg = '<svg viewBox="0 0 24 24" width="19" height="19" fill="#6366f1" style="vertical-align:middle"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>';
const oldSend = "arcItem('✈️','Gönder','#6366f1',()=>{ if(send) send.click(); });";
const newSend = "arcItem(`" + svg + "`,'Gönder','#6366f1',()=>{ if(send) send.click(); });";
if (h.includes(oldSend)) { h = h.replace(oldSend, newSend); log.push('Gönder SVG'); }
else log.push('Gönder eşleşmedi');

// 2) Eğitim Seviyesi + Konu Rehberi panelleri sağ alt köşe (posAboveDock)
const oldPos = "el.style.left='10px'; el.style.right='auto';";
const newPos = "el.style.left='auto'; el.style.right='10px';";
if (h.includes(oldPos)) { h = h.replace(oldPos, newPos); log.push('panel sağ alt'); }
else log.push('posAboveDock eşleşmedi');

fs.writeFileSync(p, h, 'utf8');

// syntax check (module)
const vm = require('vm');
const mi = h.indexOf('<script type="module">');
const me = h.indexOf('</script>', mi);
let ok = 'OK';
try { new vm.Script(h.slice(mi + 22, me)); } catch (x) { ok = 'ERR:' + x.message.split('\n')[0]; }
console.log(log.join(', ') + ' | syntax:' + ok);
console.log('SVG var:' + h.includes('M2.01 21L23 12') + ' rightPanel:' + h.includes("el.style.right='10px'"));
