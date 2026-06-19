var __BQ_PART3 = {
  "asiliDenge": {
    "lise": {
      "kolay": [
        {
          "q": "Görünür ağırlık (suda ağırlık) nedir?",
          "steps": [
            {"t": "Tanım", "a": "Sıvı içindeki dinamometre okuması", "d": "Bir cisim sıvıya daldırıldığında dinamometre, gerçek ağırlıktan daha düşük bir değer gösterir. Bu değere görünür ağırlık denir."},
            {"t": "Neden azalır?", "a": "Kaldırma kuvveti yukarı yönlü etki eder", "d": "Kaldırma kuvveti cismi yukarı ittiğinden dinamometrenin taşıması gereken kuvvet azalır."}
          ],
          "ans": "Cisim sıvı içindeyken dinamometrenin gösterdiği, gerçek ağırlıktan küçük olan değer",
          "o": ["Cismin havasız ortamdaki ağırlığı", "Cismin sıvı yüzeyinde yüzerken ağırlığı", "Kaldırma kuvvetinin büyüklüğü", "Cismin yer çekimi kuvveti"]
        },
        {
          "q": "Görünür ağırlık formülü hangisidir?",
          "steps": [
            {"t": "Kuvvet dengesi", "a": "W_görünür = W - F_k", "d": "Cisim sıvıda asılıyken; yukarı kaldırma kuvveti (F_k) ve ip gerilmesi (T) toplamı ağırlığa eşittir: T + F_k = mg → T = mg - F_k"},
            {"t": "Sonuç", "a": "F_görünür = mg - ρ_sıvı·V·g", "d": "Kaldırma kuvveti F_k = ρ_sıvı·V·g olduğundan görünür ağırlık bu kadar azalır."}
          ],
          "ans": "F_görünür = mg - ρ_sıvı·V·g",
          "o": ["F_görünür = mg + ρ_sıvı·V·g", "F_görünür = ρ_sıvı·V·g - mg", "F_görünür = mg × ρ_sıvı·V·g", "F_görünür = mg / (ρ_sıvı·V·g)"]
        },
        {
          "q": "ρ_cisim > ρ_sıvı olan bir cisim sıvıya bırakıldığında ne olur?",
          "steps": [
            {"t": "Karşılaştırma", "a": "Ağırlık > Kaldırma kuvveti", "d": "Cismin yoğunluğu sıvıdan büyükse, cismin ağırlığı kaldırma kuvvetini aşar ve cisim dibe çöker."},
            {"t": "Sonuç", "a": "Cisim batar", "d": "Yüzmek için ρ_cisim ≤ ρ_sıvı olması gerekir."}
          ],
          "ans": "Cisim dibe batar",
          "o": ["Cisim yüzer", "Cisim sıvının ortasında asılı kalır", "Cisim sıvıdan dışarı fırlar", "Cisim erir"]
        },
        {
          "q": "Aynı cisim önce havada, sonra suda tartılıyor. Hangi durumda dinamometre daha küçük değer gösterir?",
          "steps": [
            {"t": "Havada", "a": "W_hava ≈ mg", "d": "Havanın kaldırma kuvveti çok küçük olduğundan ihmal edilir; dinamometre mg okur."},
            {"t": "Suda", "a": "W_su = mg - F_k", "d": "Su kaldırma kuvveti daha büyük olduğundan dinamometre daha düşük okur."}
          ],
          "ans": "Suda tartıldığında dinamometre daha küçük değer gösterir",
          "o": ["Havada tartıldığında daha küçük değer gösterir", "Her iki durumda aynı değeri gösterir", "Suda tartıldığında daha büyük değer gösterir", "Sıvının türüne göre değişmez"]
        },
        {
          "q": "Arşimet ilkesine göre kaldırma kuvveti neye eşittir?",
          "steps": [
            {"t": "Arşimet İlkesi", "a": "F_k = ağırlığı yerinden edilen sıvının ağırlığına eşit", "d": "Sıvıya daldırılan cisim, hacmi kadar sıvıyı yerinden eder. Bu sıvının ağırlığı kaldırma kuvvetini verir."},
            {"t": "Formül", "a": "F_k = ρ_sıvı·g·V_daldırılan", "d": "V_daldırılan cismin sıvı içindeki hacmidir."}
          ],
          "ans": "Cismin yerinden ettiği sıvının ağırlığına (F_k = ρ_sıvı·g·V)",
          "o": ["Cismin kendi ağırlığına", "Cismin sıvı yüzeyindeki ağırlığına", "Sıvının toplam ağırlığına", "Sıvının yüzey alanına"]
        }
      ],
      "zor": [
        {
          "q": "Kütlesi 500 g, hacmi 64 cm³ olan demir blok suya tamamen daldırılıyor. Bloğun sudaki görünür ağırlığı kaç N'dur? (g = 10 m/s², ρ_su = 1000 kg/m³)",
          "steps": [
            {"t": "Gerçek ağırlık", "a": "W = mg = 0,5 × 10 = 5 N", "d": "m = 500 g = 0,5 kg"},
            {"t": "Kaldırma kuvveti", "a": "F_k = ρ_su·g·V = 1000 × 10 × 64×10⁻⁶ = 0,64 N", "d": "V = 64 cm³ = 64 × 10⁻⁶ m³"},
            {"t": "Görünür ağırlık", "a": "W_görünür = 5 - 0,64 = 4,36 N", "d": "W_görünür = W - F_k = 5 - 0,64 = 4,36 N"}
          ],
          "ans": "4,36 N",
          "o": ["5,64 N", "0,64 N", "3,36 N", "5 N"]
        },
        {
          "q": "Bir cismin havadaki ağırlığı 12 N, sudaki görünür ağırlığı 9 N'dur. Bu cismin kaldırma kuvveti ve sıvıda kaplanan hacmi kaçtır? (g = 10 m/s², ρ_su = 1000 kg/m³)",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_k = W_hava - W_su = 12 - 9 = 3 N", "d": "Kaldırma kuvveti gerçek ağırlık ile görünür ağırlık farkıdır."},
            {"t": "Hacim", "a": "V = F_k / (ρ_su·g) = 3 / (1000×10) = 3×10⁻⁴ m³", "d": "F_k = ρ·g·V → V = F_k/(ρ·g) = 3/10000 = 3×10⁻⁴ m³ = 300 cm³"}
          ],
          "ans": "F_k = 3 N, V = 300 cm³",
          "o": ["F_k = 3 N, V = 30 cm³", "F_k = 9 N, V = 900 cm³", "F_k = 12 N, V = 1200 cm³", "F_k = 3 N, V = 3000 cm³"]
        },
        {
          "q": "Bir cismin havadaki ağırlığı 8 N, sudaki görünür ağırlığı 6 N'dur. Bu cismin yoğunluğu kaç kg/m³'tür? (ρ_su = 1000 kg/m³)",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_k = 8 - 6 = 2 N", "d": "Görünür ağırlık farkından kaldırma kuvveti bulunur."},
            {"t": "Yoğunluk oranı", "a": "ρ_cisim/ρ_su = W_hava/F_k = 8/2 = 4", "d": "ρ_cisim/ρ_sıvı = W/(W - W_görünür) = 8/(8-6) = 4"},
            {"t": "Yoğunluk", "a": "ρ_cisim = 4 × 1000 = 4000 kg/m³", "d": "Cisim, suyun 4 katı yoğunluğa sahiptir."}
          ],
          "ans": "4000 kg/m³",
          "o": ["2000 kg/m³", "3000 kg/m³", "6000 kg/m³", "8000 kg/m³"]
        }
      ]
    }
  },
  "ciftSivi": {
    "lise": {
      "kolay": [
        {
          "q": "Karışmayan (immiscible) sıvı çifti hangisidir?",
          "steps": [
            {"t": "Tanım", "a": "Birbiriyle karışmayan sıvılar", "d": "Bazı sıvılar bir arada tutulsalar bile homojen karışım oluşturmazlar; ayrı katmanlar oluştururlar."},
            {"t": "Örnek", "a": "Su ve yağ", "d": "Su ve zeytinyağı çalkalandıktan sonra tekrar ayrışır. Su altta, yağ üstte kalır."}
          ],
          "ans": "Su ve yağ (birbiriyle homojen karışım oluşturmayan sıvılar)",
          "o": ["Su ve etanol", "Su ve sirke", "Su ve aseton", "Su ve şeker çözeltisi"]
        },
        {
          "q": "Yağ suda neden üstte kalır?",
          "steps": [
            {"t": "Yoğunluk karşılaştırması", "a": "ρ_yağ < ρ_su", "d": "Yağın yoğunluğu yaklaşık 800 kg/m³ iken suyun yoğunluğu 1000 kg/m³'tür. Yoğunluğu az olan sıvı üstte toplanır."},
            {"t": "Kural", "a": "Daha az yoğun sıvı üstte", "d": "Yoğunluk farkı nedeniyle karışmayan sıvılarda hafif olan hep üstte konumlanır."}
          ],
          "ans": "Yağın yoğunluğu suyun yoğunluğundan küçük olduğu için (ρ_yağ < ρ_su)",
          "o": ["Yağ molekülleri daha büyük olduğu için", "Yağın yüzey gerilimi daha büyük olduğu için", "Yağın viskozitesi daha büyük olduğu için", "Yağ ve su aynı yoğunluğa sahip olduğu için"]
        },
        {
          "q": "İki karışmayan sıvı arasında asılı kalan bir cisim için kuvvet dengesi nasıldır?",
          "steps": [
            {"t": "Kuvvetler", "a": "Ağırlık = F_k1 + F_k2", "d": "Cismin ağırlığı, alt sıvıdan (su) gelen kaldırma kuvveti ile üst sıvıdan (yağ) gelen kaldırma kuvvetinin toplamına eşittir."},
            {"t": "Formül", "a": "mg = ρ₁·g·V₁ + ρ₂·g·V₂", "d": "V₁ ve V₂ cismin alt ve üst sıvıdaki hacim paylarıdır; V₁ + V₂ = V_toplam"}
          ],
          "ans": "mg = ρ₁·g·V₁ + ρ₂·g·V₂ (ağırlık iki sıvının kaldırma kuvvetleri toplamına eşit)",
          "o": ["mg = ρ₁·g·V₁ - ρ₂·g·V₂", "mg = (ρ₁ + ρ₂)·g·V", "mg = ρ₁·g·V", "mg = ρ₂·g·V₂"]
        },
        {
          "q": "Bir cismin iki karışmayan sıvı arasında dengede kalabilmesi için yoğunluğu nasıl olmalıdır?",
          "steps": [
            {"t": "Koşul", "a": "ρ_alt < ρ_cisim < ρ_üst ... hayır", "d": "Üst sıvı hafif, alt sıvı ağırdır. Cismin iki sıvı arasında durabilmesi için yoğunluğu iki sıvı arasında olmalıdır."},
            {"t": "Doğru sıra", "a": "ρ_üst < ρ_cisim < ρ_alt", "d": "Örneğin ρ_yağ=800 < ρ_cisim < ρ_su=1000 olmalıdır ki cisim arayüzeyde dengede kalsın."}
          ],
          "ans": "Üst sıvının yoğunluğundan büyük, alt sıvının yoğunluğundan küçük olmalıdır (ρ_üst < ρ_cisim < ρ_alt)",
          "o": ["Her iki sıvının yoğunluğundan büyük olmalıdır", "Her iki sıvının yoğunluğundan küçük olmalıdır", "Alt sıvının yoğunluğuna eşit olmalıdır", "Sıvıların ortalama yoğunluğuna tam eşit olmalıdır"]
        },
        {
          "q": "Günlük hayattan çift sıvı kaldırma kuvvetine örnek veriniz.",
          "steps": [
            {"t": "Örnek", "a": "Deniz altı tabanına çökmüş sıvı yük", "d": "Yoğunluğu tuzlu su ile tatlı su arasında olan bir cisim, tatlı su katmanında batar ama tuzlu su katmanında yüzer; arayüzeyde dengede kalabilir."},
            {"t": "Başka örnek", "a": "Yağ-su arasında yüzen bir balmumu parçası", "d": "Balmumunun yoğunluğu yağ ile su arasında olduğundan yağ üstte su altta olacak şekilde arayüzeyde dengede durur."}
          ],
          "ans": "Yoğunluğu su ile yağ arasında olan balmumu parçası, yağ-su arayüzeyinde dengede durur",
          "o": ["Taş suda batar", "Tahta suda yüzer", "Buz suda yüzer", "Demir suda batar"]
        }
      ],
      "zor": [
        {
          "q": "Yoğunluğu 900 kg/m³ ve hacmi 100 cm³ olan bir cisim, yağ (ρ_yağ=800 kg/m³) ve su (ρ_su=1000 kg/m³) arasında denge halindedir. Cismin her sıvıdaki hacmi kaç cm³'tür?",
          "steps": [
            {"t": "Toplam hacim", "a": "V_yağ + V_su = 100 cm³", "d": "V₁ + V₂ = 100 cm³"},
            {"t": "Kuvvet dengesi", "a": "mg = ρ_yağ·g·V_yağ + ρ_su·g·V_su", "d": "ρ_cisim·V = ρ_yağ·V_yağ + ρ_su·V_su → 900×100 = 800·V_yağ + 1000·(100-V_yağ)"},
            {"t": "Çözüm", "a": "90000 = 800V_yağ + 100000 - 1000V_yağ → 200V_yağ = 10000 → V_yağ = 50 cm³", "d": "V_yağ = 50 cm³, V_su = 50 cm³"}
          ],
          "ans": "V_yağ = 50 cm³, V_su = 50 cm³",
          "o": ["V_yağ = 80 cm³, V_su = 20 cm³", "V_yağ = 20 cm³, V_su = 80 cm³", "V_yağ = 40 cm³, V_su = 60 cm³", "V_yağ = 60 cm³, V_su = 40 cm³"]
        },
        {
          "q": "Hacmi 200 cm³ ve yoğunluğu 850 kg/m³ olan bir cisim, yağ (ρ_yağ=800 kg/m³) ve su (ρ_su=1000 kg/m³) arasında dengede. Cismin yağ ve sudaki hacimleri kaçtır?",
          "steps": [
            {"t": "Denklem kurma", "a": "V_yağ + V_su = 200, ρ·V = ρ_yağ·V_yağ + ρ_su·V_su", "d": "850×200 = 800·V_yağ + 1000·(200-V_yağ)"},
            {"t": "Çözüm", "a": "170000 = 800V_yağ + 200000 - 1000V_yağ → 200V_yağ = 30000 → V_yağ = 150 cm³", "d": "V_yağ = 150 cm³, V_su = 50 cm³"}
          ],
          "ans": "V_yağ = 150 cm³, V_su = 50 cm³",
          "o": ["V_yağ = 100 cm³, V_su = 100 cm³", "V_yağ = 50 cm³, V_su = 150 cm³", "V_yağ = 160 cm³, V_su = 40 cm³", "V_yağ = 120 cm³, V_su = 80 cm³"]
        },
        {
          "q": "Bir cismin hacminin %60'ı suda (%40'ı yağda) bulunarak denge halindedir. Su yoğunluğu 1000 kg/m³, yağ yoğunluğu 800 kg/m³ ise cismin yoğunluğu kaç kg/m³'tür?",
          "steps": [
            {"t": "Kuvvet dengesi", "a": "ρ_cisim·V = ρ_su·(0,6V) + ρ_yağ·(0,4V)", "d": "Ağırlık = kaldırma kuvvetleri toplamı"},
            {"t": "V'yi böl", "a": "ρ_cisim = 1000×0,6 + 800×0,4", "d": "ρ_cisim = 600 + 320 = 920 kg/m³"}
          ],
          "ans": "920 kg/m³",
          "o": ["900 kg/m³", "860 kg/m³", "940 kg/m³", "880 kg/m³"]
        }
      ]
    }
  },
  "kaldirmaAgirlasma": {
    "lise": {
      "kolay": [
        {
          "q": "Bir cismi sıvı dolu kaba daldırdığınızda kabın altındaki terazi neden daha fazla gösterir?",
          "steps": [
            {"t": "Newton 3. Yasa", "a": "Kaldırma kuvvetinin tepkisi kaba etki eder", "d": "Sıvı cisme yukarı yönde kaldırma kuvveti uygular. Eylemsizliğin 3. yasasına göre cisim de sıvıya (ve dolayısıyla kaba) eşit ve zıt yönde aşağı kuvvet uygular."},
            {"t": "Sonuç", "a": "Terazi fazladan F_k kadar artar", "d": "Kap + sıvı + daldırılan kısım ağırlığı artar."}
          ],
          "ans": "Cisim sıvıya aşağı yönde F_kaldırma kadar tepki kuvveti uyguladığından terazi artar",
          "o": ["Sıvı sıkışınca yoğunluğu artar", "Cismin ağırlığı suya geçer", "Terazi değişmez", "Terazi azalır çünkü cisim hafifler"]
        },
        {
          "q": "Newton'un 3. yasası kaldırma kuvvetine nasıl uygulanır?",
          "steps": [
            {"t": "3. Yasa", "a": "Etki = Tepki, büyüklük eşit, yön zıt", "d": "Sıvı cisme yukarı F_k uygular; cisim de sıvıya aşağı F_k uygular. Bu kuvvetler farklı cisimlere etki eder."},
            {"t": "Sonuç", "a": "Sıvı kaba aşağı ekstra kuvvet iletir", "d": "Bu nedenle dışarıdan kap+sıvı sistemine bakıldığında ekstra ağırlık varmış gibi görünür."}
          ],
          "ans": "Cisim sıvıya kaldırma kuvvetine eşit büyüklükte zıt yönde (aşağı) kuvvet uygular",
          "o": ["Cisim sıvıya yukarı kuvvet uygular", "Kaldırma kuvveti çift yönlüdür", "3. yasa kaldırma kuvvetine uygulanmaz", "Sıvı cisme yatay kuvvet uygular"]
        },
        {
          "q": "Bir cisim ayrı bir dinamometre ile sıvıya asılı tutulduğunda, kabın altındaki terazide ne değişir?",
          "steps": [
            {"t": "Durum", "a": "Cisim dışarıdan asılıyor", "d": "Cisim harici dinamometreyle tutulduğunda, sıvı yine cisme kaldırma kuvveti uygular. Bu kaldırma kuvvetinin tepkisi yine kaba aktarılır."},
            {"t": "Terazi", "a": "Kap terazisi F_k kadar artar", "d": "Kabın terazisi kaldırma kuvveti kadar artar; ne daha fazla ne daha az."}
          ],
          "ans": "Kabın terazisi kaldırma kuvveti (F_k) kadar artar",
          "o": ["Kabın terazisi cismin tam ağırlığı kadar artar", "Kabın terazisi değişmez", "Kabın terazisi azalır", "Kabın terazisi dinamometrenin gösterdiği kadar artar"]
        },
        {
          "q": "Kaldırma kuvvetinin tepkisi hangi cisme etki eder?",
          "steps": [
            {"t": "Kuvvet çifti", "a": "Sıvı → Cisim: F_k yukarı; Cisim → Sıvı: F_k aşağı", "d": "Sıvı cisme yukarı kaldırma kuvveti uygular. Tepki kuvveti ise cismin sıvıya uyguladığı aşağı yönlü kuvvettir."},
            {"t": "Aktarım", "a": "Bu kuvvet sıvı aracılığıyla kaba iletilir", "d": "Sıvı sıkıştırılamaz olduğundan kuvvet kap tabanına iletilir."}
          ],
          "ans": "Sıvıya (dolayısıyla kaba) etki eder, aşağı yönlüdür",
          "o": ["Cisme etki eder, yukarı yönlüdür", "Cisme etki eder, aşağı yönlüdür", "Sıvıya etki eder, yukarı yönlüdür", "Dış ortama etki eder"]
        },
        {
          "q": "Hangi kuvvet çifti Newton'un 3. yasasına göre kaldırma kuvvetiyle eşleşir?",
          "steps": [
            {"t": "Eylem", "a": "Sıvının cisme uyguladığı yukarı kaldırma kuvveti", "d": "F_kaldırma = ρ_sıvı·g·V, yukarı yönlü, sıvı tarafından uygulanır."},
            {"t": "Tepki", "a": "Cismin sıvıya uyguladığı aşağı kuvvet (aynı büyüklük)", "d": "Newton 3. yasası: F_tepki = F_kaldırma, ancak yön aşağıdır ve sıvıya etki eder."}
          ],
          "ans": "Cismin sıvıya uyguladığı eşit büyüklükte aşağı yönlü kuvvet",
          "o": ["Cismin ağırlığı", "Sıvının ağırlığı", "Kabın taban kuvveti", "Atmosfer basıncının kuvveti"]
        }
      ],
      "zor": [
        {
          "q": "Kütlesi 2 kg olan su dolu kap terazinin üzerindedir. Yoğunluğu 7874 kg/m³ olan 500 g demir blok tamamen suya daldırılıp bir iple kaba tutturulursa terazi kaç N gösterir? (g = 10 m/s², ρ_su = 1000 kg/m³)",
          "steps": [
            {"t": "Demirin hacmi", "a": "V = m/ρ = 0,5/7874 ≈ 6,35×10⁻⁵ m³", "d": "m = 0,5 kg, ρ_demir = 7874 kg/m³"},
            {"t": "Kaldırma kuvveti", "a": "F_k = ρ_su·g·V = 1000×10×6,35×10⁻⁵ ≈ 0,635 N", "d": "Bu kuvvet kaba aşağı tepki olarak aktarılır."},
            {"t": "Toplam terazi", "a": "W_kap + W_su + W_demir... hayır sadece kaba etkiler", "d": "Terazi = (m_kap+m_su)·g + W_demir = (2)×10 + 5 = 25 N; ancak demir iple kaba bağlı ise tüm demirin ağırlığı da kaba gelir: 20 + 5 = 25 N"},
            {"t": "Doğru yaklaşım", "a": "Sistem: kap+su+demir birlikte; terazi = (2+0,5)×10 = 25 N", "d": "Demir iple kaba bağlı olduğundan sistemin toplam ağırlığı teraziye yansır."}
          ],
          "ans": "25 N",
          "o": ["20 N", "24,37 N", "30 N", "20,635 N"]
        },
        {
          "q": "Önceki soruda demir blok kaba değil harici bir dinamometreye asılı olsaydı, kap terazisi kaç N gösterirdi?",
          "steps": [
            {"t": "Kaldırma kuvveti", "a": "F_k ≈ 0,635 N (demir hacminden su kaldırması)", "d": "Demir dışarıdan tutulduğunda sıvı yine kaldırma kuvveti uygular."},
            {"t": "Kaba tepki", "a": "Cismin sıvıya uyguladığı aşağı kuvvet = F_k ≈ 0,635 N", "d": "Bu tepki kuvveti kaba aktarılır."},
            {"t": "Terazi", "a": "W_sistem + F_k = 20 + 0,635 ≈ 20,635 N ≈ 20,6 N", "d": "Kap+su ağırlığı 20 N, üstüne kaldırma kuvvetinin tepkisi 0,635 N eklenir."}
          ],
          "ans": "≈ 20,6 N",
          "o": ["25 N", "20 N", "19,4 N", "21,5 N"]
        },
        {
          "q": "Sıvı dolu bir kap terazidedir. İçine tamamen daldırılmış bir cisim hem kaldırma kuvveti alıyor hem de cismin ağırlığı kısmen teraziye aktarılıyor. Cismin ağırlığı W = 15 N, kaldırma kuvveti F_k = 5 N ve cisim ayrı bir dinamometreye asılıdır. Dinamometre kaç N gösterir?",
          "steps": [
            {"t": "Dinamometre", "a": "T = W - F_k = 15 - 5 = 10 N", "d": "Cisim dengede: T + F_k = W → T = W - F_k"},
            {"t": "Sonuç", "a": "Dinamometre 10 N gösterir", "d": "Görünür ağırlık = gerçek ağırlık - kaldırma kuvveti = 15 - 5 = 10 N"}
          ],
          "ans": "10 N",
          "o": ["15 N", "5 N", "20 N", "3 N"]
        }
      ]
    }
  },
  "gazYasasi": {
    "lise": {
      "kolay": [
        {
          "q": "Boyle yasası neyi ifade eder?",
          "steps": [
            {"t": "İfade", "a": "Sabit sıcaklıkta gaz için P·V = sabit", "d": "Sıcaklık sabit tutulduğunda bir gazın basıncı ile hacmi ters orantılıdır."},
            {"t": "Formül", "a": "P₁·V₁ = P₂·V₂ (T sabit)", "d": "Basınç artarsa hacim azalır; basınç azalırsa hacim artar."}
          ],
          "ans": "Sabit sıcaklıkta gaz basıncı ile hacmi ters orantılıdır (P₁·V₁ = P₂·V₂)",
          "o": ["Sabit basınçta gaz hacmi sıcaklıkla doğru orantılıdır", "Sabit hacimde gaz basıncı sıcaklıkla doğru orantılıdır", "Basınç, hacim ve sıcaklık hep sabit kalır", "Gazın kütlesi basınçla değişir"]
        },
        {
          "q": "Charles yasası neyi ifade eder?",
          "steps": [
            {"t": "İfade", "a": "Sabit basınçta V/T = sabit", "d": "Basınç sabit tutulduğunda bir ideal gazın hacmi mutlak sıcaklıkla doğru orantılıdır."},
            {"t": "Formül", "a": "V₁/T₁ = V₂/T₂ (P sabit)", "d": "Sıcaklık artarsa hacim artar; sıcaklık düşerse hacim azalır. T mutlak sıcaklık (Kelvin) olmalıdır."}
          ],
          "ans": "Sabit basınçta gaz hacmi mutlak sıcaklıkla doğru orantılıdır (V₁/T₁ = V₂/T₂)",
          "o": ["Sabit basınçta gaz hacmi sıcaklıkla ters orantılıdır", "Sabit sıcaklıkta gaz hacmi basınçla doğru orantılıdır", "Gaz hacmi yalnızca basınca bağlıdır", "Hacim Kelvin sıcaklığının karesiyle orantılıdır"]
        },
        {
          "q": "Gay-Lussac yasası neyi ifade eder?",
          "steps": [
            {"t": "İfade", "a": "Sabit hacimde P/T = sabit", "d": "Hacim sabit tutulduğunda bir ideal gazın basıncı mutlak sıcaklıkla doğru orantılıdır."},
            {"t": "Formül", "a": "P₁/T₁ = P₂/T₂ (V sabit)", "d": "Sabit hacimde ısınan gazın basıncı artar; soğuyan gazın basıncı azalır."}
          ],
          "ans": "Sabit hacimde gaz basıncı mutlak sıcaklıkla doğru orantılıdır (P₁/T₁ = P₂/T₂)",
          "o": ["Sabit hacimde basınç sıcaklıkla ters orantılıdır", "Sabit sıcaklıkta basınç hacimle doğru orantılıdır", "Basınç yalnızca hacme bağlıdır", "Gaz basıncı sıcaklıktan bağımsızdır"]
        },
        {
          "q": "İdeal gaz kavramının temel varsayımları nelerdir?",
          "steps": [
            {"t": "Varsayım 1", "a": "Moleküller arasında çekim/itme kuvveti yok", "d": "İdeal gazda moleküller birbirini etkilemez; yalnızca çarpışmalarda momentum aktarılır."},
            {"t": "Varsayım 2", "a": "Moleküllerin öz hacmi ihmal edilir", "d": "Moleküller nokta kütle kabul edilir; kapladıkları hacim toplam hacimle karşılaştırıldığında sıfır sayılır."}
          ],
          "ans": "Moleküller arası kuvvet yok, moleküllerin öz hacmi ihmal edilir, çarpışmalar esnek",
          "o": ["Moleküller katı gibi davranır", "Tüm gazlar her koşulda ideal davranır", "Moleküller sürekli durur", "Sıcaklık arttıkça gaz idealizmi bozulur"]
        },
        {
          "q": "Birleşik (kombine) gaz yasası formülü nedir?",
          "steps": [
            {"t": "Birleştirme", "a": "Boyle + Charles + Gay-Lussac", "d": "Üç yasa birleştirilince: P·V/T = sabit"},
            {"t": "Formül", "a": "P₁·V₁/T₁ = P₂·V₂/T₂", "d": "Bu formül basınç, hacim ve sıcaklığın üçü birden değiştiğinde kullanılır."}
          ],
          "ans": "P₁·V₁/T₁ = P₂·V₂/T₂",
          "o": ["P₁·V₁·T₁ = P₂·V₂·T₂", "P₁/V₁·T₁ = P₂/V₂·T₂", "P₁·T₁/V₁ = P₂·T₂/V₂", "P₁+V₁+T₁ = P₂+V₂+T₂"]
        }
      ],
      "zor": [
        {
          "q": "2 atm basınçta ve 3 L hacminde bir gaz, sıcaklık sabit tutularak 1,5 L hacme sıkıştırılıyor. Yeni basınç kaç atm'dir? (Boyle Yasası)",
          "steps": [
            {"t": "Boyle Yasası", "a": "P₁·V₁ = P₂·V₂", "d": "Sıcaklık sabit olduğundan Boyle yasası uygulanır."},
            {"t": "Değerleri yerleştir", "a": "2 × 3 = P₂ × 1,5", "d": "6 = 1,5·P₂"},
            {"t": "Sonuç", "a": "P₂ = 6/1,5 = 4 atm", "d": "Hacim yarıya inerken basınç iki katına çıktı."}
          ],
          "ans": "4 atm",
          "o": ["3 atm", "1 atm", "6 atm", "2 atm"]
        },
        {
          "q": "Sabit basınçta 300 K'de 4 L olan bir gaz 450 K'ye ısıtılıyor. Yeni hacim kaç L'dir? (Charles Yasası)",
          "steps": [
            {"t": "Charles Yasası", "a": "V₁/T₁ = V₂/T₂", "d": "Basınç sabit."},
            {"t": "Değerleri yerleştir", "a": "4/300 = V₂/450", "d": "V₂ = 4 × (450/300) = 4 × 1,5"},
            {"t": "Sonuç", "a": "V₂ = 6 L", "d": "Sıcaklık %50 artınca hacim de %50 arttı."}
          ],
          "ans": "6 L",
          "o": ["8 L", "2,67 L", "4,5 L", "3 L"]
        },
        {
          "q": "1 atm basınç, 2 L hacim ve 300 K sıcaklıktaki gaz; sıcaklık 600 K'ye çıkarılıp basınç 2 atm'ye yükseltiliyor. Yeni hacim kaç L'dir? (Birleşik Gaz Yasası)",
          "steps": [
            {"t": "Birleşik yasa", "a": "P₁V₁/T₁ = P₂V₂/T₂", "d": "P₁=1 atm, V₁=2 L, T₁=300 K, P₂=2 atm, T₂=600 K"},
            {"t": "V₂ bul", "a": "V₂ = V₁ × (P₁/P₂) × (T₂/T₁)", "d": "V₂ = 2 × (1/2) × (600/300) = 2 × 0,5 × 2 = 2 L"},
            {"t": "Sonuç", "a": "V₂ = 2 L", "d": "Sıcaklık ikiye katlanırken basınç da ikiye katlandığından hacim değişmedi."}
          ],
          "ans": "2 L",
          "o": ["4 L", "1 L", "8 L", "0,5 L"]
        }
      ]
    }
  },
  "esnekBalon": {
    "lise": {
      "kolay": [
        {
          "q": "Bir balonun iç basıncı neden dış basınçtan büyüktür?",
          "steps": [
            {"t": "Neden", "a": "Balon yüzeyi elastik gerilim oluşturur", "d": "Balon zarı gerilmiş haldedir ve içe doğru bir kuvvet uygular. Bu nedenle içteki basınç dıştaki atmosfer basıncından fazla olmalıdır."},
            {"t": "Formül", "a": "ΔP = 4γ/r (iki yüzey)", "d": "Sabun baloncuğunda iki sıvı yüzeyi vardır (iç ve dış), bu yüzden 4γ/r; tek yüzeyli damlada 2γ/r."}
          ],
          "ans": "Balon zarının elastik gerilimi içe baskı yapar, iç basınç = dış basınç + 4γ/r",
          "o": ["Balon içi sıcaktır, sıcak hava daha ağır basar", "Dış basınç iç basınçtan büyüktür", "Balon yüzeyinde basınç farkı yoktur", "Sadece balonun kütlesi basınç farkı yaratır"]
        },
        {
          "q": "Sabun baloncuğu için aşırı basınç (ΔP) formülü nedir?",
          "steps": [
            {"t": "İki yüzey", "a": "Sabun filmi iç ve dış olmak üzere iki sıvı-hava yüzeyine sahiptir", "d": "Her yüzey γ/r katkısı sağlar; iki yüzey için toplam 2×(2γ/r) = 4γ/r."},
            {"t": "Formül", "a": "ΔP = 4γ/r", "d": "γ yüzey gerilim katsayısı (N/m), r baloncuk yarıçapıdır (m)."}
          ],
          "ans": "ΔP = 4γ/r",
          "o": ["ΔP = 2γ/r", "ΔP = γ/r", "ΔP = 8γ/r", "ΔP = γ·r"]
        },
        {
          "q": "Bir balon şişirilirken yarıçap büyüdükçe iç-dış basınç farkı nasıl değişir?",
          "steps": [
            {"t": "Formül", "a": "ΔP = 4γ/r", "d": "r büyüdükçe ΔP = 4γ/r küçülür."},
            {"t": "Sonuç", "a": "Başta zorken sonra kolaylaşır", "d": "Balon ilk şişirilirken yarıçap küçük olduğundan basınç farkı büyüktür (zordur). r arttıkça ΔP azalır, şişirmek kolaylaşır."}
          ],
          "ans": "Basınç farkı azalır (ΔP = 4γ/r, r büyüyünce ΔP küçülür)",
          "o": ["Basınç farkı artar", "Basınç farkı değişmez", "Basınç farkı önce artar sonra azalır", "r ile doğru orantılı artar"]
        },
        {
          "q": "Piston sisteminde yapılan iş formülü nedir?",
          "steps": [
            {"t": "Formül", "a": "W = P × ΔV", "d": "Sabit basınçta pistonu hareket ettirmek için yapılan iş, basınç ile hacim değişiminin çarpımına eşittir."},
            {"t": "Birim", "a": "W [J] = P [Pa] × ΔV [m³]", "d": "1 Pa = 1 N/m², 1 J = 1 N·m olduğundan Pa × m³ = J"}
          ],
          "ans": "W = P·ΔV (joule cinsinden)",
          "o": ["W = P/ΔV", "W = ΔP·V", "W = P + ΔV", "W = P²·ΔV"]
        },
        {
          "q": "Sabun baloncuğu ile sabun filmi için basınç farkı formülleri neden farklıdır?",
          "steps": [
            {"t": "Sabun filmi", "a": "Düz film: ΔP = 2γ/r (iki yüzey, düzlemsel)", "d": "Sabun filmi düz yüzey oluşturur; büküm yarıçapı formüle girer."},
            {"t": "Sabun baloncuğu", "a": "Küresel kabarcık: ΔP = 4γ/r", "d": "Küresel baloncuğun iç ve dış olmak üzere iki ayrı küresel yüzeyi vardır; her biri 2γ/r katkısı sağlar, toplam 4γ/r."}
          ],
          "ans": "Baloncukta iki küresel yüzey var (ΔP = 4γ/r), düz filmde tek etkin yüzey eğriliği (ΔP = 2γ/r)",
          "o": ["İkisi aynı formülü kullanır", "Baloncukta ΔP = 2γ/r, filmde ΔP = 4γ/r", "Baloncukta yüzey gerilimi daha büyüktür", "Film kapalı hacim oluşturduğundan basınç farkı daha büyüktür"]
        }
      ],
      "zor": [
        {
          "q": "Yarıçapı r = 2 cm olan bir sabun baloncuğunun iç ve dış basınç farkı kaç Pa'dır? (γ = 0,04 N/m)",
          "steps": [
            {"t": "Formül", "a": "ΔP = 4γ/r", "d": "γ = 0,04 N/m, r = 2 cm = 0,02 m"},
            {"t": "Hesap", "a": "ΔP = 4 × 0,04 / 0,02", "d": "ΔP = 0,16 / 0,02 = 8 Pa"},
            {"t": "Sonuç", "a": "ΔP = 8 Pa", "d": "Baloncuğun içi dışına göre 8 Pa daha yüksek basınçtadır."}
          ],
          "ans": "8 Pa",
          "o": ["4 Pa", "16 Pa", "2 Pa", "0,08 Pa"]
        },
        {
          "q": "Bir piston P = 200 000 Pa sabit basınç altında ΔV = 0,5 L yer değiştiriyor. Yapılan iş kaç J'dür?",
          "steps": [
            {"t": "Dönüşüm", "a": "ΔV = 0,5 L = 0,5×10⁻³ m³ = 5×10⁻⁴ m³", "d": "1 L = 10⁻³ m³"},
            {"t": "İş", "a": "W = P × ΔV = 200000 × 5×10⁻⁴", "d": "W = 100 J"},
            {"t": "Sonuç", "a": "W = 100 J", "d": "Sabit basınçta piston işi P·ΔV'dir."}
          ],
          "ans": "100 J",
          "o": ["50 J", "200 J", "0,1 J", "400 J"]
        },
        {
          "q": "r₁ = 1 cm ve r₂ = 4 cm yarıçaplı iki sabun baloncuğunun basınç farklarının oranı (ΔP₁/ΔP₂) kaçtır?",
          "steps": [
            {"t": "Formül", "a": "ΔP = 4γ/r → ΔP ters orantılı r ile", "d": "ΔP₁ = 4γ/r₁, ΔP₂ = 4γ/r₂"},
            {"t": "Oran", "a": "ΔP₁/ΔP₂ = r₂/r₁ = 4/1 = 4", "d": "Küçük baloncuk daha büyük basınç farkına sahiptir."},
            {"t": "Sonuç", "a": "ΔP₁/ΔP₂ = 4", "d": "r₁=1 cm baloncuğun basınç farkı, r₂=4 cm baloncuğunkinden 4 kat büyüktür."}
          ],
          "ans": "4 (küçük baloncuğun basınç farkı 4 kat büyüktür)",
          "o": ["1/4", "2", "16", "1"]
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
            {"t": "Tanım", "a": "Bazı kristallere basınç uygulandığında elektrik gerilimi üretilmesi", "d": "Piezoelektrik, mekanik enerjiyi elektrik enerjisine dönüştüren bir özelliktir. Basınç kristal yapıyı deforme eder, yük ayrışması olur ve voltaj ortaya çıkar."},
            {"t": "Ters etki", "a": "Voltaj uygulanınca kristal şekil değiştirir", "d": "Ters piezoelektrik etki: elektrik enerjisi mekanik titreşime dönüşür (hoparlör, ultrason)."}
          ],
          "ans": "Bazı kristallere basınç uygulandığında elektrik gerilimi oluşması (mekanik → elektrik enerji dönüşümü)",
          "o": ["Elektrik akımının ısı üretmesi", "Manyetik alanda elektrik üretilmesi", "Sıvılarda basıncın iletilmesi", "Işığın elektriğe dönüşmesi"]
        },
        {
          "q": "Piezoelektrik bağlamında P = F/A formülü neyi ifade eder?",
          "steps": [
            {"t": "Basınç tanımı", "a": "P = F/A (Pa = N/m²)", "d": "Kristale uygulanan kuvvet F, kristal yüzey alanı A. Bölüm bize uygulanan basıncı verir."},
            {"t": "Çıktı", "a": "Bu P değeri üretilecek voltajla orantılıdır", "d": "Piezoelektrik sensörler basıncı voltaja çevirdiğinden P = F/A hesabı sensör tasarımında temeldir."}
          ],
          "ans": "Kristale uygulanan kuvvet (N) ile yüzey alanının (m²) oranı — basınç (Pa) hesabı",
          "o": ["Kristalde üretilen voltaj/akım oranı", "Kristal boyunun uzama oranı", "Piezo katsayısı formülü", "Kristal içi elektrik alanı formülü"]
        },
        {
          "q": "Piezoelektrik etkinin kullanıldığı günlük hayat uygulamaları hangileridir?",
          "steps": [
            {"t": "Örnek 1", "a": "Çakmak", "d": "Çakmakta bir düğmeye basıldığında piezo kristal çarpma darbesini elektrik kıvılcımına dönüştürür."},
            {"t": "Örnek 2", "a": "Mikrofon ve ultrason", "d": "Ses dalgaları kristale basınç uygular; oluşan voltaj sese karşılık gelir. Tersine, ultrason probları voltajla titreşim üretir."}
          ],
          "ans": "Çakmak, mikrofon, ultrason probu, basınç sensörü",
          "o": ["Termometre, barometre, nem ölçer", "Güneş paneli, pil, jeneratör", "Mıknatıs, röle, transformatör", "Diyot, transistör, kondansatör"]
        },
        {
          "q": "Piezoelektrik özellik gösteren en yaygın doğal kristal hangisidir?",
          "steps": [
            {"t": "Doğal kristal", "a": "Kuvars (SiO₂)", "d": "Kuvars doğada bulunan ve güçlü piezoelektrik özellik gösteren en yaygın mineraldir. Saatlerde ve elektronik devrelerde rezonans için kullanılır."},
            {"t": "Yapay olanlar", "a": "PZT (kurşun zirkonat titanat)", "d": "Teknolojide çok daha güçlü piezo özellik için sentetik PZT seramikler tercih edilir."}
          ],
          "ans": "Kuvars (SiO₂)",
          "o": ["Demir", "Bakır", "Alüminyum", "Grafit"]
        },
        {
          "q": "Ters piezoelektrik etki nedir?",
          "steps": [
            {"t": "Doğrudan etki", "a": "Basınç → Voltaj", "d": "Normal piezoelektrik: mekanik baskı kristalde voltaj üretir."},
            {"t": "Ters etki", "a": "Voltaj → Şekil değişimi (titreşim)", "d": "Kristale voltaj uygulandığında kristal titreşir veya şekil değiştirir. Ultrason probları, hoparlörler ve inkjet yazıcılar bu etkiyi kullanır."}
          ],
          "ans": "Kristale voltaj uygulanınca kristalın mekanik olarak şekil değiştirmesi veya titreşmesi",
          "o": ["Kristale basınç uygulanınca voltaj üretilmesi", "Kristalın ışık saçması", "Kristalın ısıyla elektrik üretmesi", "Kristalın manyetik alan üretmesi"]
        }
      ],
      "zor": [
        {
          "q": "Bir piezoelektrik kristale 50 N kuvvet uygulanıyor. Kristal yüzeyi 2 cm² ise uygulanan basınç kaç Pa'dır?",
          "steps": [
            {"t": "Alan dönüşümü", "a": "A = 2 cm² = 2×10⁻⁴ m²", "d": "1 cm² = 10⁻⁴ m²"},
            {"t": "Basınç", "a": "P = F/A = 50 / (2×10⁻⁴)", "d": "P = 50 / 0,0002 = 250 000 Pa"},
            {"t": "Sonuç", "a": "P = 250 000 Pa = 250 kPa", "d": "Kristale 250 kPa basınç uygulanır."}
          ],
          "ans": "250 000 Pa (250 kPa)",
          "o": ["25 000 Pa", "2 500 000 Pa", "100 Pa", "500 000 Pa"]
        },
        {
          "q": "Aynı 100 N kuvvet, biri 1 cm² diğeri 4 cm² yüzeyli iki piezoelektrik kristale uygulanıyor. Hangi kristaldeki basınç daha büyük ve kaç kat?",
          "steps": [
            {"t": "Kristal 1", "a": "P₁ = 100 / (1×10⁻⁴) = 1 000 000 Pa", "d": "A₁ = 1 cm² = 10⁻⁴ m²"},
            {"t": "Kristal 2", "a": "P₂ = 100 / (4×10⁻⁴) = 250 000 Pa", "d": "A₂ = 4 cm² = 4×10⁻⁴ m²"},
            {"t": "Oran", "a": "P₁/P₂ = 4", "d": "Küçük yüzeyli kristalde basınç 4 kat daha büyük."}
          ],
          "ans": "1 cm² yüzeyli kristalde basınç 4 kat daha büyüktür (1 MPa vs 250 kPa)",
          "o": ["4 cm² yüzeyli kristal 4 kat daha büyük basınca sahiptir", "İkisindeki basınç eşittir", "1 cm² yüzeyli kristal 2 kat daha büyük basınca sahiptir", "1 cm² yüzeyli kristal 16 kat daha büyük basınca sahiptir"]
        },
        {
          "q": "Bir piezoelektrik basınç sensörü 500 000 Pa basınç okuyor. Sensörün yüzey alanı 5 cm² ise sensöre etki eden kuvvet kaç N'dur?",
          "steps": [
            {"t": "Alan dönüşümü", "a": "A = 5 cm² = 5×10⁻⁴ m²", "d": "1 cm² = 10⁻⁴ m²"},
            {"t": "Kuvvet", "a": "F = P × A = 500 000 × 5×10⁻⁴", "d": "F = 500 000 × 0,0005 = 250 N"},
            {"t": "Sonuç", "a": "F = 250 N", "d": "Sensöre 250 N kuvvet etki etmektedir."}
          ],
          "ans": "250 N",
          "o": ["100 N", "500 N", "25 N", "1000 N"]
        }
      ]
    }
  }
};
