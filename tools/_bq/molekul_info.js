// Molekül Geometrisi — bilgi paneli (✎) soru bankası. konu→level→{kolay,zor}.
globalThis.__BQ = {
 "molekulSekli": {
  "ortaokul": { "kolay": [
   {"q":"Bir molekülün şeklini ne belirler?","steps":[{"t":"Etken","a":"Elektron çiftlerinin itmesi","d":"Merkez atom çevresindeki elektron çiftleri birbirini iter."},{"t":"Sonuç","a":"En uzak dizilim","d":"Çiftler en uzak konuma geçer; bu molekülün şeklini verir."}],"ans":"Merkez atomdaki elektron çiftlerinin itmesi belirler"}
  ], "zor": [
   {"q":"Su ve karbondioksit üç atomlu olduğu halde şekilleri neden farklıdır?","steps":[{"t":"Su","a":"Oksijende ortaklanmamış çift var","d":"İki ortaklanmamış çift bağları iter; su açısaldır."},{"t":"CO₂","a":"Karbonda çift yok","d":"Ortaklanmamış çift olmadığından CO₂ doğrusaldır."}],"ans":"Merkez atomdaki ortaklanmamış çift farkı nedeniyle"}
  ]},
  "lise": { "kolay": [
   {"q":"VSEPR ile molekül şekli nasıl tahmin edilir?","steps":[{"t":"1","a":"Elektron gruplarını say","d":"Merkez atomun bağ + ortaklanmamış çiftlerini say."},{"t":"2","a":"En uzak dizilim + atom konumu","d":"Grupları en uzak yerleştir; molekül şeklini bağlı atomlar belirler."}],"ans":"Elektron gruplarını sayıp en uzak dizilime göre şekil bulunur"}
  ], "zor": [
   {"q":"AX₃E ve AX₄ tiplerinin şekillerini karşılaştır.","steps":[{"t":"AX₄","a":"Dört yüzlü","d":"4 bağ, çift yok → düzgün dört yüzlü (109,5°)."},{"t":"AX₃E","a":"Üçgen piramit","d":"3 bağ + 1 çift → aynı dört yüzlü tabandan üçgen piramit (~107°)."}],"ans":"AX₄ dört yüzlü, AX₃E üçgen piramit"}
  ]}
 },
 "vseprTemel": {
  "lise": { "kolay": [
   {"q":"VSEPR kuramının temel varsayımı nedir?","steps":[{"t":"Varsayım","a":"Elektron çiftleri itişir","d":"Değerlik kabuğu elektron çiftleri negatiftir; birbirini iter."},{"t":"Sonuç","a":"En uzak geometri","d":"İtme minimuma inecek şekilde geometri oluşur."}],"ans":"Elektron çiftleri itişerek en uzak dizilimi alır"}
  ], "zor": [
   {"q":"AX₅ ve AX₆ geometrilerini ve hibritleşmelerini yaz.","steps":[{"t":"AX₅","a":"Üçgen çift piramit, sp³d","d":"5 grup → trigonal bipiramit."},{"t":"AX₆","a":"Oktahedral, sp³d²","d":"6 grup → oktahedral (90°)."}],"ans":"AX₅: sp³d üçgen çift piramit; AX₆: sp³d² oktahedral"}
  ]}
 },
 "hibritlesme": {
  "lise": { "kolay": [
   {"q":"Hibritleşme türünü elektron grubu sayısından nasıl bulursun?","steps":[{"t":"Kural","a":"2→sp, 3→sp², 4→sp³","d":"Grup sayısı hibritleşmeyi belirler."},{"t":"Devam","a":"5→sp³d, 6→sp³d²","d":"Genişlemiş oktet için d katılır."}],"ans":"Elektron grubu sayısına göre: 2 sp, 3 sp², 4 sp³, 5 sp³d, 6 sp³d²"}
  ], "zor": [
   {"q":"Etilen (C₂H₄) ve asetilen (C₂H₂) karbonlarının hibritleşmelerini bul.","steps":[{"t":"Etilen","a":"sp²","d":"Her karbon 3 sigma grubu (çift bağ tek grup) → sp², düzlemsel."},{"t":"Asetilen","a":"sp","d":"Her karbon 2 sigma grubu → sp, doğrusal."}],"ans":"Etilen sp² (düzlemsel), asetilen sp (doğrusal)"}
  ]}
 },
 "molekulPolarite": {
  "lise": { "kolay": [
   {"q":"Bir molekülün polar olup olmadığını nasıl anlarsın?","steps":[{"t":"1","a":"Bağlar polar mı?","d":"Elektronegatiflik farkı olan bağlar polardır."},{"t":"2","a":"Geometri simetrik mi?","d":"Polar bağlar simetrik dizilirse iptal olur (apolar); asimetrik ise polar."}],"ans":"Polar bağ + asimetrik geometri → polar molekül"}
  ], "zor": [
   {"q":"CCl₄ apolar, CHCl₃ polardır. Farkı açıkla.","steps":[{"t":"CCl₄","a":"Simetrik dört yüzlü","d":"Dört aynı C–Cl dipolü iptal olur → apolar."},{"t":"CHCl₃","a":"Asimetrik","d":"Bir H simetriyi bozar; dipoller iptal olmaz → polar."}],"ans":"CCl₄ simetrik (apolar), CHCl₃ asimetrik (polar)"}
  ]}
 },
 "suSekli": {
  "ilkokul": { "kolay": [
   {"q":"Su molekülü nasıl bir şekle sahiptir?","steps":[{"t":"Şekil","a":"Kırık (V) çizgi","d":"İki hidrojen oksijene açı yaparak bağlanır; molekül V şeklindedir."}],"ans":"V (açısal) şeklindedir"}
  ], "zor": [
   {"q":"Su molekülü neden düz değildir?","steps":[{"t":"Neden","a":"Oksijendeki elektron çiftleri iter","d":"Oksijenin ortaklanmamış elektron çiftleri hidrojenleri iterek molekülü büker."}],"ans":"Oksijendeki ortaklanmamış çiftler hidrojenleri iter"}
  ]}
 },
 "netDipolVektoru": {
  "lise": { "kolay": [
   {"q":"Net dipol momenti nasıl bulunur?","steps":[{"t":"Vektör","a":"Bağ dipolleri vektörel toplanır","d":"Her polar bağın dipol vektörü yön ve büyüklükle toplanır."}],"ans":"Bağ dipol vektörlerinin toplamıdır"}
  ], "zor": [
   {"q":"CO₂'de bağlar polar olduğu halde net dipol neden sıfırdır?","steps":[{"t":"Yön","a":"İki dipol 180° zıt","d":"İki C=O dipolü eşit ve zıt yöndedir."},{"t":"Toplam","a":"Sıfır","d":"Vektörel toplamları sıfırlanır → apolar."}],"ans":"Eşit ve zıt dipoller vektörel olarak iptal olur"}
  ]}
 }
};
