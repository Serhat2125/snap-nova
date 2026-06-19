var __BQ_PART2 = {
  "siviBasinci": {
    "lise": {
      "kolay": [
        {
          "q": "Durgun sıvı basıncı formülü nedir ve birimleri nelerdir?",
          "steps": [
            {"t": "Formül", "a": "P = ρ·g·h", "d": "P basınç (Pa), ρ sıvı yoğunluğu (kg/m³), g yerçekimi ivmesi (m/s²), h sıvı derinliği (m)."},
            {"t": "Birim", "a": "Pascal (Pa = N/m²)", "d": "1 Pa, 1 m² alana 1 N kuvvet uygulandığında oluşan basınçtır."}
          ],
          "ans": "P = ρ·g·h; birimi Pascal (Pa = N/m²)",
          "o": ["P = m·g·h; birimi Newton (N)", "P = ρ·g·V; birimi Pascal (Pa)", "P = F·h; birimi Joule (J)", "P = ρ·V·g/A; birimi kg/m²"]
        },
        {
          "q": "Bir sıvıda aynı derinlikte bulunan noktalarda basınç nasıldır?",
          "steps": [
            {"t": "Prensip", "a": "Tüm yönlerde eşit", "d": "Durgun sıvıda aynı yatay düzlemdeki tüm noktalarda basınç eşittir ve her yönde aynı büyüklüktedir (Pascal yasası)."},
            {"t": "Sonuç", "a": "P = ρ·g·h değeri sabittir", "d": "Derinlik h aynı olduğu sürece sıvının yoğunluğu ve g sabit olduğundan basınç değişmez."}
          ],
          "ans": "Aynı derinlikte basınç her yönde ve her noktada eşittir",
          "o": ["Hareket yönünde daha büyük, diğer yönlerde daha küçüktür", "Yalnızca aşağı yönde etki eder", "Kaba yakın noktalarda daha büyüktür", "Sıvının ortasında kenarlara göre daha azdır"]
        },
        {
          "q": "Sıvı basıncı kabın şekline bağlı mıdır?",
          "steps": [
            {"t": "Cevap", "a": "Hayır, kabın şeklinden bağımsızdır", "d": "P = ρ·g·h formülünde kap şekli ile ilgili bir değişken yoktur. Yalnızca derinlik, yoğunluk ve g etkilidir."},
            {"t": "Örnek", "a": "Geniş ve dar kaplar", "d": "Aynı yükseklikte sıvı içeren geniş kap ile dar kapta tabandaki basınç eşittir."}
          ],
          "ans": "Hayır, yalnızca derinliğe (h), yoğunluğa (ρ) ve g'ye bağlıdır",
          "o": ["Evet, geniş kaplarda basınç daha büyüktür", "Evet, silindirik kaplarda basınç daha küçüktür", "Evet, kap tabanının alanı arttıkça basınç azalır", "Evet, kap materyalinin geçirgenliğine bağlıdır"]
        },
        {
          "q": "Sıvı içindeki bir noktaya etki eden basınç kuvveti hangi yönlerde etkilidir?",
          "steps": [
            {"t": "Yön", "a": "Her yönde (izotropik)", "d": "Sıvı basıncı katı basıncından farklı olarak yalnızca bir yönde değil, tüm yönlerde eşit büyüklükte etki eder."},
            {"t": "Açıklama", "a": "Pascal yasası gereği", "d": "Sıvı molekülleri serbestçe hareket edebildiğinden basıncı her yöne eşit iletirler."}
          ],
          "ans": "Her yönde eşit büyüklükte etki eder",
          "o": ["Yalnızca aşağı yönde etki eder", "Yalnızca yukarı ve aşağı yönde etki eder", "Yalnızca yatay yönde etki eder", "Yüzeye dik yönde daha büyük etki eder"]
        },
        {
          "q": "Aynı sıvı içinde derinlik arttıkça basınç nasıl değişir? Yatay uzaklık etkiler mi?",
          "steps": [
            {"t": "Derinlik etkisi", "a": "Derinlik arttıkça basınç artar", "d": "P = ρ·g·h bağıntısına göre h arttıkça P doğru orantılı artar."},
            {"t": "Yatay etkisi", "a": "Yatay uzaklığın etkisi yoktur", "d": "Aynı derinlikte yan yana bulunan noktalar, yatay konumlarından bağımsız olarak aynı basınca sahiptir."}
          ],
          "ans": "Derinlik arttıkça basınç artar; yatay uzaklığın etkisi yoktur",
          "o": ["Derinlik ve yatay uzaklık birlikte basıncı etkiler", "Yatay uzaklık arttıkça basınç azalır", "Derinlik azaldıkça basınç artar", "Derinlik ve basınç birbirinden bağımsızdır"]
        }
      ],
      "zor": [
        {
          "q": "Yoğunluğu ρ = 1000 kg/m³ olan su dolu bir tankta h = 5 m derinliğindeki basınç kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "Veri", "a": "ρ = 1000 kg/m³, g = 10 m/s², h = 5 m", "d": "Verilen değerleri P = ρ·g·h formülüne yerleştireceğiz."},
            {"t": "Hesap", "a": "P = 1000 × 10 × 5", "d": "P = 50 000 Pa"},
            {"t": "Sonuç", "a": "P = 50 000 Pa = 50 kPa", "d": "Bu, atmosfer basıncının yaklaşık yarısına eşit ek bir basınçtır."}
          ],
          "ans": "50 000 Pa (50 kPa)",
          "o": ["5 000 Pa", "500 000 Pa", "25 000 Pa", "100 000 Pa"]
        },
        {
          "q": "Yoğunluğu ρ = 13 600 kg/m³ olan cıva sütununda h = 0,5 m derinliğindeki basınç kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "Veri", "a": "ρ = 13 600 kg/m³, g = 10 m/s², h = 0,5 m", "d": "Cıvanın yüksek yoğunluğu nedeniyle küçük yükseklik büyük basınç üretir."},
            {"t": "Hesap", "a": "P = 13 600 × 10 × 0,5", "d": "P = 68 000 Pa"},
            {"t": "Sonuç", "a": "P = 68 000 Pa", "d": "Bu değer yaklaşık 0,67 atm'e karşılık gelir."}
          ],
          "ans": "68 000 Pa",
          "o": ["6 800 Pa", "136 000 Pa", "34 000 Pa", "13 600 Pa"]
        },
        {
          "q": "Yoğunluğu ρ = 800 kg/m³ olan yağda P = 50 000 Pa basıncının oluştuğu derinlik kaç metredir? (g = 10 m/s²)",
          "steps": [
            {"t": "Formülden h çek", "a": "h = P / (ρ·g)", "d": "P = ρ·g·h bağıntısından h yalnız bırakılır: h = P / (ρ·g)"},
            {"t": "Hesap", "a": "h = 50 000 / (800 × 10)", "d": "h = 50 000 / 8 000 = 6,25 m"},
            {"t": "Sonuç", "a": "h = 6,25 m", "d": "Yağın suydan hafif olması nedeniyle aynı basınç için daha derin gitmek gerekir."}
          ],
          "ans": "6,25 m",
          "o": ["4,00 m", "5,00 m", "7,50 m", "8,00 m"]
        }
      ]
    }
  },

  "bilesikKaplar": {
    "lise": {
      "kolay": [
        {
          "q": "Birbirine bağlı kaplarda aynı sıvı bulunuyorsa sıvı seviyeleri nasıl olur?",
          "steps": [
            {"t": "Prensip", "a": "Sıvı seviyeleri eşitlenir", "d": "Birbirine bağlı kaplar aynı sıvıyla dolduğunda, dip noktasındaki basınç eşit olduğu için sıvı yüzeyi her kolda aynı yüksekliğe ulaşır."},
            {"t": "Neden", "a": "Taban basıncı eşitliği", "d": "P = ρ·g·h bağıntısı gereği, ρ ve g sabitken h eşit olduğunda taban basınçları eşit olur."}
          ],
          "ans": "Tüm kollarda sıvı seviyeleri eşit olur",
          "o": ["Geniş kolda seviye daha yüksek olur", "Dar kolda seviye daha yüksek olur", "Sıvı eklendiği kola göre seviye değişir", "Her kolda seviye bağımsız kalır"]
        },
        {
          "q": "Birbirine bağlı kaplarda aynı sıvının eşit seviyede durmasının fiziksel nedeni nedir?",
          "steps": [
            {"t": "Neden", "a": "Bağlantı noktasında basınç eşitliği", "d": "Kaplar birbirine bağlandığında bağlantı noktasındaki basınç iki koldan gelen sıvı sütunlarınca belirlenir. Denge ancak h₁ = h₂ olduğunda sağlanır."},
            {"t": "Sonuç", "a": "Sıvı akışı durur", "d": "Eşit seviyeye ulaşıldığında bağlantı noktasında net kuvvet sıfır olduğundan sıvı akmaz."}
          ],
          "ans": "Bağlantı noktasındaki basınçlar eşit olduğunda denge sağlanır",
          "o": ["Sıvıların ağırlıkları birbirine eşit olduğunda denge sağlanır", "Kapların hacimleri eşit olduğunda denge sağlanır", "Sıvı molekülleri birbirini iterek eşit seviye oluşturur", "Yüzey gerilimi seviyeleri eşitler"]
        },
        {
          "q": "Birbirine bağlı iki kolda farklı sıvılar varsa denge koşulu nedir?",
          "steps": [
            {"t": "Denge koşulu", "a": "ρ₁·h₁ = ρ₂·h₂", "d": "Bağlantı noktasında her iki sıvı sütununun basıncı eşit olmalıdır: ρ₁·g·h₁ = ρ₂·g·h₂, g sadeleşince ρ₁·h₁ = ρ₂·h₂."},
            {"t": "Sonuç", "a": "Yoğun sıvı alçakta durur", "d": "Yoğunluğu büyük olan sıvının sütun yüksekliği küçük, yoğunluğu az olanınki büyük olur."}
          ],
          "ans": "ρ₁·h₁ = ρ₂·h₂ (bağlantı noktasında basınç eşitliği)",
          "o": ["h₁ = h₂ (seviyeler her zaman eşit olur)", "ρ₁·V₁ = ρ₂·V₂ (hacimler orantılı olur)", "m₁ = m₂ (kütleler eşit olur)", "ρ₁·h₁² = ρ₂·h₂² (kareseler eşit olur)"]
        },
        {
          "q": "Hidrolik pres bileşik kaplar prensibinden nasıl yararlanır?",
          "steps": [
            {"t": "Prensip", "a": "Basınç her noktaya eşit iletilir", "d": "Pascal yasasına göre kapalı bir sıvıya uygulanan basınç her tarafa aynen iletilir: P = F₁/A₁ = F₂/A₂."},
            {"t": "Kuvvet artışı", "a": "F₂/F₁ = A₂/A₁", "d": "Büyük pistonun alanı büyük olduğundan çok daha büyük kuvvet üretilebilir. Bu mekanik avantaj sağlar."}
          ],
          "ans": "Basınç her noktaya eşit iletildiğinden büyük piston küçük kuvvetle hareket ettirilir",
          "o": ["Sıvı seviyesinin eşitlenmesiyle büyük kuvvet üretilir", "Farklı sıvı yoğunluklarından yararlanılarak kuvvet artırılır", "Sıvı sıkıştırılarak potansiyel enerji depolanır", "Ağır pistonun yerçekimi kuvvetinden yararlanılır"]
        },
        {
          "q": "Bileşik kaplarda sıvı yüksekliğini belirleyen değişken hangisidir?",
          "steps": [
            {"t": "Değişken", "a": "Yoğunluk (ρ)", "d": "Aynı bağlantı noktası basıncında ρ₁·h₁ = ρ₂·h₂ bağıntısına göre her sıvının yüksekliği kendi yoğunluğuna bağlıdır."},
            {"t": "Bağımsız değişkenler", "a": "Kap şekli ve hacmi etkisizdir", "d": "Kabın silindirik ya da konik olması, tabanın geniş ya da dar olması sıvı yüksekliğini değiştirmez."}
          ],
          "ans": "Sıvının yoğunluğu (ρ)",
          "o": ["Kap tabanının alanı", "Sıvının hacmi", "Kabın yüksekliği", "Sıvının yüzey gerilimi"]
        }
      ],
      "zor": [
        {
          "q": "Birbirine bağlı iki kollu bir kapta sol kolda ρ₁ = 800 kg/m³ yoğunluklu yağ h₁ = 30 cm yüksekliğinde durmaktadır. Sağ kolda ρ₂ = 1000 kg/m³ yoğunluklu su bulunmaktadır. Denge durumunda suyun yüksekliği kaç cm'dir?",
          "steps": [
            {"t": "Denge koşulu", "a": "ρ₁·h₁ = ρ₂·h₂", "d": "Bağlantı noktasında basınçlar eşit olmalıdır."},
            {"t": "Hesap", "a": "800 × 30 = 1000 × h₂", "d": "24 000 = 1000 × h₂ → h₂ = 24 cm"},
            {"t": "Sonuç", "a": "h₂ = 24 cm", "d": "Su yağdan daha yoğun olduğu için daha alçak sütun oluşturur."}
          ],
          "ans": "24 cm",
          "o": ["30 cm", "37,5 cm", "20 cm", "32 cm"]
        },
        {
          "q": "Bir hidrolik preste küçük pistonun alanı A₁ = 10 cm², büyük pistonun alanı A₂ = 100 cm²'dir. Küçük pistona F₁ = 50 N kuvvet uygulanırsa büyük pistonda oluşan kuvvet kaç N'dur?",
          "steps": [
            {"t": "Basınç eşitliği", "a": "F₁/A₁ = F₂/A₂", "d": "Pascal yasasına göre her iki pistonda oluşan basınçlar eşittir."},
            {"t": "Hesap", "a": "F₂ = F₁ × (A₂/A₁)", "d": "F₂ = 50 × (100/10) = 50 × 10 = 500 N"},
            {"t": "Sonuç", "a": "F₂ = 500 N", "d": "Alan 10 kat büyük olduğundan kuvvet de 10 kat büyük olur."}
          ],
          "ans": "500 N",
          "o": ["50 N", "5 000 N", "250 N", "100 N"]
        },
        {
          "q": "Bileşik kaplı bir sistemde sol kolda ρ₁ = 600 kg/m³ yoğunluklu sıvı, sağ kolda ρ₂ = 1200 kg/m³ yoğunluklu sıvı bulunmaktadır. Sol koldaki sıvı yüksekliği h₁ = 40 cm ise sağ koldaki yükseklik kaç cm'dir?",
          "steps": [
            {"t": "Denge", "a": "ρ₁·h₁ = ρ₂·h₂", "d": "600 × 40 = 1200 × h₂"},
            {"t": "Hesap", "a": "h₂ = 24 000 / 1200", "d": "h₂ = 20 cm"},
            {"t": "Sonuç", "a": "h₂ = 20 cm", "d": "Yoğunluğu 2 kat fazla olan sıvı, yarı yükseklikte denge kurar."}
          ],
          "ans": "20 cm",
          "o": ["40 cm", "80 cm", "30 cm", "15 cm"]
        }
      ]
    }
  },

  "hidrostatik": {
    "lise": {
      "kolay": [
        {
          "q": "U borusunda iki farklı sıvı dengedeyken bağlantı noktasındaki denge koşulu nedir?",
          "steps": [
            {"t": "Koşul", "a": "ρ₁·g·h₁ = ρ₂·g·h₂", "d": "Bağlantı noktasında her iki koldan gelen sıvı basıncı eşit olmalıdır. g sadeleşince ρ₁·h₁ = ρ₂·h₂ elde edilir."},
            {"t": "Yorum", "a": "Yoğun sıvı → alçak sütun", "d": "Yoğunluğu fazla olan sıvının sütun yüksekliği daha küçük olur."}
          ],
          "ans": "ρ₁·h₁ = ρ₂·h₂ (bağlantı noktasında basınç eşitliği)",
          "o": ["h₁ = h₂ (yükseklikler daima eşit olur)", "ρ₁ = ρ₂ (yoğunluklar eşit olur)", "m₁·g·h₁ = m₂·g·h₂ (kütlelerle hesaplanır)", "V₁ = V₂ (hacimler eşit olur)"]
        },
        {
          "q": "Kaldırma kuvveti (Arşimet kuvveti) nedir?",
          "steps": [
            {"t": "Tanım", "a": "Sıvının cisme uyguladığı yukarı yönlü kuvvet", "d": "Sıvıya daldırılan bir cisme, cismin yerinden ettiği sıvının ağırlığına eşit bir kuvvet yukarı yönde etki eder: F_k = ρ_sıvı·g·V_daldırılan."},
            {"t": "Formül", "a": "F_k = ρ·g·V", "d": "ρ sıvı yoğunluğu, g yerçekimi, V cismin sıvıya daldırılan hacmidir."}
          ],
          "ans": "Cismin yerinden ettiği sıvı ağırlığına eşit yukarı yönlü kuvvet (F_k = ρ·g·V)",
          "o": ["Cismin ağırlığına eşit aşağı yönlü kuvvet", "Sıvı tarafından uygulanan yatay kuvvet", "Cismin kütlesiyle orantılı sürtünme kuvveti", "Sıvının yüzeyinde oluşan gerilim kuvveti"]
        },
        {
          "q": "Bir cismin sıvı içindeki görünür ağırlığı (T) gerçek ağırlığından (W) neden küçüktür?",
          "steps": [
            {"t": "Denge", "a": "T + F_k = W", "d": "Dinamometre cismi tutarken yukarı yönlü iki kuvvet vardır: dinamometre kuvveti T ve kaldırma kuvveti F_k. Bunların toplamı ağırlığa eşittir."},
            {"t": "Çözüm", "a": "T = W - F_k", "d": "Kaldırma kuvveti gerçek ağırlıktan çıkarıldığında görünür ağırlık (dinamometre okuma) elde edilir."}
          ],
          "ans": "Kaldırma kuvveti cismi yukarı ittiğinden T = W - F_k < W olur",
          "o": ["Sıvı içindeki sürtünme ağırlığı azaltır", "Sıvı basıncı cismi sıkıştırdığından kütlesi azalır", "Cismin hacmi sıvı içinde küçüldüğünden ağırlığı azalır", "Yerçekimi sıvı içinde daha azdır"]
        },
        {
          "q": "Bir cisim sıvıya bırakıldığında hangi koşulda batar, hangi koşulda yüzer?",
          "steps": [
            {"t": "Batma koşulu", "a": "W > F_k → ρ_cisim > ρ_sıvı", "d": "Cismin yoğunluğu sıvıdan büyükse kaldırma kuvveti ağırlığı yetemez; cisim batar."},
            {"t": "Yüzme koşulu", "a": "W ≤ F_k → ρ_cisim ≤ ρ_sıvı", "d": "Cismin yoğunluğu sıvıdan küçük ya da eşitse cisim yüzer veya askıda kalır."}
          ],
          "ans": "ρ_cisim > ρ_sıvı ise batar; ρ_cisim < ρ_sıvı ise yüzer",
          "o": ["Büyük cisimler batar, küçük cisimler yüzer", "Ağır cisimler batar, hafif cisimler yüzer", "Şekli yuvarlak cisimler yüzer, köşeli cisimler batar", "Sıcak cisimler yüzer, soğuk cisimler batar"]
        },
        {
          "q": "Dinamometre ile sıvıya daldırılan bir cisim için gerilen denge denkleminden T ifadesi nedir?",
          "steps": [
            {"t": "Kuvvetler", "a": "T (yukarı) + F_k (yukarı) = W (aşağı)", "d": "Cisim dengede olduğunda net kuvvet sıfırdır. Yukarı yönlü kuvvetlerin toplamı ağırlığa eşittir."},
            {"t": "T ifadesi", "a": "T = mg - ρ_sıvı·g·V", "d": "m cismin kütlesi, ρ_sıvı sıvı yoğunluğu, V cismin daldırılan hacmidir."}
          ],
          "ans": "T = mg - ρ_sıvı·g·V (T = W - F_k)",
          "o": ["T = mg + ρ_sıvı·g·V", "T = ρ_sıvı·g·V - mg", "T = mg / (ρ_sıvı·g·V)", "T = mg · ρ_sıvı·g·V"]
        }
      ],
      "zor": [
        {
          "q": "U borusunun sol kolunda ρ₁ = 13 600 kg/m³ yoğunluklu cıva h₁ = 10 cm yüksekliğinde durmaktadır. Sağ kolda ρ₂ = 800 kg/m³ yoğunluklu yağ vardır. Denge sağlandığında yağın yüksekliği h₂ kaç cm'dir?",
          "steps": [
            {"t": "Denge", "a": "ρ₁·h₁ = ρ₂·h₂", "d": "13 600 × 10 = 800 × h₂"},
            {"t": "Hesap", "a": "h₂ = 136 000 / 800", "d": "h₂ = 170 cm"},
            {"t": "Sonuç", "a": "h₂ = 170 cm", "d": "Cıva çok yoğun olduğundan yağ sütunu çok uzun olur."}
          ],
          "ans": "170 cm",
          "o": ["10 cm", "13,6 cm", "85 cm", "340 cm"]
        },
        {
          "q": "Kütlesi m = 0,5 kg ve hacmi V = 200 cm³ = 2×10⁻⁴ m³ olan cisim suya (ρ = 1000 kg/m³) tamamen daldırılıyor. Cismin görünür ağırlığı kaç N'dur? (g = 10 m/s²)",
          "steps": [
            {"t": "Gerçek ağırlık", "a": "W = m·g = 0,5 × 10 = 5 N", "d": "Cismin havadaki ağırlığı 5 N'dur."},
            {"t": "Kaldırma kuvveti", "a": "F_k = ρ·g·V = 1000 × 10 × 2×10⁻⁴ = 2 N", "d": "Cismin yerinden ettiği su ağırlığı 2 N'dur."},
            {"t": "Görünür ağırlık", "a": "T = W - F_k = 5 - 2 = 3 N", "d": "Dinamometre 3 N gösterir."}
          ],
          "ans": "3 N",
          "o": ["5 N", "2 N", "7 N", "1 N"]
        },
        {
          "q": "Kütlesi m = 1 kg olan demir bloğu (ρ_demir = 7 800 kg/m³) suya (ρ_su = 1 000 kg/m³) tamamen daldırılıyor. Dinamometre kaç N okur? (g = 10 m/s²)",
          "steps": [
            {"t": "Hacim", "a": "V = m/ρ_demir = 1/7800 ≈ 1,28×10⁻⁴ m³", "d": "Demir bloğun hacmini yoğunluktan hesaplıyoruz."},
            {"t": "Kaldırma kuvveti", "a": "F_k = 1000 × 10 × 1,28×10⁻⁴ ≈ 1,28 N", "d": "Su kaldırma kuvveti yaklaşık 1,28 N'dur."},
            {"t": "Görünür ağırlık", "a": "T = 10 - 1,28 ≈ 8,72 N", "d": "Dinamometre yaklaşık 8,7 N gösterir."}
          ],
          "ans": "≈ 8,7 N",
          "o": ["10 N", "1,28 N", "5 N", "6,5 N"]
        }
      ]
    }
  },

  "toricelli": {
    "lise": {
      "kolay": [
        {
          "q": "Torricelli deneyi nedir ve ne ölçer?",
          "steps": [
            {"t": "Deney", "a": "Cıva dolu tüpün vakuma ters çevrilmesi", "d": "Bir ucu kapalı uzun tüp cıvayla doldurulup cıva dolu kaba baş aşağı çevrilir. Cıva sütunu belirli bir yükseklikte durur."},
            {"t": "Ölçülen büyüklük", "a": "Atmosfer basıncı", "d": "Cıva sütununun yüksekliği atmosfer basıncına eşit basıncı temsil eder: P_atm = ρ_Hg·g·h."}
          ],
          "ans": "Atmosfer basıncını ölçen deney; kapalı tüpte cıva sütunu 76 cm'de denge kurar",
          "o": ["Sıvı yoğunluğunu ölçen deney; cıva sütunu 100 cm'de denge kurar", "Yerçekimi ivmesini ölçen deney; cıva düşüş hızı ölçülür", "Yüzey gerilimini ölçen deney; cıva damlası ağırlığı ölçülür", "Kıvam katsayısını ölçen deney; cıva akış hızı ölçülür"]
        },
        {
          "q": "Torricelli barometresinde cıva sütununun 76 cm yükseklikte durması ne anlama gelir?",
          "steps": [
            {"t": "Anlam", "a": "P_atm = 1 atm = 101 325 Pa", "d": "76 cm'lik cıva sütununun oluşturduğu basınç: P = 13600 × 10 × 0,76 ≈ 103 360 Pa ≈ 1 atm."},
            {"t": "Kısaltma", "a": "76 cmHg = 1 atm = 760 mmHg", "d": "Tıp ve meteorolojide basınç birimi olarak mmHg (torr) kullanılır."}
          ],
          "ans": "Atmosfer basıncı 76 cmHg = 1 atm ≈ 101 325 Pa değerindedir",
          "o": ["Cıvanın yüzey gerilimi 76 cm yüksekliğe karşılık gelir", "Yerçekimi 76 cm başına 1 N kuvvet üretir", "Hava sütununun yoğunluğu 76 g/cm³'tür", "Tüpün üst kısmında basınç 76 Pa'dır"]
        },
        {
          "q": "Torricelli tüpünün üst kısmında (cıvanın üzerinde) ne vardır?",
          "steps": [
            {"t": "İçerik", "a": "Torricelli boşluğu (vakum)", "d": "Tüp cıva ile tamamen dolu olduğundan ters çevrildiğinde üst kısımda hava kalmaz. Bu bölgede basınç sıfıra yakındır."},
            {"t": "Basınç", "a": "P ≈ 0 (yaklaşık vakum)", "d": "Az miktarda cıva buharı bulunsa da basınç ihmal edilebilir düzeydedir."}
          ],
          "ans": "Torricelli boşluğu: yaklaşık sıfır basınçlı vakum",
          "o": ["Sıkıştırılmış hava: yüksek basınçlı gaz", "Su buharı: düşük yoğunluklu gaz karışımı", "Oksijen gazı: atmosferik basıncın yarısı", "Azot gazı: 0,5 atm basıncında"]
        },
        {
          "q": "Yüksek rakımda Torricelli barometresi daha kısa mı yoksa daha uzun mu cıva sütunu gösterir? Neden?",
          "steps": [
            {"t": "Etki", "a": "Daha kısa cıva sütunu", "d": "Yüksek rakımda hava sütunu daha kısa olduğundan atmosfer basıncı düşer. Daha az basınç daha kısa sütunu dengeler."},
            {"t": "Formül", "a": "P_atm = ρ·g·h → h azalır", "d": "P_atm küçüldükçe h = P_atm/(ρ·g) de küçülür."}
          ],
          "ans": "Daha kısa; yüksek rakımda atmosfer basıncı düşer",
          "o": ["Daha uzun; soğuk hava cıvayı yukarı iter", "Aynı; atmosfer basıncı rakımla değişmez", "Daha uzun; hava seyrelince tüpe daha az basınç uygular", "Değişmez; barometreler rakımdan etkilenmez"]
        },
        {
          "q": "Atmosfer basıncı P_atm = ρ_Hg·g·h_Hg formülünde her değişken ne anlama gelir?",
          "steps": [
            {"t": "Değişkenler", "a": "ρ_Hg cıva yoğunluğu, g yer çekimi, h_Hg cıva sütun yüksekliği", "d": "Cıvanın yoğunluğu 13 600 kg/m³, g = 9,8 m/s² ≈ 10 m/s², h_Hg normal koşullarda 0,76 m'dir."},
            {"t": "Birim", "a": "Pa = (kg/m³)·(m/s²)·m = N/m²", "d": "Formüldeki tüm büyüklükler SI birimleri cinsinden girilirse sonuç Pascal cinsinden çıkar."}
          ],
          "ans": "ρ_Hg: cıva yoğunluğu (kg/m³), g: yerçekimi (m/s²), h_Hg: cıva sütun yüksekliği (m)",
          "o": ["ρ_Hg: hava yoğunluğu, g: yüzey gerilimi, h_Hg: tüp uzunluğu", "ρ_Hg: su yoğunluğu, g: yerçekimi, h_Hg: tüp çapı", "ρ_Hg: cıva kütlesi, g: basınç katsayısı, h_Hg: atmosfer kalınlığı", "ρ_Hg: cıva hacmi, g: özgül ağırlık, h_Hg: sıcaklık"]
        }
      ],
      "zor": [
        {
          "q": "Torricelli deneyinde 76 cm cıva sütunu (ρ_Hg = 13 600 kg/m³) 1 atm basıncı temsil etmektedir. Aynı basıncı dengeleyen su sütunu (ρ_su = 1 000 kg/m³) kaç metre olur? (g = 10 m/s²)",
          "steps": [
            {"t": "Basınç eşitliği", "a": "ρ_Hg·g·h_Hg = ρ_su·g·h_su", "d": "g sadeleşir: ρ_Hg·h_Hg = ρ_su·h_su"},
            {"t": "Hesap", "a": "h_su = (13 600 × 0,76) / 1 000", "d": "h_su = 10 336 / 1 000 = 10,336 m ≈ 10,34 m"},
            {"t": "Sonuç", "a": "h_su ≈ 10,34 m", "d": "Su çok daha hafif olduğundan 10 metreden fazla su sütunu gerekir."}
          ],
          "ans": "≈ 10,34 m",
          "o": ["7,6 m", "13,6 m", "1 034 m", "0,76 m"]
        },
        {
          "q": "5 000 m yükseklikte Torricelli barometresi h_Hg = 55 cm göstermektedir. Bu yükseklikteki atmosfer basıncı kaç Pa'dır? (ρ_Hg = 13 600 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "P_atm = ρ_Hg·g·h_Hg", "d": "h_Hg = 0,55 m olarak alınır."},
            {"t": "Hesap", "a": "P = 13 600 × 10 × 0,55", "d": "P = 74 800 Pa"},
            {"t": "Sonuç", "a": "P ≈ 74 800 Pa ≈ 0,74 atm", "d": "5000 m'de basınç deniz seviyesinin yaklaşık %74'üne düşmüştür."}
          ],
          "ans": "74 800 Pa",
          "o": ["55 000 Pa", "101 325 Pa", "136 000 Pa", "37 400 Pa"]
        },
        {
          "q": "1 atm basıncı ρ = 850 kg/m³ yoğunluklu yağ sütunuyla dengelemek için gereken yağ yüksekliği kaç m'dir? (P_atm = 101 325 Pa, g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "h = P_atm / (ρ·g)", "d": "P_atm = ρ·g·h bağıntısından h yalnız bırakılır."},
            {"t": "Hesap", "a": "h = 101 325 / (850 × 10)", "d": "h = 101 325 / 8 500 ≈ 11,92 m"},
            {"t": "Sonuç", "a": "h ≈ 11,92 m", "d": "Yağ sudan hafif olduğundan sudan (≈10,34 m) daha yüksek sütun gerekir."}
          ],
          "ans": "≈ 11,92 m",
          "o": ["8,5 m", "10,34 m", "7,6 m", "13,6 m"]
        }
      ]
    }
  },

  "manometre": {
    "lise": {
      "kolay": [
        {
          "q": "Açık uçlu manometre ne ölçer?",
          "steps": [
            {"t": "Ölçülen büyüklük", "a": "Gösterge (manometrik) basınç", "d": "Açık uçlu manometre, ölçülen basıncın atmosfer basıncına göre farkını ölçer. Buna gösterge basıncı veya manometrik basınç denir."},
            {"t": "Fark", "a": "P_gösterge = P_mutlak - P_atm", "d": "Sıfır noktası atmosfer basıncıdır; manometre bu farkı okur."}
          ],
          "ans": "Gösterge basıncı: ölçülen basınç ile atmosfer basıncı arasındaki fark",
          "o": ["Mutlak basınç: sıfır referanslı toplam basınç", "Vakum basıncı: atmosfer basıncının altındaki değer", "Dinamik basınç: akan sıvının kinetik basıncı", "Osmotik basınç: çözeltideki çözünmüş madde basıncı"]
        },
        {
          "q": "Gösterge basıncı ve mutlak basınç arasındaki ilişki nedir?",
          "steps": [
            {"t": "İlişki", "a": "P_mutlak = P_gösterge + P_atm", "d": "Gösterge basıncı atmosfer basıncına göre ölçüldüğünden mutlak basınç için atmosfer basıncı eklenir."},
            {"t": "Örnek", "a": "P_gösterge = 200 000 Pa → P_mutlak = 301 325 Pa", "d": "P_atm = 101 325 Pa eklenince mutlak basınç elde edilir."}
          ],
          "ans": "P_mutlak = P_gösterge + P_atm",
          "o": ["P_mutlak = P_gösterge - P_atm", "P_mutlak = P_gösterge × P_atm", "P_mutlak = P_gösterge / P_atm", "P_mutlak = P_atm - P_gösterge"]
        },
        {
          "q": "U borusu manometresinde yükseklik farkı (Δh) nasıl okunur ve ne anlama gelir?",
          "steps": [
            {"t": "Okuma", "a": "İki kol arasındaki seviye farkı ölçülür", "d": "Manometre sıvısının (genellikle cıva veya renkli su) iki kolu arasındaki yükseklik farkı Δh, gösterge basıncına karşılık gelir."},
            {"t": "Formül", "a": "P_gösterge = ρ_mano·g·Δh", "d": "ρ_mano manometre sıvısının yoğunluğu, Δh yükseklik farkıdır."}
          ],
          "ans": "Δh iki koldaki sıvı seviyeleri arasındaki fark; P_gösterge = ρ·g·Δh",
          "o": ["Δh tüpün toplam uzunluğu; P_gösterge = ρ·g·L", "Δh en yüksek sıvı seviyesi; P_gösterge = ρ·g·h_max", "Δh atmosfer kolundaki yükseklik; P_gösterge buna eşittir", "Δh ölçülen basınç kolundaki yükseklik; P_gösterge doğrudan Δh'dır"]
        },
        {
          "q": "Kapalı uçlu manometre ne zaman kullanılır?",
          "steps": [
            {"t": "Kullanım yeri", "a": "Kapalı kaplardaki gaz basıncını ölçmek için", "d": "Kapalı uçlu manometre, atmosfere açık olmayan kapalı bir referans vakum veya gaz içerir. Gazı çevresel koşullardan bağımsız mutlak basıncı ölçmek için kullanılır."},
            {"t": "Fark", "a": "Açık → gösterge, Kapalı → mutlak", "d": "Kapalı uçlu manometre sıfır referansı kullanarak mutlak basıncı doğrudan gösterir."}
          ],
          "ans": "Kapalı kap veya boru içindeki gazın mutlak basıncını ölçmek için",
          "o": ["Sıvı akış hızını ölçmek için", "Sıcaklık değişimini izlemek için", "Sıvı seviyesini belirlemek için", "Yüzey gerilimini karşılaştırmak için"]
        },
        {
          "q": "Bir kompresörün manometresindeki gösterge değeri sıfır iken kompresör içindeki gerçek basınç nedir?",
          "steps": [
            {"t": "Sıfır göstergesi", "a": "P_gösterge = 0 → P_mutlak = P_atm", "d": "Gösterge sıfır okuyorsa ölçülen basınç atmosfer basıncına eşittir. Bu vakum ya da yüksek basınç anlamına gelmez."},
            {"t": "Değer", "a": "P_mutlak ≈ 101 325 Pa = 1 atm", "d": "Kompresör içi hava dışarıyla aynı basınçtadır; kompresör çalışmıyor veya deşarj edilmiştir."}
          ],
          "ans": "P_mutlak = P_atm ≈ 101 325 Pa (1 atm)",
          "o": ["P_mutlak = 0 Pa (vakum)", "P_mutlak = 2 × P_atm", "P_mutlak = P_atm / 2", "P_mutlak tanımsızdır"]
        }
      ],
      "zor": [
        {
          "q": "Su dolu (ρ = 1000 kg/m³) açık uçlu manometrede yükseklik farkı Δh = 30 cm'dir. Gösterge basıncı kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "Veri", "a": "ρ = 1000 kg/m³, Δh = 0,30 m, g = 10 m/s²", "d": "Tüm değerler SI birimlerine dönüştürülür."},
            {"t": "Hesap", "a": "P_gösterge = ρ·g·Δh = 1000 × 10 × 0,30", "d": "P_gösterge = 3 000 Pa"},
            {"t": "Sonuç", "a": "P_gösterge = 3 000 Pa", "d": "Bu değer atmosfer basıncının çok küçük bir kısmıdır; düşük basınç ölçümlerinde su manometreleri kullanılır."}
          ],
          "ans": "3 000 Pa",
          "o": ["300 Pa", "30 000 Pa", "1 500 Pa", "6 000 Pa"]
        },
        {
          "q": "Bir sistemin gösterge basıncı P_gösterge = 20 000 Pa ve atmosfer basıncı P_atm = 101 325 Pa'dır. Mutlak basınç kaç Pa'dır?",
          "steps": [
            {"t": "Formül", "a": "P_mutlak = P_gösterge + P_atm", "d": "Gösterge basıncı atmosfer referans noktasına göre ölçülmüştür, mutlak için eklenir."},
            {"t": "Hesap", "a": "P_mutlak = 20 000 + 101 325", "d": "P_mutlak = 121 325 Pa"},
            {"t": "Sonuç", "a": "P_mutlak = 121 325 Pa ≈ 1,20 atm", "d": "Sistem atmosfer basıncının yaklaşık %20 üzerinde çalışmaktadır."}
          ],
          "ans": "121 325 Pa",
          "o": ["81 325 Pa", "20 000 Pa", "101 325 Pa", "202 650 Pa"]
        },
        {
          "q": "Cıva dolu (ρ_Hg = 13 600 kg/m³) bir manometrede yükseklik farkı Δh = 15 cm'dir. Gösterge basıncı kaç Pa'dır? (g = 10 m/s²)",
          "steps": [
            {"t": "Veri", "a": "ρ = 13 600 kg/m³, Δh = 0,15 m", "d": "Cıva manometreleri yüksek basınçlar için kullanılır."},
            {"t": "Hesap", "a": "P_gösterge = 13 600 × 10 × 0,15", "d": "P_gösterge = 20 400 Pa"},
            {"t": "Sonuç", "a": "P_gösterge = 20 400 Pa", "d": "Aynı basıncı su manometresiyle ölçsek Δh = 204 cm olurdu; cıva çok daha pratiktir."}
          ],
          "ans": "20 400 Pa",
          "o": ["1 500 Pa", "40 800 Pa", "2 040 Pa", "13 600 Pa"]
        }
      ]
    }
  },

  "kupBasinc": {
    "lise": {
      "kolay": [
        {
          "q": "Suya daldırılmış bir küpün alt yüzeyine etki eden basınç üst yüzeyden neden daha büyüktür?",
          "steps": [
            {"t": "Neden", "a": "Alt yüzey daha derindedir", "d": "P = ρ·g·h bağıntısına göre derinlik arttıkça basınç artar. Alt yüzey, üst yüzeyden küpün boyutu kadar daha derinde bulunur."},
            {"t": "Sonuç", "a": "P_alt > P_üst", "d": "Bu basınç farkı yukarı yönde net bir kuvvet oluşturur."}
          ],
          "ans": "Alt yüzey daha derin olduğundan P_alt > P_üst; bu fark kaldırma kuvvetini yaratır",
          "o": ["Alt yüzeyin alanı üst yüzeyden büyüktür", "Alt yüzeyde yüzey gerilimi daha fazladır", "Alt yüzey suya daha yakın olduğundan daha az direnç vardır", "Alt ve üst yüzeylerde basınç eşittir fakat yönleri farklıdır"]
        },
        {
          "q": "Suya daldırılmış bir küp üzerindeki net basınç kuvvetinin yönü nedir?",
          "steps": [
            {"t": "Yön analizi", "a": "Net kuvvet yukarı yönlüdür", "d": "Alt yüzeydeki basınç kuvveti (yukarı) üst yüzeydeki basınç kuvvetinden (aşağı) büyük olduğundan net kuvvet yukarı yönde oluşur."},
            {"t": "İsim", "a": "Bu kaldırma kuvveti = Arşimet kuvvetidir", "d": "F_net = F_alt - F_üst = ρ·g·V_küp"}
          ],
          "ans": "Yukarı yönde; alt-üst yüzey arasındaki basınç farkından kaynaklanır",
          "o": ["Aşağı yönde; suyun ağırlığı baskındır", "Yatay yönde; basınç yanlara doğru iter", "Yüzeye dik yönde; basınç kuvveti yüzeyden dışarı çıkar", "Her yönde eşit; küp dengede olduğundan net kuvvet sıfırdır"]
        },
        {
          "q": "Suya daldırılmış bir küpün her yüzeyine etki eden basınç kuvveti (F = P·A) hesabında A neyi temsil eder?",
          "steps": [
            {"t": "A değişkeni", "a": "Yüzeyin alanı (m²)", "d": "F = P·A formülünde P basınç (Pa = N/m²), A ise kuvvetin etki ettiği yüzeyin alanıdır. F = (N/m²) × m² = N."},
            {"t": "Küp için", "a": "A = a² (kenar uzunluğunun karesi)", "d": "Kenar uzunluğu a olan bir küpün her yüzey alanı a²'dir."}
          ],
          "ans": "Yüzeyin alanı (m²); F = P·A = ρ·g·h·a²",
          "o": ["Sıvı molekül sayısı", "Kuvvetin etki süresi", "Yüzeye çarpan sıvı kütlesi", "Yüzey gerilim katsayısı"]
        },
        {
          "q": "Suya daldırılmış bir küp üzerindeki net yukarı kuvvetin Arşimet kuvvetine eşit olduğu nasıl gösterilir?",
          "steps": [
            {"t": "Net kuvvet", "a": "F_net = F_alt - F_üst", "d": "F_alt = ρ·g·h_alt·A ve F_üst = ρ·g·h_üst·A olduğundan F_net = ρ·g·(h_alt - h_üst)·A = ρ·g·a·A."},
            {"t": "Hacim bağlantısı", "a": "a·A = V_küp", "d": "h_alt - h_üst = a (küpün kenarı) ve A·a = V_küp olduğundan F_net = ρ·g·V_küp = F_Arşimet."}
          ],
          "ans": "F_net = ρ·g·(h_alt - h_üst)·A = ρ·g·V_küp; Arşimet kuvvetine eşittir",
          "o": ["F_net = ρ·g·h_alt·A; üst yüzey ihmal edilir", "F_net = m_sıvı·g; sıvının toplam ağırlığına eşittir", "F_net = P_atm·A; atmosfer basıncından kaynaklanır", "F_net = ρ_cisim·g·V; cisim yoğunluğuyla hesaplanır"]
        },
        {
          "q": "Arşimet prensibi nedir ve basınç farkıyla nasıl ilişkilidir?",
          "steps": [
            {"t": "Prensip", "a": "Kaldırma kuvveti = yerinden etilen sıvı ağırlığı", "d": "Bir cisim sıvıya daldırıldığında sıvı, cismin işgal ettiği hacme eşit miktarı yerinden eder ve bu sıvının ağırlığına eşit kuvveti cisime yukarı yönde uygular."},
            {"t": "Bağlantı", "a": "Basınç farkı → yukarı kuvvet = Arşimet kuvveti", "d": "Alt ve üst yüzey arasındaki basınç farkı nedeniyle oluşan net kuvvet, birebir Arşimet prensibiyle örtüşür."}
          ],
          "ans": "Cisim, ağırlığı yerinden ettiği sıvı ağırlığına eşit kaldırma kuvvetiyle karşılaşır; bu basınç farkından kaynaklanır",
          "o": ["Cisim, kendi ağırlığına eşit basınç kuvveti alır ve denge kurar", "Kaldırma kuvveti sıvının toplam ağırlığına eşittir", "Cisim sıvıyla temas eden yüzey alanıyla orantılı kuvvet alır", "Kaldırma kuvveti atmosfer basıncıyla belirlenir"]
        }
      ],
      "zor": [
        {
          "q": "Kenar uzunluğu a = 10 cm olan bir çelik küp suya daldırılmıştır. Üst yüzey h_üst = 1,0 m, alt yüzey h_alt = 1,1 m derinliğindedir. (ρ_su = 1000 kg/m³, g = 10 m/s²) Üst ve alt yüzeye etki eden kuvvetleri ve net yukarı kuvveti hesaplayınız.",
          "steps": [
            {"t": "Alan", "a": "A = (0,10)² = 0,01 m²", "d": "Küpün kenar uzunluğu 10 cm = 0,10 m; her yüzey alanı 0,01 m²."},
            {"t": "Kuvvetler", "a": "F_üst = 1000·10·1,0·0,01 = 100 N (aşağı); F_alt = 1000·10·1,1·0,01 = 110 N (yukarı)", "d": "Basınç kuvveti yüzeye dik yönde etki eder."},
            {"t": "Net kuvvet", "a": "F_net = 110 - 100 = 10 N (yukarı)", "d": "Bu değer F_k = ρ·g·V = 1000·10·0,001 = 10 N ile örtüşür."}
          ],
          "ans": "F_üst = 100 N (aşağı), F_alt = 110 N (yukarı), F_net = 10 N (yukarı)",
          "o": ["F_üst = 110 N, F_alt = 100 N, F_net = 10 N (aşağı)", "F_üst = 100 N, F_alt = 100 N, F_net = 0 N", "F_üst = 50 N, F_alt = 55 N, F_net = 5 N (yukarı)", "F_üst = 1000 N, F_alt = 1100 N, F_net = 100 N (yukarı)"]
        },
        {
          "q": "Kenar uzunluğu a = 20 cm olan bir küp suya daldırılmıştır. Üst yüzey h_üst = 0,5 m, alt yüzey h_alt = 0,7 m derinliğindedir. (ρ_su = 1000 kg/m³, g = 10 m/s²) Net kaldırma kuvveti kaç N'dur?",
          "steps": [
            {"t": "Alan ve hacim", "a": "A = (0,20)² = 0,04 m², V = (0,20)³ = 0,008 m³", "d": "20 cm = 0,20 m"},
            {"t": "Kuvvetler", "a": "F_üst = 1000·10·0,5·0,04 = 200 N; F_alt = 1000·10·0,7·0,04 = 280 N", "d": "Her iki yüzey kuvveti hesaplanır."},
            {"t": "Net kuvvet", "a": "F_net = 280 - 200 = 80 N", "d": "Kontrol: F_k = ρ·g·V = 1000·10·0,008 = 80 N ✓"}
          ],
          "ans": "80 N",
          "o": ["20 N", "40 N", "200 N", "480 N"]
        },
        {
          "q": "Suya (ρ = 1000 kg/m³) tamamen daldırılmış, kenar uzunluğu a = 5 cm olan bir küpün basınç farkından hesaplanan kaldırma kuvveti kaç N'dur? Küpün üst yüzeyi h = 2 m derinliğindedir. (g = 10 m/s²)",
          "steps": [
            {"t": "Derinlikler", "a": "h_üst = 2,0 m, h_alt = 2,05 m", "d": "Kenar uzunluğu 5 cm = 0,05 m olduğundan alt yüzey 0,05 m daha derindedir."},
            {"t": "Alan ve kuvvetler", "a": "A = (0,05)² = 0,0025 m²; F_üst = 1000·10·2,00·0,0025 = 50 N; F_alt = 1000·10·2,05·0,0025 = 51,25 N", "d": "Her iki yüzey için hesap."},
            {"t": "Net kuvvet", "a": "F_net = 51,25 - 50 = 1,25 N", "d": "Kontrol: F_k = ρ·g·V = 1000·10·(0,05)³ = 1000·10·0,000125 = 1,25 N ✓"}
          ],
          "ans": "1,25 N",
          "o": ["50 N", "0,50 N", "2,50 N", "12,5 N"]
        }
      ]
    }
  }
};
