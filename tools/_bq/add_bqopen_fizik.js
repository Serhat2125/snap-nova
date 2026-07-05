// 7 fizik dersinin bilgi paneli nav satırına ✎ (bqOpen) butonunu ekler.
// Motor (integrate_fizik.js ENGINE_BODY) zaten bqOpen'ı dinliyor
// (addEventListener('click',openPickStep)) ama buton markup'ı yoktu →
// if(_ob) guard'ı sessizce atlıyordu. Organ bio ile birebir aynı yapı:
// navPrev'in SOLUNA ✎ butonu. İdempotent (bqOpen varsa atlar). Tek geçiş.
const fs = require('fs'), path = require('path');
const AS = path.join(__dirname, '..', '..', 'assets');
const FILES = [
  'golge-olusumu-isik-yayilmasi', 'bileske-kuvvet-vektorler', 'basit-makineler',
  'dalgalar', 'optik-mercekler', 'elektrik', 'akiskanlar-mekanigi'
];
// Fizikte navPrev başlığı "Önceki" (organ bio'da "Önceki konu"); exact match.
const NAV = '<button class="nav-mini-btn" id="navPrev" title="Önceki">◀</button>';
const BTN = '<button class="nav-mini-btn" id="bqOpen" title="Sorular">✎</button>\n          ';

let ok = 0, skip = 0, fail = 0;
for (const name of FILES) {
  const fp = path.join(AS, name + '.html');
  let s = fs.readFileSync(fp, 'utf8');
  if (s.includes('id="bqOpen"')) { console.log('ATLA (zaten var):', name); skip++; continue; }
  const i = s.indexOf(NAV);
  if (i === -1 || s.indexOf(NAV, i + NAV.length) !== -1) {
    console.log('HATA (navPrev yok/çoğul):', name); fail++; continue;
  }
  s = s.slice(0, i) + BTN + s.slice(i);
  fs.writeFileSync(fp, s, 'utf8');
  console.log('OK:', name); ok++;
}
console.log(`Bitti: ${ok} eklendi, ${skip} atlandı, ${fail} hata`);
process.exit(fail ? 1 : 0);
