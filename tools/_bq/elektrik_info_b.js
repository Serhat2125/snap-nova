globalThis.__BQ = {
  "coulomb": {
    "lise": {
      "kolay": [
        {
          "q": "Coulomb Yasası'na göre iki nokta yük arasındaki elektrostatik kuvvet hangi formülle hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "F = k·q₁·q₂/r²", "d": "k Coulomb sabiti, q₁ ve q₂ yükler, r ise aralarındaki uzaklıktır."}
          ],
          "ans": "F = k·q₁·q₂/r²",
          "o": ["F = k·q₁·q₂/r", "F = k·(q₁+q₂)/r²", "F = q₁·q₂/r²", "F = k·r²/(q₁·q₂)"]
        },
        {
          "q": "Coulomb sabitinin (k) değeri kaçtır?",
          "steps": [
            {"t": "Değer", "a": "k = 9×10⁹ N·m²/C²", "d": "Bu sabit, elektrostatik kuvvetin büyüklüğünü belirler."}
          ],
          "ans": "9×10⁹ N·m²/C²",
          "o": ["9×10⁶ N·m²/C²", "6,67×10⁻¹¹ N·m²/kg²", "8,85×10⁻¹² C²/(N·m²)", "3×10⁸ N·m²/C²"]
        },
        {
          "q": "Aynı işaretli iki yük arasındaki kuvvetin yönü nasıldır?",
          "steps": [
            {"t": "Kural", "a": "Yükler birbirini iter.", "d": "Aynı işaretli yükler (++ veya −−) aralarında itme kuvveti oluşturur."}
          ],
          "ans": "Birbirini iter (itmeli kuvvet)",
          "o": ["Birbirini çeker (çekici kuvvet)", "Kuvvet sıfırdır", "Yönü belirsizdir", "Yükün işaretine göre değişir"]
        },
        {
          "q": "İki yük arasındaki mesafe 2 katına çıkarılırsa elektrostatik kuvvet nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "F ∝ 1/r²", "d": "Coulomb kuvveti mesafenin karesiyle ters orantılıdır."},
            {"t": "Sonuç", "a": "Kuvvet 4'te 1'e düşer.", "d": "r → 2r ise F → F/4."}
          ],
          "ans": "4'te birine düşer",
          "o": ["2'ye bölünür", "4 katına çıkar", "Değişmez", "Sıfır olur"]
        },
        {
          "q": "Zıt işaretli iki yük arasındaki kuvvetin yönü nasıldır?",
          "steps": [
            {"t": "Kural", "a": "Yükler birbirini çeker.", "d": "Bir yük + diğeri − ise aralarında çekme kuvveti oluşur."}
          ],
          "ans": "Birbirini çeker (çekici kuvvet)",
          "o": ["Birbirini iter", "Kuvvet sıfırdır", "Yatay kuvvet oluşur", "Her iki yönde eşit kuvvet oluşur"]
        }
      ],
      "zor": [
        {
          "q": "3×10⁻⁶ C ve 6×10⁻⁶ C büyüklüğündeki iki yük 0,3 m uzakta bulunuyor. Aralarındaki elektrostatik kuvvet kaç Newton'dur? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Formül", "a": "F = k·q₁·q₂/r²", "d": "Coulomb Yasası'nı uyguluyoruz."},
            {"t": "Yerine koy", "a": "F = 9×10⁹ × 3×10⁻⁶ × 6×10⁻⁶ / (0,3)²", "d": "Pay: 9×10⁹ × 18×10⁻¹² = 162×10⁻³ = 0,162 N·m². Payda: 0,09 m²."},
            {"t": "Hesapla", "a": "F = 0,162 / 0,09 = 1,8 N", "d": "İki yük zıt işaretliyse kuvvet çekicidir; aynı işaretliyse iticidedir."}
          ],
          "ans": "1,8 N",
          "o": ["0,18 N", "18 N", "0,9 N", "3,6 N"]
        },
        {
          "q": "İki eşit yük q, r uzaklıkta F kuvvetiyle etkileşiyor. Yüklerin her biri 3 katına çıkarılıp mesafe 3'e bölünürse yeni kuvvet ne olur?",
          "steps": [
            {"t": "Başlangıç", "a": "F = k·q·q/r²", "d": "Başlangıç koşulları."},
            {"t": "Yeni durum", "a": "F' = k·(3q)·(3q)/(r/3)²", "d": "Yeni yükler 3q, yeni mesafe r/3."},
            {"t": "Hesapla", "a": "F' = k·9q²/(r²/9) = 81·k·q²/r² = 81F", "d": "Pay 9 kat, payda 1/9 kat; toplam 81 kat artar."}
          ],
          "ans": "81F",
          "o": ["9F", "27F", "3F", "243F"]
        },
        {
          "q": "A(+2 μC) ve B(−2 μC) yükleri 0,2 m uzakta. C noktası A ile B'nin tam ortasında. A'nın C'ye uyguladığı kuvvetin büyüklüğü kaçtır? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Mesafe", "a": "r = 0,1 m", "d": "C noktası tam orta, dolayısıyla A–C ve B–C mesafesi 0,1 m."},
            {"t": "Formül", "a": "F = k·q₁·q₂/r²", "d": "Burada test yük yerine A'nın C'ye etkisi sorulmaktadır; A ile B'nin birbirine kuvvetini hesaplıyoruz (q₂ olarak B'yi alırsak 0,2 m)."},
            {"t": "A–B kuvveti", "a": "F = 9×10⁹ × 2×10⁻⁶ × 2×10⁻⁶ / (0,2)² = 36×10⁻³ / 0,04 = 0,9 N", "d": "İki yük zıt işaretli, kuvvet çekicidir; büyüklük 0,9 N."}
          ],
          "ans": "0,9 N",
          "o": ["0,45 N", "3,6 N", "9 N", "0,09 N"]
        }
      ]
    }
  },
  "elektrikAlan": {
    "lise": {
      "kolay": [
        {
          "q": "Elektrik alan şiddeti (E) nasıl tanımlanır?",
          "steps": [
            {"t": "Tanım", "a": "E = F/q", "d": "Birim pozitif test yüküne etki eden elektrostatik kuvvet, o noktadaki elektrik alanı verir."}
          ],
          "ans": "E = F/q",
          "o": ["E = q/F", "E = F·q", "E = F·r²", "E = k/q"]
        },
        {
          "q": "Nokta yük Q'dan r uzaklıkta oluşan elektrik alan büyüklüğü nedir?",
          "steps": [
            {"t": "Formül", "a": "E = k·Q/r²", "d": "Coulomb Yasası'ndan türetilir: E = F/q = k·Q·q/(r²·q) = k·Q/r²."}
          ],
          "ans": "E = k·Q/r²",
          "o": ["E = k·Q/r", "E = k·Q·r²", "E = Q/(k·r²)", "E = k/(Q·r²)"]
        },
        {
          "q": "Pozitif bir yükten çıkan elektrik alan çizgilerinin yönü nasıldır?",
          "steps": [
            {"t": "Kural", "a": "Pozitif yükten dışarıya doğru.", "d": "Alan çizgileri pozitif yüklerden çıkar, negatif yüklere girer."}
          ],
          "ans": "Yükten uzağa doğru (dışarıya)",
          "o": ["Yüke doğru (içeriye)", "Yatay yönde", "Döngüsel şekilde", "Rastgele yönlerde"]
        },
        {
          "q": "Elektrik alan çizgileri hakkında aşağıdakilerden hangisi doğrudur?",
          "steps": [
            {"t": "Kural", "a": "Alan çizgileri birbirini kesmez.", "d": "Bir noktada elektrik alanın tek bir yönü olabilir; bu nedenle çizgiler kesişemez."}
          ],
          "ans": "Alan çizgileri birbirini kesmez",
          "o": ["Alan çizgileri kapalı döngü oluşturur", "Alan çizgileri negatif yükten çıkar", "Alan çizgileri pozitif yüke girer", "Alan çizgileri her zaman paralel olur"]
        },
        {
          "q": "Birden fazla yükün oluşturduğu toplam elektrik alan nasıl bulunur?",
          "steps": [
            {"t": "Süperpozisyon", "a": "Vektörel toplam alınır.", "d": "Her yükün ayrı ayrı oluşturduğu alanlar vektörel olarak toplanır (süperpozisyon ilkesi)."}
          ],
          "ans": "Her yükün alanının vektörel toplamı",
          "o": ["Skaler toplam alınır", "Sadece büyük yükün alanı hesaplanır", "Yükler çarpılır", "Ortalaması alınır"]
        }
      ],
      "zor": [
        {
          "q": "5×10⁻⁶ C yükünden 0,5 m uzaklıktaki elektrik alan şiddeti kaç N/C'dir? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Formül", "a": "E = k·Q/r²", "d": "Nokta yük için elektrik alan formülü."},
            {"t": "Yerine koy", "a": "E = 9×10⁹ × 5×10⁻⁶ / (0,5)²", "d": "Pay: 45×10³. Payda: 0,25."},
            {"t": "Hesapla", "a": "E = 45000 / 0,25 = 1,8×10⁵ N/C", "d": "Yükten 0,5 m uzakta alan 1,8×10⁵ N/C'dir."}
          ],
          "ans": "1,8×10⁵ N/C",
          "o": ["9×10⁴ N/C", "3,6×10⁵ N/C", "4,5×10⁴ N/C", "1,8×10⁴ N/C"]
        },
        {
          "q": "+Q ve −Q büyüklüğünde iki yük d uzaklıkta karşılıklı duruyor. Tam orta noktadaki net elektrik alanın yönü ve büyüklüğü nedir?",
          "steps": [
            {"t": "+Q'nun katkısı", "a": "E₁ = k·Q/(d/2)² = 4kQ/d², yön → −Q'ya doğru", "d": "+Q'dan çıkan alan sağa (−Q yönünde) işaret eder."},
            {"t": "−Q'nun katkısı", "a": "E₂ = k·Q/(d/2)² = 4kQ/d², yön → −Q'ya doğru", "d": "−Q'ya giren alan da aynı yönde (sağa) işaret eder."},
            {"t": "Net alan", "a": "E_net = 8kQ/d², +Q'dan −Q'ya doğru", "d": "İki katkı aynı yönde olduğundan toplanır."}
          ],
          "ans": "8kQ/d², +Q'dan −Q'ya doğru",
          "o": ["Sıfır, katkılar birbirini iptal eder", "4kQ/d², +Q'dan dışarıya", "2kQ/d², dikey yönde", "8kQ/d², −Q'dan +Q'ya doğru"]
        },
        {
          "q": "Bir noktada E = 4×10⁴ N/C büyüklüğünde elektrik alan var. Bu noktaya konulan 3×10⁻⁸ C yüküne etki eden kuvvet kaç Newton'dur?",
          "steps": [
            {"t": "Formül", "a": "F = q·E", "d": "Elektrik alan içindeki yüke etki eden kuvvet."},
            {"t": "Hesapla", "a": "F = 3×10⁻⁸ × 4×10⁴ = 12×10⁻⁴ = 1,2×10⁻³ N", "d": "Kuvvet 1,2 mN olarak bulunur."}
          ],
          "ans": "1,2×10⁻³ N",
          "o": ["1,2×10⁻⁴ N", "1,2×10⁻² N", "4×10⁻⁴ N", "3×10⁻³ N"]
        }
      ]
    }
  },
  "testYuk": {
    "lise": {
      "kolay": [
        {
          "q": "Test yükü nedir ve özellikleri nelerdir?",
          "steps": [
            {"t": "Tanım", "a": "Çok küçük pozitif yük", "d": "Test yükü; ölçülmek istenen alanı bozmayacak kadar küçük, pozitif işaretli hayali bir yüktür."}
          ],
          "ans": "Alanı bozmayacak kadar küçük, pozitif işaretli yük",
          "o": ["Büyük negatif yük", "Nötr (yüksüz) cisim", "Büyük pozitif yük", "Yükü bilinmeyen cisim"]
        },
        {
          "q": "Pozitif test yükü, bir elektrik alanına bırakıldığında hangi yönde hareket eder?",
          "steps": [
            {"t": "Kural", "a": "Elektrik alanının yönünde hareket eder.", "d": "F = q·E bağıntısında q > 0 ise kuvvet ve dolayısıyla hareket alan yönündedir."}
          ],
          "ans": "Elektrik alanının yönünde",
          "o": ["Elektrik alanının zıt yönünde", "Alana dik yönde", "Hareketsiz kalır", "Dairesel hareket yapar"]
        },
        {
          "q": "Elektrik alan çizgileri fiziksel olarak neyi temsil eder?",
          "steps": [
            {"t": "Anlam", "a": "Pozitif test yükünün izleyeceği yolu gösterir.", "d": "Serbest bırakılan pozitif test yükü, alan çizgisi boyunca hareket eder."}
          ],
          "ans": "Pozitif test yükünün hareket yolunu",
          "o": ["Negatif yükün hareket yolunu", "Elektrik akımının yolunu", "Manyetik alanın yolunu", "Nötr parçacığın yolunu"]
        },
        {
          "q": "Negatif yük elektrik alanında hangi yönde kuvvet alır?",
          "steps": [
            {"t": "Kural", "a": "Elektrik alanının zıt yönünde kuvvet alır.", "d": "F = q·E; q < 0 olduğundan kuvvet, alan yönünün tersinedir."}
          ],
          "ans": "Elektrik alanının zıt yönünde",
          "o": ["Elektrik alanının yönünde", "Alana dik yönde", "Kuvvet almaz", "Dönme hareketi yapar"]
        },
        {
          "q": "Test yükü q = 2×10⁻⁹ C, E = 500 N/C olan bir noktaya konuluyor. Test yüküne etki eden kuvvet nedir?",
          "steps": [
            {"t": "Formül", "a": "F = q·E", "d": "Elektrik alanındaki yüke etki eden kuvvet."},
            {"t": "Hesapla", "a": "F = 2×10⁻⁹ × 500 = 10⁻⁶ N = 1 μN", "d": "Kuvvet 1 mikro Newton'dur."}
          ],
          "ans": "1×10⁻⁶ N",
          "o": ["2,5×10⁻⁷ N", "1×10⁻³ N", "5×10⁻⁷ N", "1×10⁻⁹ N"]
        }
      ],
      "zor": [
        {
          "q": "E = 6×10³ N/C büyüklüğünde yatay bir elektrik alanında, q = 4×10⁻⁶ C yüklü ve m = 2×10⁻⁵ kg kütleli bir cisim serbest bırakılıyor. Cismin elektriksel ivmesi kaç m/s²'dir?",
          "steps": [
            {"t": "Kuvvet", "a": "F = q·E = 4×10⁻⁶ × 6×10³ = 24×10⁻³ N", "d": "Elektrik kuvveti."},
            {"t": "İvme", "a": "a = F/m = 24×10⁻³ / 2×10⁻⁵ = 1200 m/s²", "d": "Newton'un 2. yasası: F = m·a."}
          ],
          "ans": "1200 m/s²",
          "o": ["120 m/s²", "600 m/s²", "2400 m/s²", "12 m/s²"]
        },
        {
          "q": "Pozitif test yükü +q, iki paralel plaka arasındaki düzgün elektrik alanında (E = 2000 N/C) 0,05 m boyunca alan yönünde hareket ediyor. Alan tarafından test yüküne (q = 1×10⁻⁶ C) yapılan iş nedir?",
          "steps": [
            {"t": "Kuvvet", "a": "F = q·E = 1×10⁻⁶ × 2000 = 2×10⁻³ N", "d": "Elektrik kuvveti."},
            {"t": "İş", "a": "W = F·d = 2×10⁻³ × 0,05 = 1×10⁻⁴ J", "d": "Kuvvet ve yer değiştirme aynı yönde olduğundan iş pozitiftir."}
          ],
          "ans": "1×10⁻⁴ J",
          "o": ["2×10⁻⁴ J", "4×10⁻⁸ J", "1×10⁻³ J", "5×10⁻⁵ J"]
        },
        {
          "q": "Bir test yükü (+3 μC) düzgün elektrik alanında (E = 5000 N/C) serbest bırakılıyor. 0,1 s sonra yükün hızı nedir? (m = 1,5×10⁻⁴ kg, yalnızca elektrik kuvveti var)",
          "steps": [
            {"t": "Kuvvet", "a": "F = q·E = 3×10⁻⁶ × 5000 = 1,5×10⁻² N", "d": "Elektrik kuvveti."},
            {"t": "İvme", "a": "a = F/m = 1,5×10⁻² / 1,5×10⁻⁴ = 100 m/s²", "d": "Newton'un 2. yasası."},
            {"t": "Hız", "a": "v = a·t = 100 × 0,1 = 10 m/s", "d": "Başlangıç hızı sıfırdan düzgün ivmeli hareket."}
          ],
          "ans": "10 m/s",
          "o": ["1 m/s", "100 m/s", "0,1 m/s", "50 m/s"]
        }
      ]
    }
  },
  "noktasalAlan": {
    "lise": {
      "kolay": [
        {
          "q": "Noktasal yükün oluşturduğu elektrik alan uzaklaştıkça nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "E = k·Q/r²", "d": "Mesafe arttıkça r² büyüdüğünden E azalır; alan ters kare yasasına uyar."}
          ],
          "ans": "Mesafenin karesiyle ters orantılı azalır",
          "o": ["Mesafe ile doğru orantılı artar", "Mesafeden bağımsızdır", "Mesafe ile ters orantılı azalır", "Mesafenin küpüyle ters orantılı azalır"]
        },
        {
          "q": "Noktasal bir yükün elektrik alan çizgilerinin şekli nasıldır?",
          "steps": [
            {"t": "Şekil", "a": "Radyal (yayıcı) çizgiler", "d": "Pozitif noktasal yükten her yöne eşit uzaklıkta radyal çizgiler çıkar; negatif için içeri girer."}
          ],
          "ans": "Yükten her yöne radyal yayılan çizgiler",
          "o": ["Paralel düz çizgiler", "Dairesel kapalı çizgiler", "Parabolik eğriler", "Yalnızca yatay çizgiler"]
        },
        {
          "q": "Noktasal yük Q'ya olan uzaklık 2r iken elektrik alan E ise, r uzaklıkta alan nedir?",
          "steps": [
            {"t": "Oran", "a": "E ∝ 1/r²", "d": "Uzaklık yarıya inince alan 4 katına çıkar."},
            {"t": "Hesapla", "a": "E_yeni = 4E", "d": "r → r/2 iken E → 4E."}
          ],
          "ans": "4E",
          "o": ["2E", "E/4", "E/2", "8E"]
        },
        {
          "q": "Elektrik alan biriminin SI sistemindeki karşılığı nedir?",
          "steps": [
            {"t": "Birim", "a": "N/C veya V/m", "d": "N/C (Newton bölü Coulomb) ile V/m (Volt bölü metre) eşdeğerdir."}
          ],
          "ans": "N/C (veya V/m)",
          "o": ["C/N", "J/C", "W/m", "N·m/C"]
        },
        {
          "q": "İki farklı noktasal yükten hangisinin alanı daha güçlüdür, aynı uzaklıkta Q₁ = 4 μC mi yoksa Q₂ = 8 μC mi?",
          "steps": [
            {"t": "Oran", "a": "E ∝ Q", "d": "Sabit r'de alan, yükle doğru orantılıdır."},
            {"t": "Sonuç", "a": "Q₂ = 8 μC daha güçlü alan oluşturur.", "d": "8 μC, 4 μC'nin 2 katı olduğundan alanı da 2 kat büyüktür."}
          ],
          "ans": "Q₂ = 8 μC",
          "o": ["Q₁ = 4 μC", "İkisi eşit", "Uzaklığa bağlı olarak değişir", "Yük işaretine göre değişir"]
        }
      ],
      "zor": [
        {
          "q": "Q = 8×10⁻⁶ C noktasal yükten r₁ = 0,2 m ve r₂ = 0,6 m uzaklıklardaki elektrik alan değerlerinin oranı (E₁/E₂) nedir?",
          "steps": [
            {"t": "Formül", "a": "E ∝ 1/r²", "d": "Aynı yük için farklı uzaklıklardaki oran."},
            {"t": "Hesapla", "a": "E₁/E₂ = (r₂/r₁)² = (0,6/0,2)² = 3² = 9", "d": "r₂, r₁'in 3 katı olduğundan E₁, E₂'nin 9 katıdır."}
          ],
          "ans": "9",
          "o": ["3", "6", "27", "1/9"]
        },
        {
          "q": "Q = 2×10⁻⁸ C noktasal yükten E = 800 N/C büyüklüğünde alan oluşturan noktanın uzaklığı kaç metredir? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Formül", "a": "E = k·Q/r² → r² = k·Q/E", "d": "r'yi çekelim."},
            {"t": "Hesapla", "a": "r² = 9×10⁹ × 2×10⁻⁸ / 800 = 180 / 800 = 0,225", "d": "r² = 0,225 m²."},
            {"t": "Kök", "a": "r = √0,225 ≈ 0,474 m ≈ 0,47 m", "d": "Uzaklık yaklaşık 0,47 metredir."}
          ],
          "ans": "0,47 m",
          "o": ["0,15 m", "0,225 m", "0,9 m", "0,03 m"]
        },
        {
          "q": "Noktasal yükten 0,3 m uzakta E₁ = 1200 N/C, 0,9 m uzakta E₂ = ? Alan ters kare yasasına uyuyorsa E₂ nedir?",
          "steps": [
            {"t": "Mesafe oranı", "a": "r₂/r₁ = 0,9/0,3 = 3", "d": "Mesafe 3 kat arttı."},
            {"t": "Alan oranı", "a": "E₂ = E₁/(r₂/r₁)² = 1200/9", "d": "Alan mesafenin karesiyle ters orantılı."},
            {"t": "Hesapla", "a": "E₂ ≈ 133 N/C", "d": "Mesafe 3 katına çıkınca alan 9'da bire düşer."}
          ],
          "ans": "133 N/C",
          "o": ["400 N/C", "600 N/C", "300 N/C", "1800 N/C"]
        }
      ]
    }
  },
  "ikiYuk": {
    "lise": {
      "kolay": [
        {
          "q": "Aynı işaretli iki yük arasındaki etkileşme nasıldır?",
          "steps": [
            {"t": "Kural", "a": "İtme kuvveti oluşur.", "d": "++ veya −− yükler birbirini iter."}
          ],
          "ans": "Birbirini iter",
          "o": ["Birbirini çeker", "Etkileşmez", "Önce çeker sonra iter", "Sadece büyük yük küçüğü iter"]
        },
        {
          "q": "Zıt işaretli (+) ve (−) iki yük arasındaki etkileşme nasıldır?",
          "steps": [
            {"t": "Kural", "a": "Çekme kuvveti oluşur.", "d": "Zıt işaretli yükler birbirini çeker."}
          ],
          "ans": "Birbirini çeker",
          "o": ["Birbirini iter", "Etkileşmez", "Her zaman yatay kuvvet oluşur", "Kuvvet yönü belirsizdir"]
        },
        {
          "q": "Süperpozisyon ilkesine göre, birden fazla yükün oluşturduğu net kuvvet nasıl hesaplanır?",
          "steps": [
            {"t": "İlke", "a": "Her yükün ayrı ayrı oluşturduğu kuvvetler vektörel toplanır.", "d": "Coulomb kuvvetleri vektörel büyüklük olduğundan toplanmaları vektörel yapılır."}
          ],
          "ans": "Vektörel toplam alınır",
          "o": ["Skaler toplam alınır", "Sadece en büyük kuvvet alınır", "Kuvvetler çarpılır", "Ortalama alınır"]
        },
        {
          "q": "İki özdeş negatif yükün tam ortasındaki noktada net elektrik alan nedir?",
          "steps": [
            {"t": "Simetri", "a": "Net alan sıfırdır.", "d": "Her iki yükün alanı eşit büyüklükte, zıt yönde olduğundan vektörel toplamları sıfır verir."}
          ],
          "ans": "Sıfır",
          "o": ["İki katı", "Yarısı", "Belirsiz", "Orta noktanın altına doğru"]
        },
        {
          "q": "+3 μC ve −3 μC yükleri 0,4 m uzakta. Birbirine uyguladıkları kuvvetin yönü nedir?",
          "steps": [
            {"t": "İşaret", "a": "Zıt işaretli → çekme", "d": "+3 μC ve −3 μC zıt işaretli olduğundan kuvvet çekicidir."},
            {"t": "Yön", "a": "Her yük diğerine doğru çekilir.", "d": "Newton'un 3. yasası gereği kuvvetler eşit-zıt yönlüdür."}
          ],
          "ans": "Birbirini çeker (her yük diğerine doğru)",
          "o": ["Birbirini iter", "Yalnızca pozitif yük negatife doğru", "Yalnızca negatif yük pozitife doğru", "Kuvvet yönü belirsizdir"]
        }
      ],
      "zor": [
        {
          "q": "A(+4 μC) ve B(+4 μC) yükleri 0,4 m uzakta. Bu iki yükün tam ortasına C(+1 μC) yükü konuluyor. C yüküne etki eden net kuvvet nedir?",
          "steps": [
            {"t": "A–C kuvveti", "a": "F_AC = k·4×10⁻⁶·1×10⁻⁶/(0,2)² = 9×10⁹ × 4×10⁻¹² / 0,04 = 0,9 N (sağa)", "d": "A, C'yi sağa (B yönüne) iter."},
            {"t": "B–C kuvveti", "a": "F_BC = 0,9 N (sola)", "d": "B de C'yi sola (A yönüne) iter; büyüklük eşit."},
            {"t": "Net kuvvet", "a": "F_net = 0,9 − 0,9 = 0 N", "d": "Sistem simetrisi nedeniyle net kuvvet sıfırdır."}
          ],
          "ans": "0 N (net kuvvet sıfır)",
          "o": ["1,8 N sağa", "0,9 N sola", "0,45 N sağa", "1,8 N sola"]
        },
        {
          "q": "A(+6 μC) ve B(−2 μC) yükleri 0,6 m uzakta. Yükler arasındaki Coulomb kuvvetinin büyüklüğünü bulunuz. (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Formül", "a": "F = k·q₁·q₂/r²", "d": "İşareti hesaba katmadan büyüklük alıyoruz."},
            {"t": "Yerine koy", "a": "F = 9×10⁹ × 6×10⁻⁶ × 2×10⁻⁶ / (0,6)²", "d": "Pay: 108×10⁻³ = 0,108. Payda: 0,36."},
            {"t": "Hesapla", "a": "F = 0,108 / 0,36 = 0,3 N", "d": "Zıt işaretli olduğundan kuvvet çekicidir; büyüklük 0,3 N."}
          ],
          "ans": "0,3 N",
          "o": ["0,03 N", "3 N", "0,9 N", "0,6 N"]
        },
        {
          "q": "+5 μC ve +5 μC yükleri 0,5 m aralıklı. Doğrultunun tam dışında, B yükünden 0,5 m uzakta C(+1 μC) noktası var. Sadece B'nin C'ye uyguladığı kuvvet kaçtır? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Formül", "a": "F_BC = k·q_B·q_C/r²", "d": "Yalnızca B–C çifti için Coulomb Yasası."},
            {"t": "Yerine koy", "a": "F_BC = 9×10⁹ × 5×10⁻⁶ × 1×10⁻⁶ / (0,5)²", "d": "Pay: 45×10⁻³. Payda: 0,25."},
            {"t": "Hesapla", "a": "F_BC = 0,045 / 0,25 = 0,18 N", "d": "B ve C aynı işaretli olduğundan bu kuvvet iticidedir."}
          ],
          "ans": "0,18 N",
          "o": ["0,9 N", "0,36 N", "0,045 N", "1,8 N"]
        }
      ]
    }
  },
  "iletkenKure": {
    "lise": {
      "kolay": [
        {
          "q": "Yüklü iletken bir kürede yükler nerede toplanır?",
          "steps": [
            {"t": "Kural", "a": "Yalnızca yüzeyde", "d": "İletken içindeki elektrik alan sıfır olduğundan serbest yükler yüzeye yerleşir."}
          ],
          "ans": "Yalnızca yüzeyde",
          "o": ["Yalnızca merkeze", "İç hacme eşit dağılır", "Yarıçap boyunca dağılır", "Alt yarıkürede toplanır"]
        },
        {
          "q": "İletkenin iç kısmındaki elektrik alan ne kadardır?",
          "steps": [
            {"t": "Sonuç", "a": "E = 0 (sıfır)", "d": "İletken dengede olduğunda iç kısımda serbest yük bulunmaz; dolayısıyla alan sıfırdır."}
          ],
          "ans": "Sıfır (E = 0)",
          "o": ["Maksimum değerde", "Yükle orantılı", "Merkezde en büyük, yüzeyde sıfır", "Yarıçapa bağlı değişken"]
        },
        {
          "q": "Yüklü iletken kürenin dışındaki elektrik alan nasıl hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "E = k·Q/r²", "d": "Dışarıda, tüm yük merkezdeymiş gibi davranır; nokta yük formülü geçerlidir."}
          ],
          "ans": "E = k·Q/r² (tüm yük merkezde gibi)",
          "o": ["E = k·Q/r", "E = 0 dışarıda da", "E = k·Q·r", "E = k·Q/R² (R sabit, r değil)"]
        },
        {
          "q": "Küresel iletken yüzeydeki yük dağılımı nasıldır?",
          "steps": [
            {"t": "Dağılım", "a": "Yüzeye eşit (düzgün) dağılır.", "d": "Mükemmel küre geometrisi nedeniyle yük yoğunluğu her noktada eşittir."}
          ],
          "ans": "Yüzeye düzgün (eşit) dağılır",
          "o": ["Yalnızca kutuplarda yoğunlaşır", "Alt yarıküreye toplanır", "Rastgele dağılır", "Yüzey alanına değil hacme göre dağılır"]
        },
        {
          "q": "Yüklü iletken kürenin tam yüzeyinde (r = R) elektrik alan formülü nedir?",
          "steps": [
            {"t": "Formül", "a": "E = k·Q/R²", "d": "r = R yüzeyde, dış bölge formülü geçerlidir."}
          ],
          "ans": "E = k·Q/R²",
          "o": ["E = 0", "E = k·Q/2R²", "E = k·Q·R", "E = Q/(4πR)"]
        }
      ],
      "zor": [
        {
          "q": "Yarıçapı R = 0,1 m, toplam yükü Q = 5×10⁻⁶ C olan iletken bir kürenin merkezinde, yüzeyinde ve 0,3 m uzağındaki elektrik alan değerlerini karşılaştırınız. (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Merkez", "a": "E_merkez = 0", "d": "İletken iç kısmında alan sıfırdır."},
            {"t": "Yüzey (r=R=0,1 m)", "a": "E = 9×10⁹ × 5×10⁻⁶ / (0,1)² = 4,5×10⁶ N/C", "d": "Dış bölge formülü r=R'de uygulanır."},
            {"t": "Dış nokta (r=0,3 m)", "a": "E = 9×10⁹ × 5×10⁻⁶ / (0,3)² = 5×10⁵ N/C", "d": "Mesafe 3 kat arttığından alan 9 kat azalır."}
          ],
          "ans": "Merkez: 0, Yüzey: 4,5×10⁶ N/C, 0,3 m: 5×10⁵ N/C",
          "o": [
            "Merkez: 4,5×10⁶, Yüzey: 4,5×10⁶, 0,3 m: 4,5×10⁶ N/C",
            "Merkez: 0, Yüzey: 0, 0,3 m: 4,5×10⁵ N/C",
            "Merkez: 4,5×10⁶, Yüzey: 0, 0,3 m: 5×10⁵ N/C",
            "Merkez: 0, Yüzey: 5×10⁵, 0,3 m: 4,5×10⁶ N/C"
          ]
        },
        {
          "q": "Yüklü iletken kürenin dışında (r = 2R) ve yüzeyinde (r = R) elektrik alan oranı E(2R)/E(R) nedir?",
          "steps": [
            {"t": "E(R)", "a": "E(R) = k·Q/R²", "d": "Yüzeyde alan."},
            {"t": "E(2R)", "a": "E(2R) = k·Q/(2R)² = k·Q/4R²", "d": "2R uzaklıkta alan."},
            {"t": "Oran", "a": "E(2R)/E(R) = 1/4", "d": "Mesafe 2 kat artınca alan 4'te bire düşer."}
          ],
          "ans": "1/4",
          "o": ["1/2", "1/8", "4", "2"]
        },
        {
          "q": "Q = 10 μC yüklü, R = 0,2 m yarıçaplı iletken küreden 0,8 m uzaklıkta elektrik alan kaçtır? (k = 9×10⁹ N·m²/C²)",
          "steps": [
            {"t": "Kontrol", "a": "r = 0,8 m > R = 0,2 m → dış bölge", "d": "Nokta yük formülü geçerli."},
            {"t": "Hesapla", "a": "E = 9×10⁹ × 10×10⁻⁶ / (0,8)² = 90000 / 0,64", "d": "Pay: 9×10⁴. Payda: 0,64."},
            {"t": "Sonuç", "a": "E ≈ 1,41×10⁵ N/C", "d": "Yaklaşık 141 000 N/C."}
          ],
          "ans": "≈ 1,41×10⁵ N/C",
          "o": ["5,6×10⁵ N/C", "2,25×10⁶ N/C", "7×10⁴ N/C", "3,6×10⁵ N/C"]
        }
      ]
    }
  },
  "gucFatura": {
    "lise": {
      "kolay": [
        {
          "q": "Elektrik gücü (P) nasıl hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "P = V·I", "d": "Güç, gerilim ile akımın çarpımına eşittir. Birimi Watt (W)."}
          ],
          "ans": "P = V·I",
          "o": ["P = V/I", "P = V+I", "P = I/V", "P = V²·I"]
        },
        {
          "q": "1 kWh kaç Joule'e eşittir?",
          "steps": [
            {"t": "Dönüşüm", "a": "1 kWh = 1000 W × 3600 s = 3,6×10⁶ J", "d": "1 kilo Watt = 1000 W; 1 saat = 3600 saniye."}
          ],
          "ans": "3,6×10⁶ J",
          "o": ["1000 J", "3600 J", "3,6×10³ J", "1,6×10⁻¹⁹ J"]
        },
        {
          "q": "220 V gerilimde çalışan bir ampul 2 A akım çekiyor. Gücü nedir?",
          "steps": [
            {"t": "Hesapla", "a": "P = V·I = 220 × 2 = 440 W", "d": "P = V·I formülü uygulanır."}
          ],
          "ans": "440 W",
          "o": ["110 W", "220 W", "880 W", "44 W"]
        },
        {
          "q": "Elektrik enerjisi (W) güç ve süre cinsinden nasıl hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "W = P·t", "d": "Enerji, gücün süre ile çarpımına eşittir."}
          ],
          "ans": "W = P·t",
          "o": ["W = P/t", "W = P+t", "W = P²·t", "W = t/P"]
        },
        {
          "q": "Ohm Yasası'ndan türetilen güç formülleri hangileridir?",
          "steps": [
            {"t": "Türetim", "a": "P = I²·R ve P = V²/R", "d": "V = I·R kullanılarak P = V·I → P = (I·R)·I = I²·R veya P = V·(V/R) = V²/R."}
          ],
          "ans": "P = I²·R ve P = V²/R",
          "o": ["P = I/R² ve P = V·R", "P = I²/R ve P = V²·R", "P = I·R ve P = V/R", "P = R/I² ve P = R/V²"]
        }
      ],
      "zor": [
        {
          "q": "1800 W gücünde bir fırın günde 2 saat çalışıyor. 30 günlük enerji tüketimi kaç kWh'dir ve 1 kWh = 2,5 TL ise aylık fatura kaç TL'dir?",
          "steps": [
            {"t": "Günlük enerji", "a": "E_gün = 1,8 kW × 2 h = 3,6 kWh", "d": "1800 W = 1,8 kW."},
            {"t": "Aylık enerji", "a": "E_ay = 3,6 × 30 = 108 kWh", "d": "30 günlük toplam."},
            {"t": "Fatura", "a": "Fatura = 108 × 2,5 = 270 TL", "d": "Aylık elektrik maliyeti 270 TL'dir."}
          ],
          "ans": "108 kWh, 270 TL",
          "o": ["54 kWh, 135 TL", "216 kWh, 540 TL", "108 kWh, 250 TL", "36 kWh, 90 TL"]
        },
        {
          "q": "220 V'a bağlı, direnci R = 484 Ω olan bir elektrikli su ısıtıcısı 15 dakika çalışıyor. Harcanan enerji kaç Joule'dür?",
          "steps": [
            {"t": "Güç", "a": "P = V²/R = (220)² / 484 = 48400 / 484 = 100 W", "d": "P = V²/R formülü."},
            {"t": "Süre", "a": "t = 15 × 60 = 900 s", "d": "Dakikayı saniyeye çevir."},
            {"t": "Enerji", "a": "W = P·t = 100 × 900 = 90 000 J = 9×10⁴ J", "d": "W = P·t."}
          ],
          "ans": "9×10⁴ J",
          "o": ["4,84×10⁴ J", "1,8×10⁵ J", "4,5×10³ J", "4,84×10³ J"]
        },
        {
          "q": "Bir ev 3 adet 100 W ampul, 1 adet 2000 W çamaşır makinesi ve 1 adet 500 W buzdolabı kullanıyor. Tüm cihazlar günde 5 saat çalışırsa aylık (30 gün) tüketim kaç kWh'dir?",
          "steps": [
            {"t": "Toplam güç", "a": "P_top = 3×100 + 2000 + 500 = 300 + 2000 + 500 = 2800 W = 2,8 kW", "d": "Tüm güçlerin toplamı."},
            {"t": "Günlük enerji", "a": "E_gün = 2,8 kW × 5 h = 14 kWh", "d": "Günlük toplam tüketim."},
            {"t": "Aylık enerji", "a": "E_ay = 14 × 30 = 420 kWh", "d": "30 günlük toplam tüketim."}
          ],
          "ans": "420 kWh",
          "o": ["140 kWh", "42 kWh", "280 kWh", "840 kWh"]
        }
      ]
    }
  },
  "ohmKanunu2": {
    "lise": {
      "kolay": [
        {
          "q": "Seri bağlı dirençlerde eşdeğer direnç nasıl hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "R_seri = R₁ + R₂ + R₃ + ...", "d": "Seri devrde dirençler toplanır; akım her dirençten aynı büyüklükte geçer."}
          ],
          "ans": "R_seri = R₁ + R₂ + ... (toplamları)",
          "o": ["1/R = 1/R₁ + 1/R₂", "R = R₁ · R₂ / (R₁+R₂)", "R = (R₁+R₂)/2", "R = R₁ − R₂"]
        },
        {
          "q": "Paralel bağlı dirençlerde eşdeğer direnç nasıl hesaplanır?",
          "steps": [
            {"t": "Formül", "a": "1/R_paralel = 1/R₁ + 1/R₂ + ...", "d": "Paralel devrde ters dirençler toplanır; gerilim her dirençte aynıdır."}
          ],
          "ans": "1/R = 1/R₁ + 1/R₂ + ...",
          "o": ["R = R₁ + R₂", "R = R₁ · R₂", "R = (R₁·R₂)/(R₁−R₂)", "R = R₁/R₂"]
        },
        {
          "q": "Ohm Yasası nedir?",
          "steps": [
            {"t": "Tanım", "a": "V = I·R", "d": "Bir iletkenin iki ucu arasındaki gerilim, içinden geçen akım ile direncin çarpımına eşittir."}
          ],
          "ans": "V = I·R",
          "o": ["V = I/R", "V = I+R", "V = I²·R", "V = R/I"]
        },
        {
          "q": "12 Ω ve 6 Ω dirençler seri bağlanıyor. Eşdeğer direnç nedir?",
          "steps": [
            {"t": "Hesapla", "a": "R_eş = 12 + 6 = 18 Ω", "d": "Seri bağlı dirençler toplanır."}
          ],
          "ans": "18 Ω",
          "o": ["4 Ω", "72 Ω", "9 Ω", "2 Ω"]
        },
        {
          "q": "12 Ω ve 6 Ω dirençler paralel bağlanıyor. Eşdeğer direnç nedir?",
          "steps": [
            {"t": "Formül", "a": "1/R = 1/12 + 1/6 = 1/12 + 2/12 = 3/12 = 1/4", "d": "Ters dirençler toplandı."},
            {"t": "Sonuç", "a": "R = 4 Ω", "d": "Paralel eşdeğer direnç her zaman en küçük dirençten küçüktür."}
          ],
          "ans": "4 Ω",
          "o": ["18 Ω", "9 Ω", "3 Ω", "6 Ω"]
        }
      ],
      "zor": [
        {
          "q": "12 V'luk pil, 4 Ω ve 8 Ω dirençler seri bağlı devreye bağlanıyor. Her dirençten geçen akım ve her direnç üzerindeki gerilim nedir?",
          "steps": [
            {"t": "Eşdeğer direnç", "a": "R_eş = 4 + 8 = 12 Ω", "d": "Seri bağlı dirençlerin toplamı."},
            {"t": "Akım", "a": "I = V/R = 12/12 = 1 A", "d": "Seri devrde akım her yerde aynıdır."},
            {"t": "Gerilimler", "a": "V₁ = 1×4 = 4 V, V₂ = 1×8 = 8 V", "d": "V = I·R ile her direnç üzerindeki gerilim bulunur. V₁+V₂ = 12 V ✓."}
          ],
          "ans": "I = 1 A; V₁ = 4 V, V₂ = 8 V",
          "o": [
            "I = 1 A; V₁ = 6 V, V₂ = 6 V",
            "I = 2 A; V₁ = 8 V, V₂ = 4 V",
            "I = 0,5 A; V₁ = 2 V, V₂ = 4 V",
            "I = 1 A; V₁ = 8 V, V₂ = 4 V"
          ]
        },
        {
          "q": "24 V'luk pil, 6 Ω ve 12 Ω paralel koldan oluşan bir devreye bağlı. Her koldan geçen akım ve devreden çekilen toplam akım nedir?",
          "steps": [
            {"t": "Her koldaki akım", "a": "I₁ = 24/6 = 4 A, I₂ = 24/12 = 2 A", "d": "Paralel devrde her kolun gerilimi kaynak gerilimine eşittir."},
            {"t": "Toplam akım", "a": "I_top = I₁ + I₂ = 4 + 2 = 6 A", "d": "Paralel devrde toplam akım kollar akımlarının toplamıdır."},
            {"t": "Kontrol", "a": "R_eş = (6×12)/(6+12) = 72/18 = 4 Ω → I = 24/4 = 6 A ✓", "d": "Eşdeğer direnç üzerinden de aynı sonuç elde edilir."}
          ],
          "ans": "I₁ = 4 A, I₂ = 2 A, I_top = 6 A",
          "o": [
            "I₁ = 2 A, I₂ = 4 A, I_top = 6 A",
            "I₁ = 4 A, I₂ = 2 A, I_top = 2 A",
            "I₁ = 3 A, I₂ = 3 A, I_top = 6 A",
            "I₁ = 4 A, I₂ = 2 A, I_top = 8 A"
          ]
        },
        {
          "q": "Karışık devrede: 30 V kaynağa, 3 Ω (seri) ve ardından paralel bağlı 6 Ω ile 12 Ω bağlı. Devre akımı (I) ve paralel kolların her birindeki akım nedir?",
          "steps": [
            {"t": "Paralel eşdeğer", "a": "R_p = (6×12)/(6+12) = 4 Ω", "d": "6 Ω ∥ 12 Ω eşdeğer direnci."},
            {"t": "Toplam direnç", "a": "R_top = 3 + 4 = 7 Ω", "d": "Seri kısım ve paralel kısım toplanır."},
            {"t": "Devre akımı", "a": "I = 30/7 ≈ 4,3 A", "d": "Ohm Yasası: I = V/R."},
            {"t": "Paralel kollar", "a": "V_p = I × R_p = (30/7) × 4 = 120/7 ≈ 17,1 V → I₆ ≈ 2,86 A, I₁₂ ≈ 1,43 A", "d": "Paralel gerilimden her kol akımı: I₆ = V_p/6, I₁₂ = V_p/12."}
          ],
          "ans": "I ≈ 4,3 A; I₆ ≈ 2,86 A, I₁₂ ≈ 1,43 A",
          "o": [
            "I = 5 A; I₆ = 3 A, I₁₂ = 2 A",
            "I = 10 A; I₆ = 5 A, I₁₂ = 5 A",
            "I = 4 A; I₆ = 2 A, I₁₂ = 2 A",
            "I = 6 A; I₆ = 4 A, I₁₂ = 2 A"
          ]
        }
      ]
    }
  }
};
