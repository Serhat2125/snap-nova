globalThis.__BQ = {
  "potansiyel": {
    "lise": {
      "kolay": [
        {
          "q": "Bir nokta yükün oluşturduğu elektriksel potansiyel hangi formülle hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "V = k·Q/r", "d": "k = 9×10⁹ N·m²/C², Q yük miktarı, r uzaklık."},
            {"t": "Birim", "a": "Volt (V)", "d": "Potansiyel birimi Volt'tur; 1 V = 1 J/C."}
          ],
          "ans": "V = k·Q/r",
          "o": ["V = k·Q·r", "V = k·Q/r²", "V = Q/(4πr)", "V = k·r/Q"]
        },
        {
          "q": "Elektriksel potansiyel bir skaler mi yoksa vektör mü büyüklüktür?",
          "steps": [
            {"t": "Tanım", "a": "Skaler büyüklüktür.", "d": "Potansiyelin yönü yoktur; yalnızca sayısal değeri (ve işareti) vardır."},
            {"t": "Fark", "a": "Elektrik alanı E vektörsel, potansiyel V skelerdir.", "d": "Bu nedenle birden fazla yükün potansiyelleri cebirsel olarak toplanır."}
          ],
          "ans": "Skaler büyüklük",
          "o": ["Vektör büyüklük", "Hem skaler hem vektör", "Yalnızca pozitif olduğunda vektör", "Tensör büyüklük"]
        },
        {
          "q": "q yükünü A noktasından B noktasına taşımak için yapılan iş W = q·ΔV formülüyle bulunur. ΔV = 50 V ve q = 2 C ise W kaç Joule'dür?",
          "steps": [
            {"t": "Formül", "a": "W = q·ΔV", "d": "Yapılan iş = yük × potansiyel farkı."},
            {"t": "Hesap", "a": "W = 2 × 50 = 100 J", "d": "2 C yükü 50 V'luk fark boyunca taşımak 100 J iş gerektirir."}
          ],
          "ans": "100 J",
          "o": ["25 J", "50 J", "200 J", "400 J"]
        },
        {
          "q": "Eş potansiyel yüzeyler ile elektrik alan çizgileri arasındaki açı nedir?",
          "steps": [
            {"t": "Tanım", "a": "90° (dik açı)", "d": "Eş potansiyel yüzeyler boyunca hareket etmek iş gerektirmez, dolayısıyla alan kuvveti bu yüzeylere dik olmalıdır."},
            {"t": "Sonuç", "a": "E ⊥ eş potansiyel yüzey", "d": "Alan çizgileri daima yüksek potansiyelden alçak potansiyele doğru gider."}
          ],
          "ans": "90°",
          "o": ["0°", "45°", "180°", "60°"]
        },
        {
          "q": "Pozitif bir yükün bulunduğu noktadan uzaklaştıkça potansiyel nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "V = k·Q/r → r artınca V azalır.", "d": "r paydada olduğundan uzaklık arttıkça V küçülür."},
            {"t": "Limit", "a": "r → ∞ iken V → 0", "d": "Sonsuzda referans potansiyel sıfır kabul edilir."}
          ],
          "ans": "Azalır (V → 0)",
          "o": ["Artar", "Değişmez", "Önce artar sonra azalır", "Negatif olur"]
        }
      ],
      "zor": [
        {
          "q": "r = 0,3 m uzaklıkta V = 300 V olan bir nokta yükün büyüklüğü nedir? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Formül", "a": "V = k·Q/r → Q = V·r/k", "d": "Q'yu bulmak için formülü Q'ya göre düzenle."},
            {"t": "Hesap", "a": "Q = 300 × 0,3 / (9×10⁹) = 90 / (9×10⁹) = 10⁻⁸ C = 10 nC", "d": "Sonuç 10 nanocoulomb'dur."}
          ],
          "ans": "10 nC (10⁻⁸ C)",
          "o": ["1 nC", "100 nC", "1 μC", "0,1 nC"]
        },
        {
          "q": "+Q ve −Q yükleri r uzaklıkta bulunuyor. Bu iki yükün tam ortasındaki net potansiyel nedir?",
          "steps": [
            {"t": "Her yükün katkısı", "a": "V₊ = k·Q/(r/2), V₋ = k·(−Q)/(r/2)", "d": "Her yük orta noktaya r/2 uzaklıktadır."},
            {"t": "Toplam", "a": "V_net = V₊ + V₋ = kQ/(r/2) − kQ/(r/2) = 0", "d": "Potansiyel skelerdir; eşit büyüklüklü zıt işaretli katkılar sıfırlanır."}
          ],
          "ans": "0 V",
          "o": ["2kQ/r", "kQ/r", "−kQ/r", "kQ/r²"]
        },
        {
          "q": "Bir elektron (q = −1,6×10⁻¹⁹ C) 200 V'luk potansiyel farkı boyunca hızlanıyor. Elektrona yapılan iş nedir?",
          "steps": [
            {"t": "Formül", "a": "W = q·ΔV", "d": "Elektron negatif yüklüdür."},
            {"t": "Hesap", "a": "W = (−1,6×10⁻¹⁹) × 200 = −3,2×10⁻¹⁷ J", "d": "İşaret: elektron yüksek potansiyelden alçağa gittiğinde sisteme enerji verilir; hız artar."},
            {"t": "Kinetik enerji artışı", "a": "ΔEk = |W| = 3,2×10⁻¹⁷ J", "d": "Elektronun kinetik enerjisi 3,2×10⁻¹⁷ J artar."}
          ],
          "ans": "−3,2×10⁻¹⁷ J (kinetik enerji 3,2×10⁻¹⁷ J artar)",
          "o": ["3,2×10⁻¹⁷ J", "1,6×10⁻¹⁷ J", "6,4×10⁻¹⁷ J", "0 J"]
        }
      ]
    }
  },
  "potEnerji": {
    "lise": {
      "kolay": [
        {
          "q": "İki nokta yük arasındaki elektriksel potansiyel enerji hangi formülle hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "U = k·q₁·q₂/r", "d": "k Coulomb sabiti, q₁ ve q₂ yükler, r aralarındaki uzaklık."},
            {"t": "Birim", "a": "Joule (J)", "d": "Potansiyel enerji Joule cinsinden ifade edilir."}
          ],
          "ans": "U = k·q₁·q₂/r",
          "o": ["U = k·q₁·q₂·r", "U = k·(q₁+q₂)/r", "U = k·q₁·q₂/r²", "U = (q₁·q₂)/(4πr²)"]
        },
        {
          "q": "Zıt işaretli iki yük arasındaki potansiyel enerji pozitif mi, negatif mi olur?",
          "steps": [
            {"t": "İşaret analizi", "a": "U = k·q₁·q₂/r; q₁ ve q₂ zıt işaretli → çarpım negatif → U < 0", "d": "Negatif U, sistemin bağlı olduğunu gösterir; yükleri ayırmak için iş yapılması gerekir."},
            {"t": "Fiziksel anlam", "a": "U < 0 → çekici sistem", "d": "Yükler birbirini çektiğinden potansiyel enerji referansa göre düşüktür."}
          ],
          "ans": "Negatif (U < 0)",
          "o": ["Pozitif (U > 0)", "Sıfır", "Her zaman pozitif", "Uzaklığa bağlı olarak değişir ancak sıfırdan büyüktür"]
        },
        {
          "q": "Aynı işaretli iki yük arasındaki potansiyel enerji ne anlam taşır?",
          "steps": [
            {"t": "İşaret", "a": "q₁ ve q₂ aynı işaretli → U = k·q₁·q₂/r > 0", "d": "Pozitif potansiyel enerji: yükler iticidirler."},
            {"t": "Fiziksel anlam", "a": "U > 0 → sistem enerji depolamış", "d": "Yükler bırakıldığında bu enerji kinetik enerjiye dönüşür."}
          ],
          "ans": "Pozitif (U > 0) — itici sistem",
          "o": ["Negatif (U < 0) — çekici", "Sıfır", "Yüklerin büyüklüğüne bağlıdır", "Daima sabittir"]
        },
        {
          "q": "Bir yükü A'dan B'ye taşırken yapılan iş W = −ΔU = −(U_B − U_A) formülüyle verilir. U_A = 20 J, U_B = 8 J ise yapılan iş nedir?",
          "steps": [
            {"t": "Hesap", "a": "ΔU = U_B − U_A = 8 − 20 = −12 J", "d": "Potansiyel enerji 12 J azaldı."},
            {"t": "İş", "a": "W = −ΔU = −(−12) = +12 J", "d": "Sistem dışarıya 12 J iş yapar."}
          ],
          "ans": "+12 J",
          "o": ["−12 J", "28 J", "−28 J", "0 J"]
        },
        {
          "q": "İki yük arasındaki uzaklık 2 katına çıkarılırsa potansiyel enerji nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "U = k·q₁·q₂/r", "d": "U, r ile ters orantılıdır."},
            {"t": "Değişim", "a": "r → 2r ise U → U/2", "d": "Uzaklık 2 katına çıkınca potansiyel enerji yarıya düşer."}
          ],
          "ans": "Yarıya düşer",
          "o": ["Dörtte birine düşer", "İki katına çıkar", "Dört katına çıkar", "Değişmez"]
        }
      ],
      "zor": [
        {
          "q": "q₁ = +2 μC ve q₂ = −3 μC yükleri r = 0,1 m uzakta. Sistemin potansiyel enerjisi nedir? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Değerleri yerine koy", "a": "U = k·q₁·q₂/r = 9×10⁹ × (2×10⁻⁶) × (−3×10⁻⁶) / 0,1", "d": "Her büyüklüğü dikkatli çevir."},
            {"t": "Hesap", "a": "= 9×10⁹ × (−6×10⁻¹²) / 0,1 = −54×10⁻³ / 0,1 = −0,54 J", "d": "Negatif değer çekici sistemi gösterir."}
          ],
          "ans": "−0,54 J",
          "o": ["0,54 J", "−5,4 J", "0,054 J", "−0,054 J"]
        },
        {
          "q": "Üç eşit pozitif yük Q, eşkenar üçgenin köşelerine yerleştiriliyor; kenar uzunluğu a. Sistemin toplam potansiyel enerjisi nedir?",
          "steps": [
            {"t": "Çift sayısı", "a": "3 çift var: (1,2), (1,3), (2,3)", "d": "Her çiftin uzaklığı a'dır."},
            {"t": "Her çiftin enerjisi", "a": "U_çift = kQ²/a", "d": "Her çift aynı uzaklıkta ve aynı yüklerde."},
            {"t": "Toplam", "a": "U_toplam = 3·kQ²/a", "d": "Üç çiftin toplamı alınır."}
          ],
          "ans": "3·k·Q²/a",
          "o": ["kQ²/a", "2kQ²/a", "kQ²/(3a)", "kQ³/a"]
        },
        {
          "q": "Proton (q = +1,6×10⁻¹⁹ C, m = 1,67×10⁻²⁷ kg) çok uzaktan hareketsizken +Q = 2×10⁻⁹ C yükün 0,1 m yakınına geliyor. Protonun bu noktadaki hızını enerji korunumundan bulun.",
          "steps": [
            {"t": "Enerji korunumu", "a": "Ek_başlangıç + U_başlangıç = Ek_son + U_son", "d": "Başlangıçta her ikisi de sıfır: ∞ uzaklıkta U→0, v=0."},
            {"t": "U_son", "a": "U = kQq/r = 9×10⁹×2×10⁻⁹×1,6×10⁻¹⁹/0,1 = 2,88×10⁻¹⁷ J", "d": "İki pozitif yük arasında itici etkili."},
            {"t": "Ancak", "a": "Proton uzaktan gelirken enerjisi artmaz; bu kez proton enerji harcamak zorunda.", "d": "Proton pozitif alana karşı hareket ediyor → başlangıçta kinetik enerji olması lazım."},
            {"t": "Minimum kinetik enerji", "a": "Ek_gerekli = U = 2,88×10⁻¹⁷ J → v = √(2Ek/m)", "d": "v = √(2×2,88×10⁻¹⁷/1,67×10⁻²⁷) ≈ 5,88×10⁵ m/s"}
          ],
          "ans": "≈ 5,9×10⁵ m/s (minimum başlangıç hızı gerekir)",
          "o": ["≈ 1,2×10⁵ m/s", "≈ 3×10⁶ m/s", "0 m/s (enerji gerekmez)", "≈ 5,9×10³ m/s"]
        }
      ]
    }
  },
  "paralelLevha": {
    "lise": {
      "kolay": [
        {
          "q": "Paralel levhalar arasındaki düzgün elektrik alan şiddeti hangi formülle hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "E = V/d", "d": "V: levhalar arası potansiyel fark, d: levhalar arası mesafe."},
            {"t": "Birim", "a": "V/m veya N/C", "d": "Her iki birim de elektrik alan birimidir."}
          ],
          "ans": "E = V/d",
          "o": ["E = V·d", "E = d/V", "E = V²/d", "E = V/(d²)"]
        },
        {
          "q": "Paralel levhalar arasındaki elektrik alan çizgileri nasıldır?",
          "steps": [
            {"t": "Özellik", "a": "Paralel ve birbirine eşit aralıklı", "d": "Düzgün (uniform) alan — her noktada alan şiddeti ve yönü aynı."},
            {"t": "Yön", "a": "Pozitif levhadan negatif levhaya", "d": "Alan çizgileri + yükten − yüke doğru gider."}
          ],
          "ans": "Paralel ve eşit aralıklı (düzgün alan)",
          "o": ["Levhalara paralel", "Dairesel", "Radyal (dışa yayılan)", "Rastgele yönlerde"]
        },
        {
          "q": "Levhalar arası mesafe d = 0,05 m, potansiyel fark V = 250 V ise alan şiddeti nedir?",
          "steps": [
            {"t": "Formül", "a": "E = V/d", "d": "Değerleri yerleştir."},
            {"t": "Hesap", "a": "E = 250/0,05 = 5000 V/m", "d": "Alan 5000 V/m'dir."}
          ],
          "ans": "5000 V/m",
          "o": ["500 V/m", "12,5 V/m", "250 V/m", "10000 V/m"]
        },
        {
          "q": "Paralel levhaların dışında elektrik alan ne kadardır (ideal kondansatör)?",
          "steps": [
            {"t": "İdeal durum", "a": "Dışarıda E = 0", "d": "Levhaların oluşturduğu alanlar dışarıda birbirini iptal eder; alan yalnızca levhalar arasında vardır."},
            {"t": "Gerçek durum", "a": "Kenarlarda saçak (fringe) etkileri görülebilir.", "d": "Ancak lise düzeyinde levhalar dışında alan sıfır kabul edilir."}
          ],
          "ans": "Sıfır (E = 0)",
          "o": ["E = V/2d", "E = V/d (aynı değer)", "Sonsuz büyük", "Negatif değerde"]
        },
        {
          "q": "Paralel levhalardan oluşan bir yapı hangi temel devre elemanının modelidir?",
          "steps": [
            {"t": "Tanım", "a": "Kondansatör (kapasitör)", "d": "Paralel levhalar kondansatörün temel yapısıdır; yük depolar."},
            {"t": "Kapasite", "a": "C = ε₀·A/d", "d": "Alan A büyükçe, mesafe d küçükçe kapasite artar."}
          ],
          "ans": "Kondansatör",
          "o": ["Direnç", "Bobin (endüktans)", "Diyot", "Transistör"]
        }
      ],
      "zor": [
        {
          "q": "Paralel levhalı kondansatörde levhalar arası mesafe iki katına çıkarılırken potansiyel fark sabit tutuluyor. Alan şiddeti ve yüzey yük yoğunluğu nasıl değişir?",
          "steps": [
            {"t": "Alan", "a": "E = V/d → d iki katına çıkınca E yarıya düşer.", "d": "V sabit, d büyüdü."},
            {"t": "Yük yoğunluğu", "a": "σ = ε₀·E → σ da yarıya düşer.", "d": "E azalınca yüzey yük yoğunluğu da azalır."},
            {"t": "Sonuç", "a": "Her iki büyüklük de yarıya iner.", "d": "Kondansatörün depoladığı yük azalır."}
          ],
          "ans": "Her ikisi de yarıya düşer",
          "o": ["Alan artar, yük yoğunluğu sabit kalır", "Alan sabit, yük yoğunluğu artar", "İkisi de iki katına çıkar", "Alan sabit kalır, yük yoğunluğu yarıya düşer"]
        },
        {
          "q": "V = 400 V, d = 0,02 m olan paralel levhalar arasına diyagonal 45° açıyla q = 1 μC, m = 10⁻⁶ kg yük giriliyor. Yükün dikey ivmesi nedir?",
          "steps": [
            {"t": "Alan", "a": "E = V/d = 400/0,02 = 20000 V/m", "d": "Düzgün alan."},
            {"t": "Kuvvet", "a": "F = qE = 1×10⁻⁶ × 20000 = 0,02 N", "d": "Dikey yöndeki elektrostatik kuvvet."},
            {"t": "İvme", "a": "a = F/m = 0,02/10⁻⁶ = 2×10⁴ m/s²", "d": "Yükün kütlesi küçük olduğundan ivme büyüktür."}
          ],
          "ans": "2×10⁴ m/s²",
          "o": ["2×10² m/s²", "2×10³ m/s²", "4×10⁴ m/s²", "2×10⁵ m/s²"]
        },
        {
          "q": "Paralel levhalar arasında V = 600 V, d = 0,03 m. Bu alana dik bir eş potansiyel yüzeyde iki nokta arasında 5 C yük taşıyorsak yapılan iş nedir?",
          "steps": [
            {"t": "Eş potansiyel", "a": "Eş potansiyel yüzey üzerinde ΔV = 0", "d": "Eş potansiyel boyunca hareket edildiğinde potansiyel değişmez."},
            {"t": "İş", "a": "W = q·ΔV = q × 0 = 0 J", "d": "Potansiyel fark sıfır olduğundan hiç iş yapılmaz."}
          ],
          "ans": "0 J",
          "o": ["3000 J", "300 J", "10 J", "150 J"]
        }
      ]
    }
  },
  "parcacikSapma": {
    "lise": {
      "kolay": [
        {
          "q": "Düzgün elektrik alana dik giren yüklü bir parçacık nasıl bir yol izler?",
          "steps": [
            {"t": "Yatay", "a": "Sabit hız (ivme yok)", "d": "Alan yatay bileşen oluşturmaz."},
            {"t": "Dikey", "a": "Düzgün ivmeli hareket (F = qE)", "d": "Mermi hareketi benzeşimi: yatay = düzgün, dikey = düzgün ivmeli."},
            {"t": "Sonuç", "a": "Parabolik yol", "d": "Atış hareketi ile aynı kinematik yapı."}
          ],
          "ans": "Parabolik",
          "o": ["Dairesel", "Düz çizgi", "Eliptik", "Hiperbolik"]
        },
        {
          "q": "Elektrik alan içindeki yüklü parçacığın dikey ivmesi hangi formülle hesaplanır?",
          "steps": [
            {"t": "Kuvvet", "a": "F = q·E", "d": "Elektrik kuvveti."},
            {"t": "İkinci yasa", "a": "F = m·a → a = qE/m", "d": "Newton'un ikinci yasası ile ivme bulunur."}
          ],
          "ans": "a = qE/m",
          "o": ["a = m/(qE)", "a = q/(mE)", "a = qm/E", "a = E/(qm)"]
        },
        {
          "q": "E = 5000 V/m, q = 1,6×10⁻¹⁹ C, m = 9,1×10⁻³¹ kg olan elektron için dikey ivmeyi bulun.",
          "steps": [
            {"t": "Formül", "a": "a = qE/m", "d": "Değerleri yerleştir."},
            {"t": "Hesap", "a": "a = (1,6×10⁻¹⁹ × 5000) / 9,1×10⁻³¹ ≈ 8,8×10¹⁴ m/s²", "d": "Elektronun kütlesi çok küçük olduğundan ivme çok büyüktür."}
          ],
          "ans": "≈ 8,8×10¹⁴ m/s²",
          "o": ["≈ 8,8×10¹¹ m/s²", "≈ 8,8×10¹² m/s²", "≈ 8,8×10¹⁶ m/s²", "≈ 8,8×10⁹ m/s²"]
        },
        {
          "q": "Paralel levhalar arasına yatay hızla giren parçacığın yatay bileşeninde ne olur?",
          "steps": [
            {"t": "Yatay yön", "a": "Elektrik kuvveti dikey yönde etkir.", "d": "Yatay yönde net kuvvet yoktur."},
            {"t": "Sonuç", "a": "Yatay hız sabit kalır (v_x = v₀)", "d": "Atış hareketi ile özdeş."}
          ],
          "ans": "Sabit kalır",
          "o": ["Azalır", "Artar", "Önce azalır sonra artar", "Sıfıra düşer"]
        },
        {
          "q": "Yüklü parçacık elektrik alan içine girerken hangi fizik konusundaki hareket kalıbını taklit eder?",
          "steps": [
            {"t": "Benzerlik", "a": "Yatay atış hareketi (mermi hareketi)", "d": "Yatay: sabit hız; dikey: düzgün ivmeli hareket."},
            {"t": "Fark", "a": "Gravitasyonel ivme yerine a = qE/m ivmesi geçer.", "d": "Formüllerin yapısı özdeştir."}
          ],
          "ans": "Yatay atış hareketi",
          "o": ["Düşey serbest düşme", "Dairesel hareket", "Basit harmonik hareket", "Eğik atış hareketi"]
        }
      ],
      "zor": [
        {
          "q": "v₀ = 2×10⁶ m/s yatay hızla giren proton (q = 1,6×10⁻¹⁹ C, m = 1,67×10⁻²⁷ kg), E = 2×10⁴ V/m dikey alana giriyor. L = 0,1 m uzunluktaki levhalardan çıkarken dikey sapma ne kadardır?",
          "steps": [
            {"t": "Geçiş süresi", "a": "t = L/v₀ = 0,1/(2×10⁶) = 5×10⁻⁸ s", "d": "Yatay hız sabittir."},
            {"t": "Dikey ivme", "a": "a = qE/m = (1,6×10⁻¹⁹×2×10⁴)/(1,67×10⁻²⁷) ≈ 1,92×10¹² m/s²", "d": "Proton için ivme."},
            {"t": "Sapma", "a": "y = ½·a·t² = ½×1,92×10¹²×(5×10⁻⁸)² = ½×1,92×10¹²×2,5×10⁻¹⁵ ≈ 2,4×10⁻³ m", "d": "Yaklaşık 2,4 mm sapma oluşur."}
          ],
          "ans": "≈ 2,4 mm",
          "o": ["≈ 0,24 mm", "≈ 24 mm", "≈ 0,024 mm", "≈ 4,8 mm"]
        },
        {
          "q": "Elektron ile proton aynı E alanına aynı başlangıç hızıyla sokuluyor. Hangisinin sapması daha fazla olur ve neden?",
          "steps": [
            {"t": "İvme karşılaştırması", "a": "a = qE/m; her ikisinde de q değerleri eşit büyüklükte.", "d": "Fark kütlede: m_e << m_p."},
            {"t": "Elektron ivmesi", "a": "a_e = eE/m_e, daha büyük (m_e ≈ 1/1836 m_p)", "d": "Elektron çok daha hafif."},
            {"t": "Sapma", "a": "y = ½·a·t², a büyük → y büyük → elektron daha çok sapar.", "d": "Ama yön zıt: elektron alana ters, proton alan yönünde sapar."}
          ],
          "ans": "Elektron daha fazla sapar (kütlesi 1836 kat küçük)",
          "o": ["Proton daha fazla sapar (yükü büyük)", "Eşit saparlar (yükler eşit)", "Proton daha fazla sapar (kütlesi büyük, ivme küçük ama ivme büyük)", "Hiçbiri sapmaz"]
        },
        {
          "q": "Levhadan çıkan parçacığın dikey hızı v_y = a·t ise çıkış hızının yatayla yaptığı açı θ nedir? (v₀ = 10⁶ m/s, v_y = 10⁵ m/s)",
          "steps": [
            {"t": "Trigonometri", "a": "tan θ = v_y / v_x = v_y / v₀", "d": "Yatay bileşen değişmez."},
            {"t": "Hesap", "a": "tan θ = 10⁵/10⁶ = 0,1 → θ ≈ 5,7°", "d": "arctan(0,1) ≈ 5,7°."}
          ],
          "ans": "≈ 5,7°",
          "o": ["≈ 45°", "≈ 10°", "≈ 30°", "≈ 1°"]
        }
      ]
    }
  },
  "kondansator": {
    "lise": {
      "kolay": [
        {
          "q": "Kondansatörün kapasitesi hangi formülle tanımlanır?",
          "steps": [
            {"t": "Tanım", "a": "C = Q/V", "d": "C: kapasite (Farad), Q: depolanan yük (Coulomb), V: gerilim (Volt)."},
            {"t": "Birim", "a": "1 F = 1 C/V", "d": "Farad büyük bir birimdir; genellikle μF veya pF kullanılır."}
          ],
          "ans": "C = Q/V",
          "o": ["C = V/Q", "C = Q·V", "C = Q²/V", "C = V²/Q"]
        },
        {
          "q": "Paralel levhalı kondansatörün kapasitesi hangi formülle hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "C = ε₀·A/d", "d": "ε₀ = 8,85×10⁻¹² F/m; A: levha yüz alanı, d: levhalar arası mesafe."},
            {"t": "Yorum", "a": "A büyük veya d küçükse kapasite artar.", "d": "Levhalar geniş ve yakın olursa daha fazla yük depolanır."}
          ],
          "ans": "C = ε₀·A/d",
          "o": ["C = ε₀·d/A", "C = A/(ε₀·d)", "C = ε₀·A·d", "C = ε₀/(A·d)"]
        },
        {
          "q": "Kondansatörde depolanan enerji hangi formüllerle ifade edilir?",
          "steps": [
            {"t": "Formüller", "a": "U = ½C·V² = Q²/(2C) = ½Q·V", "d": "Üç eşdeğer ifade; Q = C·V ilişkisi kullanılır."},
            {"t": "Birim", "a": "Joule (J)", "d": "Enerji SI biriminde Joule'dür."}
          ],
          "ans": "U = ½C·V²",
          "o": ["U = C·V²", "U = ½C·V", "U = C·V", "U = 2C·V²"]
        },
        {
          "q": "Paralel bağlı iki kondansatörün eşdeğer kapasitesi nasıl bulunur?",
          "steps": [
            {"t": "Paralel bağlantı", "a": "C_eş = C₁ + C₂", "d": "Paralelde kapasiteler toplanır; dirençlerin serisine benzer."},
            {"t": "Örnek", "a": "C₁ = 3 μF, C₂ = 5 μF → C_eş = 8 μF", "d": "Toplam kapasite artar."}
          ],
          "ans": "C_eş = C₁ + C₂",
          "o": ["1/C_eş = 1/C₁ + 1/C₂", "C_eş = C₁ · C₂", "C_eş = C₁ − C₂", "C_eş = (C₁ + C₂)/2"]
        },
        {
          "q": "Seri bağlı iki kondansatörün eşdeğer kapasitesi nasıl bulunur?",
          "steps": [
            {"t": "Seri bağlantı", "a": "1/C_eş = 1/C₁ + 1/C₂", "d": "Seride ters kapasiteler toplanır; dirençlerin paralelindeki gibi."},
            {"t": "Örnek", "a": "C₁ = C₂ = 4 μF → 1/C_eş = 1/4+1/4 = 1/2 → C_eş = 2 μF", "d": "Seri bağlantı kapasiteyi düşürür."}
          ],
          "ans": "1/C_eş = 1/C₁ + 1/C₂",
          "o": ["C_eş = C₁ + C₂", "C_eş = C₁ · C₂ / (C₁ + C₂)... (aynı formül farklı yazılış değil, bu yanlış seçenek)", "C_eş = C₁ − C₂", "C_eş = 2(C₁ + C₂)"]
        }
      ],
      "zor": [
        {
          "q": "C = 10 μF kondansatör V = 100 V'a şarj ediliyor. Depolanan enerji nedir?",
          "steps": [
            {"t": "Formül", "a": "U = ½C·V²", "d": "C = 10×10⁻⁶ F, V = 100 V."},
            {"t": "Hesap", "a": "U = ½ × 10×10⁻⁶ × 100² = ½ × 10⁻⁵ × 10⁴ = 0,05 J", "d": "50 mJ enerji depolanır."}
          ],
          "ans": "0,05 J (50 mJ)",
          "o": ["0,5 J", "5 J", "0,005 J", "50 J"]
        },
        {
          "q": "C₁ = 6 μF ve C₂ = 3 μF seri bağlı; bu kombinasyon C₃ = 4 μF ile paralel. Toplam eşdeğer kapasite nedir?",
          "steps": [
            {"t": "Seri C₁, C₂", "a": "1/C_s = 1/6 + 1/3 = 1/6 + 2/6 = 3/6 = 1/2 → C_s = 2 μF", "d": "C₁ ve C₂ seri kombinasyonu 2 μF."},
            {"t": "Paralel C_s, C₃", "a": "C_eş = 2 + 4 = 6 μF", "d": "Paralel kombinasyon ile toplam 6 μF."}
          ],
          "ans": "6 μF",
          "o": ["13 μF", "2 μF", "4 μF", "9 μF"]
        },
        {
          "q": "Paralel levhalı kondansatörde levhalar arası mesafe yarıya indirilirse, V sabit tutulurken depolanan enerji nasıl değişir?",
          "steps": [
            {"t": "Kapasite", "a": "C = ε₀A/d → d yarıya iner → C iki katına çıkar.", "d": "C ∝ 1/d."},
            {"t": "Enerji", "a": "U = ½CV² → C iki katı → U iki katına çıkar.", "d": "V sabit tutulduğundan."},
            {"t": "Sonuç", "a": "Enerji iki katına çıkar.", "d": "Kaynağın ek enerji sağladığını unutma."}
          ],
          "ans": "İki katına çıkar",
          "o": ["Yarıya düşer", "Dört katına çıkar", "Değişmez", "Dörtte birine düşer"]
        }
      ]
    }
  },
  "sagElKurali": {
    "lise": {
      "kolay": [
        {
          "q": "Düz bir iletken telde akan akımın oluşturduğu manyetik alanın yönünü bulmak için hangi kural kullanılır?",
          "steps": [
            {"t": "Kural", "a": "Sağ el kuralı (iletken için)", "d": "Sağ elin başparmağı akım yönünü gösterirken kıvrılan parmaklar B alanının yönünü gösterir."},
            {"t": "Sonuç", "a": "B alanı telin çevresinde dairesel halkalar oluşturur.", "d": "Ampere yasasından türetilir."}
          ],
          "ans": "Sağ el kuralı (başparmak = akım, parmaklar = B)",
          "o": ["Sol el kuralı", "Lenz kuralı", "Fleming'in sol el kuralı (motor için)", "Yalnızca pusula ile belirlenir"]
        },
        {
          "q": "Solenoidde kuzey kutbu tarafını bulmak için sağ el nasıl kullanılır?",
          "steps": [
            {"t": "Yöntem", "a": "Sağ elin parmakları akımın sarım yönünde kıvrılırken başparmak kuzey kutbunu gösterir.", "d": "Başparmak = N kutbu yönü."},
            {"t": "Fiziksel anlam", "a": "N kutbundan B çizgileri dışarı çıkar.", "d": "Mıknatısın davranışı ile aynıdır."}
          ],
          "ans": "Parmaklar akım yönünde kıvrılır, başparmak N kutbunu gösterir",
          "o": ["Başparmak akım yönünde, parmaklar N kutbunu gösterir", "Sol el kullanılır", "Parmaklar B alanına paralel tutulur", "Herhangi bir el kullanılabilir"]
        },
        {
          "q": "Sayfadan çıkan (⊙) akım taşıyan telin etrafındaki B alanı hangi yöndedir?",
          "steps": [
            {"t": "Sağ el kuralı", "a": "Başparmağı sayfadan çıkar yönünde tut (⊙), parmaklar saat yönünün tersine kıvrılır.", "d": "Sağ el başparmağı akım yönünde."},
            {"t": "Sonuç", "a": "B alanı telin çevresinde saat yönünün tersinde (CCW).", "d": "Üstten bakıldığında saat yönünün tersidir."}
          ],
          "ans": "Saat yönünün tersinde (CCW)",
          "o": ["Saat yönünde (CW)", "Sayfadan dışarıya radyal", "Sayfaya içeriye radyal", "Sabit bir yönde düz çizgiler"]
        },
        {
          "q": "Düz iletken telden r = 0,1 m uzaklıkta B alanı hesaplamak için kullanılan formül hangisidir?",
          "steps": [
            {"t": "Ampere yasası", "a": "B = μ₀·I / (2π·r)", "d": "μ₀ = 4π×10⁻⁷ T·m/A, I akım, r uzaklık."},
            {"t": "Yorum", "a": "r arttıkça B azalır (1/r ile ters orantılı).", "d": "Düz iletken tel için."}
          ],
          "ans": "B = μ₀·I / (2π·r)",
          "o": ["B = μ₀·I·r / 2π", "B = μ₀·I / (4π·r²)", "B = μ₀·I / r", "B = 2π·r / (μ₀·I)"]
        },
        {
          "q": "Akım taşıyan iletkene manyetik alan içinde etki eden kuvvet hangisiyle bulunur?",
          "steps": [
            {"t": "Formül", "a": "F = I·L·B·sin θ", "d": "I akım, L tel uzunluğu, B alan, θ aralarındaki açı."},
            {"t": "Maksimum kuvvet", "a": "θ = 90° → F = ILB", "d": "Tel ve B birbirine dik ise kuvvet maksimum."}
          ],
          "ans": "F = I·L·B·sin θ",
          "o": ["F = I·L·B·cos θ", "F = I·B·sin θ / L", "F = I²·L·B", "F = I·L / (B·sin θ)"]
        }
      ],
      "zor": [
        {
          "q": "I = 5 A akım taşıyan düz iletken telden r = 0,2 m uzaklıktaki B alanı nedir? (μ₀ = 4π×10⁻⁷ T·m/A)",
          "steps": [
            {"t": "Formül", "a": "B = μ₀·I / (2π·r)", "d": "Değerleri yerleştir."},
            {"t": "Hesap", "a": "B = (4π×10⁻⁷ × 5) / (2π × 0,2) = (20π×10⁻⁷) / (0,4π) = 50×10⁻⁷ / 1 = 5×10⁻⁶ T", "d": "B = 5 μT."}
          ],
          "ans": "5 μT (5×10⁻⁶ T)",
          "o": ["50 μT", "0,5 μT", "2,5 μT", "10 μT"]
        },
        {
          "q": "Birbirine paralel, aynı yönde akım taşıyan iki tel birbirini iter mi çeker mi? Sağ el kuralıyla açıklayın.",
          "steps": [
            {"t": "Tel 1'in B alanı", "a": "Tel 1'in oluşturduğu B, Tel 2'nin konumunda belirli bir yöndedir (sağ el kuralı).", "d": "Tel 2'yi etkileyen alan belirlenir."},
            {"t": "Tel 2'ye kuvvet", "a": "F = I₂·L·B₁; yön: sağ el (ya da F = IL×B vektörel çarpım)", "d": "Kuvvet Tel 1'e doğru yönelir."},
            {"t": "Sonuç", "a": "Aynı yönde akım → teller birbirini çeker.", "d": "Zıt yönde akım tutan teller ise iter."}
          ],
          "ans": "Çekerler (aynı yönde akım → çekme)",
          "o": ["İterler", "Kuvvet sıfırdır", "Önce çeker sonra iter", "Sadece eşit akımlarda çekerler"]
        },
        {
          "q": "N = 500 sarımlı, L = 0,4 m uzunluğunda, I = 2 A akım taşıyan bir solenoidin içindeki B alanı nedir? (μ₀ = 4π×10⁻⁷ T·m/A)",
          "steps": [
            {"t": "Sarım yoğunluğu", "a": "n = N/L = 500/0,4 = 1250 sarım/m", "d": "Birim uzunlukta sarım sayısı."},
            {"t": "Alan formülü", "a": "B = μ₀·n·I = 4π×10⁻⁷ × 1250 × 2", "d": "Solenoid içi düzgün alan."},
            {"t": "Hesap", "a": "B = 4π×10⁻⁷ × 2500 = 10000π×10⁻⁷ ≈ 3,14×10⁻³ T ≈ 3,14 mT", "d": "Yaklaşık 3,14 milliTesla."}
          ],
          "ans": "≈ 3,14 mT",
          "o": ["≈ 31,4 mT", "≈ 0,314 mT", "≈ 6,28 mT", "≈ 1,57 mT"]
        }
      ]
    }
  },
  "jenerator": {
    "lise": {
      "kolay": [
        {
          "q": "Faraday'ın elektromanyetik indüksiyon yasasına göre bir bobinde EMK oluşması için ne gereklidir?",
          "steps": [
            {"t": "Koşul", "a": "Manyetik akının değişmesi gerekir.", "d": "Sabit akı EMK oluşturmaz; ΔΦ/Δt ≠ 0 olmalıdır."},
            {"t": "Faraday yasası", "a": "ε = −N·ΔΦ/Δt", "d": "N: sarım sayısı, ΔΦ: akı değişimi, Δt: zaman."}
          ],
          "ans": "Manyetik akının değişmesi",
          "o": ["Sabit manyetik alan yeterlidir", "Yalnızca güçlü mıknatıs yeterlidir", "Akımın yüksek olması gerekir", "Sıcaklığın düşük olması gerekir"]
        },
        {
          "q": "Manyetik alanda dönen bobinde oluşan EMK'nın maksimum değeri hangi formülle hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "ε_max = N·B·A·ω", "d": "N: sarım sayısı, B: alan şiddeti, A: bobin alanı, ω: açısal hız."},
            {"t": "Değişim", "a": "ε = ε_max · sin(ωt)", "d": "Dönen bobinde EMK sinüzoidal değişir → AC üretimi."}
          ],
          "ans": "ε_max = N·B·A·ω",
          "o": ["ε_max = N·B·A/ω", "ε_max = N·B·ω/A", "ε_max = B·A·ω/N", "ε_max = N·B/(A·ω)"]
        },
        {
          "q": "AC jeneratör hangi enerji dönüşümünü gerçekleştirir?",
          "steps": [
            {"t": "Giriş", "a": "Mekanik enerji (döndürme)", "d": "Türbin, rüzgar, su veya buhar bobini döndürür."},
            {"t": "Çıkış", "a": "Elektrik enerjisi (AC)", "d": "Bobin dönünce değişen akı alternatif EMK üretir."}
          ],
          "ans": "Mekanik → Elektrik",
          "o": ["Elektrik → Mekanik", "Isı → Elektrik", "Kimyasal → Elektrik", "Işık → Elektrik"]
        },
        {
          "q": "Lenz yasasına göre indüklenen akım hangi yöndedir?",
          "steps": [
            {"t": "Lenz yasası", "a": "İndüklenen akım, onu üreten akı değişimine karşı koyacak yönde akar.", "d": "Enerji korunumunun manyetik karşılığıdır."},
            {"t": "Sonuç", "a": "Faraday formülündeki eksi işareti (−) bu yasayı temsil eder.", "d": "ε = −N·ΔΦ/Δt"}
          ],
          "ans": "Akı değişimine karşı koyacak yönde",
          "o": ["Akı değişimiyle aynı yönde", "Her zaman saat yönünde", "Her zaman saat yönünün tersinde", "Akımın yönü indüklenen EMK ile alakasız"]
        },
        {
          "q": "Bir jeneratörde bobinin dönme hızı (ω) iki katına çıkarılırsa maksimum EMK nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "ε_max = N·B·A·ω", "d": "ε_max, ω ile doğru orantılı."},
            {"t": "Sonuç", "a": "ω iki katına çıkınca ε_max da iki katına çıkar.", "d": "Hızla doğrusal ilişki."}
          ],
          "ans": "İki katına çıkar",
          "o": ["Yarıya düşer", "Dört katına çıkar", "Değişmez", "Karesine çıkar"]
        }
      ],
      "zor": [
        {
          "q": "N = 100 sarımlı bobin, B = 0,5 T alanda, A = 0,02 m², ω = 100π rad/s ile dönüyor. ε_max ve üretilen EMK'nın frekansı nedir?",
          "steps": [
            {"t": "ε_max", "a": "ε_max = N·B·A·ω = 100 × 0,5 × 0,02 × 100π = 100π ≈ 314 V", "d": "Maksimum EMK 100π V."},
            {"t": "Frekans", "a": "f = ω/(2π) = 100π/(2π) = 50 Hz", "d": "Türkiye şebeke frekansına eşit!"}
          ],
          "ans": "ε_max ≈ 314 V, f = 50 Hz",
          "o": ["ε_max = 100 V, f = 100 Hz", "ε_max ≈ 628 V, f = 50 Hz", "ε_max ≈ 314 V, f = 100 Hz", "ε_max = 50 V, f = 50 Hz"]
        },
        {
          "q": "Bir bobinden geçen akı Φ = 0,4·cos(100πt) Wb olarak değişiyor. N = 200 sarımlı bobindeki indüklenen EMK ifadesini ve maksimum değerini bulun.",
          "steps": [
            {"t": "Faraday", "a": "ε = −N·dΦ/dt", "d": "Türev alınmalı."},
            {"t": "Türev", "a": "dΦ/dt = −0,4 × 100π · sin(100πt) = −40π · sin(100πt)", "d": "Cosinus türevi -sinüs."},
            {"t": "EMK", "a": "ε = −200 × (−40π · sin(100πt)) = 8000π · sin(100πt) ≈ 25133 · sin(100πt) V", "d": "ε_max = 8000π ≈ 25133 V ≈ 25,1 kV."}
          ],
          "ans": "ε = 8000π · sin(100πt) V; ε_max ≈ 25,1 kV",
          "o": ["ε_max = 4000π V ≈ 12,6 kV", "ε_max = 40π V ≈ 125,7 V", "ε_max = 200 × 0,4 = 80 V", "ε_max = 8000 V = 8 kV"]
        },
        {
          "q": "Transformatörsüz iletim: jeneratör 10 kW güç üretiyor. İletim direnci R = 10 Ω. V = 500 V'da iletilirse kayıp gücü ve kayıp yüzdesi nedir?",
          "steps": [
            {"t": "Akım", "a": "I = P/V = 10000/500 = 20 A", "d": "İletim akımı."},
            {"t": "Kayıp güç", "a": "P_kayıp = I²·R = 20² × 10 = 400 × 10 = 4000 W", "d": "Direnç ısısı olarak harcanan güç."},
            {"t": "Yüzde", "a": "% kayıp = 4000/10000 × 100 = %40", "d": "Yüksek gerilimle iletimin neden kritik olduğunu gösterir."}
          ],
          "ans": "4000 W — %40 kayıp",
          "o": ["1000 W — %10 kayıp", "2000 W — %20 kayıp", "400 W — %4 kayıp", "5000 W — %50 kayıp"]
        }
      ]
    }
  },
  "rcDevre": {
    "lise": {
      "kolay": [
        {
          "q": "RC devresinde zaman sabiti τ hangi formülle hesaplanır ve birimi nedir?",
          "steps": [
            {"t": "Formül", "a": "τ = R·C", "d": "R: direnç (Ω), C: kapasite (F)."},
            {"t": "Birim", "a": "Ω × F = s (saniye)", "d": "τ birimi saniyedir; şarj/deşarj hızını belirler."}
          ],
          "ans": "τ = R·C (birimi saniye)",
          "o": ["τ = R/C", "τ = C/R", "τ = R+C", "τ = √(R·C)"]
        },
        {
          "q": "RC devresinde kondansatör şarj edilirken gerilim nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "V_C(t) = V₀ · (1 − e üstü (−t/τ))", "d": "Üstel artış; asimptotik olarak V₀'a yaklaşır."},
            {"t": "Grafik", "a": "Başlangıçta hızlı yükselir, giderek yavaşlar.", "d": "Hiçbir zaman teorik olarak tam V₀'a ulaşamaz."}
          ],
          "ans": "Üstel olarak artar: V_C = V₀(1 − e^(−t/τ))",
          "o": ["Doğrusal artar", "Sabit kalır", "Üstel azalır", "Sinüzoidal değişir"]
        },
        {
          "q": "t = τ anında kondansatör gerilimi V₀'ın yüzde kaçına ulaşmıştır?",
          "steps": [
            {"t": "Hesap", "a": "V_C(τ) = V₀(1 − e⁻¹) = V₀(1 − 0,368) = 0,632·V₀", "d": "e⁻¹ ≈ 0,368."},
            {"t": "Sonuç", "a": "Yaklaşık %63,2", "d": "Bir zaman sabiti sonunda kapasite %63 dolmuştur."}
          ],
          "ans": "%63,2",
          "o": ["%37", "%50", "%86", "%100"]
        },
        {
          "q": "τ büyük olursa şarj süresi nasıl değişir?",
          "steps": [
            {"t": "Yorum", "a": "τ büyük → şarj yavaş gerçekleşir.", "d": "R veya C büyüdükçe τ büyür ve kondansatör daha yavaş dolar."},
            {"t": "Pratikte", "a": "Tam şarj için yaklaşık 5τ gerekir.", "d": "5τ sonunda %99,3 doluluğa ulaşılır."}
          ],
          "ans": "Uzar (şarj yavaşlar)",
          "o": ["Kısalır", "Değişmez", "Önce kısalır sonra uzar", "Sıfıra iner"]
        },
        {
          "q": "Deşarj sırasında kondansatör gerilimi nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "V_C(t) = V₀ · e üstü (−t/τ)", "d": "Üstel azalış; sıfıra asimptotik yaklaşır."},
            {"t": "t = τ", "a": "V_C = V₀ · e⁻¹ ≈ 0,368·V₀", "d": "Bir zaman sabiti sonunda başlangıç geriliminin %37'sine düşer."}
          ],
          "ans": "Üstel azalır: V_C = V₀ · e^(−t/τ)",
          "o": ["Doğrusal azalır", "Sabit kalır", "Üstel artar", "Sıfıra anında düşer"]
        }
      ],
      "zor": [
        {
          "q": "R = 2 kΩ, C = 500 μF olan RC devresi V₀ = 12 V'a şarj ediliyor. t = τ anında kondansatördeki enerji nedir?",
          "steps": [
            {"t": "τ", "a": "τ = R·C = 2000 × 500×10⁻⁶ = 1 s", "d": "Zaman sabiti 1 saniye."},
            {"t": "t = τ anındaki V", "a": "V_C = 12(1 − e⁻¹) ≈ 12 × 0,632 = 7,58 V", "d": "Yaklaşık 7,58 V."},
            {"t": "Enerji", "a": "U = ½CV² = ½ × 500×10⁻⁶ × 7,58² ≈ ½ × 5×10⁻⁴ × 57,5 ≈ 0,0144 J ≈ 14,4 mJ", "d": "Yaklaşık 14,4 mJ enerji depolanmış."}
          ],
          "ans": "≈ 14,4 mJ",
          "o": ["≈ 36 mJ", "≈ 7,2 mJ", "≈ 28,8 mJ", "≈ 5,4 mJ"]
        },
        {
          "q": "RC devresinde R = 1 kΩ, C = 100 μF. Şarj başladıktan kaç saniye sonra gerilim V₀'ın %86,5'ine ulaşır?",
          "steps": [
            {"t": "τ", "a": "τ = 1000 × 100×10⁻⁶ = 0,1 s", "d": "Zaman sabiti 0,1 s."},
            {"t": "%86,5 koşulu", "a": "1 − e^(−t/τ) = 0,865 → e^(−t/τ) = 0,135 ≈ e⁻²", "d": "e⁻² ≈ 0,135."},
            {"t": "Süre", "a": "−t/τ = −2 → t = 2τ = 2 × 0,1 = 0,2 s", "d": "İki zaman sabiti sonunda %86,5 doluluk."}
          ],
          "ans": "0,2 s (2τ)",
          "o": ["0,1 s (1τ)", "0,3 s (3τ)", "0,05 s (τ/2)", "0,4 s (4τ)"]
        },
        {
          "q": "RC devresinde C tamamen şarjlı (V_C = V₀) iken anahtar açılıp deşarja bırakılıyor. t = 3τ anında kondansatör gerilimi V₀'ın yüzde kaçıdır?",
          "steps": [
            {"t": "Deşarj formülü", "a": "V_C = V₀ · e^(−t/τ)", "d": "t = 3τ için hesapla."},
            {"t": "Hesap", "a": "V_C = V₀ · e⁻³ ≈ V₀ × 0,0498 ≈ %5,0", "d": "e⁻³ ≈ 0,0498."}
          ],
          "ans": "Yaklaşık %5",
          "o": ["Yaklaşık %37", "Yaklaşık %14", "Yaklaşık %1", "Yaklaşık %50"]
        }
      ]
    }
  },
  "faraday": {
    "lise": {
      "kolay": [
        {
          "q": "Faraday kafesinin temel ilkesi nedir?",
          "steps": [
            {"t": "İlke", "a": "İletken kafes içindeki elektrik alan sıfırdır (E_iç = 0).", "d": "Dış elektrik alan, kafes yüzeyinde yük dağılımına neden olur; bu yükler iç alanı iptal eder."},
            {"t": "Sonuç", "a": "İçerideki cihazlar dış elektrosta tik alandan korunur.", "d": "Kafes dış alana karşı kalkan görevi görür."}
          ],
          "ans": "İletken kafes içinde E = 0; dış alandan koruma sağlar",
          "o": ["Kafes içinde E en büyük olur", "Kafes yalnızca manyetik alandan korur", "Kafes hem E hem B'yi engeller", "Kafes sadece AC alanları engeller"]
        },
        {
          "q": "İletken bir kürenin iç yüzeyindeki elektrik alan nedir?",
          "steps": [
            {"t": "Gauss yasası", "a": "İletken içinde E = 0.", "d": "Statik denge durumunda iletken içinde serbest yük olmaz; alan sıfırdır."},
            {"t": "Yük dağılımı", "a": "Tüm fazla yükler dış yüzeyde toplanır.", "d": "İç yüzeyde ve hacimde yük yoktur."}
          ],
          "ans": "Sıfır (E = 0)",
          "o": ["E = kQ/r²", "E = V/d", "E = σ/ε₀", "E en büyük değerdedir"]
        },
        {
          "q": "Faraday kafesinin günlük hayattan bir örneği nedir?",
          "steps": [
            {"t": "Örnek 1", "a": "Araç içinde cep telefonu sinyali zayıflar.", "d": "Metal kaporta kafes işlevi görür."},
            {"t": "Örnek 2", "a": "Mikrodalga fırının metal kafesi", "d": "Mikrodalgaların dışarı kaçmasını engeller."}
          ],
          "ans": "Metal araç gövdesi / mikrodalga fırın kafesi",
          "o": ["Ahşap kulübe", "Cam pencere", "Plastik çanta", "Su dolu kap"]
        },
        {
          "q": "Faraday kafesi yıldırımdan nasıl korur?",
          "steps": [
            {"t": "Mekanizma", "a": "Yıldırım çarptığında yük kafes yüzeyinde dağılır, içeriye alan geçmez.", "d": "İletken yüzey dış alana karşı kalkan oluşturur."},
            {"t": "Pratik", "a": "Araçlar içindeki insanlar yıldırımdan bu nedenle korunur.", "d": "Metal kaporta Faraday kafesi işlevi görür."}
          ],
          "ans": "Yıldırım yükü yüzeyde dağılır, iç alan sıfır kalır",
          "o": ["Kafes yıldırımı çeker ve soğurur", "Kafes yıldırımı geri yansıtır", "Kafes sıcaklığı düşürür", "Kafes hava akışını keser"]
        },
        {
          "q": "Faraday kafesi dış manyetik alandan da tam koruma sağlar mı?",
          "steps": [
            {"t": "Yanıt", "a": "Hayır; Faraday kafesi yalnızca statik ve değişken elektrik alanlardan korur.", "d": "Statik B alanı (DC manyetik alan) kafesi geçer; tam B koruması için mumetal gibi özel malzeme gerekir."},
            {"t": "AC manyetik", "a": "Yüksek frekanslı AC B alanları kısmen engellenir (deri etkisi).", "d": "Ama statik B için koruma yoktur."}
          ],
          "ans": "Hayır, yalnızca elektrik alanlardan korur",
          "o": ["Evet, hem E hem B'yi tam engeller", "Evet ama yalnızca statik B'yi engeller", "Hayır, hiçbir alandan korumaz", "Evet, her tür radyasyondan korur"]
        }
      ],
      "zor": [
        {
          "q": "İçi boş iletken küreye dışarıdan Q yükü verildiğinde yük nasıl dağılır? Gauss yasasıyla açıklayın.",
          "steps": [
            {"t": "Gauss yüzeyi içte", "a": "İletken içinde E = 0 → Gauss yasası: Φ = Q_iç/ε₀ = 0 → Q_iç = 0", "d": "İçteki Gauss yüzeyinden geçen akı sıfır."},
            {"t": "Sonuç", "a": "Tüm Q yükü dış yüzeyde toplanır.", "d": "Boş kürenin iç yüzeyinde ve hacminde yük bulunmaz."}
          ],
          "ans": "Tüm yük dış yüzeyde toplanır; iç yüzey ve hacimde yük yok",
          "o": ["Yük eşit olarak iç ve dış yüzeye dağılır", "Yük tamamı iç yüzeyde toplanır", "Yük hacme eşit dağılır", "Yük dış ortama kaçar"]
        },
        {
          "q": "İçi boş iletken kürenin tam merkezine +q yükü konuluyor. İç ve dış yüzeylerde oluşan yük dağılımları nelerdir?",
          "steps": [
            {"t": "İç yüzey", "a": "Gauss: E = 0 → Q_kapalı = 0 → iç yüzeyde −q indüklenir.", "d": "+q yükünü nötralize etmek için iç yüzeyde −q toplanır."},
            {"t": "Dış yüzey", "a": "Küre nötrse dış yüzeyde +q toplanır.", "d": "Toplam yük korunur: (−q) + (+q) = 0."},
            {"t": "Dış alan", "a": "Dışarıda sanki +q merkezdeymiş gibi radyal alan oluşur.", "d": "Kürenin şekli önemli değil; dışarıdan bakınca tek nokta yük gibi davranır."}
          ],
          "ans": "İç yüzey: −q; dış yüzey: +q",
          "o": ["İç: +q, dış: −q", "İç: 0, dış: 0", "İç: −q/2, dış: +q/2", "İç: +q/2, dış: +q/2"]
        },
        {
          "q": "Faraday kafesi neden sinyal engelleyici olarak kullanılır? Hangi frekanslarda daha etkilidir?",
          "steps": [
            {"t": "Mekanizma", "a": "Dış EM dalgaların elektrik bileşeni iletken yüzeyde serbest yükleri titreştirir; bu yükler dış alanı iptal eden ters alan oluşturur.", "d": "Kafes içine alan giremez."},
            {"t": "Frekans bağımlılığı", "a": "Deri derinliği: δ = √(2ρ/(ωμ)). Yüksek frekansta δ küçülür; ince metal bile yeterli olur.", "d": "Düşük frekanslarda (örneğin güç frekansı 50 Hz) kalın metallar gerekir."},
            {"t": "GSM/WiFi", "a": "GHz frekanslarında ince metal örgü yeterlidir; deri derinliği mm altında.", "d": "Bu yüzden örgü kafes yeterli koruma sağlar."}
          ],
          "ans": "Yüksek frekanslarda daha etkili; deri etkisi ile EM dalgayı yüzeyde söndürür",
          "o": ["Yalnızca DC alanları engeller", "Yalnızca düşük frekanslarda etkili", "Frekans bağımsız — tüm frekanslarda eşit etkili", "Yalnızca manyetik bileşeni engeller"]
        }
      ]
    }
  },
  "topraklama": {
    "lise": {
      "kolay": [
        {
          "q": "Elektrikte topraklama nedir ve referans potansiyeli ne olarak kabul edilir?",
          "steps": [
            {"t": "Tanım", "a": "İletkeni dünyaya (toprağa) bağlama işlemi.", "d": "Toprak sonsuz yük kapasiteli bir rezervuar olarak kabul edilir."},
            {"t": "Referans", "a": "Toprağın potansiyeli V = 0 alınır.", "d": "Tüm potansiyel ölçümleri bu referansa göre yapılır."}
          ],
          "ans": "İletkeni toprağa bağlamak; V_toprak = 0",
          "o": ["İletkeni izole etmek; V_toprak = ∞", "İletkeni başka bir iletkene bağlamak; V = sabit", "Toprağın potansiyeli 220 V'dur", "Toprağın potansiyeli negatiftir"]
        },
        {
          "q": "Topraklanan iletken üzerindeki fazla yüke ne olur?",
          "steps": [
            {"t": "Akış", "a": "Fazla yük toprak yoluyla yayılır; iletken nötr hale gelir.", "d": "Toprak sonsuz yük rezervuarı gibi davranır."},
            {"t": "Sonuç", "a": "İletkenin potansiyeli sıfır olur (V = 0).", "d": "Fazla yük ne pozitif ne de negatif olsa da toprağa geçer."}
          ],
          "ans": "Toprağa akar; iletken nötrleşir",
          "o": ["Yük havaya dağılır", "Yük iletkenin içinde hapsolur", "Yük artarak birikir", "Yük komşu nesnelere zıplar"]
        },
        {
          "q": "Yıldırım paratonu neden toprağa bağlıdır?",
          "steps": [
            {"t": "İşlev", "a": "Yıldırım çarptığında büyük yükü güvenli şekilde toprağa iletir.", "d": "Toprak bu yükü yayar; bina ve insanlar korunur."},
            {"t": "Uç geometrisi", "a": "Sivri uç yüksek E alanı oluşturur → korona deşarjı → yükü sürekli boşaltır.", "d": "Yıldırım çarpmadan önce yük azalır."}
          ],
          "ans": "Yükü güvenli şekilde toprağa iletmek için",
          "o": ["Yıldırımı çekmek için yeterli yük biriktirmek", "Binayı ısıtmak için", "Yıldırımı geri yansıtmak için", "Atmosferi nötrleştirmek için"]
        },
        {
          "q": "İndükleme yoluyla yüklenmiş bir iletken topraklanırsa ne olur?",
          "steps": [
            {"t": "Önce", "a": "Dış yüke yakın tarafta zıt, uzak tarafta aynı işaretli yük indüklenir.", "d": "İndüklenen yük dengesiz dağılmış."},
            {"t": "Topraklama sonrası", "a": "Uzaktaki yük (dış yükle aynı işaretli) toprağa kaçar; yakındaki zıt işaretli yük kalır.", "d": "Toprak bağlantısı kesilince iletken net yüklü kalır (indükleme ile yükleme yöntemi)."}
          ],
          "ans": "Aynı işaretli yük toprağa kaçar; zıt işaretli yük kalır",
          "o": ["Tüm yükler toprağa kaçar", "Zıt işaretli yük toprağa kaçar", "Yük değişmez", "Yük iki katına çıkar"]
        },
        {
          "q": "Ev elektrik tesisatında topraklama hattının rengi nedir (Türk standardı)?",
          "steps": [
            {"t": "Standart", "a": "Sarı-yeşil çizgili kablo topraklama hattıdır.", "d": "IEC/TSE standartlarına göre."},
            {"t": "Diğerleri", "a": "Faz: kahverengi/siyah; Nötr: mavi.", "d": "Topraklama hiçbir zaman tek düz renkle gösterilmez."}
          ],
          "ans": "Sarı-yeşil çizgili",
          "o": ["Kırmızı", "Mavi", "Siyah", "Beyaz"]
        }
      ],
      "zor": [
        {
          "q": "İndükleme yöntemiyle yükleme adımlarını sıralayın: +Q yükü yaklaştırılıyor, iletken topraklanıyor, bağlantı kesiliyor, +Q uzaklaştırılıyor. Sonuçta iletkenin net yükü nedir?",
          "steps": [
            {"t": "Adım 1", "a": "+Q yaklaşınca iletkende yakın taraf −, uzak taraf + yüklenir.", "d": "Elektrostatik indüksiyon."},
            {"t": "Adım 2", "a": "Topraklama: uzak taraftaki + yükler toprağa kaçar; yakın tarafta − kalır.", "d": "Toprak + yükü alır."},
            {"t": "Adım 3", "a": "Toprak bağlantısı kesilir; iletkenin tamamı − yüklü.", "d": "Net yük eksilendi."},
            {"t": "Adım 4", "a": "+Q uzaklaşınca − yükler iletken üzerine eşit dağılır.", "d": "Sonuç: iletken net negatif yüklüdür."}
          ],
          "ans": "Net negatif yük (−Q'ya orantılı)",
          "o": ["Net pozitif yük", "Net yük sıfır", "Net yük +2Q", "Net yük +Q"]
        },
        {
          "q": "Adım gerilimi (step voltage) nedir ve toprağa düşen yıldırım yakınındaki insanlara nasıl zarar verir?",
          "steps": [
            {"t": "Tanım", "a": "Yıldırım isabet noktası çevresinde toprağa büyük akım akar; radyal potansiyel farkı oluşur.", "d": "Toprak üzerinde iki nokta arası gerilim = adım gerilimi."},
            {"t": "Tehlike", "a": "Ayaklar farklı potansiyeldeki noktalarda ise vücuttan akım geçer.", "d": "İki bacak arası gerilim (~0,5−1 m) ölümcül olabilir."},
            {"t": "Önlem", "a": "Yıldırım sırasında küçük adımlarla ya da sıçrayarak alan terk edilmeli.", "d": "Asla koşmayın; adım uzadıkça gerilim artar."}
          ],
          "ans": "İmpakt noktasından radyal akım → ayaklar arası potansiyel farkı → vücuttan akım geçer",
          "o": ["Yıldırım doğrudan vücuda çarpar", "Manyetik alan kalp ritmine zarar verir", "Hava şoku darbesi zarar verir", "Yerden yansıyan ışık zarar verir"]
        },
        {
          "q": "İletken bir küre ile toprak arasındaki kapasitans C = 4πε₀R formülü ile verilir. R = 1 m olan küre V = 9×10⁹ V'a yükseltilirse küre üzerindeki yük nedir?",
          "steps": [
            {"t": "Kapasitans", "a": "C = 4πε₀R = 4π × 8,85×10⁻¹² × 1 ≈ 1,11×10⁻¹⁰ F ≈ 111 pF", "d": "Yalnız kürenin kapasitansı."},
            {"t": "Yük", "a": "Q = C·V = 1,11×10⁻¹⁰ × 9×10⁹ = 1,11 × 9 × 10⁻¹ ≈ 1 C", "d": "1 Coulomb yük çok büyüktür; pratikte bu gerilime ulaşmak imkânsız."}
          ],
          "ans": "≈ 1 C",
          "o": ["≈ 1 nC", "≈ 1 μC", "≈ 1 mC", "≈ 10 C"]
        }
      ]
    }
  },
  "uygulama": {
    "lise": {
      "kolay": [
        {
          "q": "Havanın elektrik delinme dayanımı yaklaşık kaç V/m'dir ve yıldırım bu değerle nasıl ilgilidir?",
          "steps": [
            {"t": "Değer", "a": "Havanın delinme dayanımı ≈ 3×10⁶ V/m", "d": "Bu değeri aşan E alanında hava iyonize olur ve iletken hale gelir."},
            {"t": "Yıldırım", "a": "Bulut-yer arası E > 3×10⁶ V/m olduğunda hava kopar ve dev kıvılcım (yıldırım) akar.", "d": "Yıldırım havanın elektrik delinmesidir."}
          ],
          "ans": "≈ 3×10⁶ V/m; bu eşik aşılınca hava delinir ve yıldırım oluşur",
          "o": ["≈ 3×10³ V/m", "≈ 3×10⁹ V/m", "≈ 300 V/m", "≈ 3×10¹² V/m"]
        },
        {
          "q": "Yıldırım paratonu sivri uçlu yapılır. Bunun nedeni nedir?",
          "steps": [
            {"t": "Elektrostatik", "a": "Sivri yüzeylerde yük yoğunluğu σ ve dolayısıyla E alanı çok büyük olur.", "d": "E = σ/ε₀; eğrilik yarıçapı küçükse σ büyür."},
            {"t": "Korona deşarjı", "a": "Sivri uçta havadaki iyonlar hızlanır; hava lokal olarak iletken hale gelir.", "d": "Bu sürekli küçük deşarj yükü boşaltır; büyük yıldırım vuruşu önlenir."}
          ],
          "ans": "Sivri uçta E alanı büyük → korona deşarjı → yük yavaşça boşalır",
          "o": ["Yıldırımı daha güçlü çekmek için", "Estetik görünüm için", "Isıyı dağıtmak için", "Manyetik alanı artırmak için"]
        },
        {
          "q": "Yıldırım oluşumu sırasında buluttaki yük dağılımı nasıldır?",
          "steps": [
            {"t": "Tipik dağılım", "a": "Bulutun alt kısmı negatif (−), üst kısmı pozitif (+).", "d": "Negatif alt kısım yere yakın olduğundan yerle arasında büyük E alanı oluşur."},
            {"t": "Yıldırım yönü", "a": "Genellikle buluttan yere (bulut → yer) yıldırımı şeklinde gerçekleşir.", "d": "Negatif yük yerden yükselen pozitif lidere doğru hareket eder."}
          ],
          "ans": "Alt kısım negatif, üst kısım pozitif; alt kısımdan yıldırım akar",
          "o": ["Alt kısım pozitif, üst kısım negatif", "Homojen dağılmış tek işaretli yük", "Yük yalnızca bulutun dış yüzeyinde", "Dağılım rastgele değişir, belirli değil"]
        },
        {
          "q": "Yıldırım çarpmasında açığa çıkan enerji hangi mertebeye ulaşabilir?",
          "steps": [
            {"t": "Tipik değerler", "a": "Yıldırımda I ≈ 20.000−30.000 A; süre ≈ birkaç yüz μs; enerji ≈ 1−5 GJ/bolt (toplam) ama faydalı kısmı ≈ 1 kWh civarı.", "d": "Çok kısa sürede devasa güç açığa çıkar."},
            {"t": "Sıcaklık", "a": "Kanal sıcaklığı ≈ 30.000 K (Güneş yüzeyinin yaklaşık 5 katı).", "d": "Bu sıcaklık çevreyi anında ısıtır; ani genleşme gök gürültüsüne neden olur."}
          ],
          "ans": "≈ 1−5 GJ; kanal sıcaklığı ≈ 30.000 K",
          "o": ["≈ 1 J; kanal sıcaklığı oda sıcaklığı", "≈ 1 kJ; kanal sıcaklığı 300 K", "≈ 1 MJ; kanal sıcaklığı 1000 K", "≈ 1 TJ; kanal sıcaklığı 10⁶ K"]
        },
        {
          "q": "Yıldırım sırasında açık arazide bulunuyorsanız en güvenli duruş pozisyonu hangisidir?",
          "steps": [
            {"t": "Kural", "a": "Ayaklar bitişik, çömelme pozisyonu (topuk-topuk temas).", "d": "Adım gerilimini minimuma indirir; vücuttan geçecek akımı azaltır."},
            {"t": "Kaçınılması gerekenler", "a": "Ağaç altı, yüksek yer, yatmak, koşmak.", "d": "Yatmak temas yüzeyini artırır; adım geriliminden zarar görme riski yükselir."}
          ],
          "ans": "Ayaklar bitişik çömelme — adım gerilimini minimize eder",
          "o": ["Yere uzanmak", "Ağaç dibine yaslanmak", "Yüksek bir yere çıkmak", "Koşarak uzaklaşmak"]
        }
      ],
      "zor": [
        {
          "q": "Bulut ile yer arasındaki mesafe h = 1000 m, potansiyel fark V = 10⁸ V ise ortalama E alanı nedir? Bu değer havanın delinme dayanımıyla karşılaştırıldığında ne söylenebilir?",
          "steps": [
            {"t": "Ortalama alan", "a": "E = V/h = 10⁸/1000 = 10⁵ V/m", "d": "Ortalama değer."},
            {"t": "Karşılaştırma", "a": "Delinme dayanımı = 3×10⁶ V/m >> 10⁵ V/m", "d": "Ortalama alan yetersiz görünür; ancak yük kümelenen bölgelerde E yerel olarak çok yükselebilir."},
            {"t": "Yorum", "a": "Yıldırım homojen alanda değil yerel E artışlarının (sivri nesneler, bulut uçları) tetiklediği bir delinme sürecidir.", "d": "Step leader (lider kanal) çok daha yüksek yerel E oluşturur."}
          ],
          "ans": "E_ort = 10⁵ V/m < 3×10⁶ V/m; yıldırım yerel E artışlarıyla tetiklenir",
          "o": ["E_ort = 10⁸ V/m; havayı anında delinir", "E_ort = 10³ V/m; delinme gerçekleşmez", "E_ort = 3×10⁶ V/m; ortalama değer tam delinme eşiğinde", "E_ort = 10⁵ V/m; ortalama değer delinme için yeterli"]
        },
        {
          "q": "Yıldırım paratonu lider yöntemiyle çalışır. Sivri uçtaki korona deşarjı nasıl yıldırımı yönlendirir? Aşama aşama açıklayın.",
          "steps": [
            {"t": "Bulut yükü", "a": "Bulutun alt kısmında negatif yük birikir; E alanı artar.", "d": "Yere doğru basamaklı lider (stepped leader) oluşur."},
            {"t": "Paratonun rolü", "a": "Sivri uçta yüksek E → havayı iyonize → yukarı doğru yükselen lider (streamer) oluşur.", "d": "Paratondan yükselen streamer, buluttan inen liderle buluşur."},
            {"t": "Kavuşma", "a": "Lider ve streamer kavuşunca iletken kanal tamamlanır → ana deşarj akımı (geri çakım) akar.", "d": "Enerji bu geri çakım sırasında açığa çıkar."},
            {"t": "Sonuç", "a": "Yıldırım paratona çarpar; topraklama kablosi enerjiyi güvenle toprağa iletir.", "d": "Binanın olası deşarj noktası olması önlenmiş olur."}
          ],
          "ans": "Sivri uç → streamer → liderle kavuşma → geri çakım → topraklama",
          "o": ["Paratonu yükü geri yansıtır", "Paratonu yıldırımı manyetik alanla saptırır", "Paratonu yüksek direnç göstererek akımı keser", "Paratonu yıldırım enerjisini ısıya çevirip havaya salar"]
        },
        {
          "q": "Yıldırımın yan flaş (side flash) tehlikesi nedir? Hangi koşulda oluşur ve nasıl önlenir?",
          "steps": [
            {"t": "Tanım", "a": "Yıldırımın vuruş noktasından çevredeki nesnelere (insan, ağaç vb.) yatay sıçrama yapması.", "d": "Yan flaş olarak bilinir."},
            {"t": "Koşul", "a": "Vuruş noktasıyla çevre nesne arasındaki direnç, havadan geçişin direncinden büyük olursa.", "d": "Akım daha az dirençli yolu tercih eder (hava kanalı)."},
            {"t": "Önlem", "a": "Topraklama hattı ve potansiyel eşitleme iletkenlerinin yeterli kesitte olması; insanların iletken nesnelerden uzak durması.", "d": "Ekipotansiyel eşitleme yan flaşı engeller."}
          ],
          "ans": "Yıldırımın yüksek dirençli yoldan havaya sıçraması; potansiyel eşitleme ile önlenir",
          "o": ["Yıldırımın buluta geri dönmesi", "Yıldırımın güneş panellerini bozması", "Yıldırım sonrası oluşan ses dalgası", "Yıldırımın zemine paralel hareket etmesi"]
        }
      ]
    }
  }
};
