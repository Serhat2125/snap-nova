globalThis.__BQ = {
  "yuzeyGerilimi": {
    "lise": {
      "kolay": [
        {
          "q": "Yüzey gerilimi nedir?",
          "steps": [
            {"t": "Tanım", "a": "Sıvı yüzeyindeki gerilme kuvveti", "d": "Sıvı molekülleri birbirini çekerek yüzeyde bir film tabakası oluşturur. Bu film tabakası, yüzeyin küçülme eğiliminde olmasını sağlar."},
            {"t": "Formül", "a": "γ = F/L", "d": "γ yüzey gerilim katsayısı (N/m), F çizgiye etki eden kuvvet, L çizginin uzunluğudur."}
          ],
          "ans": "Sıvı yüzeyinin birim uzunluğuna etki eden yüzey kuvveti (γ = F/L)",
          "o": ["Sıvının akma hızı", "Katı-sıvı temas açısı", "Sıvı moleküllerinin ortalama kinetik enerjisi", "Sıvının iç sürtünme kuvveti"]
        },
        {
          "q": "γ = F/L formülünde γ'nın birimi nedir?",
          "steps": [
            {"t": "Birim analizi", "a": "N/m", "d": "F Newton (N), L metre (m) cinsinden olduğundan γ = F/L → N/m olur."},
            {"t": "Alternatif birim", "a": "J/m²", "d": "Yüzey gerilimi aynı zamanda birim alana düşen yüzey enerjisi olarak da ifade edilir: J/m² = N/m."}
          ],
          "ans": "N/m",
          "o": ["N/m²", "Pa", "kg/m", "J/m"]
        },
        {
          "q": "Kohezyon kuvveti nedir?",
          "steps": [
            {"t": "Tanım", "a": "Aynı cins moleküller arası çekim", "d": "Kohezyon, su moleküllerinin birbirini çekmesi gibi aynı cins moleküller arasındaki çekim kuvvetidir."},
            {"t": "Örnek", "a": "Su-su etkileşimi", "d": "Su damlasının küresel şekil alması kohezyon sayesindedir; su molekülleri birbirini çekerek yüzeyi en aza indirir."}
          ],
          "ans": "Aynı cins moleküller arasındaki çekim kuvveti (örneğin su-su)",
          "o": ["Farklı cins moleküller arası çekim", "Katı-gaz arayüzündeki kuvvet", "Elektrik yükleri arasındaki itme kuvveti", "Sürtünme kuvvetinin özel bir türü"]
        },
        {
          "q": "Sabun veya deterjan suyun yüzey gerilimini nasıl etkiler?",
          "steps": [
            {"t": "Etki", "a": "Yüzey gerilimini azaltır", "d": "Sabun molekülleri (amfifillik) su yüzeyinde dizilerek su molekülleri arasındaki kohezyon kuvvetini zayıflatır."},
            {"t": "Sonuç", "a": "γ azalır", "d": "Bu nedenle sabunlu su, yalın suya kıyasla çok daha büyük kabarcıklar ve ince filmler oluşturabilir."}
          ],
          "ans": "Yüzey gerilimini azaltır",
          "o": ["Yüzey gerilimini artırır", "Yüzey gerilimine etkisi yoktur", "Önce artırır sonra azaltır", "Yalnızca sıcakken azaltır"]
        },
        {
          "q": "Yüzey enerjisi ile yüzey gerilimi arasındaki ilişki nedir?",
          "steps": [
            {"t": "Yüzey enerjisi", "a": "Birim alana düşen enerji (J/m²)", "d": "Yüzey oluşturmak için gereken enerji miktarı, yüzey enerjisi olarak tanımlanır."},
            {"t": "Eşdeğerlik", "a": "γ = W/A → J/m² = N/m", "d": "Yüzey gerilimi ve yüzey enerjisi boyutsal olarak eşdeğerdir; N/m = J/m²."}
          ],
          "ans": "Yüzey enerjisi J/m² ile ifade edilir ve γ (N/m) ile eşdeğerdir",
          "o": ["Yüzey enerjisi yüzey geriliminin karesidir", "Yüzey enerjisi yalnızca katılara özgüdür", "İkisi birbirinden bağımsız farklı büyüklüklerdir", "Yüzey enerjisi yüzey geriliminin negatifidir"]
        }
      ],
      "zor": [
        {
          "q": "Yüzey gerilim katsayısı γ = 0,072 N/m olan su, L = 6 cm uzunluğundaki bir tel üzerinde film oluşturuyor. Bu filme etki eden yüzey gerilim kuvveti kaç mN'dur? (Filmin iki yüzeyi vardır.)",
          "steps": [
            {"t": "Veri", "a": "γ = 0,072 N/m, L = 0,06 m, 2 yüzey", "d": "Film iki yüzeyden oluştuğundan toplam etkin uzunluk 2L alınır."},
            {"t": "Hesap", "a": "F = γ × 2L", "d": "F = 0,072 × 2 × 0,06 = 0,00864 N"},
            {"t": "Sonuç", "a": "F ≈ 8,64 mN", "d": "1 N = 1000 mN dönüşümü ile 0,00864 N = 8,64 mN."}
          ],
          "ans": "8,64 mN",
          "o": ["4,32 mN", "17,28 mN", "0,864 mN", "72 mN"]
        },
        {
          "q": "Su yüzeyinde 4 cm × 3 cm boyutlarında yeni bir yüzey oluşturuluyor. Suyun yüzey gerilimi γ = 0,072 N/m olduğuna göre, bu yüzeyi oluşturmak için gereken enerji kaç μJ'dür?",
          "steps": [
            {"t": "Alan", "a": "A = 0,04 × 0,03 = 0,0012 m²", "d": "Yüzey alanı uzunluk × genişlik formülüyle bulunur."},
            {"t": "Enerji", "a": "W = γ × A", "d": "W = 0,072 × 0,0012 = 8,64 × 10⁻⁵ J"},
            {"t": "Sonuç", "a": "W = 86,4 μJ", "d": "1 J = 10⁶ μJ dönüşümüyle 8,64 × 10⁻⁵ J = 86,4 μJ."}
          ],
          "ans": "86,4 μJ",
          "o": ["43,2 μJ", "172,8 μJ", "8,64 μJ", "864 μJ"]
        },
        {
          "q": "Dikdörtgen bir tel çerçeve (kısa kenar 5 cm, uzun kenar 10 cm) su filmi tutuyor. γ = 0,072 N/m için çerçevenin kısa kenarına etki eden toplam yüzey gerilim kuvveti kaç mN'dur?",
          "steps": [
            {"t": "Tek kısa kenar", "a": "L = 0,05 m", "d": "Kısa kenar L = 5 cm = 0,05 m."},
            {"t": "İki yüzey", "a": "F = γ × 2L", "d": "Film iki yüzeye sahip olduğundan F = 0,072 × 2 × 0,05 = 0,0072 N."},
            {"t": "Sonuç", "a": "F = 7,2 mN", "d": "0,0072 N = 7,2 mN."}
          ],
          "ans": "7,2 mN",
          "o": ["3,6 mN", "14,4 mN", "72 mN", "0,72 mN"]
        }
      ]
    }
  },
  "yuzeyGerilimFaktor": {
    "lise": {
      "kolay": [
        {
          "q": "Sıcaklık arttıkça suyun yüzey gerilimi nasıl değişir?",
          "steps": [
            {"t": "Moleküler etki", "a": "Termal titreşimler artar", "d": "Sıcaklık artışı moleküllerin kinetik enerjisini artırır; moleküller arası kohezyon kuvveti zayıflar."},
            {"t": "Sonuç", "a": "γ azalır", "d": "Yüksek sıcaklıkta su molekülleri birbirini daha az çektiğinden yüzey gerilimi düşer."}
          ],
          "ans": "Azalır",
          "o": ["Artar", "Önce artar sonra azalır", "Değişmez", "Kaynama noktasında aniden artar"]
        },
        {
          "q": "Sabun neden yüzey gerilimini azaltır?",
          "steps": [
            {"t": "Amfifillik", "a": "Hidrofil baş + hidrofob kuyruk", "d": "Sabun molekülleri su yüzeyine yerleşerek su-su kohezyon bağlarını keser."},
            {"t": "Etki", "a": "Su yüzeyindeki kohezyon azalır", "d": "Daha az kohezyon → daha düşük yüzey gerilimi → sabunlu su geniş köpükler oluşturabilir."}
          ],
          "ans": "Amfifillik özelliğiyle su yüzeyine dizilerek kohezyon kuvvetini zayıflatır",
          "o": ["Su moleküllerini büyütür", "Su yoğunluğunu artırır", "Suyu kimyasal olarak parçalar", "Suya elektrik yükü kazandırır"]
        },
        {
          "q": "Sıcak su neden soğuk suya kıyasla daha iyi temizler?",
          "steps": [
            {"t": "γ etkisi", "a": "Sıcaklıkla γ azalır", "d": "Düşük yüzey gerilimi, suyun kirli yüzeylere daha kolay yayılıp nüfuz etmesini sağlar."},
            {"t": "Çözünürlük", "a": "Yağ çözünürlüğü artar", "d": "Yüksek sıcaklıkta yağ ve kir molekülleri daha kolay ayrışıp su içinde dağılır."}
          ],
          "ans": "Yüzey gerilimi azalır; yağ ve kir daha kolay çözünür ve yüzeylere nüfuz artar",
          "o": ["Sıcak su daha hafiftir, bu yüzden kiri kaldırır", "Sıcaklık kiri yakar", "Sıcak su daha yoğundur, bu yüzden daha iyi yıkar", "Sıcaklık suyun pH'ını değiştirir"]
        },
        {
          "q": "Deterjanlar suda nasıl çalışır?",
          "steps": [
            {"t": "Misel oluşumu", "a": "Yağ damlacıklarını kuşatır", "d": "Deterjan molekülleri yağ damlasını çevreleyerek misel oluşturur; hidrofil başları suya dönük, hidrofob kuyrukları yağa dönük olur."},
            {"t": "Yüzey gerilimi", "a": "γ azaltır", "d": "Aynı zamanda su yüzeyinde dizilerek yüzey gerilimini düşürür ve suyun yüzeye yayılmasını kolaylaştırır."}
          ],
          "ans": "Yağı misel içinde sarar ve yüzey gerilimini düşürür",
          "o": ["Yağı kimyasal olarak yakar", "Suyu katı hale getirir", "Yalnızca su yoğunluğunu artırır", "Kir moleküllerini elektrikle iter"]
        },
        {
          "q": "Bir sıvıya yabancı madde (kirlilik) karışması yüzey gerilimini nasıl etkiler?",
          "steps": [
            {"t": "Genel kural", "a": "Çoğunlukla azaltır", "d": "Yabancı maddeler su molekülleri arasına girerek kohezyon kuvvetini zayıflatır."},
            {"t": "İstisna", "a": "Bazı tuzlar γ'yı artırabilir", "d": "NaCl gibi iyonik tuzlar su yapısını güçlendirerek yüzey gerilimini hafifçe artırabilir."}
          ],
          "ans": "Çoğunlukla azaltır; bazı iyonik tuzlar hafifçe artırabilir",
          "o": ["Her zaman artırır", "Her zaman değişmez", "Her zaman iki katına çıkar", "Yalnızca gazlar yüzey gerilimini etkiler"]
        }
      ],
      "zor": [
        {
          "q": "Su için 20°C'de γ = 0,073 N/m ve 60°C'de γ = 0,066 N/m'dir. 20°C'de L = 8 cm telde oluşan film kuvveti ile 60°C'deki fark kaç mN'dur? (Filmin iki yüzeyi vardır.)",
          "steps": [
            {"t": "20°C kuvveti", "a": "F₁ = 0,073 × 2 × 0,08", "d": "F₁ = 0,073 × 0,16 = 0,01168 N = 11,68 mN"},
            {"t": "60°C kuvveti", "a": "F₂ = 0,066 × 2 × 0,08", "d": "F₂ = 0,066 × 0,16 = 0,01056 N = 10,56 mN"},
            {"t": "Fark", "a": "ΔF = 11,68 - 10,56 = 1,12 mN", "d": "Sıcaklık artışıyla yüzey gerilimi azaldığından kuvvet de azalmıştır."}
          ],
          "ans": "1,12 mN",
          "o": ["0,56 mN", "2,24 mN", "11,68 mN", "0,112 mN"]
        },
        {
          "q": "Sabun eklenmesiyle γ = 0,072 N/m'den 0,040 N/m'ye düşen suda, r = 2 mm yarıçaplı bir sabun baloncuğunun iç ve dış basınç farkı kaç Pa'dır? (4γ/r formülü, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "ΔP = 4γ/r", "d": "Sabun baloncuğunun iki yüzeyi olduğundan basınç farkı ΔP = 4γ/r ile bulunur."},
            {"t": "Hesap", "a": "ΔP = 4 × 0,040 / 0,002", "d": "ΔP = 0,160 / 0,002 = 80 Pa"},
            {"t": "Sonuç", "a": "ΔP = 80 Pa", "d": "İçerideki basınç dışarıdakinden 80 Pa fazladır."}
          ],
          "ans": "80 Pa",
          "o": ["40 Pa", "160 Pa", "20 Pa", "8 Pa"]
        },
        {
          "q": "Saf su (γ = 0,072 N/m) ile deterjanl su (γ = 0,030 N/m) aynı r = 1 cm yarıçaplı damlalar oluşturursa, deterjanl su damlasının basınç farkı saf su damlasına oranı kaçtır? (Su damlası tek yüzey: ΔP = 2γ/r)",
          "steps": [
            {"t": "Saf su", "a": "ΔP₁ = 2 × 0,072 / 0,01 = 14,4 Pa", "d": "Tek yüzeyli damla için ΔP = 2γ/r formülü kullanılır."},
            {"t": "Deterjanl su", "a": "ΔP₂ = 2 × 0,030 / 0,01 = 6 Pa", "d": "Aynı formül uygulanır; γ azaldığı için ΔP de azalmıştır."},
            {"t": "Oran", "a": "ΔP₂/ΔP₁ = 6/14,4 ≈ 0,417", "d": "Deterjanl su damlasının basınç farkı yaklaşık 5/12 ≈ 0,417 oranındadır."}
          ],
          "ans": "≈ 0,417 (yaklaşık 5/12)",
          "o": ["0,5", "0,25", "0,72", "2,4"]
        }
      ]
    }
  },
  "adhezyon": {
    "lise": {
      "kolay": [
        {
          "q": "Adhezyon kuvveti nedir?",
          "steps": [
            {"t": "Tanım", "a": "Farklı cins moleküller arası çekim", "d": "Adhezyon, su ile cam gibi farklı maddelerin molekülleri arasındaki çekim kuvvetidir."},
            {"t": "Örnek", "a": "Su-cam etkileşimi", "d": "Su cam yüzeyine yapışır; bu durum adhezyonun kohezyon kuvvetinden büyük olmasından kaynaklanır."}
          ],
          "ans": "Farklı cins moleküller arasındaki çekim kuvveti (örneğin su-cam)",
          "o": ["Aynı cins moleküller arası çekim", "Elektrik yükleri arası itme", "Katılar arası sürtünme kuvveti", "Gaz moleküllerinin duvara çarpması"]
        },
        {
          "q": "Kohezyon kuvveti adhezyondan büyükse cıva cam tüpte ne yapar?",
          "steps": [
            {"t": "Cıva özelliği", "a": "Kohezyon > Adhezyon", "d": "Cıva molekülleri birbirini cam moleküllerinden daha kuvvetli çeker."},
            {"t": "Sonuç", "a": "Cıva cam tüpte aşağı çöker (konveks menisküs)", "d": "Cıva cam yüzeyini ıslatmaz; temas açısı θ > 90° olduğundan menisküs dışa doğru kabarır ve sıvı düşer."}
          ],
          "ans": "Tüp içinde düzeyden aşağı çökelerek konveks menisküs oluşturur",
          "o": ["Cam tüpte yükselir", "Cam tüpte değişim göstermez", "Önce yükselir sonra düşer", "Cam tüpü eritir"]
        },
        {
          "q": "Suyun cam tüpte konkav menisküs oluşturmasının nedeni nedir?",
          "steps": [
            {"t": "Güç karşılaştırması", "a": "Adhezyon > Kohezyon", "d": "Su molekülleri birbirini çektiğinden daha kuvvetli cam moleküllerini çeker; bu nedenle su cam yüzeyine doğru çekilir."},
            {"t": "Menisküs şekli", "a": "Konkav (içbükey)", "d": "Su yüzeyi kenarlarda daha yüksek, ortada daha alçak olur: temas açısı θ < 90°."}
          ],
          "ans": "Adhezyon (su-cam) kohezyon (su-su) kuvvetinden büyük olduğundan su kenarlarda yükselir",
          "o": ["Kohezyon adhezyondan büyük olduğundan", "Su ve cam arasında kimyasal reaksiyon olduğundan", "Suyun yoğunluğu camdan büyük olduğundan", "Cam negatif yüklü olduğundan"]
        },
        {
          "q": "Temas açısı (ıslanma açısı) θ < 90° ne anlama gelir?",
          "steps": [
            {"t": "Tanım", "a": "Sıvı yüzeyi yatay ile dar açı yapar", "d": "θ < 90° durumunda sıvı katı yüzeyi ıslatır; adhezyon kohezyon kuvvetini geçer."},
            {"t": "Sonuç", "a": "Sıvı yayılır (ıslatma)", "d": "Su-cam, su-tahta gibi sistemlerde θ küçük olup sıvı yüzeyde yayılma eğilimindedir."}
          ],
          "ans": "Sıvı yüzeyi ıslatır; adhezyon kohezyon kuvvetinden büyüktür",
          "o": ["Sıvı yüzeyi ıslatmaz; kohezyon büyüktür", "Sıvı buharlaşır", "Sıvı yüzey gerilimi sıfırdır", "Menisküs konveks olur"]
        },
        {
          "q": "Cıva için temas açısı yaklaşık θ ≈ 140° olduğunda menisküs nasıl olur?",
          "steps": [
            {"t": "θ > 90°", "a": "Kohezyon > Adhezyon", "d": "Cıva-cam sisteminde θ ≈ 140° olup cam yüzeyi cıva tarafından ıslatılmaz."},
            {"t": "Menisküs", "a": "Konveks (dışbükey)", "d": "Ortası kenarlara göre daha yüksek olan dışbükey yüzey oluşur; cıva cam tüpte aşağı çöker."}
          ],
          "ans": "Konveks (dışbükey) menisküs oluşur; cıva tüpte düzeyden aşağı çöker",
          "o": ["Konkav menisküs oluşur", "Menisküs düz kalır", "Cıva cam tüpte yükselir", "Menisküs şekli temas açısından bağımsızdır"]
        }
      ],
      "zor": [
        {
          "q": "Su kılcal borusunda h = 2γ·cosθ/(ρ·g·r) formülüne göre θ = 60° için r = 0,5 mm'lik tüpte h kaç cm'dir? (γ = 0,072 N/m, ρ = 1000 kg/m³, g = 10 m/s², cos60° = 0,5)",
          "steps": [
            {"t": "Veri", "a": "γ=0,072, cosθ=0,5, ρ=1000, g=10, r=5×10⁻⁴ m", "d": "Tüm değerler SI birimine çevrilir."},
            {"t": "Hesap", "a": "h = 2 × 0,072 × 0,5 / (1000 × 10 × 5×10⁻⁴)", "d": "h = 0,072 / 5 = 0,0144 m"},
            {"t": "Sonuç", "a": "h = 1,44 cm", "d": "0,0144 m × 100 = 1,44 cm."}
          ],
          "ans": "1,44 cm",
          "o": ["2,88 cm", "0,72 cm", "14,4 cm", "0,144 cm"]
        },
        {
          "q": "Adhezyon çalışması W_A = γ·(1 + cosθ) formülüyle hesaplanıyor. Su-cam sisteminde θ = 20° ve γ = 0,072 N/m için W_A kaç mJ/m²'dir? (cos20° ≈ 0,94)",
          "steps": [
            {"t": "Formül", "a": "W_A = γ·(1 + cosθ)", "d": "Adhezyon çalışması, sıvı-katı arayüzeyinin birim alanı oluşturmak için gereken enerjidir."},
            {"t": "Hesap", "a": "W_A = 0,072 × (1 + 0,94) = 0,072 × 1,94", "d": "W_A = 0,13968 J/m²"},
            {"t": "Sonuç", "a": "W_A ≈ 139,7 mJ/m²", "d": "0,13968 J/m² = 139,68 mJ/m² ≈ 139,7 mJ/m²."}
          ],
          "ans": "≈ 139,7 mJ/m²",
          "o": ["72 mJ/m²", "68 mJ/m²", "211,7 mJ/m²", "94 mJ/m²"]
        },
        {
          "q": "Bir sıvı cam yüzeyinde temas açısı θ = 30° yapıyor. Aynı sıvı plastik yüzeyinde θ = 90° yapıyor. Cam yüzeyindeki kılcal yükselme h_cam ile plastik yüzeyindeki h_plastik oranı h_cam/h_plastik kaçtır? (cos30° = √3/2 ≈ 0,866, cos90° = 0)",
          "steps": [
            {"t": "h formülü", "a": "h ∝ cosθ", "d": "h = 2γ·cosθ/(ρ·g·r) formülünde γ, ρ, g, r sabit ise h, cosθ ile orantılıdır."},
            {"t": "Plastik", "a": "cosθ = 0 → h_plastik = 0", "d": "θ = 90° için cos90° = 0, dolayısıyla sıvı plastik tüpte yükselmez."},
            {"t": "Oran", "a": "h_cam/h_plastik → tanımsız (∞)", "d": "h_plastik = 0 olduğundan oran tanımsızdır; cam yüzeyinde yükselme var, plastikte yok."}
          ],
          "ans": "h_plastik = 0 olduğundan oran tanımsız; sıvı cam tüpte yükselir, plastik tüpte yükselmez",
          "o": ["√3/2 ≈ 0,866", "2", "0,5", "√3 ≈ 1,732"]
        }
      ]
    }
  },
  "kilcalBoru": {
    "lise": {
      "kolay": [
        {
          "q": "Kılcal yükselme formülü nedir?",
          "steps": [
            {"t": "Formül", "a": "h = 2γ·cosθ/(ρ·g·r)", "d": "h yükselme yüksekliği, γ yüzey gerilimi, θ temas açısı, ρ sıvı yoğunluğu, g yerçekimi ivmesi, r tüp yarıçapıdır."},
            {"t": "Yorum", "a": "r azalırsa h artar", "d": "Tüp ne kadar ince ise sıvı o kadar yüksek çıkar."}
          ],
          "ans": "h = 2γ·cosθ/(ρ·g·r)",
          "o": ["h = ρ·g·r/(2γ)", "h = γ·r/(ρ·g)", "h = 2ρ·g·r/γ", "h = γ/(ρ·g·r²)"]
        },
        {
          "q": "Kılcal boru yarıçapı küçüldükçe yükselme yüksekliği nasıl değişir?",
          "steps": [
            {"t": "h formülü", "a": "h ∝ 1/r", "d": "h = 2γ·cosθ/(ρ·g·r) ifadesinde r azalırsa h artar: ters orantılı."},
            {"t": "Örnek", "a": "r ikiye bölünürse h iki katına çıkar", "d": "Bu nedenle çok ince kılcal damarlar sıvıyı daha yüksek taşır."}
          ],
          "ans": "Artar (h ∝ 1/r ilişkisi)",
          "o": ["Azalır", "Değişmez", "Önce artar sonra azalır", "Karekökle artar"]
        },
        {
          "q": "Su cam kılcal borada yükselirken cıva neden düşer?",
          "steps": [
            {"t": "Su-cam", "a": "θ < 90° → cosθ > 0 → h > 0", "d": "Su camı ıslatır; adhezyon kohezyon kuvvetini geçer, su yükselir."},
            {"t": "Cıva-cam", "a": "θ > 90° → cosθ < 0 → h < 0", "d": "Cıva camı ıslatmaz; kohezyon adhezyonu geçer, cıva tüpte düzeyden aşağı çöker."}
          ],
          "ans": "Cıva için θ > 90° olduğundan cosθ < 0 ve sıvı düşer (negatif kılcallık)",
          "o": ["Cıva yoğunluğu çok düşük olduğundan", "Cıvanın yüzey gerilimi sıfır olduğundan", "Cıva cam ile kimyasal tepkimeye girdiğinden", "Cıva için yer çekimi ters yönde etki ettiğinden"]
        },
        {
          "q": "Bitkilerde kılcallık hangi süreçte rol oynar?",
          "steps": [
            {"t": "Su taşınması", "a": "Kökten yaprağa su iletimi", "d": "Bitki ksilem borucukları çok ince (r ~ 20-200 μm) olduğundan kılcallık ve transpirasyon çekişiyle su yukarı taşınır."},
            {"t": "Yükseklik", "a": "Ağaçlarda 100 m'ye kadar", "d": "Kılcallık tek başına yeterli olmasa da önemli katkı sağlar."}
          ],
          "ans": "Ksilem borucuklarında suyun kökten yaprağa taşınmasına katkı sağlar",
          "o": ["Yapraklarda fotosentez sırasında CO₂ emilimine", "Meyvelerin olgunlaşma sürecine", "Kök uçlarında oksijen difüzyonuna", "Polen taşınmasına"]
        },
        {
          "q": "θ = 0° olduğunda kılcal yükselme formülü ne olur?",
          "steps": [
            {"t": "cos0°", "a": "cos0° = 1", "d": "Temas açısı sıfır olduğunda sıvı tüp duvarını tam ıslatır."},
            {"t": "Formül", "a": "h = 2γ/(ρ·g·r)", "d": "Bu, kılcal yükselmenin maksimum olduğu durumdur; cos terimi en büyük değeri 1'dir."}
          ],
          "ans": "h = 2γ/(ρ·g·r) — maksimum yükselme durumu",
          "o": ["h = γ/(ρ·g·r)", "h = 0", "h = 4γ/(ρ·g·r)", "h = γ/(2ρ·g·r)"]
        }
      ],
      "zor": [
        {
          "q": "r = 0,5 mm yarıçaplı cam tüpte su için kılcal yükselme yüksekliği kaç cm'dir? (γ = 0,072 N/m, θ = 0°, ρ = 1000 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Veri", "a": "r = 5×10⁻⁴ m, cos0° = 1", "d": "θ = 0° tam ıslatma varsayımı; birimler SI'ya çevrildi."},
            {"t": "Hesap", "a": "h = 2 × 0,072 / (1000 × 10 × 5×10⁻⁴)", "d": "h = 0,144 / 5 = 0,0288 m"},
            {"t": "Sonuç", "a": "h = 2,88 cm", "d": "0,0288 m × 100 = 2,88 cm."}
          ],
          "ans": "2,88 cm",
          "o": ["1,44 cm", "5,76 cm", "0,288 cm", "28,8 cm"]
        },
        {
          "q": "r₁ = 0,4 mm tüpte h₁ = 3,6 cm ise aynı sıvı r₂ = 1,2 mm tüpte h₂ kaç cm yükselir?",
          "steps": [
            {"t": "Ters orantı", "a": "h ∝ 1/r → h₁·r₁ = h₂·r₂", "d": "h = 2γcosθ/(ρgr) formülünde sabit değerler çarpıldığında h·r = sabit."},
            {"t": "Hesap", "a": "h₂ = h₁·r₁/r₂ = 3,6 × 0,4/1,2", "d": "h₂ = 3,6 × 0,333... = 1,2 cm"},
            {"t": "Sonuç", "a": "h₂ = 1,2 cm", "d": "Yarıçap 3 katına çıkınca yükseklik 3'te birine düşer."}
          ],
          "ans": "1,2 cm",
          "o": ["10,8 cm", "0,4 cm", "2,4 cm", "3,6 cm"]
        },
        {
          "q": "Cıva için θ = 140°, γ = 0,485 N/m, ρ = 13600 kg/m³ ve r = 1 mm'lik cam tüpte kılcal çökme miktarı kaç mm'dir? (cos140° ≈ -0,766, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "h = 2γ·cosθ/(ρ·g·r)", "d": "cosθ negatif olduğundan h negatif çıkacak (çökme)."},
            {"t": "Hesap", "a": "h = 2 × 0,485 × (-0,766) / (13600 × 10 × 0,001)", "d": "h = -0,7430 / 136 ≈ -0,00546 m"},
            {"t": "Sonuç", "a": "h ≈ 5,46 mm çöker", "d": "Negatif işaret çökmeyi ifade eder; büyüklük ≈ 5,46 mm."}
          ],
          "ans": "≈ 5,46 mm (aşağı çöker)",
          "o": ["5,46 mm yükselir", "2,73 mm çöker", "10,92 mm çöker", "0,546 mm çöker"]
        }
      ]
    }
  },
  "meniskus": {
    "lise": {
      "kolay": [
        {
          "q": "Su cam tüpte hangi şekilde menisküs oluşturur?",
          "steps": [
            {"t": "Adhezyon > Kohezyon", "a": "Su camı ıslatır", "d": "Su molekülleri cam yüzeyine çekilir; kenarlar daha yüksek, orta daha alçak olur."},
            {"t": "Şekil", "a": "Konkav (içbükey)", "d": "Yüzey, tıpkı bir kâse gibi içe doğru eğimlidir; temas açısı θ < 90°."}
          ],
          "ans": "Konkav (içbükey) menisküs",
          "o": ["Konveks (dışbükey) menisküs", "Düz yüzey", "Dalgalı yüzey", "Eliptik yüzey"]
        },
        {
          "q": "Cıva cam tüpte hangi şekilde menisküs oluşturur?",
          "steps": [
            {"t": "Kohezyon > Adhezyon", "a": "Cıva camı ıslatmaz", "d": "Cıva molekülleri birbirini cam moleküllerinden daha kuvvetli çeker; kenarlarda sıvı düşer, orta yükselir."},
            {"t": "Şekil", "a": "Konveks (dışbükey)", "d": "Yüzey dışa doğru kabarır; temas açısı θ > 90° (≈ 140°)."}
          ],
          "ans": "Konveks (dışbükey) menisküs",
          "o": ["Konkav (içbükey) menisküs", "Düz yüzey", "Dalgalı yüzey", "Yatay düzlem"]
        },
        {
          "q": "Mezür (dereceli silindir) ile hacim ölçümü yaparken su menisküsünün neresinden okuma yapılır?",
          "steps": [
            {"t": "Konkav menisküs", "a": "Altta kavisli yüzey", "d": "Su konkav menisküs oluşturduğundan en alçak noktadan (menisküs dibi) okuma yapılır."},
            {"t": "Okuma hatası", "a": "Üstten okursan hata artar", "d": "Gözü menisküsün alt sınırıyla aynı hizaya getirmek doğru ölçüm için gereklidir."}
          ],
          "ans": "Menisküsün en alt noktasından (konkav tabanından)",
          "o": ["Menisküsün en üst noktasından", "Menisküsün orta değerinden", "Tüpün dış kenarından", "Her ikisinin ortalaması alınarak"]
        },
        {
          "q": "Suyun cam tüpte konkav menisküs oluşturmasının temel nedeni nedir?",
          "steps": [
            {"t": "Kuvvet karşılaştırması", "a": "F_adhezyon > F_kohezyon", "d": "Su-cam adhezyon kuvveti, su-su kohezyon kuvvetinden büyük olduğundan su cam yüzeyine çekilir."},
            {"t": "Yüzey eğimi", "a": "Kenarlar yükselir, orta düşer", "d": "Cam yüzeyine yakın su molekülleri yukarı çekildiğinden menisküs konkav şeklini alır."}
          ],
          "ans": "Su-cam adhezyonu su-su kohezyon kuvvetinden büyük olduğundan",
          "o": ["Su-su kohezyon kuvveti su-cam adhezyonundan büyük olduğundan", "Camın elektrik yüklü olmasından", "Suyun yoğunluğunun camdan küçük olmasından", "Yer çekiminin yatay bileşeni olmasından"]
        },
        {
          "q": "Cıvanın cam tüpte konveks menisküs oluşturmasının temel nedeni nedir?",
          "steps": [
            {"t": "Kuvvet karşılaştırması", "a": "F_kohezyon > F_adhezyon", "d": "Cıva-cıva kohezyon kuvveti, cıva-cam adhezyon kuvvetinden büyüktür."},
            {"t": "Sonuç", "a": "Cıva camdan uzaklaşır", "d": "Cıva cam yüzeyini ıslatmaz; ortada kabarık bir yüzey oluşur."}
          ],
          "ans": "Cıva-cıva kohezyon kuvveti cıva-cam adhezyonundan büyük olduğundan",
          "o": ["Cıva-cam adhezyonu kohezyon kuvvetinden büyük olduğundan", "Cıvanın yoğunluğunun çok yüksek olmasından", "Cıvanın sıvı metal olmasından", "Cıvanın ışığı yansıtmasından"]
        }
      ],
      "zor": [
        {
          "q": "Bir mezürde su menisküsünün alt noktası 24,0 mL, üst noktası 24,6 mL'yi gösteriyor. Doğru hacim okuması kaç mL'dir ve ölçüm hatası nedir?",
          "steps": [
            {"t": "Doğru okuma", "a": "Alt noktadan: 24,0 mL", "d": "Su konkav menisküs oluşturduğundan alt noktadan okunur."},
            {"t": "Hata", "a": "Üst noktadan okursa +0,6 mL hata", "d": "Üst noktadan okumak 24,6 mL verir; bu 0,6 mL pozitif hata demektir."},
            {"t": "Sonuç", "a": "Doğru: 24,0 mL; hata: +0,6 mL", "d": "Gözü menisküs tabanıyla aynı hizaya getirmek hatayı sıfırlar."}
          ],
          "ans": "24,0 mL; üstten okursa +0,6 mL hata oluşur",
          "o": ["24,3 mL; hata ±0,3 mL", "24,6 mL; hata yok", "23,4 mL; hata -0,6 mL", "24,0 mL; hata 0,06 mL"]
        },
        {
          "q": "Bir sıvının cam tüpte temas açısı θ = 45° ise (cos45° = √2/2 ≈ 0,707) ve γ = 0,050 N/m, r = 0,5 mm, ρ = 900 kg/m³, g = 10 m/s² için kılcal yükselme kaç cm'dir?",
          "steps": [
            {"t": "Formül", "a": "h = 2γ·cosθ/(ρ·g·r)", "d": "Tüm değerler SI biriminde."},
            {"t": "Hesap", "a": "h = 2 × 0,050 × 0,707 / (900 × 10 × 0,0005)", "d": "h = 0,0707 / 4,5 ≈ 0,01571 m"},
            {"t": "Sonuç", "a": "h ≈ 1,57 cm", "d": "0,01571 m × 100 ≈ 1,57 cm."}
          ],
          "ans": "≈ 1,57 cm",
          "o": ["3,14 cm", "0,785 cm", "7,07 cm", "0,157 cm"]
        },
        {
          "q": "r = 0,8 mm cam tüpte su (γ = 0,072 N/m, θ = 0°, ρ = 1000 kg/m³, g = 10 m/s²) ne kadar yükselir? Aynı tüpte cıva (γ = 0,485 N/m, θ = 140°, ρ = 13600 kg/m³) ne kadar çöker? (cos140° ≈ -0,766)",
          "steps": [
            {"t": "Su yükselmesi", "a": "h_su = 2×0,072/(1000×10×8×10⁻⁴) = 0,144/8 = 0,018 m = 1,8 cm", "d": "Su r = 0,8 mm tüpte 1,8 cm yükselir."},
            {"t": "Cıva çökmesi", "a": "h_Hg = 2×0,485×(-0,766)/(13600×10×8×10⁻⁴)", "d": "h_Hg = -0,7430/108,8 ≈ -0,00683 m ≈ -6,83 mm"},
            {"t": "Sonuç", "a": "Su 1,8 cm yükselir; cıva ≈ 6,8 mm çöker", "d": "İşaret farkı yükselme ve çökmeyi gösterir."}
          ],
          "ans": "Su 1,8 cm yükselir; cıva ≈ 6,8 mm çöker",
          "o": ["Su 0,9 cm yükselir; cıva 3,4 mm çöker", "Su 3,6 cm yükselir; cıva 13,6 mm çöker", "Su 1,8 cm çöker; cıva 6,8 mm yükselir", "Her ikisi de 1,8 cm yükselir"]
        }
      ]
    }
  },
  "katiBasinc": {
    "lise": {
      "kolay": [
        {
          "q": "Basınç formülü nedir ve birimi nedir?",
          "steps": [
            {"t": "Formül", "a": "P = F/A", "d": "P basınç, F yüzeye dik uygulanan kuvvet (N), A temas alanıdır (m²)."},
            {"t": "Birim", "a": "Pa = N/m²", "d": "Pascal (Pa), SI basınç birimidir; 1 Pa = 1 N/m²."}
          ],
          "ans": "P = F/A; birimi Pa (Pascal = N/m²)",
          "o": ["P = F×A; birimi N·m²", "P = A/F; birimi m²/N", "P = F/A; birimi J/m", "P = F²/A; birimi N²/m²"]
        },
        {
          "q": "Kar ayakkabısı giymek neden karda batmayı azaltır?",
          "steps": [
            {"t": "P = F/A", "a": "Alan artınca basınç azalır", "d": "Kar ayakkabısı temas alanını artırır; aynı ağırlık daha büyük alana yayıldığından birim alana düşen kuvvet (basınç) azalır."},
            {"t": "Sonuç", "a": "P azalır → kar daha az sıkışır", "d": "Düşük basınç, karın yüzeyinin daha az baskılanmasına yol açar."}
          ],
          "ans": "Temas alanını artırarak birim alana düşen kuvveti (basıncı) azaltır",
          "o": ["Ağırlığı azaltır", "Kara ısı iletimini artırır", "Karın yapısını değiştirir", "Sürtünmeyi tamamen ortadan kaldırır"]
        },
        {
          "q": "Keskin bıçak neden daha iyi keser?",
          "steps": [
            {"t": "P = F/A", "a": "Alan azalınca basınç artar", "d": "Keskin bıçak çok küçük temas alanına sahiptir; aynı kuvvette çok yüksek basınç oluşur."},
            {"t": "Kesme", "a": "Yüksek P → maddeye daha kolay nüfuz", "d": "Küçük alan büyük basınç demektir; madde daha az kuvvetle kesilir."}
          ],
          "ans": "Keskin bıçak çok küçük temas alanına sahip olduğundan aynı kuvvette çok büyük basınç oluşturur",
          "o": ["Keskin bıçak daha hafiftir", "Keskin bıçak sürtünmeyi artırır", "Keskin bıçak daha büyük alana sahiptir", "Keskin bıçak farklı bir metal alaşımından yapılır"]
        },
        {
          "q": "1 atm kaç Pa'dır?",
          "steps": [
            {"t": "Standart atmosfer", "a": "1 atm = 101325 Pa", "d": "Deniz seviyesindeki ortalama atmosfer basıncı 101 325 Pa olarak tanımlanmıştır."},
            {"t": "Yaklaşık", "a": "≈ 10⁵ Pa = 100 kPa", "d": "Hesaplamalarda çoğunlukla 1 atm ≈ 1,013 × 10⁵ Pa kullanılır."}
          ],
          "ans": "101325 Pa (≈ 1,013 × 10⁵ Pa)",
          "o": ["1000 Pa", "9800 Pa", "13600 Pa", "760 Pa"]
        },
        {
          "q": "Raptiye (toplu iğne) neden kolayca tahta yüzeye girer?",
          "steps": [
            {"t": "Küçük uç alanı", "a": "A çok küçük → P çok büyük", "d": "Raptiye ucunun alanı çok küçüktür; parmakla uygulanan küçük kuvvet bile büyük basınç oluşturur."},
            {"t": "Geniş baş", "a": "Parmak tarafında büyük alan", "d": "Parmak temas ettiği geniş başta düşük basınç hisseder; uçta ise çok yüksek basınç oluşur."}
          ],
          "ans": "Ucunun temas alanı çok küçük olduğundan küçük kuvvetle bile yüksek basınç oluşturur",
          "o": ["Ucu çok ağır olduğundan", "Tahta yüzeyi ısıttığından", "Raptiye manyetik özellik taşıdığından", "Ucunun alanı büyük olduğundan"]
        }
      ],
      "zor": [
        {
          "q": "Kütlesi 60 kg olan bir kişi kar ayakkabısı giyiyor. Her bir ayakkabının taban alanı 0,03 m² ise iki ayakla karda oluşan basınç kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "Ağırlık", "a": "F = m·g = 60 × 10 = 600 N", "d": "Kişinin ağırlığı yerçekimi ivmesiyle çarpılır."},
            {"t": "Toplam alan", "a": "A = 2 × 0,03 = 0,06 m²", "d": "İki ayak birlikte 0,06 m² alan oluşturur."},
            {"t": "Basınç", "a": "P = 600/0,06 = 10000 Pa", "d": "P = F/A = 600/0,06 = 10 000 Pa = 10 kPa."}
          ],
          "ans": "10 000 Pa (10 kPa)",
          "o": ["20 000 Pa", "5 000 Pa", "600 Pa", "1 000 Pa"]
        },
        {
          "q": "Bir raptiyenin ucunun temas alanı A = 1 mm² = 1 × 10⁻⁶ m² ve parmakla uygulanan kuvvet F = 10 N ise raptiye ucundaki basınç kaç MPa'dır?",
          "steps": [
            {"t": "Formül", "a": "P = F/A", "d": "F = 10 N, A = 1 × 10⁻⁶ m² değerleri yerine koyulur."},
            {"t": "Hesap", "a": "P = 10 / (1×10⁻⁶) = 10⁷ Pa", "d": "10 000 000 Pa = 10 MPa."},
            {"t": "Sonuç", "a": "P = 10 MPa", "d": "Bu değer atmosfer basıncının yaklaşık 100 katıdır."}
          ],
          "ans": "10 MPa",
          "o": ["1 MPa", "100 MPa", "0,1 MPa", "10 kPa"]
        },
        {
          "q": "Aynı F = 120 N kuvvet; A₁ = 0,04 m² ve A₂ = 0,002 m² alanlara uygulanıyor. P₁ ve P₂ farkı kaç Pa'dır?",
          "steps": [
            {"t": "P₁", "a": "P₁ = 120/0,04 = 3000 Pa", "d": "Büyük alana uygulanan kuvvet düşük basınç verir."},
            {"t": "P₂", "a": "P₂ = 120/0,002 = 60 000 Pa", "d": "Küçük alana uygulanan aynı kuvvet çok yüksek basınç verir."},
            {"t": "Fark", "a": "ΔP = 60 000 - 3000 = 57 000 Pa", "d": "Alan 20 kat azalınca basınç 20 kat artar; fark 57 000 Pa = 57 kPa."}
          ],
          "ans": "57 000 Pa (57 kPa)",
          "o": ["60 000 Pa", "3 000 Pa", "30 000 Pa", "63 000 Pa"]
        }
      ]
    }
  },
  "siviBasinci": {
    "lise": {
      "kolay": [
        {
          "q": "Durgun sıvı basıncı formülü nedir ve hangi değişkenlere bağlıdır?",
          "steps": [
            {"t": "Formül", "a": "P = ρ·g·h", "d": "ρ sıvı yoğunluğu (kg/m³), g yerçekimi ivmesi (m/s²), h sıvı yüzeyinden derinlik (m)."},
            {"t": "Bağımsız", "a": "Kap şekli etkisizdir", "d": "Basınç yalnızca h, ρ ve g'ye bağlıdır; kabın biçimi ve yatay konum önemli değildir."}
          ],
          "ans": "P = ρ·g·h; yoğunluk, yer çekimi ivmesi ve derinliğe bağlıdır",
          "o": ["P = m·g/V; kütle ve hacme bağlıdır", "P = F·h; kuvvet ve derinliğe bağlıdır", "P = ρ·g·V; yoğunluk ve hacme bağlıdır", "P = ρ·h²; derinlik karesine bağlıdır"]
        },
        {
          "q": "Aynı derinlikte durgun sıvı basıncı hangi yönde eşit büyüklüktedir?",
          "steps": [
            {"t": "İzotropik", "a": "Her yönde eşit", "d": "Durgun sıvıda bir noktadaki basınç büyüklüğü her yönde (yukarı, aşağı, yatay) aynıdır."}
          ],
          "ans": "Aynı derinlikte her yönde eşittir",
          "o": ["Yalnızca aşağı yönde", "Yalnızca yatay yönde", "Yalnızca yukarı yönde", "Yalnızca kabın tabanına doğru"]
        },
        {
          "q": "Sıvı basıncı kabın şeklinden bağımsız mıdır?",
          "steps": [
            {"t": "P = ρ·g·h", "a": "Formülde kap şekli yer almaz", "d": "Derinlik, yoğunluk ve g etkili; kap şekli basıncı değiştirmez (hidrostatik paradoks)."}
          ],
          "ans": "Evet, kap şeklinden bağımsızdır; yalnızca h, ρ ve g'ye bağlıdır",
          "o": ["Hayır, geniş kap daha fazla basınç oluşturur", "Hayır, dar kap daha fazla basınç oluşturur", "Basınç hem derinliğe hem kap şekline bağlıdır", "Basınç kabın ağırlığına bağlıdır"]
        },
        {
          "q": "Sıvıda yatay konumda hareket ederken (derinlik sabit) basınç nasıl değişir?",
          "steps": [
            {"t": "h sabit", "a": "P değişmez", "d": "P = ρ·g·h formülünde h sabit ise P sabit kalır; yatay konum basıncı etkilemez."}
          ],
          "ans": "Değişmez; basınç yatay konumdan bağımsızdır",
          "o": ["Artar; sıvı içinde ilerledikçe basınç artar", "Azalır; uzaklaştıkça basınç düşer", "Önce artar sonra azalır", "Yatay harekette basınç yarıya iner"]
        },
        {
          "q": "Deniz yüzeyinden 10 m derinlikte suyun oluşturduğu basınç kaç Pa'dır? (ρ = 1000 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "P = ρ·g·h = 1000 × 10 × 10", "d": "Değerler yerine konulur."},
            {"t": "Sonuç", "a": "P = 100 000 Pa = 100 kPa ≈ 1 atm", "d": "10 m derinlik yaklaşık 1 atm'ye karşılık gelir."}
          ],
          "ans": "100 000 Pa (100 kPa)",
          "o": ["10 000 Pa", "1 000 000 Pa", "50 000 Pa", "200 000 Pa"]
        }
      ],
      "zor": [
        {
          "q": "ρ = 800 kg/m³ olan yağın 25 cm derinliğinde oluşturduğu basınç kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "h", "a": "h = 0,25 m", "d": "25 cm = 0,25 m"},
            {"t": "Hesap", "a": "P = 800 × 10 × 0,25 = 2000 Pa", "d": ""},
            {"t": "Sonuç", "a": "P = 2000 Pa", "d": ""}
          ],
          "ans": "2000 Pa",
          "o": ["1000 Pa", "4000 Pa", "20 000 Pa", "800 Pa"]
        },
        {
          "q": "Su dolu bir kabın tabanında P = 30 000 Pa ölçüldü. ρ = 1000 kg/m³, g = 10 m/s² ise suyun derinliği kaç m'dir?",
          "steps": [
            {"t": "Formül", "a": "h = P/(ρ·g)", "d": "P = ρ·g·h denkleminden h çekilir."},
            {"t": "Hesap", "a": "h = 30 000/(1000 × 10) = 3 m", "d": ""},
            {"t": "Sonuç", "a": "h = 3 m", "d": ""}
          ],
          "ans": "3 m",
          "o": ["1,5 m", "6 m", "30 m", "0,3 m"]
        },
        {
          "q": "ρ₁ = 1000 kg/m³ su (20 cm) ve ρ₂ = 800 kg/m³ yağ (15 cm) üst üste bulunuyor. Kabın tabanındaki toplam basınç kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "Su basıncı", "a": "P₁ = 1000 × 10 × 0,20 = 2000 Pa", "d": ""},
            {"t": "Yağ basıncı", "a": "P₂ = 800 × 10 × 0,15 = 1200 Pa", "d": ""},
            {"t": "Toplam", "a": "P = 2000 + 1200 = 3200 Pa", "d": "Sıvı katmanlarının basınçları toplanır."}
          ],
          "ans": "3200 Pa",
          "o": ["2000 Pa", "1200 Pa", "4000 Pa", "2800 Pa"]
        }
      ]
    }
  },
  "bilesikKaplar": {
    "lise": {
      "kolay": [
        {
          "q": "Bileşik kaplarda aynı sıvıyla dolu birbirine bağlı kapların sıvı seviyeleri nasıl olur?",
          "steps": [
            {"t": "Pascal ilkesi", "a": "Taban basınçları eşit → seviyeler eşit", "d": "Birbirine bağlı kaplarda aynı sıvının tabanındaki basınç eşit olduğundan sıvı seviyeleri aynı yükseklikte dengede durur."}
          ],
          "ans": "Kabın şeklinden bağımsız olarak aynı seviyede dengede olur",
          "o": ["Geniş kapta daha yüksek olur", "Dar kapta daha yüksek olur", "Ağır kaptan sığ kaba geçer", "Eğik konumdaki kaba doğru akar"]
        },
        {
          "q": "Birbirine bağlı iki kaba farklı sıvılar doldurulduğunda denge koşulu nedir?",
          "steps": [
            {"t": "Basınç eşitliği", "a": "ρ₁·g·h₁ = ρ₂·g·h₂", "d": "Bağlantı noktasında her iki sıvının basıncı eşit olmalı; g sadeleşince ρ₁·h₁ = ρ₂·h₂ elde edilir."}
          ],
          "ans": "ρ₁·h₁ = ρ₂·h₂ (bağlantı noktasında basınçlar eşit)",
          "o": ["h₁ = h₂ (seviyeler eşit)", "ρ₁ = ρ₂ (yoğunluklar eşit)", "V₁ = V₂ (hacimler eşit)", "m₁ = m₂ (kütleler eşit)"]
        },
        {
          "q": "Hidrolik pres hangi ilkeye dayanır ve nasıl çalışır?",
          "steps": [
            {"t": "Pascal ilkesi", "a": "Kapalı sıvıda basınç her yöne eşit iletilir", "d": "Küçük pistona uygulanan basınç büyük pistona eksiksiz iletilir; büyük alanlı pistonda büyük kuvvet elde edilir."},
            {"t": "Formül", "a": "F₁/A₁ = F₂/A₂", "d": "Basınç eşitliğinden büyük kuvvet elde edilir."}
          ],
          "ans": "Pascal ilkesi: P = F₁/A₁ = F₂/A₂; küçük kuvvetle büyük kuvvet üretilir",
          "o": ["Archimedes ilkesi: kaldırma kuvveti eşit aktarılır", "Bernoulli ilkesi: hız artınca basınç düşer", "Boyle yasası: P·V = sabit", "Newton 3. yasası: etki-tepki çifti"]
        },
        {
          "q": "Aynı sıvıyla dolu U borucuğunun sol kolunda su seviyesi h = 20 cm ise sağ koldaki su seviyesi kaç cm'dir?",
          "steps": [
            {"t": "Aynı sıvı", "a": "Seviyeler eşit olur", "d": "Aynı sıvı dolu birbirine bağlı kaplarda sıvı seviyeleri her zaman eşit dengede durur."}
          ],
          "ans": "20 cm (seviyeler eşit)",
          "o": ["10 cm", "40 cm", "30 cm", "Hesaplanamaz"]
        },
        {
          "q": "Hidrolik frende küçük pistonun alanı A₁ = 10 cm², büyük pistonun alanı A₂ = 50 cm²'dir. F₁ = 100 N uygulandığında F₂ kaç N'dur?",
          "steps": [
            {"t": "Basınç eşitliği", "a": "P = F₁/A₁ = F₂/A₂", "d": "F₂ = F₁ × A₂/A₁"},
            {"t": "Hesap", "a": "F₂ = 100 × 50/10 = 500 N", "d": "Alan 5 kat büyük olduğundan kuvvet 5 kat artar."}
          ],
          "ans": "500 N",
          "o": ["100 N", "1000 N", "250 N", "50 N"]
        }
      ],
      "zor": [
        {
          "q": "U borusunda sol kolda su (ρ₁ = 1000 kg/m³) h₁ = 12 cm, sağ kolda yağ h₂ = 15 cm yüksekliğindedir. Yağın yoğunluğu kaç kg/m³'tür?",
          "steps": [
            {"t": "Denge", "a": "ρ₁·h₁ = ρ₂·h₂", "d": "Bağlantı noktasında basınçlar eşit."},
            {"t": "ρ₂", "a": "ρ₂ = 1000 × 0,12 / 0,15 = 800 kg/m³", "d": ""},
            {"t": "Sonuç", "a": "ρ₂ = 800 kg/m³", "d": ""}
          ],
          "ans": "800 kg/m³",
          "o": ["1200 kg/m³", "600 kg/m³", "1000 kg/m³", "400 kg/m³"]
        },
        {
          "q": "Hidrolik sistemde A₁ = 5 cm², A₂ = 200 cm²'dir. Büyük pistonda F₂ = 8000 N elde etmek için F₁ kaç N olmalıdır?",
          "steps": [
            {"t": "Formül", "a": "F₁ = F₂ × A₁/A₂", "d": "Basınç eşitliğinden F₁ çekilir."},
            {"t": "Hesap", "a": "F₁ = 8000 × 5/200 = 200 N", "d": ""},
            {"t": "Sonuç", "a": "F₁ = 200 N", "d": ""}
          ],
          "ans": "200 N",
          "o": ["400 N", "100 N", "1600 N", "40 N"]
        },
        {
          "q": "U borusunda sol kolda su (ρ = 1000 kg/m³) h_su = 13,6 cm, sağ kolda cıva (ρ = 13 600 kg/m³) bulunuyor. Denge için cıva kolundaki yükseklik kaç cm'dir?",
          "steps": [
            {"t": "Denge", "a": "ρ_su·h_su = ρ_Hg·h_Hg", "d": ""},
            {"t": "h_Hg", "a": "h_Hg = 1000 × 0,136 / 13 600 = 0,01 m = 1 cm", "d": ""},
            {"t": "Sonuç", "a": "h_Hg = 1 cm", "d": "Cıva çok yoğun olduğundan çok daha az yükselir."}
          ],
          "ans": "1 cm",
          "o": ["13,6 cm", "6,8 cm", "2 cm", "0,1 cm"]
        }
      ]
    }
  },
  "hidrostatik": {
    "lise": {
      "kolay": [
        {
          "q": "Sıvı içinde iple asılı duran cisme etki eden kuvvetler ve denge koşulu nedir?",
          "steps": [
            {"t": "Kuvvetler", "a": "T + F_k = W (ağırlık)", "d": "Cisim dengede; yukarı yönlü T (ip) ve F_k (kaldırma) toplamı ağırlığa eşit."},
            {"t": "İp gerilmesi", "a": "T = W − F_k = mg − ρ_sıvı·V·g", "d": "Kaldırma kuvveti ağırlığı azaltır; ip bu farkı taşır."}
          ],
          "ans": "T + F_k = W → T = mg − ρ_sıvı·V·g",
          "o": ["T = W + F_k", "T = F_k − W", "F_k = W + T", "T = mg + ρ_sıvı·V·g"]
        },
        {
          "q": "U borusunda ρ₁·h₁ = ρ₂·h₂ eşitliği ne zaman kullanılır?",
          "steps": [
            {"t": "Koşul", "a": "Farklı sıvılar, birbirine bağlı kaplar", "d": "Her iki kolda farklı yoğunluklu sıvılar dengede olduğunda bağlantı noktasındaki basınç eşitliğinden türetilir."}
          ],
          "ans": "Birbirine bağlı kaplarda farklı yoğunluklu sıvılar denge halinde olduğunda",
          "o": ["Aynı sıvıyla dolu kaplarda", "Sıvı akarken", "Kaldırma kuvveti hesabında", "Katı basıncı hesabında"]
        },
        {
          "q": "Archimedes ilkesine göre kaldırma kuvveti formülü nedir?",
          "steps": [
            {"t": "İlke", "a": "F_k = ρ_sıvı·V_batık·g", "d": "Sıvıya batırılan cisim, yerinden ettiği sıvı ağırlığına eşit kaldırma kuvveti alır."}
          ],
          "ans": "F_k = ρ_sıvı·V_batık·g",
          "o": ["F_k = ρ_cisim·V·g", "F_k = m_cisim·g", "F_k = ρ_sıvı·V·g²", "F_k = (ρ_sıvı − ρ_cisim)·g"]
        },
        {
          "q": "Sıvı içindeki cismin görünür ağırlığı neden gerçek ağırlığından azdır?",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_k yukarı yönde", "d": "Sıvı yukarı yönlü kaldırma kuvveti uygular; bu kuvvet görünür ağırlığı azaltır."},
            {"t": "Formül", "a": "W_görünür = W − F_k", "d": "Görünür ağırlık her zaman gerçek ağırlıktan azdır."}
          ],
          "ans": "Sıvının uyguladığı yukarı yönlü kaldırma kuvveti (F_k) ağırlığı azaltır",
          "o": ["Sıvı içinde yerçekimi azalır", "Cismin kütlesi sıvıda değişir", "Sıvı cismi sıkıştırdığı için küçülür", "Ağırlık yalnızca havada ölçülebilir"]
        },
        {
          "q": "Cisim sıvıya tamamen batırıldığında kaldırma kuvveti neye bağlıdır?",
          "steps": [
            {"t": "Formül", "a": "F_k = ρ_sıvı·V_cisim·g", "d": "Tam batık halde V_batık = V_cisim; F_k sıvı yoğunluğuna ve cismin toplam hacmine bağlıdır."},
            {"t": "Bağımsız", "a": "Cisim yoğunluğu F_k'yi etkilemez", "d": "Aynı hacimde farklı yoğunluklu cisimler aynı F_k alır."}
          ],
          "ans": "Sıvının yoğunluğuna (ρ_sıvı) ve cismin hacmine (V) bağlıdır",
          "o": ["Yalnızca cismin kütlesine bağlıdır", "Cismin yoğunluğuna ve hacmine bağlıdır", "Sıvının kütlesi ve derinliğe bağlıdır", "Cismin ağırlığına eşittir"]
        }
      ],
      "zor": [
        {
          "q": "m = 500 g, V = 200 cm³ olan cisim su (ρ = 1000 kg/m³) içine tamamen batırılıyor. İpteki gerilme kaç N'dur? (g = 10 m/s²)",
          "steps": [
            {"t": "Ağırlık", "a": "W = 0,5 × 10 = 5 N", "d": ""},
            {"t": "Kaldırma", "a": "F_k = 1000 × 200 × 10⁻⁶ × 10 = 2 N", "d": "V = 200 cm³ = 2 × 10⁻⁴ m³"},
            {"t": "Gerilme", "a": "T = 5 − 2 = 3 N", "d": ""}
          ],
          "ans": "3 N",
          "o": ["5 N", "2 N", "7 N", "1 N"]
        },
        {
          "q": "U borusunda sol kolda yağ (ρ = 800 kg/m³) h₁ = 10 cm, sağ kolda cıva (ρ = 13 600 kg/m³) var. Denge için cıva yüksekliği kaç cm'dir?",
          "steps": [
            {"t": "Denge", "a": "800 × 0,10 = 13 600 × h₂", "d": ""},
            {"t": "h₂", "a": "h₂ = 80/13 600 ≈ 5,88 × 10⁻³ m ≈ 0,59 cm", "d": ""},
            {"t": "Sonuç", "a": "≈ 0,59 cm", "d": "Cıva çok yoğun olduğundan çok az yükselir."}
          ],
          "ans": "≈ 0,59 cm",
          "o": ["≈ 1,18 cm", "≈ 10,0 cm", "≈ 5,88 cm", "≈ 0,29 cm"]
        },
        {
          "q": "Havada ağırlığı 6 N olan cisim ρ = 1200 kg/m³ sıvıya tamamen batırılınca dinamometre 2 N gösteriyor. Cismin hacmi kaç cm³'tür? (g = 10 m/s²)",
          "steps": [
            {"t": "F_k", "a": "F_k = 6 − 2 = 4 N", "d": "Kaldırma kuvveti görünür ağırlık farkından bulunur."},
            {"t": "Hacim", "a": "V = F_k/(ρ·g) = 4/(1200 × 10) = 3,33 × 10⁻⁴ m³", "d": ""},
            {"t": "cm³", "a": "V = 333 cm³", "d": "1 m³ = 10⁶ cm³"}
          ],
          "ans": "≈ 333 cm³",
          "o": ["167 cm³", "500 cm³", "400 cm³", "250 cm³"]
        }
      ]
    }
  },
  "toricelli": {
    "lise": {
      "kolay": [
        {
          "q": "Torricelli deneyi nedir ve 1 atm basınca karşılık gelen cıva sütunu yüksekliği nedir?",
          "steps": [
            {"t": "Deney", "a": "Cıvalı tüpü ters çevirme", "d": "Cıva dolu kapalı tüp bir kaba ters çevrilir; cıva sütunu atmosfer basıncıyla denge kurana kadar alçalır."},
            {"t": "Değer", "a": "h = 76 cm cıva = 1 atm", "d": "Standart koşullarda atmosfer basıncı 76 cm cıva sütununa eşittir."}
          ],
          "ans": "76 cm cıva sütunu (760 mm Hg) = 1 atm",
          "o": ["100 cm cıva", "13,6 cm cıva", "1 cm cıva", "101,3 cm cıva"]
        },
        {
          "q": "Torricelli deneyi su ile yapılsaydı sütun yüksekliği ne olurdu? (ρ_Hg = 13 600 kg/m³, ρ_su = 1000 kg/m³, h_Hg = 0,76 m)",
          "steps": [
            {"t": "Denge", "a": "ρ_su·g·h_su = ρ_Hg·g·h_Hg", "d": "g sadeleşir."},
            {"t": "h_su", "a": "h_su = 13 600 × 0,76 / 1000 ≈ 10,3 m", "d": "Su çok daha az yoğun olduğundan çok daha uzun sütun gerekir."}
          ],
          "ans": "≈ 10,3 m",
          "o": ["0,76 m", "1,36 m", "76 m", "0,056 m"]
        },
        {
          "q": "Yüksek irtifaya çıkıldığında barometre neden daha düşük gösterir?",
          "steps": [
            {"t": "Hava sütunu", "a": "Yüksekte atmosfer basıncı düşer", "d": "Üst katmanlardaki hava miktarı azaldığından P_atm düşer; cıva sütunu kısalır."}
          ],
          "ans": "Yüksekte atmosfer basıncı düştüğünden cıva sütunu kısalır",
          "o": ["Yüksekte yerçekimi artar, cıvayı aşağı iter", "Yüksekte sıcaklık düştüğünden cıva büzülür", "Yüksekte nem artar, basınç düşük görünür", "Barometrenin hassasiyeti irtifayla değişir"]
        },
        {
          "q": "Torricelli tüpünün üst kısmındaki (Torricelli) boşluk ne içerir?",
          "steps": [
            {"t": "Boşluk", "a": "Neredeyse vakum", "d": "Cıva alçaldığında üst kısımda çok düşük basınçlı cıva buharı kalır; pratik olarak vakum kabul edilir."}
          ],
          "ans": "Neredeyse vakum (çok küçük cıva buhar basıncı, ≈ 0 Pa)",
          "o": ["Hava", "Su buharı", "Karbondioksit", "Azot gazı"]
        },
        {
          "q": "P_atm = ρ_Hg·g·h formülü ne anlama gelir?",
          "steps": [
            {"t": "Açıklama", "a": "Atmosfer basıncı = cıva sütununun oluşturduğu basınç", "d": "Denge halinde atmosfer basıncı, barometredeki cıva sütununun ağırlığından oluşan basınca eşittir."}
          ],
          "ans": "Atmosfer basıncı, cıva sütununun oluşturduğu basınca eşit olduğunda denge sağlanır",
          "o": ["Cıvanın yoğunluğu atmosfer basıncına eşittir", "Yükseklik artışıyla cıva yoğunluğu değişir", "Cıva sütun yüksekliği yerçekiminden bağımsızdır", "Tüp içindeki vakum basıncı cıva ağırlığına eşittir"]
        }
      ],
      "zor": [
        {
          "q": "Cıva yerine ρ = 680 kg/m³ benzin kullanılan Torricelli deneyinde sıvı sütunu kaç m yükselir? (ρ_Hg = 13 600 kg/m³, h_Hg = 0,76 m)",
          "steps": [
            {"t": "Denge", "a": "ρ_Hg·h_Hg = ρ_benzin·h_benzin", "d": "g her iki tarafta sadeleşir."},
            {"t": "h_benzin", "a": "h = 13 600 × 0,76 / 680 = 10 336/680 ≈ 15,2 m", "d": ""},
            {"t": "Sonuç", "a": "≈ 15,2 m", "d": ""}
          ],
          "ans": "≈ 15,2 m",
          "o": ["≈ 7,6 m", "≈ 30,4 m", "≈ 0,76 m", "≈ 1,52 m"]
        },
        {
          "q": "Dağın tepesinde barometre h = 70 cm Hg gösteriyor. Bu basınç kaç Pa'a karşılık gelir? (ρ_Hg = 13 600 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "P = ρ·g·h = 13 600 × 10 × 0,70", "d": "h = 70 cm = 0,70 m"},
            {"t": "Hesap", "a": "P = 95 200 Pa", "d": ""},
            {"t": "Sonuç", "a": "P = 95 200 Pa", "d": ""}
          ],
          "ans": "95 200 Pa",
          "o": ["101 325 Pa", "76 000 Pa", "952 000 Pa", "9520 Pa"]
        },
        {
          "q": "P₀ = 101 000 Pa, ρ_Hg = 13 600 kg/m³, g = 10 m/s² ise Torricelli tüpündeki cıva sütunu kaç cm'dir?",
          "steps": [
            {"t": "Formül", "a": "h = P₀/(ρ·g)", "d": "h = 101 000/(13 600 × 10)"},
            {"t": "Hesap", "a": "h = 101 000/136 000 ≈ 0,743 m", "d": ""},
            {"t": "Sonuç", "a": "≈ 74,3 cm", "d": "Standart 76 cm'den biraz farklı çünkü P₀ = 101 000 Pa alındı."}
          ],
          "ans": "≈ 74,3 cm",
          "o": ["76,0 cm", "72,0 cm", "80,0 cm", "68,5 cm"]
        }
      ]
    }
  },
  "manometre": {
    "lise": {
      "kolay": [
        {
          "q": "Açık manometre ne ölçer ve nasıl okunur?",
          "steps": [
            {"t": "Gösterge basıncı", "a": "P_gösterge = P_mutlak − P_atm", "d": "Atmosfere açık taraf referans noktasıdır; iki kol arasındaki yükseklik farkı ρ·g·Δh ile gösterge basıncını verir."}
          ],
          "ans": "Gösterge basıncını (P_mutlak − P_atm) ölçer; iki kol yükseklik farkı × ρ·g ile hesaplanır",
          "o": ["Mutlak basıncı doğrudan ölçer", "Yalnızca atmosfer basıncını ölçer", "Vakum basıncını ölçer", "Yüzey gerilimini ölçer"]
        },
        {
          "q": "Mutlak basınç, gösterge basıncı ve atmosfer basıncı arasındaki ilişki nedir?",
          "steps": [
            {"t": "Formül", "a": "P_mutlak = P_gösterge + P_atm", "d": "Mutlak basınç, gösterge basıncına atmosfer basıncı eklenerek bulunur."}
          ],
          "ans": "P_mutlak = P_gösterge + P_atm",
          "o": ["P_mutlak = P_gösterge − P_atm", "P_gösterge = P_mutlak + P_atm", "P_atm = P_mutlak × P_gösterge", "P_mutlak = P_gösterge / P_atm"]
        },
        {
          "q": "Kapalı manometre (vakum referanslı) ile açık manometre arasındaki fark nedir?",
          "steps": [
            {"t": "Açık manometre", "a": "Gösterge basıncı ölçer (atmosfer referanslı)", "d": "Bir kolu atmosfere açık; ölçülen değer P_atm'ye göreli."},
            {"t": "Kapalı manometre", "a": "Mutlak basınç ölçer (vakum referanslı)", "d": "Bir kolu kapalı ve vakumda; ölçülen değer gerçek mutlak basınçtır."}
          ],
          "ans": "Açık manometre gösterge basıncı, kapalı manometre mutlak basınç ölçer",
          "o": ["Açık mutlak, kapalı gösterge basıncı ölçer", "İkisi de aynı basıncı ölçer", "Açık vakum, kapalı atmosfer basıncını ölçer", "Kapalı manometre her zaman daha yüksek değer verir"]
        },
        {
          "q": "Manometre neden cıva gibi yoğun sıvılarla doldurulur?",
          "steps": [
            {"t": "Yüksek yoğunluk", "a": "Aynı basınç için daha kısa sütun", "d": "P = ρ·g·h; ρ büyük ise aynı basınç için h çok küçük olur. Bu da ölçümü pratik kılar."}
          ],
          "ans": "Yüksek yoğunluk sayesinde aynı basınç için daha kısa sütun yeterli; ölçüm pratiktir",
          "o": ["Cıva daha ucuzdur", "Cıva manyetik özelliği sayesinde ölçer", "Cıvanın yüzey gerilimi sıfırdır", "Cıva renksizdir; okunması kolaydır"]
        },
        {
          "q": "Bir sistemin gösterge basıncı 50 000 Pa, atmosfer basıncı 100 000 Pa ise mutlak basınç kaç Pa'dır?",
          "steps": [
            {"t": "Formül", "a": "P_mutlak = P_gösterge + P_atm", "d": ""},
            {"t": "Hesap", "a": "P_mutlak = 50 000 + 100 000 = 150 000 Pa", "d": ""}
          ],
          "ans": "150 000 Pa",
          "o": ["50 000 Pa", "100 000 Pa", "200 000 Pa", "250 000 Pa"]
        }
      ],
      "zor": [
        {
          "q": "Açık manometrenin iki kolundaki cıva yükseklik farkı Δh = 15 cm'dir. Gösterge basıncı kaç Pa'dır? (ρ_Hg = 13 600 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "P_gösterge = ρ·g·Δh", "d": "Δh = 0,15 m"},
            {"t": "Hesap", "a": "P = 13 600 × 10 × 0,15 = 20 400 Pa", "d": ""},
            {"t": "Sonuç", "a": "P_gösterge = 20 400 Pa", "d": ""}
          ],
          "ans": "20 400 Pa",
          "o": ["13 600 Pa", "40 800 Pa", "2040 Pa", "136 000 Pa"]
        },
        {
          "q": "Bir kapın içindeki gazın gösterge basıncı P_gösterge = 30 000 Pa, atmosfer basıncı P₀ = 101 000 Pa ise mutlak basınç kaç kPa'dır?",
          "steps": [
            {"t": "Formül", "a": "P_mutlak = 30 000 + 101 000 = 131 000 Pa", "d": ""},
            {"t": "kPa", "a": "131 000 Pa = 131 kPa", "d": ""},
            {"t": "Sonuç", "a": "131 kPa", "d": ""}
          ],
          "ans": "131 kPa",
          "o": ["71 kPa", "30 kPa", "101 kPa", "161 kPa"]
        },
        {
          "q": "Su manometresinde (ρ = 1000 kg/m³) iki kol arasındaki yükseklik farkı Δh = 25 cm ise gösterge basıncı kaç Pa'dır? Aynı basınç cıva manometresinde (ρ = 13 600 kg/m³) kaç cm yükseklik farkına karşılık gelir? (g = 10 m/s²)",
          "steps": [
            {"t": "Su manometresi", "a": "P = 1000 × 10 × 0,25 = 2500 Pa", "d": ""},
            {"t": "Cıva farkı", "a": "Δh_Hg = 2500/(13 600 × 10) ≈ 0,0184 m ≈ 1,84 cm", "d": ""},
            {"t": "Sonuç", "a": "P = 2500 Pa; cıva farkı ≈ 1,84 cm", "d": ""}
          ],
          "ans": "P = 2500 Pa; cıva yükseklik farkı ≈ 1,84 cm",
          "o": ["P = 2500 Pa; cıva farkı ≈ 25 cm", "P = 25 000 Pa; cıva farkı ≈ 1,84 cm", "P = 2500 Pa; cıva farkı ≈ 3,68 cm", "P = 1250 Pa; cıva farkı ≈ 0,92 cm"]
        }
      ]
    }
  },
  "kupBasinc": {
    "lise": {
      "kolay": [
        {
          "q": "Sıvıya daldırılan bir küpün üst ve alt yüzeylerine etki eden basınç kuvvetleri neden farklıdır?",
          "steps": [
            {"t": "Derinlik farkı", "a": "Alt yüzey daha derindir", "d": "P = ρ·g·h olduğundan alt yüzey daha yüksek derinlikte olup daha büyük basınca maruzdur."},
            {"t": "Net kuvvet", "a": "F_alt > F_üst → yukarı net kuvvet", "d": "Bu fark, Archimedes kaldırma kuvvetini oluşturur."}
          ],
          "ans": "Alt yüzey daha derin olduğundan daha büyük basınca maruz kalır; F_alt > F_üst",
          "o": ["Üst yüzey daha derin olduğundan daha büyük basınca maruz kalır", "İki yüzey de aynı basınca maruz kalır", "Yalnızca yan yüzeyler basınca maruz kalır", "Alt yüzeyde basınç sıfırdır"]
        },
        {
          "q": "Tamamen batık bir küpe etki eden net basınç kuvveti (kaldırma kuvveti) neye eşittir?",
          "steps": [
            {"t": "Net kuvvet", "a": "F_net = F_alt − F_üst = ρ_sıvı·g·V_cisim", "d": "F_alt ve F_üst farkı, cismin yerinden ettiği sıvı ağırlığına eşittir."}
          ],
          "ans": "F_k = ρ_sıvı·g·V_cisim (Archimedes ilkesi)",
          "o": ["F_k = ρ_cisim·g·V_cisim", "F_k = ρ_sıvı·g·A·h²", "F_k = (ρ_sıvı − ρ_cisim)·g·V", "F_k = m_cisim·g"]
        },
        {
          "q": "Sıvı içinde batan bir küpün kenar uzunluğu a, sıvı yoğunluğu ρ ise alt yüzeye etki eden kuvvet nedir? (küp tamamen batık, alt yüzey h derinlikte)",
          "steps": [
            {"t": "Alt yüzey basıncı", "a": "P_alt = ρ·g·h", "d": "Alt yüzey h derinliğindedir."},
            {"t": "Kuvvet", "a": "F_alt = P_alt × A = ρ·g·h·a²", "d": "Alt yüzey alanı a² (kenar uzunluğu a olan kare)."}
          ],
          "ans": "F_alt = ρ·g·h·a²",
          "o": ["F_alt = ρ·g·h·a³", "F_alt = ρ·g·a²", "F_alt = ρ·g·(h+a)·a", "F_alt = ρ·g·h/a²"]
        },
        {
          "q": "Kaldırma kuvveti, yalnızca batık hacme mi yoksa tam hacme mi bağlıdır?",
          "steps": [
            {"t": "F_k = ρ·V_batık·g", "a": "Yalnızca sıvıya daldırılan kısım", "d": "Cisim kısmen batıksa yalnızca sıvı içindeki hacim kaldırma kuvvetini belirler."}
          ],
          "ans": "Yalnızca sıvıya daldırılan (batık) hacme bağlıdır",
          "o": ["Cismin toplam hacmine bağlıdır", "Cismin havadaki kısmına bağlıdır", "Sıvının toplam hacmine bağlıdır", "Cismin alanına bağlıdır"]
        },
        {
          "q": "Bir küp sıvıya batırıldığında üst yüzeyine 12 N, alt yüzeyine 20 N basınç kuvveti uygulanıyor. Kaldırma kuvveti kaç N'dur?",
          "steps": [
            {"t": "Net kuvvet", "a": "F_k = F_alt − F_üst = 20 − 12 = 8 N", "d": "Alt yüzey kuvveti yukarı, üst yüzey kuvveti aşağı yönde; net kuvvet yukarı yönlüdür."}
          ],
          "ans": "8 N",
          "o": ["20 N", "12 N", "32 N", "4 N"]
        }
      ],
      "zor": [
        {
          "q": "Kenar uzunluğu a = 10 cm olan küp, su (ρ = 1000 kg/m³) içinde tamamen batık ve alt yüzeyi h = 30 cm derinlikte. Küpe etki eden net kaldırma kuvveti kaç N'dur? (g = 10 m/s²)",
          "steps": [
            {"t": "Hacim", "a": "V = (0,10)³ = 10⁻³ m³", "d": ""},
            {"t": "Kaldırma", "a": "F_k = ρ·g·V = 1000 × 10 × 10⁻³ = 10 N", "d": ""},
            {"t": "Sonuç", "a": "F_k = 10 N", "d": "Alt ve üst yüzey kuvveti farkından veya doğrudan V ile hesaplanır."}
          ],
          "ans": "10 N",
          "o": ["30 N", "5 N", "100 N", "1 N"]
        },
        {
          "q": "Kenar a = 10 cm küp, alt yüzeyi h₁ = 25 cm ve üst yüzeyi h₂ = 15 cm derinlikte batık. Su (ρ = 1000 kg/m³, g = 10 m/s²). Alt ve üst yüzeylere etki eden kuvvetler ve kaldırma kuvveti kaçtır?",
          "steps": [
            {"t": "F_alt", "a": "F_alt = ρ·g·h₁·a² = 1000 × 10 × 0,25 × 0,01 = 25 N", "d": "Alan = 0,1² = 0,01 m²"},
            {"t": "F_üst", "a": "F_üst = 1000 × 10 × 0,15 × 0,01 = 15 N", "d": ""},
            {"t": "F_k", "a": "F_k = 25 − 15 = 10 N", "d": "= ρ·g·V = 1000 × 10 × 10⁻³ = 10 N ✓"}
          ],
          "ans": "F_alt = 25 N, F_üst = 15 N, F_k = 10 N",
          "o": ["F_alt = 15 N, F_üst = 25 N, F_k = 10 N", "F_alt = 25 N, F_üst = 15 N, F_k = 40 N", "F_alt = 20 N, F_üst = 10 N, F_k = 10 N", "F_alt = 25 N, F_üst = 15 N, F_k = 5 N"]
        },
        {
          "q": "Yoğunluğu ρ_c = 600 kg/m³ ve hacmi V = 500 cm³ olan cisim su (ρ = 1000 kg/m³) içinde denge halinde yüzüyor. Cismin ne kadarı suyun altında kalır? (g = 10 m/s²)",
          "steps": [
            {"t": "Denge", "a": "F_k = W → ρ_su·V_batık·g = ρ_c·V·g", "d": "g her iki tarafta sadeleşir."},
            {"t": "V_batık", "a": "V_batık = ρ_c·V/ρ_su = 600 × 500/1000 = 300 cm³", "d": ""},
            {"t": "Oran", "a": "300/500 = 0,60 → %60'ı suyun altında", "d": ""}
          ],
          "ans": "%60'ı (300 cm³) suyun altında",
          "o": ["%40'ı suyun altında", "%50'si suyun altında", "%75'i suyun altında", "Tamamı suyun altında"]
        }
      ]
    }
  },
  "asiliDenge": {
    "lise": {
      "kolay": [
        {
          "q": "Sıvıya batırılmış bir cismin görünür ağırlığı nasıl hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "W_görünür = W − F_k = mg − ρ_sıvı·V·g", "d": "Dinamometre, kaldırma kuvveti düşüldükten sonraki ağırlığı gösterir."}
          ],
          "ans": "W_görünür = mg − ρ_sıvı·V·g",
          "o": ["W_görünür = mg + ρ_sıvı·V·g", "W_görünür = ρ_sıvı·V·g", "W_görünür = mg / ρ_sıvı", "W_görünür = mg × ρ_sıvı·V"]
        },
        {
          "q": "Havada 5 N, suda 3 N gösteren dinamometreye bakılarak kaldırma kuvveti kaç N'dur?",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_k = W_hava − W_sıvı = 5 − 3 = 2 N", "d": "Görünür ağırlık farkı kaldırma kuvvetine eşittir."}
          ],
          "ans": "2 N",
          "o": ["5 N", "3 N", "8 N", "1 N"]
        },
        {
          "q": "Cismin özgül kütlesini (yoğunluk oranını) görünür ağırlıktan nasıl buluruz?",
          "steps": [
            {"t": "Yöntem", "a": "ρ_cisim/ρ_sıvı = W_hava/(W_hava − W_sıvı)", "d": "F_k = ρ_sıvı·V·g ve W = ρ_cisim·V·g; bölünce ρ_cisim/ρ_sıvı = W/(W − W_görünür) elde edilir."}
          ],
          "ans": "ρ_cisim/ρ_sıvı = W_hava / (W_hava − W_sıvı)",
          "o": ["ρ_cisim/ρ_sıvı = W_sıvı / W_hava", "ρ_cisim/ρ_sıvı = (W_hava − W_sıvı) / W_hava", "ρ_cisim/ρ_sıvı = W_hava × W_sıvı", "ρ_cisim = ρ_sıvı × W_sıvı"]
        },
        {
          "q": "Cisim sıvıya daldırıldığında dinamometre neden daha düşük değer gösterir?",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_k yukarı yönde etki eder", "d": "Sıvının uyguladığı yukarı yönlü kaldırma kuvveti ipin taşıması gereken yükü azaltır."}
          ],
          "ans": "Sıvının yukarı yönlü kaldırma kuvveti dinamometrenin ölçtüğü yükü azaltır",
          "o": ["Cisim sıvıda küçülür", "Sıvı içinde yerçekimi azalır", "İpin uzaması ölçümü değiştirir", "Dinamometre sıvıda yanlış okur"]
        },
        {
          "q": "Havada W = 8 N, sıvıda W_görünür = 5 N olan cismin yoğunluğu, ρ_sıvı = 1000 kg/m³ ise kaç kg/m³'tür?",
          "steps": [
            {"t": "F_k", "a": "F_k = 8 − 5 = 3 N", "d": ""},
            {"t": "Oran", "a": "ρ_cisim/ρ_sıvı = W/(F_k) = 8/3 ≈ 2,67", "d": "Ayrıca ρ_c/ρ_s = W_hava/(W_hava − W_sıvı)"},
            {"t": "ρ_cisim", "a": "ρ_cisim = 2,67 × 1000 ≈ 2667 kg/m³", "d": ""}
          ],
          "ans": "≈ 2667 kg/m³",
          "o": ["1000 kg/m³", "1333 kg/m³", "3000 kg/m³", "800 kg/m³"]
        }
      ],
      "zor": [
        {
          "q": "Havada 6 N, suda (ρ = 1000 kg/m³) 4 N olan cismin hacmi ve yoğunluğu nedir? (g = 10 m/s²)",
          "steps": [
            {"t": "F_k", "a": "F_k = 6 − 4 = 2 N", "d": ""},
            {"t": "Hacim", "a": "V = F_k/(ρ·g) = 2/(1000 × 10) = 2 × 10⁻⁴ m³ = 200 cm³", "d": ""},
            {"t": "Yoğunluk", "a": "m = W/g = 6/10 = 0,6 kg; ρ = 0,6/(2 × 10⁻⁴) = 3000 kg/m³", "d": ""}
          ],
          "ans": "V = 200 cm³, ρ = 3000 kg/m³",
          "o": ["V = 400 cm³, ρ = 1500 kg/m³", "V = 100 cm³, ρ = 6000 kg/m³", "V = 200 cm³, ρ = 1500 kg/m³", "V = 600 cm³, ρ = 1000 kg/m³"]
        },
        {
          "q": "Havada 10 N, ρ₁ = 800 kg/m³ yağda 6 N olan cismin yoğunluğu kaç kg/m³'tür? (g = 10 m/s²)",
          "steps": [
            {"t": "F_k (yağda)", "a": "F_k = 10 − 6 = 4 N", "d": ""},
            {"t": "Hacim", "a": "V = F_k/(ρ₁·g) = 4/(800 × 10) = 5 × 10⁻⁴ m³", "d": ""},
            {"t": "Yoğunluk", "a": "m = 10/10 = 1 kg; ρ_c = 1/(5 × 10⁻⁴) = 2000 kg/m³", "d": ""}
          ],
          "ans": "2000 kg/m³",
          "o": ["800 kg/m³", "1000 kg/m³", "1600 kg/m³", "4000 kg/m³"]
        },
        {
          "q": "m = 300 g, V = 100 cm³ cisim ρ_sıvı = 1200 kg/m³ sıvıya tamamen batırılıyor. Dinamometrenin göstereceği değer kaç N'dur? (g = 10 m/s²)",
          "steps": [
            {"t": "Ağırlık", "a": "W = 0,3 × 10 = 3 N", "d": ""},
            {"t": "Kaldırma", "a": "F_k = 1200 × 10⁻⁴ × 10 = 1,2 N", "d": "V = 100 cm³ = 10⁻⁴ m³"},
            {"t": "Dinamometre", "a": "T = 3 − 1,2 = 1,8 N", "d": ""}
          ],
          "ans": "1,8 N",
          "o": ["3,0 N", "1,2 N", "4,2 N", "0,6 N"]
        }
      ]
    }
  },
  "ciftSivi": {
    "lise": {
      "kolay": [
        {
          "q": "Birbirine karışmayan iki sıvıda yüzen bir cisme etki eden kaldırma kuvveti nasıl hesaplanır?",
          "steps": [
            {"t": "Toplam kaldırma", "a": "F_k = ρ₁·g·V₁ + ρ₂·g·V₂", "d": "Her sıvı, cismin kendi içindeki hacmi kadar kaldırma kuvveti uygular."},
            {"t": "Denge", "a": "F_k = mg", "d": "Yüzen cisimde toplam kaldırma kuvveti ağırlığa eşittir."}
          ],
          "ans": "F_k = ρ₁·g·V₁ + ρ₂·g·V₂ = mg (denge koşulu)",
          "o": ["F_k = (ρ₁ + ρ₂)·g·V_toplam", "F_k = ρ₁·g·V_toplam", "F_k = ρ₂·g·V_toplam", "F_k = (ρ₁·ρ₂)·g·V₁"]
        },
        {
          "q": "Yağ (ρ = 800 kg/m³) ve su (ρ = 1000 kg/m³) arayüzünde bir cisim yüzüyor. Cismin hangi kısmı daha yoğun olan sıvıdadır?",
          "steps": [
            {"t": "Yoğunluk farkı", "a": "Su daha yoğun → daha güçlü kaldırma", "d": "Aynı hacim için su daha büyük kaldırma kuvveti sağlar."},
            {"t": "Konum", "a": "Cismin alt kısmı suda", "d": "Daha yoğun sıvı altta bulunur; cismin alt kısmı suda kalır."}
          ],
          "ans": "Cismin alt kısmı daha yoğun olan suyun içindedir",
          "o": ["Cismin üst kısmı suyun içindedir", "Cisim ikisi arasında eşit paylaşılır", "Cismin konumu yoğunluktan bağımsızdır", "Cisim yağ yüzeyinde tamamen yüzüyor"]
        },
        {
          "q": "ρ_cisim = 900 kg/m³, yağ ρ₁ = 800 kg/m³, su ρ₂ = 1000 kg/m³. Cisim hangi sıvıda daha az yoğun olduğunu söyler?",
          "steps": [
            {"t": "Karşılaştırma", "a": "ρ_yağ < ρ_cisim < ρ_su", "d": "Cisim yağdan yoğun, sudan az yoğun."},
            {"t": "Sonuç", "a": "Yağda batar, suda yüzer; arayüzde dengede olur", "d": "Cisim her iki sıvının arayüzünde denge bulur."}
          ],
          "ans": "Cisim yağdan yoğun ama sudan az yoğun; arayüzde bir kısım suda, bir kısım yağda durur",
          "o": ["Cisim yağda yüzer, suda batar", "Cisim her iki sıvıda da tamamen batar", "Cisim her iki sıvıda da tamamen yüzer", "Cisim suyun dibine çöker"]
        },
        {
          "q": "Birbirine karışmayan iki sıvıda yüzen cismin denge koşulu nedir?",
          "steps": [
            {"t": "Denge", "a": "F_k₁ + F_k₂ = W", "d": "Her iki sıvıdan gelen kaldırma kuvvetleri toplamı cismin ağırlığına eşit olmalıdır."},
            {"t": "Açık", "a": "ρ₁·g·V₁ + ρ₂·g·V₂ = m·g", "d": "g sadeleşirse ρ₁·V₁ + ρ₂·V₂ = m"}
          ],
          "ans": "ρ₁·V₁ + ρ₂·V₂ = m (g sadeleşince); her iki sıvının kaldırma kuvvetleri toplamı ağırlığa eşit",
          "o": ["ρ₁·V₁ = ρ₂·V₂", "V₁ = V₂", "ρ₁·V₁ = m·g", "ρ₂·V₂ = m·g"]
        },
        {
          "q": "Yağ-su arayüzündeki bir cismin yağda kalan hacmi V₁ = 60 cm³, suda kalan hacmi V₂ = 40 cm³'tür. Bu cismin ortalama yoğunluğu, ρ_yağ = 800 kg/m³ ve ρ_su = 1000 kg/m³ cinsinden nedir?",
          "steps": [
            {"t": "Denge", "a": "ρ_yağ·V₁ + ρ_su·V₂ = ρ_c·(V₁+V₂)", "d": "Toplam kaldırma = ağırlık"},
            {"t": "ρ_c", "a": "ρ_c = (800×60 + 1000×40)/(60+40) = (48000+40000)/100 = 880 kg/m³", "d": ""},
            {"t": "Sonuç", "a": "ρ_c = 880 kg/m³", "d": ""}
          ],
          "ans": "880 kg/m³",
          "o": ["900 kg/m³", "800 kg/m³", "1000 kg/m³", "840 kg/m³"]
        }
      ],
      "zor": [
        {
          "q": "m = 90 g cisim yağ (ρ₁ = 800 kg/m³) ve su (ρ₂ = 1000 kg/m³) arayüzünde yüzüyor. Toplam hacim V = 100 cm³. Cismin yağda kalan hacmi V₁ ve suda kalan hacmi V₂ kaç cm³'tür?",
          "steps": [
            {"t": "Denklem 1", "a": "V₁ + V₂ = 100 cm³", "d": "Toplam hacim"},
            {"t": "Denklem 2", "a": "800·V₁ + 1000·V₂ = 90 000 (g/cm³ × cm³ = g; m = 90 g)", "d": "Kaldırma = ağırlık; g sadeleşir"},
            {"t": "Çözüm", "a": "V₁ = 50 cm³, V₂ = 50 cm³; kontrol: 800×50+1000×50 = 90 000 ✓", "d": ""}
          ],
          "ans": "V₁ = 50 cm³ (yağda), V₂ = 50 cm³ (suda)",
          "o": ["V₁ = 60 cm³, V₂ = 40 cm³", "V₁ = 40 cm³, V₂ = 60 cm³", "V₁ = 75 cm³, V₂ = 25 cm³", "V₁ = 90 cm³, V₂ = 10 cm³"]
        },
        {
          "q": "m = 84 g, V = 100 cm³ cisim yağ (ρ₁ = 800 kg/m³ = 0,8 g/cm³) ve su (ρ₂ = 1 g/cm³) arayüzünde yüzüyor. Yağda kalan hacim kaç cm³'tür?",
          "steps": [
            {"t": "Denklem", "a": "0,8·V₁ + 1·(100−V₁) = 84", "d": "V₂ = 100 − V₁ yerine koyuldu"},
            {"t": "Çöz", "a": "0,8V₁ + 100 − V₁ = 84 → −0,2V₁ = −16 → V₁ = 80 cm³", "d": ""},
            {"t": "Sonuç", "a": "V₁ = 80 cm³ yağda, V₂ = 20 cm³ suda", "d": ""}
          ],
          "ans": "80 cm³ yağda, 20 cm³ suda",
          "o": ["20 cm³ yağda, 80 cm³ suda", "50 cm³ yağda, 50 cm³ suda", "60 cm³ yağda, 40 cm³ suda", "40 cm³ yağda, 60 cm³ suda"]
        },
        {
          "q": "Yağ (ρ₁ = 0,8 g/cm³) ve su (ρ₂ = 1 g/cm³) arayüzünde V = 200 cm³ cisim yüzüyor. Cismin %30'u yağda, %70'i suda. Cismin yoğunluğu kaç g/cm³'tür?",
          "steps": [
            {"t": "V₁, V₂", "a": "V₁ = 60 cm³, V₂ = 140 cm³", "d": "%30 yağda"},
            {"t": "Denge", "a": "m = ρ₁·V₁ + ρ₂·V₂ = 0,8×60 + 1×140 = 48 + 140 = 188 g", "d": ""},
            {"t": "ρ_c", "a": "ρ_c = 188/200 = 0,94 g/cm³", "d": ""}
          ],
          "ans": "0,94 g/cm³ (= 940 kg/m³)",
          "o": ["0,80 g/cm³", "1,00 g/cm³", "0,88 g/cm³", "0,70 g/cm³"]
        }
      ]
    }
  },
  "kaldirmaAgirlasma": {
    "lise": {
      "kolay": [
        {
          "q": "Boş bir kaba nesne konulunca tartının göstergesi ne kadar artar?",
          "steps": [
            {"t": "Newton 3. yasası", "a": "Reaksiyon kuvveti taban", "d": "Nesne, kabın tabanını aşağı iter; Newton'un 3. yasası gereği kap da nesneyi yukarı iter. Tartı bu kuvveti ölçer."},
            {"t": "Artış", "a": "Tartı artışı = nesnenin ağırlığı", "d": ""}
          ],
          "ans": "Nesnenin ağırlığı (mg) kadar artar",
          "o": ["Nesnenin ağırlığının iki katı artar", "Hiç değişmez", "Kaldırma kuvveti kadar azalır", "Nesnenin kütlesi kadar artar (kg cinsinden)"]
        },
        {
          "q": "İple asılı cisim, su dolu bir kabın içine (kabı tutmadan) daldırıldığında tartının göstergesi nasıl değişir?",
          "steps": [
            {"t": "Reaksiyon", "a": "Sıvı cisme F_k uygular; cisim de suya F_k (aşağı) uygular", "d": "Newton 3. yasası: cisme yukarı kaldırma kuvveti uygulayan sıvı, cisimden aşağı yönde aynı büyüklükte kuvvet alır."},
            {"t": "Tartı", "a": "Tartı F_k kadar artar", "d": ""}
          ],
          "ans": "Kaldırma kuvveti (F_k) kadar artar",
          "o": ["Cismin ağırlığı kadar artar", "Değişmez", "F_k kadar azalır", "İpteki gerilme kadar artar"]
        },
        {
          "q": "Tartı üzerinde su dolu kap var, cisim iple asılı şekilde suya daldırılıyor. Sistemin toplam ağırlığı değişiyor mu?",
          "steps": [
            {"t": "Toplam sistem", "a": "Ağırlık korunumu", "d": "Cisim iple ayrı tutulduğunda tartı yalnızca kap + su ağırlığını ölçer; cismin ağırlığı ipe aktarılır. Ancak kaldırma reaksiyonu tartıyı artırır."},
            {"t": "Sonuç", "a": "Tartı F_k kadar artar", "d": ""}
          ],
          "ans": "Evet; tartı kaldırma kuvveti kadar artar (Newton 3. yasası reaksiyonu)",
          "o": ["Hayır; toplam ağırlık değişmez", "Tartı cismin ağırlığı kadar artar", "Tartı cismin ağırlığı kadar azalır", "Tartı F_k kadar azalır"]
        },
        {
          "q": "Bir buz parçası su dolu bardakta eridiğinde su seviyesi nasıl değişir?",
          "steps": [
            {"t": "Yüzen buz", "a": "Buzun yerinden ettiği su hacmi = eriyen suyun hacmi", "d": "Buz yüzerken ağırlığı kadar su yerinden eder. Buz eriyince oluşan su, yerinden edilen su ile aynı hacimdir (ρ_buz < ρ_su)."},
            {"t": "Sonuç", "a": "Su seviyesi değişmez", "d": ""}
          ],
          "ans": "Değişmez",
          "o": ["Artar; buz eritilince su hacmi büyür", "Azalır; buz eridikçe hacim küçülür", "Önce artar sonra azalır", "Kabın şekline bağlıdır"]
        },
        {
          "q": "Bir teknede taş var ve taş denize atılıyor. Su seviyesi nasıl değişir?",
          "steps": [
            {"t": "Teknede", "a": "Taş ağırlığı kadar su yerinden edilir (ρ_taş >> ρ_su)", "d": "Tekne taşın ağırlığına eşit su kütlesini yerinden eder; bu hacim büyüktür."},
            {"t": "Denizde", "a": "Taş batınca yalnızca kendi hacmi kadar su yerinden edilir", "d": "ρ_taş > ρ_su; batan taşın yerinden ettiği su hacmi < teknenin yerinden ettiği hacim."},
            {"t": "Sonuç", "a": "Su seviyesi düşer", "d": ""}
          ],
          "ans": "Düşer; batık taş ağırlığından daha az hacim kadar su yerinden eder",
          "o": ["Artar; taş suda daha fazla yer kaplar", "Değişmez; toplam ağırlık aynı", "Önce artar sonra azalır", "Taşın yoğunluğuna bağlıdır"]
        }
      ],
      "zor": [
        {
          "q": "Su dolu bir kap (m_kap = 500 g, m_su = 2000 g) tartı üzerinde duruyor. m = 300 g, V = 150 cm³ cisim iple asılarak suya tamamen daldırılıyor. Tartının göstergesi kaç g artar? (ρ_su = 1 g/cm³)",
          "steps": [
            {"t": "F_k", "a": "F_k = ρ_su·V·g = 1 × 150 × g = 150 g·g kuvveti", "d": "Kaldırma kuvveti 150 g kuvvetine eşit."},
            {"t": "Tartı değişimi", "a": "Tartı F_k kadar artar → +150 g", "d": "Newton 3. yasası: sıvı cisme F_k uygular; cisim de suya aynı kuvveti aşağı yönde uygular."},
            {"t": "Toplam", "a": "Toplam = 500 + 2000 + 150 = 2650 g", "d": "Cisim ipteyse tartı sadece F_k kadar artar, cisim ağırlığı ipe aktarılır."}
          ],
          "ans": "150 g artar (toplam 2650 g gösterir)",
          "o": ["300 g artar", "0 g artar (değişmez)", "150 g azalır", "450 g artar"]
        },
        {
          "q": "Tartı üzerinde su dolu kap (toplam 3000 g). Bir cisim iple tartıya bağlı değil, doğrudan kabın içine bırakılıyor (batar). Cisim m = 400 g, V = 100 cm³. Tartı kaç g gösterir?",
          "steps": [
            {"t": "Durum", "a": "Cisim kabın dibine oturur", "d": "Cisim batar ve kabın tabanına oturur; ağırlığı tam olarak tartıya aktarılır."},
            {"t": "Toplam", "a": "Tartı = 3000 + 400 = 3400 g", "d": "Cismin tüm ağırlığı kap üzerinden tartıya aktarılır."}
          ],
          "ans": "3400 g",
          "o": ["3000 g", "3300 g (kaldırma kuvveti çıkarılır)", "3100 g", "3500 g"]
        },
        {
          "q": "m₁ = 200 g cisim su dolu kaptaki tartı üzerinde, m₂ = 500 g cisim iple asılı suya tamamen daldırılmış (V₂ = 200 cm³, ρ_su = 1 g/cm³). Başlangıçta tartı 2000 g gösteriyordu. Şimdi kaç g gösterir?",
          "steps": [
            {"t": "m₁ (kabın içinde)", "a": "Tartı m₁·g = 200 g kadar artar", "d": "Cisim doğrudan kaba konulmuş; ağırlığı tartıya aktarılır."},
            {"t": "m₂ (iple asılı)", "a": "Tartı F_k = ρ·V₂·g = 1 × 200 = 200 g kadar artar", "d": "Yalnızca kaldırma reaksiyonu tartıya aktarılır."},
            {"t": "Toplam", "a": "2000 + 200 + 200 = 2400 g", "d": ""}
          ],
          "ans": "2400 g",
          "o": ["2700 g", "2200 g", "2500 g", "2000 g"]
        }
      ]
    }
  },
  "gazYasasi": {
    "lise": {
      "kolay": [
        {
          "q": "Boyle yasası nedir ve hangi koşulda geçerlidir?",
          "steps": [
            {"t": "Boyle yasası", "a": "P₁·V₁ = P₂·V₂ (T sabit)", "d": "Sabit sıcaklıkta ideal gaz için basınç ve hacim ters orantılıdır."}
          ],
          "ans": "P₁·V₁ = P₂·V₂; sabit sıcaklıkta (T = sabit)",
          "o": ["P₁/T₁ = P₂/T₂; sabit hacimde", "V₁/T₁ = V₂/T₂; sabit basınçta", "P·V·T = sabit her koşulda", "P₁·T₁ = P₂·T₂; sabit hacimde"]
        },
        {
          "q": "Charles yasası nedir?",
          "steps": [
            {"t": "Charles yasası", "a": "V₁/T₁ = V₂/T₂ (P sabit)", "d": "Sabit basınçta ideal gazın hacmi mutlak sıcaklıkla doğru orantılıdır. T mutlak sıcaklık (K cinsinden)."}
          ],
          "ans": "V₁/T₁ = V₂/T₂; sabit basınçta (P = sabit); T Kelvin",
          "o": ["P₁·V₁ = P₂·V₂; sabit sıcaklıkta", "P₁/T₁ = P₂/T₂; sabit hacimde", "V₁·T₁ = V₂·T₂; sabit basınçta", "V/T = sabit; sabit sıcaklıkta"]
        },
        {
          "q": "Gay-Lussac yasası nedir?",
          "steps": [
            {"t": "Gay-Lussac", "a": "P₁/T₁ = P₂/T₂ (V sabit)", "d": "Sabit hacimde ideal gaz için basınç mutlak sıcaklıkla doğru orantılıdır."}
          ],
          "ans": "P₁/T₁ = P₂/T₂; sabit hacimde (V = sabit); T Kelvin",
          "o": ["P₁·V₁ = P₂·V₂; sabit sıcaklıkta", "V₁/T₁ = V₂/T₂; sabit basınçta", "P₁·T₁ = P₂·T₂; sabit hacimde", "P/V = sabit; her koşulda"]
        },
        {
          "q": "Birleşik gaz yasası formülü nedir?",
          "steps": [
            {"t": "Birleşik yasa", "a": "P₁·V₁/T₁ = P₂·V₂/T₂", "d": "Üç değişkeni (P, V, T) birleştiren genel formüldür. T mutlak sıcaklık (K) olmalıdır."}
          ],
          "ans": "P₁·V₁/T₁ = P₂·V₂/T₂",
          "o": ["P₁·V₁·T₁ = P₂·V₂·T₂", "P₁/V₁·T₁ = P₂/V₂·T₂", "P₁+V₁+T₁ = P₂+V₂+T₂", "P₁·V₁ = P₂·V₂·T₂/T₁ (yanlış sıra)"]
        },
        {
          "q": "İdeal gaz yasalarında sıcaklık neden Kelvin (K) cinsinden kullanılmalıdır?",
          "steps": [
            {"t": "Mutlak sıfır", "a": "0 K = −273 °C; gaz hacmi sıfıra ulaşır", "d": "Celsius ölçeği negatif değerler alabilir; bu da formüllerde fiziksel anlam kaybına yol açar. Kelvin her zaman pozitiftir."},
            {"t": "Doğru orantı", "a": "V ∝ T yalnızca K'de doğrudur", "d": "Charles yasasındaki doğru orantı mutlak sıcaklıkla kurulur."}
          ],
          "ans": "Kelvin mutlak sıcaklık ölçeğidir; 0 K gerçek sıfır nokta olup gaz yasalarındaki orantı ilişkileri yalnızca K'de doğrudur",
          "o": ["Çünkü Celsius uluslararası birim değildir", "Çünkü Fahrenheit çok büyük değerler verir", "Çünkü Kelvin ölçeği daha hassastır", "Çünkü sıcaklık farkları Kelvin'de daha küçüktür"]
        }
      ],
      "zor": [
        {
          "q": "27 °C ve 2 atm basınçta V₁ = 3 L olan gaz, sabit sıcaklıkta V₂ = 6 L'ye genişliyor. Yeni basınç kaç atm'dir? (Boyle yasası)",
          "steps": [
            {"t": "Boyle", "a": "P₁·V₁ = P₂·V₂", "d": "T sabit."},
            {"t": "P₂", "a": "P₂ = P₁·V₁/V₂ = 2 × 3/6 = 1 atm", "d": ""},
            {"t": "Sonuç", "a": "P₂ = 1 atm", "d": "Hacim iki katına çıkınca basınç yarıya düşer."}
          ],
          "ans": "1 atm",
          "o": ["2 atm", "4 atm", "0,5 atm", "3 atm"]
        },
        {
          "q": "27 °C ve 1 atm basınçta V₁ = 4 L olan gaz, sabit basınçta 127 °C'ye ısıtılıyor. Yeni hacim kaç L'dir? (Charles yasası)",
          "steps": [
            {"t": "K'ye çevirme", "a": "T₁ = 300 K, T₂ = 400 K", "d": "27 + 273 = 300, 127 + 273 = 400"},
            {"t": "Charles", "a": "V₁/T₁ = V₂/T₂ → V₂ = 4 × 400/300", "d": ""},
            {"t": "Sonuç", "a": "V₂ = 16/3 ≈ 5,33 L", "d": ""}
          ],
          "ans": "≈ 5,33 L",
          "o": ["4,00 L", "8,00 L", "2,67 L", "6,00 L"]
        },
        {
          "q": "Bir gaz 300 K'de 2 atm ve 5 L durumunda. 600 K ve 4 atm'de hacmi kaç L olur? (Birleşik gaz yasası)",
          "steps": [
            {"t": "Formül", "a": "P₁V₁/T₁ = P₂V₂/T₂", "d": ""},
            {"t": "V₂", "a": "V₂ = P₁V₁T₂/(T₁P₂) = 2 × 5 × 600/(300 × 4) = 6000/1200 = 5 L", "d": ""},
            {"t": "Sonuç", "a": "V₂ = 5 L", "d": "Sıcaklık iki katına çıkıp basınç da iki katına çıkınca hacim değişmez."}
          ],
          "ans": "5 L",
          "o": ["10 L", "2,5 L", "20 L", "1,25 L"]
        }
      ]
    }
  },
  "esnekBalon": {
    "lise": {
      "kolay": [
        {
          "q": "Sabun balonu içindeki basınç neden dış basınçtan fazladır?",
          "steps": [
            {"t": "İki yüzey", "a": "Baloncuğun iç ve dış yüzeyi", "d": "Sabun filmi iki yüzeyden oluşur (iç ve dış); her iki yüzeyin yüzey gerilimi de içe doğru etki eder."},
            {"t": "Fazla basınç", "a": "ΔP = 4γ/r", "d": "İki yüzey nedeniyle fazla basınç 4γ/r'dir (bir su damlası için 2γ/r)."}
          ],
          "ans": "Yüzey gerilimi içe doğru etki eder; ΔP = 4γ/r (iki yüzey)",
          "o": ["Hava akımı balonu şişirir, basıncı dışarıdan arttırır", "İç basınç dış basınca eşittir", "İç basınç dış basınçtan azdır", "ΔP = 2γ/r (tek yüzey için)"]
        },
        {
          "q": "Balon şişirilirken başlangıçta zorlanıp daha sonra kolay şişmesinin nedeni nedir?",
          "steps": [
            {"t": "Küçük r", "a": "r küçükken ΔP = 4γ/r büyük → zor şişirme", "d": "Baloncuğun başlangıçtaki küçük yarıçapında fazla basınç yüksek olduğundan şişirmek güçtür."},
            {"t": "Büyük r", "a": "r büyüyünce ΔP azalır → kolay şişirme", "d": "Yarıçap büyüdüğünde iç-dış basınç farkı azalır; şişirmek kolaylaşır."}
          ],
          "ans": "Küçük yarıçapta ΔP = 4γ/r büyüktür; r büyüyünce ΔP azalır ve şişirmek kolaylaşır",
          "o": ["Balon malzemesi ilk başta soğuktur", "Hava nemi balonu ilk başta sertleştirir", "Büyük r'de yüzey gerilimi sıfıra ulaşır", "İlk anda içerideki hava basıncı sıfırdır"]
        },
        {
          "q": "Piston-silindir sisteminde gaz sabit basınçta V₁ = 2 L'den V₂ = 5 L'ye genişliyor. P = 1 atm = 101 000 Pa ise yapılan iş kaç J'dur?",
          "steps": [
            {"t": "Formül", "a": "W = P·ΔV", "d": "ΔV = V₂ − V₁ = 3 L = 3 × 10⁻³ m³"},
            {"t": "Hesap", "a": "W = 101 000 × 3 × 10⁻³ = 303 J", "d": ""},
            {"t": "Sonuç", "a": "W = 303 J", "d": ""}
          ],
          "ans": "303 J",
          "o": ["101 J", "606 J", "30,3 J", "101 000 J"]
        },
        {
          "q": "İki aynı boyutta sabun balonunu birbirine bağladığımızda ne olur?",
          "steps": [
            {"t": "Basınç eşit", "a": "Aynı r → aynı ΔP = 4γ/r", "d": "İki balon aynı yarıçapta ise iç basınçları eşit; hava geçişi olmaz, boyutlar değişmez."}
          ],
          "ans": "Boyutlar değişmez; iç basınçları eşit olduğundan hava geçişi olmaz",
          "o": ["Büyük olan daha da büyür", "Küçük olan daha da küçülür", "İkisi de yarı yarıya olur", "Her ikisi de söner"]
        },
        {
          "q": "Farklı boyutta iki sabun balonunu birleştirince ne olur?",
          "steps": [
            {"t": "Küçük balon", "a": "r küçük → ΔP = 4γ/r büyük → yüksek basınç", "d": "Küçük balondaki basınç büyük balondakinden daha yüksektir."},
            {"t": "Sonuç", "a": "Hava küçükten büyüğe geçer; küçük büzülür, büyük şişer", "d": ""}
          ],
          "ans": "Küçük balon büzülür, büyük balon şişer; hava küçükten büyüğe geçer",
          "o": ["Büyük balon büzülür, küçük şişer", "İkisi de eşit boyuta gelir", "Her ikisi de söner", "Boyutlar değişmez"]
        }
      ],
      "zor": [
        {
          "q": "γ = 0,04 N/m olan sabun balonunun yarıçapı r = 5 cm. İç-dış basınç farkı kaç Pa'dır?",
          "steps": [
            {"t": "Formül", "a": "ΔP = 4γ/r", "d": "r = 0,05 m"},
            {"t": "Hesap", "a": "ΔP = 4 × 0,04 / 0,05 = 0,16/0,05 = 3,2 Pa", "d": ""},
            {"t": "Sonuç", "a": "ΔP = 3,2 Pa", "d": ""}
          ],
          "ans": "3,2 Pa",
          "o": ["1,6 Pa", "6,4 Pa", "0,32 Pa", "32 Pa"]
        },
        {
          "q": "γ = 0,025 N/m olan sabun balonunda iç-dış basınç farkı 10 Pa olması için yarıçap kaç cm olmalıdır?",
          "steps": [
            {"t": "Formül", "a": "r = 4γ/ΔP", "d": "ΔP = 4γ/r denkleminden r çekilir."},
            {"t": "Hesap", "a": "r = 4 × 0,025 / 10 = 0,1/10 = 0,01 m = 1 cm", "d": ""},
            {"t": "Sonuç", "a": "r = 1 cm", "d": ""}
          ],
          "ans": "1 cm",
          "o": ["2 cm", "0,5 cm", "4 cm", "10 cm"]
        },
        {
          "q": "Bir pistonda P = 200 000 Pa sabit basınçta gaz genişliyor ve W = 60 J iş yapıyor. Hacim değişimi kaç L'dir?",
          "steps": [
            {"t": "Formül", "a": "ΔV = W/P", "d": "W = P·ΔV → ΔV = W/P"},
            {"t": "Hesap", "a": "ΔV = 60/200 000 = 3 × 10⁻⁴ m³", "d": ""},
            {"t": "Sonuç", "a": "ΔV = 0,3 L", "d": "1 m³ = 1000 L; 3 × 10⁻⁴ m³ = 0,3 L"}
          ],
          "ans": "0,3 L",
          "o": ["0,6 L", "0,15 L", "3,0 L", "30 L"]
        }
      ]
    }
  },
  "piezoelektrik": {
    "lise": {
      "kolay": [
        {
          "q": "Piezoelektrik etki nedir?",
          "steps": [
            {"t": "Tanım", "a": "Basınç uygulandığında elektrik gerilimi oluşması", "d": "Belirli kristallere (kuvars, turmalin vb.) mekanik basınç uygulandığında kristal yüzeylerinde elektrik yükü birikir ve voltaj oluşur."}
          ],
          "ans": "Bazı kristallere mekanik basınç uygulandığında elektrik gerilimi üretmesi",
          "o": ["Elektrik uygulayınca kristallerin ısınması", "Basınç altında kristallerin erimesi", "Sıvı içinde basınç iletimi", "Işık enerjisinin elektriğe dönüşmesi"]
        },
        {
          "q": "Piezoelektrik etkinin günlük hayatta kullanıldığı iki örnek nedir?",
          "steps": [
            {"t": "Çakmak", "a": "Piezo çakmak: basınçla kıvılcım üretir", "d": "Bir kristale ani basınç uygulanarak yüksek voltaj ve kıvılcım oluşturulur."},
            {"t": "Mikrofon", "a": "Ses dalgaları basınç → voltaj", "d": "Piezoelektrik mikrofon, ses basıncını elektrik sinyaline çevirir."}
          ],
          "ans": "Piezo çakmak ve piezoelektrik mikrofon",
          "o": ["Güneş paneli ve pil", "Transistör ve kondansatör", "Transformatör ve jeneratör", "LED ve güneş pili"]
        },
        {
          "q": "Piezoelektrik etki P = F/A formülüyle nasıl ilişkilidir?",
          "steps": [
            {"t": "Basınç", "a": "P = F/A formülü uygulanan mekanik basıncı verir", "d": "Kristale uygulanan kuvvet F ve temas alanı A ile basınç P hesaplanır."},
            {"t": "Bağlantı", "a": "P ne kadar büyük → voltaj o kadar büyük", "d": "Oluşan elektrik gerilimi uygulanan basınçla doğru orantılıdır."}
          ],
          "ans": "P = F/A ile hesaplanan mekanik basınç arttıkça üretilen elektrik gerilimi de artar",
          "o": ["Piezoelektrik P = F/A ile ilgisizdir", "P = F/A basınç küçüldükçe voltaj artar", "P = ρ·g·h formülü kullanılır", "Voltaj yalnızca alana bağlıdır, kuvvete değil"]
        },
        {
          "q": "Ters piezoelektrik etki nedir?",
          "steps": [
            {"t": "Ters etki", "a": "Elektrik gerilimi uygulanınca kristal mekanik deformasyon yapar", "d": "Kristale elektrik uygulandığında kristal büzülür veya genişler; ultrasonik transdüserler bu prensiple çalışır."}
          ],
          "ans": "Elektrik gerilimi uygulandığında kristalde mekanik deformasyon (titreşim) oluşması",
          "o": ["Basınç uygulanınca elektrik üretilmesi", "Kristal ısıtılınca elektrik üretilmesi", "Sıvı basıncının elektriğe dönüşmesi", "Elektrik uygulanınca kristal erimesi"]
        },
        {
          "q": "Piezoelektrik basınç sensörü nasıl çalışır?",
          "steps": [
            {"t": "Çalışma ilkesi", "a": "Basınç → kristal deformasyonu → voltaj → ölçüm", "d": "Ölçülmek istenen basınç kristale uygulanır; üretilen voltaj kalibrasyon eğrisiyle basınca dönüştürülür."}
          ],
          "ans": "Uygulanan basınç kristalde voltaj üretir; bu voltaj kalibre edilerek basınç değerine dönüştürülür",
          "o": ["Sıvı yüksekliği ölçülerek basınç bulunur", "Cismin ağırlığı ölçülerek basınç hesaplanır", "Sıcaklık değişimi ölçülerek basınç hesaplanır", "Işık şiddeti değişimiyle basınç belirlenir"]
        }
      ],
      "zor": [
        {
          "q": "Piezoelektrik sensörün kare yüzeyi 2 cm × 2 cm'dir. Yüzeye 40 N kuvvet uygulanıyor. Sensöre etki eden basınç kaç Pa'dır?",
          "steps": [
            {"t": "Alan", "a": "A = 0,02 × 0,02 = 4 × 10⁻⁴ m²", "d": "2 cm = 0,02 m"},
            {"t": "Basınç", "a": "P = F/A = 40/(4 × 10⁻⁴) = 100 000 Pa", "d": ""},
            {"t": "Sonuç", "a": "P = 100 000 Pa = 100 kPa ≈ 1 atm", "d": ""}
          ],
          "ans": "100 000 Pa (100 kPa)",
          "o": ["20 000 Pa", "400 000 Pa", "10 000 Pa", "50 000 Pa"]
        },
        {
          "q": "Piezoelektrik sensör çıkışı 0,5 V/MPa hassasiyetine sahiptir. Sensöre P = 2 MPa basınç uygulandığında çıkış voltajı kaç V olur? Bu basınç, A = 1 cm² yüzeyde kaç N kuvvete karşılık gelir?",
          "steps": [
            {"t": "Voltaj", "a": "V_çıkış = 0,5 × 2 = 1 V", "d": "Hassasiyet × basınç"},
            {"t": "Alan", "a": "A = 1 cm² = 10⁻⁴ m²", "d": ""},
            {"t": "Kuvvet", "a": "F = P × A = 2 × 10⁶ × 10⁻⁴ = 200 N", "d": ""}
          ],
          "ans": "Voltaj = 1 V, Kuvvet = 200 N",
          "o": ["Voltaj = 2 V, Kuvvet = 200 N", "Voltaj = 1 V, Kuvvet = 100 N", "Voltaj = 0,5 V, Kuvvet = 400 N", "Voltaj = 1 V, Kuvvet = 20 N"]
        },
        {
          "q": "İki piezoelektrik sensör aynı kuvvet F = 60 N alıyor. Sensör-1 alanı A₁ = 3 cm², Sensör-2 alanı A₂ = 0,5 cm². Hangi sensörde daha yüksek basınç var ve basınç farkı kaç Pa'dır?",
          "steps": [
            {"t": "P₁", "a": "P₁ = 60/(3 × 10⁻⁴) = 200 000 Pa", "d": "A₁ = 3 cm² = 3 × 10⁻⁴ m²"},
            {"t": "P₂", "a": "P₂ = 60/(0,5 × 10⁻⁴) = 1 200 000 Pa", "d": "A₂ = 0,5 cm² = 5 × 10⁻⁵ m²"},
            {"t": "Fark", "a": "ΔP = 1 200 000 − 200 000 = 1 000 000 Pa = 1 MPa", "d": "Sensör-2 daha küçük alanlı, çok daha yüksek basınç."}
          ],
          "ans": "Sensör-2 daha yüksek; ΔP = 1 000 000 Pa (1 MPa)",
          "o": ["Sensör-1 daha yüksek; ΔP = 1 MPa", "Her ikisi eşit basınca sahip", "Sensör-2 daha yüksek; ΔP = 0,5 MPa", "Sensör-2 daha yüksek; ΔP = 2 MPa"]
        }
      ]
    }
  }
};
