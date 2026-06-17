// Makine bankalarındaki eksik kovaları elle yazılmış kaliteli sorularla tamamlar.
const vm=require("vm"), fs=require("fs"), path=require("path");
const BQ=path.resolve(__dirname,"..");
function load(f){const c={};c.globalThis=c;vm.createContext(c);vm.runInContext(fs.readFileSync(path.join(BQ,f),"utf8"),c);return c.__BQ;}

const test=load("makine_test.js");
const info=load("makine_info.js");

// ── TEST ortaokul zor: 42 → 45 (3 ekle) ──
test.ortaokul.zor.push(
 {q:"Bir kaldıraçta destek noktasından 60 cm uzaktaki 300 N'luk yük, destekten 90 cm uzaktan uygulanan bir kuvvetle dengeleniyor. Uygulanan kuvvet kaç N'dur?",
  fig:"<svg viewBox='0 0 320 150'><line x1='30' y1='110' x2='300' y2='110' stroke='#1a2b45' stroke-width='4'/><polygon points='165,110 150,138 180,138' fill='#5b6b85'/><rect x='70' y='86' width='26' height='24' fill='#4aa3df' stroke='#1a2b45'/><text x='83' y='80' font-size='11' text-anchor='middle' fill='#1a2b45'>300 N</text><line x1='250' y1='110' x2='250' y2='60' stroke='#e0552b' stroke-width='2'/><polygon points='250,58 245,70 255,70' fill='#e0552b'/><text x='250' y='52' font-size='11' text-anchor='middle' fill='#1a2b45'>F=?</text><text x='120' y='128' font-size='10' text-anchor='middle' fill='#1a2b45'>60 cm</text><text x='210' y='128' font-size='10' text-anchor='middle' fill='#1a2b45'>90 cm</text></svg>",
  steps:[{t:"Moment dengesi",a:"Yük×yük kolu = Kuvvet×kuvvet kolu",d:"300·60 = F·90 olur."},{t:"Kuvveti bul",a:"200 N",d:"18000 = 90·F → F = 18000/90 = 200 N."}],
  ans:"200 N", o:["300 N","450 N","150 N","250 N"]},
 {q:"Hareketli makarayla bir yük sabit hızla kaldırılıyor ve uygulanan kuvvet 200 N ölçülüyor. Sürtünmeler önemsizken yükün ağırlığı kaç N'dur?",
  steps:[{t:"Hareketli makara",a:"Kuvvetten yarı kazanç",d:"Hareketli makarada F = Yük/2 olduğundan Yük = 2·F."},{t:"Hesap",a:"400 N",d:"Yük = 2·200 = 400 N."}],
  ans:"400 N", o:["200 N","100 N","800 N","600 N"]},
 {q:"Yüksekliği 2 m, eğik yüzey uzunluğu 6 m olan sürtünmesiz eğik düzlemde 120 N'luk yük tepeye çıkarılıyor. Gereken en küçük kuvvet kaç N'dur?",
  fig:"<svg viewBox='0 0 300 150'><polygon points='30,130 270,130 30,40' fill='#eef2f8' stroke='#1a2b45' stroke-width='2'/><rect x='150' y='70' width='22' height='16' fill='#4aa3df' stroke='#1a2b45' transform='rotate(-20 161 78)'/><text x='150' y='145' font-size='10' text-anchor='middle' fill='#1a2b45'>L = 6 m</text><line x1='30' y1='40' x2='30' y2='130' stroke='#e0552b' stroke-width='1.5' stroke-dasharray='4 3'/><text x='14' y='88' font-size='10' fill='#1a2b45'>h=2 m</text></svg>",
  steps:[{t:"Eğik düzlem",a:"F = Yük·h/L",d:"İdeal (sürtünmesiz) eğik düzlemde F = Yük·yükseklik/uzunluk."},{t:"Hesap",a:"40 N",d:"F = 120·2/6 = 240/6 = 40 N."}],
  ans:"40 N", o:["60 N","120 N","20 N","80 N"]}
);

// ── INFO eksik lise kovaları (şıksız) ──
info.disliCark.lise.zor.push(
 {q:"40 dişli bir çark, kendisine geçmiş 10 dişli bir çarkı döndürüyor. Büyük çark dakikada 30 devir yaparsa küçük çark dakikada kaç devir yapar?",
  steps:[{t:"Dişli kuralı",a:"Diş sayısı × devir korunur",d:"Birbirine geçen dişlilerde N₁·n₁ = N₂·n₂; diş sayısı ile devir ters orantılıdır."},{t:"Hesap",a:"120 devir",d:"40·30 = 10·n₂ → n₂ = 1200/10 = 120 devir/dakika. Küçük çark daha hızlı döner."}],
  ans:"120 devir/dakika"}
);
info.kaldiracTur.lise.zor.push(
 {q:"İnsan ön kolu (dirsek–pazu kası–eldeki yük) hangi tür kaldıraçtır ve bu yapı neden kuvvetten kayıp pahasına hız/yol kazandırır?",
  steps:[{t:"Bileşenleri yerleştir",a:"Kuvvet ortada → 3. tür",d:"Destek dirsekte, yük elde, kas kuvveti ikisinin arasında uygulanır; bu 3. tür kaldıraçtır."},{t:"Sonucu yorumla",a:"Kuvvet kolu kısa",d:"Kuvvet kolu yük kolundan kısa olduğundan kas büyük kuvvet uygular; karşılığında el küçük kas kısalmasıyla büyük yol ve hız kazanır."}],
  ans:"3. tür kaldıraç; kuvvet kolu kısa olduğundan kuvvetten kayıp, yoldan ve hızdan kazanç sağlar"}
);
info.palanga.lise.kolay.push(
 {q:"Yükü taşıyan ip kolu sayısı 4 olan bir palanga sisteminde mekanik avantaj kaçtır ve 600 N'luk yük için gereken ideal kuvvet nedir?",
  steps:[{t:"Mekanik avantaj",a:"MA = n = 4",d:"Palangada yükü taşıyan ip kolu sayısı mekanik avantaja eşittir."},{t:"Kuvveti bul",a:"150 N",d:"F = Yük/n = 600/4 = 150 N (ideal, sürtünmesiz)."}],
  ans:"Mekanik avantaj 4; gereken ideal kuvvet 150 N"}
);
info.sabitMakara.lise.kolay.push(
 {q:"Sabit bir makaradan 250 N'luk yük sabit hızla yukarı çekiliyor. Sürtünme yokken çekme kuvveti ne kadardır ve sabit makara hangi kolaylığı sağlar?",
  steps:[{t:"Kuvveti belirle",a:"250 N",d:"Sabit makara kuvvetten kazanç sağlamaz; mekanik avantajı 1 olduğundan F = Yük = 250 N."},{t:"Kolaylığı söyle",a:"Yön değiştirir",d:"Sabit makara yalnızca kuvvetin yönünü değiştirir; ipi aşağı çekerek yükü yukarı kaldırma imkânı verir."}],
  ans:"250 N; sabit makara yalnızca kuvvetin yönünü değiştirir (MA = 1)"}
);

fs.writeFileSync(path.join(BQ,"makine_test.js"),"globalThis.__BQ = "+JSON.stringify(test)+";\n","utf8");
fs.writeFileSync(path.join(BQ,"makine_info.js"),"globalThis.__BQ = "+JSON.stringify(info)+";\n","utf8");
console.log("topup tamam: orta.zor="+test.ortaokul.zor.length+" disliCark.lise.zor="+info.disliCark.lise.zor.length+" kaldiracTur.lise.zor="+info.kaldiracTur.lise.zor.length+" palanga.lise.kolay="+info.palanga.lise.kolay.length+" sabitMakara.lise.kolay="+info.sabitMakara.lise.kolay.length);
