globalThis.__BQ = {
  "dikeyIvme": {
    "lise": {
      "kolay": [
        {
          "q": "Yukarı ivmeli bir asansörde g_eff (etkin yerçekimi) nasıl hesaplanır?",
          "steps": [
            {"t": "Kuvvet analizi", "a": "N - mg = ma", "d": "Asansör yukarı ivmelenirken taban yolcuya ekstra normal kuvvet uygular."},
            {"t": "Görünür ağırlık", "a": "N = m·(g + a)", "d": "Bu nedenle etkin yerçekimi g_eff = g + a olur."}
          ],
          "ans": "g_eff = g + a",
          "o": ["g_eff = g - a", "g_eff = g · a", "g_eff = a/g", "g_eff = g² + a²"]
        },
        {
          "q": "Asansör serbest düşüşte iken içindeki suyun bulunduğu kaba etki eden basınç nedir?",
          "steps": [
            {"t": "Serbest düşüş", "a": "g_eff = g - g = 0", "d": "Serbest düşüşte asansörün ivmesi g'ye eşit ve aşağı yönlüdür."},
            {"t": "Basınç formülü", "a": "P = ρ·g_eff·h = 0", "d": "g_eff = 0 olduğundan sıvı basıncı sıfır olur; sıvı 'ağırlıksız' hale gelir."}
          ],
          "ans": "Sıfır",
          "o": ["ρ·g·h", "ρ·g·h/2", "ρ·h", "2·ρ·g·h"]
        },
        {
          "q": "Kütlesi 70 kg olan bir kişi, aşağı doğru 2 m/s² ivmeyle hareket eden asansörde kendini kaç N ağırlığında hisseder? (g = 10 m/s²)",
          "steps": [
            {"t": "g_eff hesabı", "a": "g_eff = g - a = 10 - 2 = 8 m/s²", "d": "Asansör aşağı ivmelenince etkin yerçekimi azalır."},
            {"t": "Görünür ağırlık", "a": "G_görünür = m·g_eff = 70·8 = 560 N", "d": "Kişi zemine 560 N basınç uygular."}
          ],
          "ans": "560 N",
          "o": ["700 N", "840 N", "490 N", "280 N"]
        },
        {
          "q": "İvmeli asansörde su dolu bir kabın tabanındaki P = ρ·g_eff·h formülünde g_eff neyi temsil eder?",
          "steps": [
            {"t": "Tanım", "a": "g_eff = g ± a", "d": "Asansör yukarı ivmelenirse + , aşağı ivmelenirse − işareti kullanılır."},
            {"t": "Yorum", "a": "Etkin yer çekimi ivmesi", "d": "Sıvı, gerçek g yerine g_eff'i 'hissederek' basınç oluşturur."}
          ],
          "ans": "Etkin (görünür) yerçekimi ivmesi",
          "o": ["Sıvının yüzey gerilimi katsayısı", "Asansörün mutlak hızı", "Sıvının özgül ısısı", "Kabın taban alanı"]
        },
        {
          "q": "Asansör yukarı doğru 5 m/s² ivmeyle hızlanırken, içindeki 1 kg su kütlesi üzerine etki eden etkin ağırlık kuvveti kaçtır? (g = 10 m/s²)",
          "steps": [
            {"t": "g_eff", "a": "g_eff = 10 + 5 = 15 m/s²", "d": "Yukarı ivmeli asansörde etkin yerçekimi artar."},
            {"t": "Ağırlık", "a": "G = m·g_eff = 1·15 = 15 N", "d": "Su kütlesi sanki 15 N ağırlığında gibi davranır."}
          ],
          "ans": "15 N",
          "o": ["10 N", "5 N", "20 N", "50 N"]
        }
      ],
      "zor": [
        {
          "q": "Yukarı doğru 3 m/s² ivmeyle hareket eden asansörde, tabanından 40 cm yüksekliğinde su dolu bir kap var. Kabın tabanındaki basınç kaç Pa'dır? (ρ_su = 1000 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "g_eff hesabı", "a": "g_eff = g + a = 10 + 3 = 13 m/s²", "d": "Yukarı ivmeli asansörde etkin yerçekimi artar."},
            {"t": "h değeri", "a": "h = 0,40 m", "d": "Sıvı derinliği 40 cm = 0,40 m."},
            {"t": "Basınç", "a": "P = ρ·g_eff·h = 1000·13·0,40 = 5200 Pa", "d": "Etkin yerçekimi ile hesaplanan hidrostatik basınç."}
          ],
          "ans": "5200 Pa",
          "o": ["4000 Pa", "6000 Pa", "3200 Pa", "5000 Pa"]
        },
        {
          "q": "Asansör aşağı doğru a ivmesiyle yavaşlıyor (hız aşağı yönlü). 80 kg kişinin görünür ağırlığı gerçek ağırlığının 1,25 katı oluyor. a kaç m/s²'dir? (g = 10 m/s²)",
          "steps": [
            {"t": "Görünür ağırlık denklemi", "a": "G_görünür = m·(g + a)", "d": "Asansör aşağı giderken yavaşlıyorsa ivme yukarı yönlüdür → g_eff = g + a."},
            {"t": "1,25 katı koşulu", "a": "m·(g + a) = 1,25·m·g → g + a = 1,25·g", "d": "Her iki taraf m ile sadeleşir."},
            {"t": "a değeri", "a": "a = 0,25·g = 0,25·10 = 2,5 m/s²", "d": "Aşağı yönlü hızın azalması yukarı yönlü ivme anlamına gelir."}
          ],
          "ans": "2,5 m/s²",
          "o": ["5 m/s²", "1,25 m/s²", "10 m/s²", "0,8 m/s²"]
        },
        {
          "q": "Asansör serbest düşüşe geçerken içindeki su dolu açık kaptaki sıvı seviyesi değişir mi? Açıklayın.",
          "steps": [
            {"t": "g_eff = 0 durumu", "a": "Serbest düşüşte g_eff = 0", "d": "Asansör g ivmesiyle düşerken içindeki her şey ağırlıksız hale gelir."},
            {"t": "Basınç farkı", "a": "P = ρ·g_eff·h = 0", "d": "Derinlikle basınç değişmediğinden sıvı 'yüzdüğü' konumda kalır, seviye değişmez fakat sıvı sıfır basınçla adeta asılı haldedir."},
            {"t": "Sonuç", "a": "Seviye korunur, sıvı yüzer hale gelir", "d": "Sıvı kaba yapışmadan salınmaya başlayabilir; tabanına basınç uygulamaz."}
          ],
          "ans": "Seviye geometrik olarak değişmez; sıvı ağırlıksız (basınçsız) hale gelir",
          "o": ["Sıvı taşar çünkü basınç artar", "Sıvı alta çöker", "Sıvı anında buharlaşır", "Sıvı seviyesi yarıya düşer"]
        }
      ]
    }
  },
  "ivmeliAkiskan": {
    "lise": {
      "kolay": [
        {
          "q": "Yatay ivmeli bir araçta sıvı yüzeyinin eğimi için formül nedir?",
          "steps": [
            {"t": "Denge koşulu", "a": "Yatay: ma, Dikey: mg", "d": "Eğik yüzey üzerindeki sıvı parçacığına iki kuvvet etki eder."},
            {"t": "Açı formülü", "a": "tan θ = a/g", "d": "Eğim açısının tangenti ivmenin yerçekimine oranına eşittir."}
          ],
          "ans": "tan θ = a/g",
          "o": ["tan θ = g/a", "sin θ = a/g", "tan θ = a·g", "cos θ = a/g"]
        },
        {
          "q": "İvmeli araçta sıvı yüzeyinin yüksek tarafı hangi yöndedir?",
          "steps": [
            {"t": "Atalet", "a": "Sıvı geriye doğru itilir", "d": "Araç öne ivmelenince sıvı eylemsizlik nedeniyle arkaya toplanır."},
            {"t": "Yüzey eğimi", "a": "Arka taraf yükselir", "d": "Yüksek basınç ve yüksek yüzey seviyesi ivmenin karşı yönündedir."}
          ],
          "ans": "İvmenin zıt yönü (arka taraf)",
          "o": ["İvmenin yönü (ön taraf)", "Her iki taraf eşit yükselir", "Alt taraf alçalır, fark oluşmaz", "Yatay ivmede sıvı yüzey değişmez"]
        },
        {
          "q": "Yatay ivmeli bir araçta sıvı yüzeyi eğik hale gelir. Bu eğim açısı θ = 30° ise ivme a kaçtır? (g = 10 m/s²)",
          "steps": [
            {"t": "Formül", "a": "tan θ = a/g", "d": "30° için tan 30° ≈ 0,577."},
            {"t": "a değeri", "a": "a = g·tan 30° ≈ 10·0,577 ≈ 5,77 m/s²", "d": "Yaklaşık 5,8 m/s² yatay ivme gerekir."}
          ],
          "ans": "≈ 5,8 m/s²",
          "o": ["≈ 10 m/s²", "≈ 8,7 m/s²", "≈ 3,3 m/s²", "≈ 1,0 m/s²"]
        },
        {
          "q": "Yatay ivmeli kapta sıvı içindeki basınç yatay yönde nasıl değişir?",
          "steps": [
            {"t": "Yatay basınç gradyanı", "a": "dP/dx = −ρ·a", "d": "İvme yönünde (öne doğru) basınç azalır."},
            {"t": "Arkaya doğru", "a": "Basınç artar", "d": "Sıvı arkaya toplanır ve arka taraftaki basınç daha yüksektir."}
          ],
          "ans": "İvmenin ters yönünde (arkaya doğru) artar",
          "o": ["İvme yönünde artar", "Yatay yönde basınç değişmez", "Her iki uca doğru artar", "Sadece düşey yönde değişir"]
        },
        {
          "q": "Araç aniden frene basınca sıvının hangi tarafı yükselir?",
          "steps": [
            {"t": "Frenleme", "a": "İvme öne yönlü değil, geriye yönlü (yavaşlama)", "d": "Araç frenle yavaşlayınca ivme arkaya doğrudur, ya da başka deyişle sıvı öne fırlar."},
            {"t": "Sıvı tepkisi", "a": "Sıvı ön tarafa toplanır", "d": "Yüksek seviye ivmenin zıt yönünde olacak: frenleme ivmesi geriyeyse ön taraf yükselir."}
          ],
          "ans": "Ön taraf (ivmenin zıt yönü)",
          "o": ["Arka taraf", "Her iki taraf eşit yükselir", "Alt yüzey yükselir", "Sıvı seviyesi değişmez"]
        }
      ],
      "zor": [
        {
          "q": "Genişliği 60 cm olan bir kap, a = 4 m/s² yatay ivmeyle hareket ediyor. İki kenar arasındaki yükseklik farkı kaç cm'dir? (g = 10 m/s²)",
          "steps": [
            {"t": "Eğim açısı", "a": "tan θ = a/g = 4/10 = 0,4", "d": "Sıvı yüzeyinin eğim tanjantı."},
            {"t": "Yükseklik farkı", "a": "Δh = L·tan θ = 0,60·0,4 = 0,24 m", "d": "Kap genişliği L = 0,60 m üzerindeki yükseklik farkı."},
            {"t": "cm cinsinden", "a": "Δh = 24 cm", "d": "Arka taraf 24 cm daha yüksek olur."}
          ],
          "ans": "24 cm",
          "o": ["12 cm", "40 cm", "6 cm", "30 cm"]
        },
        {
          "q": "Yatay ivmeli araçtaki sıvı için hem yatay hem dikey basınç gradyanlarını yazarak, derinliği h ve yatay uzaklığı x olan bir noktadaki basıncı ifade edin. (Referans: sıvı yüzeyi serbest, o noktada P₀ = atmosfer basıncı)",
          "steps": [
            {"t": "Dikey gradyan", "a": "dP/dz = −ρ·g", "d": "Derinlik arttıkça basınç artar: +ρ·g·h."},
            {"t": "Yatay gradyan", "a": "dP/dx = −ρ·a", "d": "İvme yönünde (öne) basınç azalır: serbest yüzeyden x kadar gerideyse +ρ·a·x."},
            {"t": "Toplam basınç", "a": "P = P₀ + ρ·g·h + ρ·a·x", "d": "h derinlik (aşağı pozitif), x arka mesafe (ivme zıttı yön pozitif)."}
          ],
          "ans": "P = P₀ + ρ·g·h + ρ·a·x",
          "o": ["P = P₀ + ρ·(g − a)·h", "P = P₀ + ρ·g·h − ρ·a·x", "P = P₀ + ρ·a·h + ρ·g·x", "P = P₀ · ρ · g · a · h"]
        },
        {
          "q": "Dikdörtgen bir kapta su, a = 5 m/s² yatay ivmeyle taşınırken eğim açısı kaç derecedir? Ön ve arka duvarlar arasındaki yatay mesafe 1 m, su başlangıçta 50 cm derinliğindeyse arka duvardaki su yüksekliği kaç cm'ye çıkar? (g = 10 m/s²)",
          "steps": [
            {"t": "Eğim açısı", "a": "tan θ = 5/10 = 0,5 → θ ≈ 26,6°", "d": "Yüzey bu açıyla eğilir."},
            {"t": "Yükseklik farkı", "a": "Δh = 1·0,5 = 0,5 m = 50 cm", "d": "1 m'lik mesafede Δh = L·tan θ = 50 cm."},
            {"t": "Arka duvar yüksekliği", "a": "h_arka = 50 + 25 = 75 cm", "d": "Yüzey ortası 50 cm'de kalır (hacim korunur), arka +25 cm, ön −25 cm."}
          ],
          "ans": "θ ≈ 26,6° ve arka duvar yüksekliği 75 cm",
          "o": ["θ = 45° ve 100 cm", "θ ≈ 26,6° ve 60 cm", "θ = 30° ve 70 cm", "θ ≈ 26,6° ve 50 cm (değişmez)"]
        }
      ]
    }
  },
  "balonIrtifa": {
    "lise": {
      "kolay": [
        {
          "q": "Atmosfer basıncı yükseklikle nasıl değişir?",
          "steps": [
            {"t": "Basınç-yükseklik ilişkisi", "a": "Yükseklik arttıkça basınç azalır", "d": "Üstteki hava kütlesi azaldığından atmosfer basıncı üstel olarak düşer."},
            {"t": "Matematiksel ifade", "a": "P ≈ P₀·e^(−h/H)", "d": "H ≈ 8,5 km ölçek yüksekliği; 5,5 km'de basınç yarıya iner."}
          ],
          "ans": "Üstel olarak azalır",
          "o": ["Doğrusal olarak artar", "Sabit kalır", "Üstel olarak artar", "Önce artar sonra azalır"]
        },
        {
          "q": "Sıcak hava balonu için kaldırma kuvveti koşulu nedir?",
          "steps": [
            {"t": "Arşimet prensibi", "a": "F_kaldırma = ρ_dış·V·g", "d": "Balon, dışarıdaki havanın ağırlığı kadar kaldırma kuvveti alır."},
            {"t": "Uçuş koşulu", "a": "ρ_dış > ρ_iç", "d": "İçerideki havanın yoğunluğu dışarıdakinden düşük olmalı ki balon yukarı kalksın."}
          ],
          "ans": "Dışarıdaki hava yoğunluğu içeridekinden büyük olmalı (ρ_dış > ρ_iç)",
          "o": ["İçerideki hava yoğunluğu dışarıdakinden büyük olmalı", "İç ve dış hava yoğunlukları eşit olmalı", "Balonun basıncı atmosfer basıncından büyük olmalı", "Dış sıcaklık iç sıcaklıktan yüksek olmalı"]
        },
        {
          "q": "Sıcak hava balonunun kaldırma kuvveti formülü nedir?",
          "steps": [
            {"t": "Net kaldırma", "a": "F_net = (ρ_dış − ρ_iç)·V·g", "d": "Dışarıdaki ve içerideki hava yoğunlukları farkının hacim ve g ile çarpımı."},
            {"t": "Yorum", "a": "Yoğunluk farkı ne kadar büyükse kaldırma o kadar fazla", "d": "Balonun hacmini ve sıcaklık farkını artırmak kaldırmayı artırır."}
          ],
          "ans": "F = (ρ_dış − ρ_iç)·V·g",
          "o": ["F = ρ_iç·V·g", "F = (ρ_dış + ρ_iç)·V·g", "F = ρ_dış·V·g²", "F = (ρ_dış − ρ_iç)·V/g"]
        },
        {
          "q": "Yükseklere çıkıldıkça atmosfer yoğunluğu değişir mi?",
          "steps": [
            {"t": "Yoğunluk-basınç ilişkisi", "a": "ρ ≈ P·M/(R·T)", "d": "İdeal gaz denklemiyle yoğunluk basınçla doğru orantılıdır."},
            {"t": "Yükseklikle değişim", "a": "Yükseldikçe P azalır → ρ azalır", "d": "Hava inceldikçe balon daha az kaldırma kuvveti alır."}
          ],
          "ans": "Azalır (hava incelir)",
          "o": ["Artar", "Sabit kalır", "Önce azalır sonra artar", "Yalnızca sıcaklıkla değişir, yükseklikle değişmez"]
        },
        {
          "q": "Bir sıcak hava balonu denge yüksekliğine ulaştığında ne olur?",
          "steps": [
            {"t": "Denge koşulu", "a": "F_kaldırma = W_balon", "d": "Kaldırma kuvveti balonun toplam ağırlığına eşit olunca ivme sıfır olur."},
            {"t": "Yükseklikle yoğunluk", "a": "Yükseldikçe ρ_dış azalır", "d": "Kaldırma kuvveti düştükçe balon denge noktasına ulaşır."}
          ],
          "ans": "Kaldırma kuvveti toplam ağırlığa eşit olur ve balon sabit yükseklikte kalır",
          "o": ["Balon durmaksızın yükselmeye devam eder", "Balon patlar", "Balonun iç basıncı sıfıra düşer", "Balon dışarıdaki havanın yoğunluğunu artırır"]
        }
      ],
      "zor": [
        {
          "q": "V = 2000 m³ hacimdeki bir balonun iç havası ρ_iç = 0,9 kg/m³ ve dış hava ρ_dış = 1,2 kg/m³'tür. Net kaldırma kuvveti kaç N'dur? (g = 10 m/s²)",
          "steps": [
            {"t": "Yoğunluk farkı", "a": "Δρ = 1,2 − 0,9 = 0,3 kg/m³", "d": "Dış ve iç hava yoğunlukları arasındaki fark."},
            {"t": "Net kaldırma", "a": "F = Δρ·V·g = 0,3·2000·10 = 6000 N", "d": "Net yukarı kuvvet."},
            {"t": "Yorum", "a": "6000 N ≈ 600 kg yük taşıyabilir", "d": "Balon zarf kütlesi ve ekipman dahil 600 kg'a kadar kaldırabilir."}
          ],
          "ans": "6000 N",
          "o": ["2400 N", "3000 N", "24 000 N", "600 N"]
        },
        {
          "q": "Atmosfer basıncı her 5,5 km'de yarıya düştüğüne göre, deniz seviyesinde P₀ = 101 325 Pa iken 11 km yükseklikte basınç yaklaşık kaç Pa'dır?",
          "steps": [
            {"t": "Katlanma sayısı", "a": "11 km / 5,5 km = 2 kat", "d": "Basınç iki kez yarıya iner."},
            {"t": "İkinci yarılanma", "a": "101 325 / 2 / 2 ≈ 25 331 Pa", "d": "Her 5,5 km'de bir çarpı 1/2."},
            {"t": "Yaklaşık değer", "a": "≈ 25 000 Pa ≈ ¼ P₀", "d": "11 km'de basınç deniz seviyesinin yaklaşık dörtte birine iner."}
          ],
          "ans": "≈ 25 300 Pa",
          "o": ["≈ 50 000 Pa", "≈ 12 500 Pa", "≈ 75 000 Pa", "≈ 5000 Pa"]
        },
        {
          "q": "Deniz seviyesinde ρ_hava = 1,25 kg/m³ olan hava, sıcak hava balonunda ısıtılarak ρ_iç = 0,85 kg/m³'e düşürülüyor. Balonun hacmi V = 3000 m³ ve zarf + sepet kütlesi 500 kg ise balon kalkabilir mi? Net kuvveti bulun. (g = 10 m/s²)",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_K = (ρ_dış − ρ_iç)·V·g = (1,25 − 0,85)·3000·10 = 12 000 N", "d": "Net Arşimet kaldırma kuvveti."},
            {"t": "Ağırlık", "a": "W_zarf = 500·10 = 5000 N", "d": "Zarf ve sepetin ağırlığı."},
            {"t": "İç hava ağırlığı", "a": "W_iç = 0,85·3000·10 = 25 500 N", "d": "Balon içindeki havanın ağırlığı da taşınan yük."},
            {"t": "Net kuvvet", "a": "F_net = F_K − W_zarf = 12 000 − 5000 = 7000 N yukarı", "d": "İç hava ağırlığı zaten kaldırma formülüne dahil (F_K = (Δρ)Vg = dışarıdaki havanın ağırlığı − içerideki havanın ağırlığı). Balon kalkar."}
          ],
          "ans": "Evet, net 7000 N yukarı kuvvetle kalkar",
          "o": ["Hayır, kaldırma kuvveti yetersiz", "Evet, ama sadece 2000 N net kuvvetle", "Evet, 12 000 N net kuvvetle", "Hayır, iç hava ağırlığı kaldırmayı sıfırlar"]
        }
      ]
    }
  },
  "sicakBalon": {
    "lise": {
      "kolay": [
        {
          "q": "İdeal gazda sabit basınçta hacim ile sıcaklık arasındaki ilişki nedir?",
          "steps": [
            {"t": "Charles Yasası", "a": "V/T = sabit (P sabit)", "d": "Mutlak sıcaklık (Kelvin) ile hacim doğru orantılıdır."},
            {"t": "Formül", "a": "V₁/T₁ = V₂/T₂", "d": "Sıcaklık iki katına çıkarsa hacim de iki katına çıkar."}
          ],
          "ans": "V ∝ T (Kelvin); hacim sıcaklıkla doğru orantılı",
          "o": ["V ∝ 1/T; hacim sıcaklıkla ters orantılı", "V ∝ T²; hacim sıcaklığın karesiyle değişir", "V sabit kalır, sadece basınç değişir", "V ∝ T yalnızca Celsius için geçerli"]
        },
        {
          "q": "Sıcak hava balonunda hava ısıtılınca yoğunluk neden azalır?",
          "steps": [
            {"t": "Sabit basınç", "a": "Balonun ağzı açık → P = P_atm", "d": "Dışarıyla bağlantılı olduğundan basınç sabit kalır."},
            {"t": "Hacim ve kütle", "a": "Isınan hava genişler, bir kısmı dışarı çıkar", "d": "Kalan hava kütlesi azalır, hacim sabit kalır → yoğunluk düşer."}
          ],
          "ans": "Sabit hacimde kalan hava kütlesi azaldığından (ısınan hava dışarı çıkar)",
          "o": ["Sıcaklık arttıkça hava molekülleri küçülür", "Isı enerjisi kütleye dönüşerek hava hafifler", "Balon duvarları genişleyerek hacim artar", "Sıcak havada basınç düşer ve yoğunluk artar"]
        },
        {
          "q": "0°C'ta V = 1000 m³ hacimli balonun hava sıcaklığı 91°C'ye çıkarılırsa yeni hacim kaç m³ olur? (Basınç sabit)",
          "steps": [
            {"t": "Kelvin dönüşümü", "a": "T₁ = 273 K, T₂ = 273 + 91 = 364 K", "d": "Celsius → Kelvin: +273."},
            {"t": "Charles Yasası", "a": "V₂ = V₁·T₂/T₁ = 1000·364/273 ≈ 1333 m³", "d": "Sıcaklık 273'ten 364'e artınca hacim de orantılı artar."}
          ],
          "ans": "≈ 1333 m³",
          "o": ["2000 m³", "1091 m³", "1500 m³", "910 m³"]
        },
        {
          "q": "Sıcak hava balonunun iç basıncı ile dış atmosfer basıncı arasındaki fazla basıncı veren formül nedir?",
          "steps": [
            {"t": "Yüzey gerilimi etkisi", "a": "ΔP = 4γ/r", "d": "Küresel balon zarfındaki yüzey gerilimi γ ve yarıçap r."},
            {"t": "Fiziksel anlam", "a": "İç basınç dışarıdan biraz fazladır", "d": "Bu fark küçük olduğundan pratikte P_iç ≈ P_dış kabul edilir."}
          ],
          "ans": "ΔP = 4γ/r",
          "o": ["ΔP = 2γ/r", "ΔP = γ/r", "ΔP = 8γ/r²", "ΔP = 4γ·r"]
        },
        {
          "q": "Sıcak hava balonunda hava ısıtılınca hava yoğunluğu azalır. Bu durumda balon yükselmek için hangi koşul sağlanmalıdır?",
          "steps": [
            {"t": "Kaldırma = Ağırlık", "a": "ρ_dış·V·g ≥ (m_zarf + ρ_iç·V)·g", "d": "Kaldırma kuvveti toplam ağırlıktan büyük ya da eşit olmalı."},
            {"t": "Sadeleştirme", "a": "(ρ_dış − ρ_iç)·V ≥ m_zarf", "d": "Yoğunluk farkı × hacim ≥ zarf kütlesi."}
          ],
          "ans": "(ρ_dış − ρ_iç)·V ≥ m_zarf",
          "o": ["ρ_iç·V ≥ m_zarf", "ρ_dış·V = ρ_iç·V", "m_zarf ≥ (ρ_dış − ρ_iç)·V", "ρ_dış = ρ_iç + m_zarf"]
        }
      ],
      "zor": [
        {
          "q": "Balon iç havası T₁ = 300 K iken ρ₁ = 1,2 kg/m³'tür. Kaldırmak için ρ_iç = 0,9 kg/m³ gerekiyor. Hava hangi sıcaklığa (K) ısıtılmalıdır? (Basınç sabit, ideal gaz)",
          "steps": [
            {"t": "Sabit P'de ρ·T = sabit", "a": "ρ₁·T₁ = ρ₂·T₂", "d": "İdeal gazda P sabitken yoğunluk sıcaklıkla ters orantılı: P = ρ·R·T/M → ρT = sabit."},
            {"t": "T₂ hesabı", "a": "T₂ = ρ₁·T₁/ρ₂ = 1,2·300/0,9 = 400 K", "d": "1,2/0,9 = 4/3 oranı uygulandı."},
            {"t": "Celsius", "a": "T₂ = 400 K = 127°C", "d": "Hava yaklaşık 127°C'ye ısıtılmalıdır."}
          ],
          "ans": "400 K (127°C)",
          "o": ["360 K (87°C)", "450 K (177°C)", "300 K (27°C)", "500 K (227°C)"]
        },
        {
          "q": "V = 2500 m³, zarf kütlesi m_zarf = 400 kg olan sıcak hava balonu ρ_dış = 1,25 kg/m³ olan havada uçacak. Gereken minimum iç hava yoğunluğu kaç kg/m³'tür? (g = 10 m/s²)",
          "steps": [
            {"t": "Denge koşulu", "a": "(ρ_dış − ρ_iç)·V·g = m_zarf·g", "d": "Minimum kaldırma = zarf ağırlığı (iç hava ağırlığı kaldırma formülünde zaten hesaba katıldı)."},
            {"t": "ρ_iç'i çek", "a": "ρ_iç = ρ_dış − m_zarf/V = 1,25 − 400/2500", "d": "m_zarf/V = 0,16 kg/m³."},
            {"t": "Sonuç", "a": "ρ_iç = 1,25 − 0,16 = 1,09 kg/m³", "d": "İç hava en fazla 1,09 kg/m³ olmalı ki balon kalksın."}
          ],
          "ans": "≤ 1,09 kg/m³",
          "o": ["≤ 0,85 kg/m³", "≤ 1,25 kg/m³", "≤ 0,16 kg/m³", "≤ 1,41 kg/m³"]
        },
        {
          "q": "Sıcak hava balonunda T_dış = 293 K, ρ_dış = 1,2 kg/m³. Balon iç havası T_iç = 440 K'a ısıtılıyor. İç hava yoğunluğu (ρ_iç) kaç kg/m³'tür ve bu balon dışarı yoğunluğuna kıyasla ne kadarlık kaldırma sağlar? (V = 1000 m³, g = 10 m/s²)",
          "steps": [
            {"t": "ρ_iç hesabı", "a": "ρ_iç = ρ_dış·T_dış/T_iç = 1,2·293/440 ≈ 0,80 kg/m³", "d": "Sabit basınçta ρ·T = sabit ilişkisi."},
            {"t": "Yoğunluk farkı", "a": "Δρ = 1,2 − 0,80 = 0,40 kg/m³", "d": "İç ve dış yoğunluk farkı."},
            {"t": "Kaldırma kuvveti", "a": "F = Δρ·V·g = 0,40·1000·10 = 4000 N", "d": "Net Arşimet kuvveti, yaklaşık 400 kg yük taşır."}
          ],
          "ans": "ρ_iç ≈ 0,80 kg/m³; kaldırma = 4000 N",
          "o": ["ρ_iç ≈ 0,65 kg/m³; kaldırma = 5500 N", "ρ_iç ≈ 0,80 kg/m³; kaldırma = 8000 N", "ρ_iç ≈ 1,0 kg/m³; kaldırma = 2000 N", "ρ_iç ≈ 0,80 kg/m³; kaldırma = 400 N"]
        }
      ]
    }
  },
  "bernoulli": {
    "lise": {
      "kolay": [
        {
          "q": "Süreklilik denklemi (A₁·v₁ = A₂·v₂) ne anlama gelir?",
          "steps": [
            {"t": "Kütle korunumu", "a": "Boru içindeki akışkan kütlesi korunur", "d": "Birim zamanda boru kesitinden geçen hacimsel debi Q = A·v sabit."},
            {"t": "Kesit-hız ilişkisi", "a": "A küçüldükçe v büyür", "d": "Boru daralırsa akışkan hızlanır."}
          ],
          "ans": "Akışkan hızı boru kesit alanıyla ters orantılıdır",
          "o": ["Akışkan hızı boru kesit alanıyla doğru orantılıdır", "Basınç tüm kesitlerde eşittir", "Akışkan kütlesi azalır", "Hız her noktada sabit kalır"]
        },
        {
          "q": "Bernoulli denklemine göre boru daralınca hız artar. Bu durumda basınç ne olur?",
          "steps": [
            {"t": "Bernoulli", "a": "P + ½·ρ·v² = sabit", "d": "Yükseklik sabitken basınç + kinetik basınç = sabit."},
            {"t": "Hız artar", "a": "Basınç azalır", "d": "½·ρ·v² artarsa P azalmalı ki toplam sabit kalsın."}
          ],
          "ans": "Azalır",
          "o": ["Artar", "Değişmez", "Sıfır olur", "Hızla orantılı artar"]
        },
        {
          "q": "Uçak kanadının üst yüzeyi alt yüzeyine göre nasıl şekillendirilmiştir ve bu şekil nasıl kaldırma kuvveti oluşturur?",
          "steps": [
            {"t": "Kanat şekli", "a": "Üst yüzey daha kavisli (uzun yol)", "d": "Hava üst yüzeyde daha hızlı akar."},
            {"t": "Bernoulli uygulaması", "a": "Üstte hız büyük → basınç küçük", "d": "Alt taraf yavaş hava, yüksek basınç → net yukarı kuvvet = kaldırma."}
          ],
          "ans": "Üst yüzey kavisli; üstte hız artar, basınç düşer; altta basınç fazlası kaldırma oluşturur",
          "o": ["Alt yüzey kavisli; altta hız artar, basınç artar", "Her iki yüzey düz; kaldırma motor itimiyle sağlanır", "Üstte basınç fazla, altta az; aşağı doğru kuvvet oluşur", "Kanat şeklinin önemi yok, sadece motor iter"]
        },
        {
          "q": "Tam Bernoulli denklemi (yükseklik dahil) nasıl yazılır?",
          "steps": [
            {"t": "Enerji korunumu", "a": "Basınç + kinetik + potansiyel = sabit", "d": "Akışkanın birim hacmine ait enerji korunur."},
            {"t": "Formül", "a": "P + ½·ρ·v² + ρ·g·h = sabit", "d": "Her terim Pa (N/m²) biriminde."}
          ],
          "ans": "P + ½·ρ·v² + ρ·g·h = sabit",
          "o": ["P + ρ·v² + ρ·g·h = sabit", "P · ½·ρ·v² · ρ·g·h = sabit", "P = ½·ρ·v² − ρ·g·h", "P + ρ·v + ρ·g·h² = sabit"]
        },
        {
          "q": "Venturi tüpünde dar kesitte hız artar. Bu ilke hangi cihazlarda kullanılır?",
          "steps": [
            {"t": "Venturi etkisi", "a": "Dar kesit → hız artar → basınç düşer", "d": "Bernoulli ilkesinin doğrudan uygulaması."},
            {"t": "Kullanım alanları", "a": "Karbüratör, hava hızı ölçer (pitot), ilaçlama pompası", "d": "Düşük basınç bölgesi emme veya ölçme amacıyla kullanılır."}
          ],
          "ans": "Karbüratör, hava hızı ölçer (pitot tüpü), ilaçlama pompası",
          "o": ["Yalnızca uçak motoru", "Yalnızca su pompaları", "Hidrolik frenler", "Isı eşanjörleri"]
        }
      ],
      "zor": [
        {
          "q": "Yatay boru kesiti A₁ = 8 cm²'den A₂ = 2 cm²'ye daralıyor. v₁ = 3 m/s ise v₂ kaçtır ve P₁ − P₂ kaç Pa'dır? (ρ_su = 1000 kg/m³)",
          "steps": [
            {"t": "Süreklilik", "a": "v₂ = v₁·A₁/A₂ = 3·8/2 = 12 m/s", "d": "Kesit 4'te 1'e iner, hız 4 katına çıkar."},
            {"t": "Bernoulli (yatay)", "a": "P₁ + ½·ρ·v₁² = P₂ + ½·ρ·v₂²", "d": "Yükseklik sabit."},
            {"t": "Basınç farkı", "a": "P₁ − P₂ = ½·ρ·(v₂² − v₁²) = ½·1000·(144 − 9) = 67 500 Pa", "d": "½·1000·135 = 67 500 Pa."}
          ],
          "ans": "v₂ = 12 m/s; P₁ − P₂ = 67 500 Pa",
          "o": ["v₂ = 6 m/s; P₁ − P₂ = 13 500 Pa", "v₂ = 12 m/s; P₁ − P₂ = 54 000 Pa", "v₂ = 4 m/s; P₁ − P₂ = 67 500 Pa", "v₂ = 12 m/s; P₁ − P₂ = 135 000 Pa"]
        },
        {
          "q": "Bir borudan su akıyor. 1. nokta 2 m yükseklikte, P₁ = 150 000 Pa, v₁ = 2 m/s. 2. nokta 0 m yükseklikte, v₂ = 4 m/s. P₂ kaç Pa'dır? (ρ = 1000 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Bernoulli denklemi", "a": "P₁ + ½·ρ·v₁² + ρ·g·h₁ = P₂ + ½·ρ·v₂² + ρ·g·h₂", "d": "Tam Bernoulli uygulaması."},
            {"t": "Sayısal değerleri koy", "a": "150 000 + ½·1000·4 + 1000·10·2 = P₂ + ½·1000·16 + 0", "d": "150 000 + 2000 + 20 000 = P₂ + 8000."},
            {"t": "P₂", "a": "P₂ = 172 000 − 8000 = 164 000 Pa", "d": "Yükseklikten kazanılan enerji ve hız artışı dengelenir."}
          ],
          "ans": "164 000 Pa",
          "o": ["150 000 Pa", "172 000 Pa", "130 000 Pa", "186 000 Pa"]
        },
        {
          "q": "Uçak kanadında üst yüzeydeki hız v_üst = 80 m/s, alt yüzeydeki hız v_alt = 60 m/s. Kanat alanı A = 30 m² olan uçakta kaldırma kuvveti kaç N'dur? (ρ_hava = 1,2 kg/m³)",
          "steps": [
            {"t": "Basınç farkı", "a": "ΔP = ½·ρ·(v_üst² − v_alt²) = ½·1,2·(6400 − 3600)", "d": "ΔP = 0,6·2800 = 1680 Pa."},
            {"t": "Kaldırma kuvveti", "a": "F = ΔP·A = 1680·30 = 50 400 N", "d": "Alttaki yüksek basınç yukarı iter."},
            {"t": "Yorum", "a": "≈ 50 400 N ≈ 5 ton kaldırma kuvveti", "d": "Gerçek uçaklarda kanat şekli ve hücum açısı da katkıda bulunur."}
          ],
          "ans": "50 400 N",
          "o": ["25 200 N", "100 800 N", "16 800 N", "168 000 N"]
        }
      ]
    }
  },
  "toricelliBosalma": {
    "lise": {
      "kolay": [
        {
          "q": "Torricelli teoremi: Kap tabanındaki delikten sıvı çıkış hızı formülü nedir?",
          "steps": [
            {"t": "Bernoulli uygulaması", "a": "P_atm + 0 + ρ·g·h = P_atm + ½·ρ·v²", "d": "Yüzey yavaş hareket eder (geniş kap), delikte P = P_atm."},
            {"t": "Sadeleştirme", "a": "v = √(2·g·h) (2·g·h'nin karekökü)", "d": "Bu ifade, h yükseklikten serbest düşen cismin hızıyla aynıdır."}
          ],
          "ans": "v = 2·g·h'nin karekökü",
          "o": ["v = √(g·h)", "v = √(2·g·h²)", "v = 2·g·h", "v = g·h/2"]
        },
        {
          "q": "Torricelli teoremindeki v = 2·g·h'nin karekökü ifadesinde h neyi temsil eder?",
          "steps": [
            {"t": "Geometri", "a": "h = sıvı yüzeyinden deliğe kadar olan yükseklik", "d": "Kap tabanında delik varsa h = sıvı derinliğidir."},
            {"t": "Dikkat", "a": "Delik tabanda değil yan yüzeydeyse h = yüzeyden deliğe uzaklık", "d": "h her zaman sıvı yüzeyi ile delik arasındaki düşey mesafedir."}
          ],
          "ans": "Sıvı yüzeyinden deliğe kadar olan düşey yükseklik",
          "o": ["Delikten kap tabanına kadar olan yükseklik", "Kabın toplam yüksekliği", "Sıvının ortalama derinliği", "Delikten yere kadar olan mesafe"]
        },
        {
          "q": "h = 5 m yüksekliğindeki su yüzeyinin altında bulunan delikten su kaç m/s hızla çıkar? (g = 10 m/s²)",
          "steps": [
            {"t": "Torricelli formülü", "a": "v = 2·g·h'nin karekökü = 2·10·5'in karekökü", "d": "= 100'ün karekökü = 10 m/s."},
            {"t": "Sonuç", "a": "v = 10 m/s", "d": "Aynı değer h = 5 m yükseklikten serbest düşen cismin çarpma hızına eşittir."}
          ],
          "ans": "10 m/s",
          "o": ["5 m/s", "√5 m/s ≈ 2,24 m/s", "50 m/s", "√50 ≈ 7,07 m/s"]
        },
        {
          "q": "Delikten çıkan suyun hacimsel debi formülü Q nedir? (A_delik: delik alanı, v: çıkış hızı)",
          "steps": [
            {"t": "Debi tanımı", "a": "Q = A·v", "d": "Birim zamanda delikten geçen hacim."},
            {"t": "Torricelli ile", "a": "Q = A_delik·√(2·g·h)", "d": "Delik alanı ile Torricelli hızının çarpımı."}
          ],
          "ans": "Q = A_delik · 2·g·h'nin karekökü",
          "o": ["Q = A_delik / √(2·g·h)", "Q = A_delik · g · h", "Q = √(A_delik · 2·g·h)", "Q = A_delik² · √(2·g·h)"]
        },
        {
          "q": "Bir kap yüksekliği H, delik yüzeyden h derinliğindeyse (kap tabanında değil yan yüzeyinde), suyun yere çarpma yatay menzili x nedir?",
          "steps": [
            {"t": "Düşey düşme", "a": "Delik yerden (H − h) yükseklikte", "d": "Düşme yüksekliği: y = H − h."},
            {"t": "Düşme süresi", "a": "t = (2·(H−h)/g)'nin karekökü", "d": "Serbest düşme formülü."},
            {"t": "Yatay menzil", "a": "x = v·t = √(2·g·h)·√(2·(H−h)/g) = 2·√(h·(H−h))", "d": "Torricelli hızı ile düşme süresi çarpılır."}
          ],
          "ans": "x = 2·(h·(H−h))'nin karekökü",
          "o": ["x = √(2·g·h·H)", "x = h·√(2·g)", "x = 2·√(g·H)", "x = √(h·H)"]
        }
      ],
      "zor": [
        {
          "q": "H = 2 m yüksekliğindeki kapta delik yüzeyden h = 0,5 m aşağıda (yani yerden H − h = 1,5 m yüksekte). Çıkış hızı ve yatay menzil kaçtır? (g = 10 m/s²)",
          "steps": [
            {"t": "Çıkış hızı", "a": "v = √(2·g·h) = √(2·10·0,5) = √10 ≈ 3,16 m/s", "d": "Torricelli teoremi."},
            {"t": "Düşme süresi", "a": "t = √(2·1,5/10) = √0,3 ≈ 0,548 s", "d": "Delik yerden 1,5 m yüksekte."},
            {"t": "Yatay menzil", "a": "x = v·t = 3,16·0,548 ≈ 1,73 m", "d": "Alternatif: x = 2·√(h·(H−h)) = 2·√(0,5·1,5) = 2·√0,75 ≈ 1,73 m."}
          ],
          "ans": "v ≈ 3,16 m/s; x ≈ 1,73 m",
          "o": ["v ≈ 3,16 m/s; x ≈ 1,0 m", "v ≈ 6,32 m/s; x ≈ 1,73 m", "v ≈ 3,16 m/s; x ≈ 2,45 m", "v ≈ 4,47 m/s; x ≈ 1,73 m"]
        },
        {
          "q": "Kare taban alanı A_kap = 0,25 m² olan kap, taban ortasındaki A_delik = 1 cm² = 10⁻⁴ m² delikten boşalıyor. Başlangıç su yüksekliği h₀ = 4 m iken çıkış hızı ve debisi nedir? (g = 10 m/s²)",
          "steps": [
            {"t": "Çıkış hızı", "a": "v = √(2·10·4) = √80 ≈ 8,94 m/s", "d": "Torricelli h₀ = 4 m için."},
            {"t": "Debi", "a": "Q = A_delik·v = 10⁻⁴·8,94 ≈ 8,94×10⁻⁴ m³/s", "d": "Yaklaşık 0,9 L/s."},
            {"t": "Kapın boşalma hızı", "a": "dh/dt = −Q/A_kap = −8,94×10⁻⁴ / 0,25 ≈ −3,58×10⁻³ m/s", "d": "Su seviyesi çok yavaş düşer çünkü A_kap >> A_delik."}
          ],
          "ans": "v ≈ 8,94 m/s; Q ≈ 8,94×10⁻⁴ m³/s",
          "o": ["v ≈ 4,47 m/s; Q ≈ 4,47×10⁻⁴ m³/s", "v ≈ 8,94 m/s; Q ≈ 8,94×10⁻² m³/s", "v ≈ 2,83 m/s; Q ≈ 2,83×10⁻⁴ m³/s", "v ≈ 8,94 m/s; Q ≈ 2,24×10⁻³ m³/s"]
        },
        {
          "q": "H = 5 m yüksekliğindeki kap yan yüzeyinde iki delik var: biri yüzeyden h₁ = 1 m, diğeri h₂ = 4 m aşağıda. Hangi delikten çıkan su daha uzağa gider?",
          "steps": [
            {"t": "Delik 1 menzili", "a": "x₁ = 2·√(h₁·(H−h₁)) = 2·√(1·4) = 2·2 = 4 m", "d": "h₁ = 1, H−h₁ = 4."},
            {"t": "Delik 2 menzili", "a": "x₂ = 2·√(h₂·(H−h₂)) = 2·√(4·1) = 2·2 = 4 m", "d": "h₂ = 4, H−h₂ = 1."},
            {"t": "Sonuç", "a": "Her iki delik de aynı menzile ulaşır", "d": "h₁ ve h₂ = H − h₁ olduğundan h₁·(H−h₁) = h₂·(H−h₂) → menziller eşit."}
          ],
          "ans": "İki delik de eşit menzile (4 m) ulaşır; simetriktir",
          "o": ["Üstteki delik (h₁ = 1 m) daha uzağa gider", "Alttaki delik (h₂ = 4 m) daha uzağa gider", "Üstteki delikten su hiç çıkmaz", "Alttaki delik x₂ = 8 m, üstteki x₁ = 2 m"]
        }
      ]
    }
  },
  "kilcalBitki": {
    "lise": {
      "kolay": [
        {
          "q": "Kılcal yükselme formülü nedir? (γ: yüzey gerilimi, θ: temas açısı, ρ: yoğunluk, r: yarıçap)",
          "steps": [
            {"t": "Denge koşulu", "a": "Yukarı çeken kuvvet = Ağırlık", "d": "2π·r·γ·cosθ = π·r²·ρ·g·h."},
            {"t": "h'yi çek", "a": "h = 2·γ·cosθ / (ρ·g·r)", "d": "Kılcal yükselme: yarıçap azaldıkça h artar."}
          ],
          "ans": "h = 2·γ·cosθ / (ρ·g·r)",
          "o": ["h = ρ·g·r / (2·γ·cosθ)", "h = 2·γ / (ρ·g·r·cosθ)", "h = γ·cosθ / (ρ·g·r)", "h = 4·γ·cosθ / (ρ·g·r)"]
        },
        {
          "q": "Bitkilerde ksilem ne taşır ve hangi mekanizmayla çalışır?",
          "steps": [
            {"t": "Ksilem işlevi", "a": "Su ve mineralleri kökten yaprağa taşır", "d": "Yönü: yukarı doğru (kök → gövde → yaprak)."},
            {"t": "Mekanizma", "a": "Kılcallık + terleme çekimi (kohezyon-gerilim teorisi)", "d": "Yapraklardaki buharlaşma (terleme) suyu yukarı çeker; su molekülleri birbirini çeker (kohezyon)."}
          ],
          "ans": "Su ve mineralleri taşır; kılcallık + terleme çekimi (kohezyon-gerilim teorisi) ile",
          "o": ["Şekeri yapraktan köke taşır; osmoz ile", "Oksijeni hücreden dışarı atar; difüzyon ile", "Su ve şekeri birlikte taşır; aktif taşıma ile", "Mineralleri yapraktan köke taşır; basınç akışı ile"]
        },
        {
          "q": "Bitkilerde floem ne taşır ve hangi mekanizmayla çalışır?",
          "steps": [
            {"t": "Floem işlevi", "a": "Fotosentez ürünlerini (şeker, amino asit) taşır", "d": "Kaynak (yaprak) → alıcı (kök, meyve, büyüyen dokular)."},
            {"t": "Mekanizma", "a": "Basınç akışı (pressure flow) teorisi", "d": "Kaynakta şeker yüklenir → ozmozu aktive → su girer → basınç oluşur → alıcıya doğru akar."}
          ],
          "ans": "Şeker (organik besin) taşır; kaynak-alıcı basınç akışı ile",
          "o": ["Su taşır; terleme çekimi ile", "Oksijen taşır; difüzyon ile", "Mineral taşır; kılcallık ile", "Su ve mineralleri birlikte taşır; aktif pompa ile"]
        },
        {
          "q": "Kılcal yarıçap r azalırsa yükselme yüksekliği h nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "h = 2·γ·cosθ / (ρ·g·r)", "d": "h, r ile ters orantılı."},
            {"t": "Yorum", "a": "İnce boruda daha yüksek yükselme", "d": "r küçüldükçe h artar: ksilem boruları (~20 μm) ile 100 m yüksekliğe ulaşılabilir."}
          ],
          "ans": "Artar (r ile ters orantılı)",
          "o": ["Azalır (r ile doğru orantılı)", "Değişmez", "Önce artar sonra azalır", "r² ile ters orantılı artar"]
        },
        {
          "q": "Su, kılcallıkla yalnızca birkaç metreye çıkabilir. Devasa ağaçlarda (>100 m) suyu yukarı çeken ek mekanizma nedir?",
          "steps": [
            {"t": "Sınır", "a": "Saf kılcallık ~1–2 m sağlayabilir", "d": "h = 2γcosθ/(ρgr) ile ~20 μm için yaklaşık 1,5 m."},
            {"t": "Terleme çekimi", "a": "Yapraklarda buharlaşma sürekli negatif basınç (gerilim) oluşturur", "d": "Kohezyon: su molekülleri birbirini çeker. Adhezyon: ksilem duvarına yapışır. Sürekli sütun 100 m'ye taşınır."}
          ],
          "ans": "Terleme çekimi: yaprak buharlaşmasının oluşturduğu negatif basınç (kohezyon-gerilim teorisi)",
          "o": ["Kök basıncı tek başına suyu 100 m'ye iter", "Aktif pompa enzimleri suyu iterek yukarı taşır", "Klorofil molekülleri suyu emer", "Floem basıncı suyu ksilem içinde iter"]
        }
      ],
      "zor": [
        {
          "q": "Su için γ = 0,0728 N/m, temas açısı θ ≈ 0° (cosθ = 1), ρ = 1000 kg/m³, g = 10 m/s². Yarıçapı r = 20 μm olan ksilem borusu için kılcal yükselme yüksekliği h kaç m'dir?",
          "steps": [
            {"t": "r'yi SI'ye çevir", "a": "r = 20×10⁻⁶ m", "d": "20 μm = 20 mikrometre."},
            {"t": "h formülü", "a": "h = 2·0,0728·1 / (1000·10·20×10⁻⁶)", "d": "Payda: 1000·10·20×10⁻⁶ = 0,2."},
            {"t": "Hesap", "a": "h = 0,1456 / 0,2 = 0,728 m ≈ 73 cm", "d": "Yalnızca kılcallıkla yaklaşık 73 cm yükselme sağlanır."}
          ],
          "ans": "≈ 0,73 m (73 cm)",
          "o": ["≈ 7,3 m", "≈ 0,073 m (7,3 cm)", "≈ 73 m", "≈ 14,6 m"]
        },
        {
          "q": "Kohezyon-gerilim teorisine göre yaprakta negatif basınç (su gerilimi) oluşuyor. 100 m yüksekteki suyu taşımak için gereken minimum basınç gerilimi kaç Pa'dır? (ρ = 1000 kg/m³, g = 10 m/s²)",
          "steps": [
            {"t": "Hidrostatik basınç", "a": "P = ρ·g·h = 1000·10·100 = 1 000 000 Pa", "d": "100 m su sütunu ağırlığı."},
            {"t": "Negatif basınç", "a": "Su sütununda −1 MPa gerilim oluşmalı", "d": "Su molekülleri arasındaki kohezyon kuvvetleri bu gerilimi taşıyabilir (teorik limit ~30 MPa)."},
            {"t": "Yorum", "a": "−1 MPa ≈ −10 atm, su bağları bunu kaldırabilir", "d": "Gerçekte bitkilerde −2 ile −8 MPa arası ölçülmüştür."}
          ],
          "ans": "En az −1 000 000 Pa (−1 MPa, yani −10 atm gerilim)",
          "o": ["−100 Pa", "−10 000 Pa (−0,1 atm)", "−1 000 000 000 Pa (−1 GPa)", "−500 Pa"]
        },
        {
          "q": "Floem basınç akışı modelinde kaynak hücre neden yüksek basınçlıdır? Adım adım açıklayın.",
          "steps": [
            {"t": "Şeker yükleme", "a": "Fotosentez ile üretilen şeker aktif taşımayla floem borularına girer", "d": "ATP harcayarak şeker konsantrasyonu artırılır."},
            {"t": "Osmotik su girişi", "a": "Artan şeker konsantrasyonu → su ozmozla içeri girer", "d": "Su potansiyeli düşer → ksilemden su çekilir."},
            {"t": "Turgor basıncı", "a": "Giren su hücreyi şişirerek yüksek turgor (basınç) oluşturur", "d": "Bu basınç şekeri alıcı bölgeye (kök, meyve) doğru iter."}
          ],
          "ans": "Aktif şeker yüklemesi → osmotik su girişi → yüksek turgor basıncı → akış",
          "o": ["Güneş ısısı flo'em borularını genişletir", "Ksilem pompası floemi iter", "Kök basıncı floemi doğrudan doldurur", "Terleme çekimi floemde negatif basınç oluşturur"]
        }
      ]
    }
  }
};
