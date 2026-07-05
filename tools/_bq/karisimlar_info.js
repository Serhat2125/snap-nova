// Karışımlar ve Çözeltiler — bilgi paneli (✎ step) soru bankası.
// Yapı: konu → level → {kolay:[...], zor:[...]}. Şıksız, adım-adım çözümlü.
// Motor lvKey: lise = üniversite (ilkokul/ortaokul/lise anahtarları yeterli).
globalThis.__BQ = {
 "safKarisim": {
  "ilkokul": { "kolay": [
   {"q":"Tuzlu su neden bir karışımdır?","steps":[{"t":"Karışım tanımı","a":"İki madde birleşmiş","d":"Tuz ve su, kimlikleri değişmeden bir araya gelmiştir."},{"t":"Sonuç","a":"Karışımdır","d":"Bileşenler ayrılabildiği için karışımdır."}],"ans":"Tuz ve suyun kimliği korunarak karışmasıdır"}
  ], "zor": [
   {"q":"Saf su ile tuzlu suyu birbirinden nasıl ayırt ederiz?","steps":[{"t":"Gözlem","a":"Tat/kaynama","d":"Tuzlu su tuzlu tada sahiptir ve biraz daha geç kaynar."},{"t":"Deney","a":"Buharlaştırma","d":"Tuzlu su buharlaşınca tuz kalır; saf suda kalıntı olmaz."}],"ans":"Buharlaştırınca tuzlu suda tuz kalır"}
  ]},
  "lise": { "kolay": [
   {"q":"Saf madde ile karışım arasındaki temel farkları sınıflandır.","steps":[{"t":"Saf madde","a":"Sabit bileşim","d":"Element/bileşik; belirli erime-kaynama noktası vardır."},{"t":"Karışım","a":"Değişken bileşim","d":"Farklı oranlarda olabilir; belirli erime-kaynama noktası yoktur."}],"ans":"Saf madde sabit bileşimli, karışım değişken bileşimlidir"}
  ], "zor": [
   {"q":"Bir maddenin karışım mı saf mı olduğunu ısınma grafiğinden nasıl anlarız?","steps":[{"t":"Saf madde","a":"Yatay platolar","d":"Saf maddede hal değişimi sabit sıcaklıkta olur (yatay çizgi)."},{"t":"Karışım","a":"Eğik bölge","d":"Karışımda hal değişimi bir sıcaklık aralığında olur; grafik eğimlidir."}],"ans":"Saf maddede plato, karışımda eğimli hal değişimi görülür"}
  ]}
 },
 "homojenHeterojen": {
  "ortaokul": { "kolay": [
   {"q":"Bir karışımın homojen mi heterojen mi olduğuna nasıl karar veririz?","steps":[{"t":"Bak","a":"Tek görünüm mü?","d":"Her yeri aynı ve tek fazlı görünüyorsa homojendir."},{"t":"Karar","a":"Ayrı fazlar → heterojen","d":"Bileşenler ayrı görünüyorsa heterojendir."}],"ans":"Tek düzen görünüm homojen, ayrı fazlar heterojendir"}
  ], "zor": [
   {"q":"Ayran çalkalanmadan bekletilince neden bazen heterojen görünür?","steps":[{"t":"Yapı","a":"Kolloidal parçacıklar","d":"Ayran kolloittir; parçacıklar zamanla çökebilir."},{"t":"Sonuç","a":"Ayrışma","d":"Bekleyince faz ayrışması görülebilir; çalkalayınca homojenleşir."}],"ans":"Kolloidal parçacıklar çökünce faz ayrışır"}
  ]},
  "lise": { "kolay": [
   {"q":"Çözelti, kolloit ve süspansiyonu tanecik boyutuna göre sırala.","steps":[{"t":"Çözelti","a":"En küçük (<1 nm)","d":"İyon/molekül boyutunda; ışığı saçmaz."},{"t":"Kolloit-süspansiyon","a":"Orta ve büyük","d":"Kolloit 1-1000 nm (ışık saçar), süspansiyon en büyük (çöker)."}],"ans":"Çözelti < kolloit < süspansiyon"}
  ], "zor": [
   {"q":"Tyndall etkisi ile çözelti ve kolloit nasıl ayırt edilir?","steps":[{"t":"Işık gönder","a":"Işık demeti","d":"Karışıma yandan ışık tutulur."},{"t":"Gözlem","a":"Saçılma","d":"Kolloitte ışık yolu görünür (saçılır); gerçek çözeltide görünmez."}],"ans":"Kolloit ışığı saçar, çözelti saçmaz"}
  ]}
 },
 "cozunmeNedir": {
  "ortaokul": { "kolay": [
   {"q":"Şeker suda çözününce nereye gider?","steps":[{"t":"Süreç","a":"Su molekülleri sarar","d":"Su molekülleri şeker taneciklerini sarıp ayırır."},{"t":"Sonuç","a":"Dağılır","d":"Şeker tanecikleri su içinde eşit dağılır; görünmez olur ama kaybolmaz."}],"ans":"Su molekülleri şekeri sarıp dağıtır"}
  ], "zor": [
   {"q":"Çözünmenin fiziksel bir olay olduğunu nasıl kanıtlarız?","steps":[{"t":"Ölçüt","a":"Yeni madde yok","d":"Çözünmede yeni madde oluşmaz."},{"t":"Kanıt","a":"Geri kazanım","d":"Suyu buharlaştırınca şeker/tuz aynen geri elde edilir → fiziksel olay."}],"ans":"Suyu buharlaştırınca madde aynen geri elde edilir"}
  ]},
  "lise": { "kolay": [
   {"q":"'Benzer benzeri çözer' kuralını su ve tuz üzerinden açıkla.","steps":[{"t":"Su","a":"Polar","d":"Su polar bir moleküldür."},{"t":"Tuz","a":"İyonik/polar","d":"Polar su, iyonik tuzu iyonlarına ayırıp çözer."}],"ans":"Polar su, polar/iyonik tuzu çözer"}
  ], "zor": [
   {"q":"Bir maddenin çözünmesi için enerji koşulunu açıkla.","steps":[{"t":"Bağlar","a":"Kopar ve kurulur","d":"Çözünen-çözünen ve çözen-çözen çekimleri kopar, çözünen-çözen çekimi kurulur."},{"t":"Koşul","a":"Yeni çekim karşılamalı","d":"Yeni oluşan çekimler eskileri karşılarsa çözünme gerçekleşir."}],"ans":"Yeni çözünen-çözen çekimleri eski bağları karşılamalıdır"}
  ]}
 },
 "cozunmeHizi": {
  "ortaokul": { "kolay": [
   {"q":"Şekerin daha hızlı çözünmesi için üç yöntem yaz.","steps":[{"t":"Etkenler","a":"Isıt, karıştır, küçült","d":"Sıcaklık, karıştırma ve tane boyutunu küçültme çözünmeyi hızlandırır."}],"ans":"Isıtmak, karıştırmak, taneleri küçültmek"}
  ], "zor": [
   {"q":"Tanecik boyutu çözünme hızını neden etkiler?","steps":[{"t":"Yüzey","a":"Küçük tane = çok yüzey","d":"Küçük tanecikler daha fazla yüzey alanı sunar."},{"t":"Temas","a":"Daha çok temas","d":"Su ile temas artar; çözünme hızlanır."}],"ans":"Küçük taneler daha çok yüzey sunar, temas artar"}
  ]},
  "lise": { "kolay": [
   {"q":"Çözünme hızı ile çözünürlük arasındaki farkı açıkla.","steps":[{"t":"Hız","a":"Ne kadar hızlı","d":"Çözünme hızı, birim zamanda çözünen miktarıdır."},{"t":"Çözünürlük","a":"En fazla ne kadar","d":"Çözünürlük, belirli sıcaklıkta çözünebilecek en fazla miktardır."}],"ans":"Hız = hızlılık; çözünürlük = miktar sınırı"}
  ], "zor": [
   {"q":"Sıcaklık artışı hem hızı hem çözünürlüğü nasıl etkiler (katı)?","steps":[{"t":"Hız","a":"Artar","d":"Sıcaklık tanecik hareketini artırır; çözünme hızlanır."},{"t":"Çözünürlük","a":"Genelde artar","d":"Çoğu katının çözünürlüğü de sıcaklıkla artar."}],"ans":"Sıcaklık hem çözünme hızını hem çözünürlüğü (katıda) artırır"}
  ]}
 },
 "ayirmaTemel": {
  "ilkokul": { "kolay": [
   {"q":"Su, kum ve demir tozu karışımını hangi sırayla ayırırsın?","steps":[{"t":"1. adım","a":"Mıknatıs","d":"Önce mıknatısla demir tozu çekilir."},{"t":"2. adım","a":"Süz + buharlaştır","d":"Kalan kum-su süzülür; kumdan ayrılan su buharlaştırılırsa varsa tuz kalır."}],"ans":"Önce mıknatıs, sonra süzme"}
  ], "zor": [
   {"q":"Tuz-kum karışımından saf tuz nasıl elde edilir?","steps":[{"t":"1","a":"Su ekle","d":"Su tuzu çözer, kum çözünmez."},{"t":"2-3","a":"Süz, buharlaştır","d":"Süzerek kum ayrılır; su buharlaştırılınca tuz kristalleri kalır."}],"ans":"Su ekle → süz → buharlaştır"}
  ]},
  "lise": { "kolay": [
   {"q":"Ayırma yöntemi seçerken hangi fiziksel özelliklere bakılır?","steps":[{"t":"Özellikler","a":"Tane boyutu, çözünürlük, kaynama noktası, mıknatıslanma","d":"Bileşenlerin farklı fiziksel özelliğine göre uygun yöntem seçilir."}],"ans":"Tane boyutu, çözünürlük, kaynama noktası, mıknatıslanma"}
  ], "zor": [
   {"q":"Ham petrolün bileşenlerine ayrılması hangi yöntemle ve neden bu yöntemle olur?","steps":[{"t":"Yöntem","a":"Ayrımsal damıtma","d":"Bileşenlerin kaynama noktaları farklıdır."},{"t":"İlke","a":"Kaynama noktası farkı","d":"Kolonda farklı yükseklikte farklı bileşenler yoğunlaşır."}],"ans":"Ayrımsal damıtma; kaynama noktası farkı nedeniyle"}
  ]}
 },
 "derisimKavram": {
  "lise": { "kolay": [
   {"q":"Molarite (M) nasıl hesaplanır, örnekle açıkla.","steps":[{"t":"Formül","a":"M = n/V","d":"Mol sayısı bölü çözelti hacmi (L)."},{"t":"Örnek","a":"1 mol / 2 L = 0,5 M","d":"1 mol madde 2 L çözeltide 0,5 molar verir."}],"ans":"M = mol çözünen / litre çözelti"}
  ], "zor": [
   {"q":"49 g H₂SO₄ (M=98) ile 250 mL çözeltinin molaritesini bul.","steps":[{"t":"Mol","a":"49/98 = 0,5 mol","d":"mol = kütle/molar kütle."},{"t":"Molarite","a":"0,5/0,25 = 2 M","d":"0,5 mol ÷ 0,25 L = 2 M."}],"ans":"2 M"}
  ]}
 },
 "cozunurlukEgri": {
  "lise": { "kolay": [
   {"q":"Çözünürlük eğrisi neyi gösterir?","steps":[{"t":"Eksen","a":"Sıcaklık-çözünürlük","d":"Yatay eksen sıcaklık, dikey eksen 100 g suda çözünen miktarıdır."},{"t":"Yorum","a":"Eğim","d":"Eğrinin yükselmesi çözünürlüğün sıcaklıkla arttığını gösterir."}],"ans":"Sıcaklığa göre çözünürlük değişimini gösterir"}
  ], "zor": [
   {"q":"Çözünürlüğü 40°C'de 60 g/100 g su olan bir tuzun, 200 g suda kaç g çözüneceğini bul.","steps":[{"t":"Orantı","a":"100 g → 60 g","d":"Çözünürlük 100 g su başınadır."},{"t":"Hesap","a":"200 g → 120 g","d":"İki katı su → iki katı çözünen."}],"ans":"120 g"}
  ]}
 },
 "koligatifTYT": {
  "lise": { "kolay": [
   {"q":"Koligatif özellik ne demektir, örnek ver.","steps":[{"t":"Tanım","a":"Tanecik sayısına bağlı","d":"Çözünenin cinsine değil, tanecik sayısına bağlı özelliklerdir."},{"t":"Örnekler","a":"Donma alçalması, kaynama yükselmesi","d":"Ozmotik basınç ve buhar basıncı düşmesi de koligatiftir."}],"ans":"Tanecik sayısına bağlı özellikler (donma alçalması vb.)"}
  ], "zor": [
   {"q":"0,5 molal NaCl çözeltisinin donma alçalmasını hesapla (Kd=1,86, i=2).","steps":[{"t":"Formül","a":"ΔTd = Kd·m·i","d":"NaCl 2 iyona ayrışır, i=2."},{"t":"Hesap","a":"1,86·0,5·2 = 1,86 °C","d":"Donma noktası −1,86 °C."}],"ans":"1,86 °C alçalma (−1,86 °C)"}
  ]}
 },
 "ozmosBasinc": {
  "lise": { "kolay": [
   {"q":"Ozmoz olayını açıkla.","steps":[{"t":"Zar","a":"Yarı geçirgen","d":"Su geçer, çözünen geçmez."},{"t":"Yön","a":"Seyreltikten derişiğe","d":"Su, derişimi düşük taraftan yüksek tarafa geçer."}],"ans":"Su, yarı geçirgen zardan seyreltikten derişiğe geçer"}
  ], "zor": [
   {"q":"0,2 M çözeltinin 27°C'deki ozmotik basıncını bul (R=0,082, T=300 K).","steps":[{"t":"Formül","a":"π = MRT","d":"Ozmotik basınç = derişim × R × sıcaklık."},{"t":"Hesap","a":"0,2·0,082·300 ≈ 4,92 atm","d":"≈4,92 atm."}],"ans":"≈4,92 atm"}
  ]}
 },
 "damitma": {
  "ortaokul": { "kolay": [
   {"q":"Tuzlu sudan saf su nasıl elde edilir?","steps":[{"t":"Buharlaştır","a":"Su buharlaşır","d":"Tuzlu su ısıtılır, su buharı yükselir, tuz geride kalır."},{"t":"Yoğunlaştır","a":"Buharı soğut","d":"Su buharı soğuk yüzeyde yoğunlaşıp saf su olarak toplanır (damıtma)."}],"ans":"Damıtma: su buharlaştırılıp yoğunlaştırılır"}
  ], "zor": [
   {"q":"Su-alkol karışımı neden damıtma ile ayrılır?","steps":[{"t":"Kaynama","a":"Farklı noktalar","d":"Alkol sudan düşük sıcaklıkta kaynar."},{"t":"Ayrım","a":"Önce alkol buharlaşır","d":"Isıtınca önce alkol buharlaşıp ayrılır; su geride kalır."}],"ans":"Kaynama noktaları farklı olduğu için damıtma ile ayrılır"}
  ]}
 }
};
