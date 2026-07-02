// ═══════════════════════════════════════════════════════════════════════════════
//  EXAM CATALOG — Ülkelerin ulusal/merkezi sınav sistemleri (Sınav Modu).
//
//  curriculum_catalog.dart'taki normal (sınıf bazlı) müfredattan FARKLI bir
//  eksen: burada "hangi resmi sınava hazırlanıyorsun" sorulur (LGS/YKS/KPSS
//  gibi), sonra o sınavdan çıkan dersler ve konular listelenir. Bilgi
//  Ligi'nde "Sınav modu" açıldığında bu katalog kullanılır.
//
//  Yapı:
//    ExamGroup   → kullanıcının gördüğü üst kategori (LGS, TYT, AYT, KPSS…)
//    ExamDefinition → grubun somut bir varyantı (AYT'nin Sayısal/EA/Sözel'i,
//                     KPSS'nin Ortaöğretim/Önlisans/Lisans/Öğretmenlik'i gibi).
//                     Tek varyantlı gruplarda (LGS, TYT, DGS) grup ve varyant
//                     birebir aynıdır (tek elemanlı liste).
//
//  Kaynak: her ülkenin resmi sınav kurumu/müfredat çerçevesi (MEB/ÖSYM,
//  College Board/ACT, ENEM/INEP, KMK/Abitur, Éducation Nationale, Гособрнадзор
//  vb. — Jan 2026 bilgi güncelliği). ~40 ülke dolu (kExamCatalog anahtarlarına
//  bak); listede olmayan ülkelerde examGroupsFor() null döner → UI'da
//  "Sınav modu" girişi o ülkede hiç gösterilmez (kırık/boş ekran yerine).
//
//  Ülke kodu: EduProfile.country ile aynı küçük harf ISO-2 kısaltması
//  (curriculum_catalog.dart'taki _lookupKeys ile birebir aynı sözleşme —
//  örn. İngiltere 'uk', ISO 'gb' DEĞİL). examGroupsFor() içeride upper-case'e
//  çevirir. NOT: bilgi_ligi_screen.dart'taki geo-sıralama alanı olan
//  _location.countryCode BAŞKA bir kod alanıdır (~29 ülkeyle sınırlı, League
//  konum seçicisinden gelir) — Sınav Modu kapısı BUNU DEĞİL, EduProfile.country'yi
//  kullanmalı, yoksa çoğu ülke burada tanımlı olsa bile hiç erişilemez olur.
// ═══════════════════════════════════════════════════════════════════════════════

import 'curriculum_catalog.dart' show CurriculumSubject;

class ExamDefinition {
  /// Global olarak benzersiz kimlik (örn. 'ayt_sayisal', 'kpss_lisans').
  final String key;
  /// Kısa görünen ad (örn. "AYT (Sayısal)").
  final String displayName;
  final List<CurriculumSubject> subjects;
  const ExamDefinition({
    required this.key,
    required this.displayName,
    required this.subjects,
  });
}

class ExamGroup {
  /// örn. 'lgs', 'tyt', 'ayt', 'dgs', 'kpss'
  final String key;
  final String displayName;
  final String emoji;
  final String description;
  /// Tek varyantlı gruplarda 1 eleman; AYT/KPSS gibi gruplarda birden fazla.
  final List<ExamDefinition> variants;
  const ExamGroup({
    required this.key,
    required this.displayName,
    required this.emoji,
    required this.description,
    required this.variants,
  });

  bool get hasSingleVariant => variants.length == 1;
}

// ── TÜRKİYE ──────────────────────────────────────────────────────────────────

const _lgsSubjects = <CurriculumSubject>[
  CurriculumSubject(key: 'turkce', displayName: 'Türkçe', emoji: '📖', topics: [
    'Sözcükte Anlam', 'Cümlede Anlam', 'Paragrafta Anlam', 'Fiilimsiler',
    'Cümlenin Öğeleri', 'Cümle Türleri', 'Anlatım Bozuklukları',
    'Yazım Kuralları', 'Noktalama İşaretleri', 'Söz Sanatları',
  ]),
  CurriculumSubject(key: 'matematik', displayName: 'Matematik', emoji: '🔢', topics: [
    'Çarpanlar ve Katlar', 'Üslü İfadeler', 'Kareköklü İfadeler',
    'Veri Analizi', 'Olasılık', 'Cebirsel İfadeler ve Özdeşlikler',
    'Doğrusal Denklemler', 'Eşitsizlikler', 'Üçgenler', 'Eşlik ve Benzerlik',
    'Dönüşüm Geometrisi', 'Geometrik Cisimler',
  ]),
  CurriculumSubject(key: 'fen', displayName: 'Fen Bilimleri', emoji: '🔬', topics: [
    'Mevsimler ve İklim', 'DNA ve Genetik Kod', 'Basınç',
    'Madde ve Endüstri', 'Basit Makineler',
    'Enerji Dönüşümleri ve Çevre Bilimi', 'Elektrik Yükleri ve Elektrik Enerjisi',
  ]),
  CurriculumSubject(key: 'inkilap', displayName: 'T.C. İnkılap Tarihi ve Atatürkçülük', emoji: '🏛️', topics: [
    'Bir Kahraman Doğuyor', 'Milli Uyanış: Bağımsızlık Yolunda',
    'Ya İstiklal Ya Ölüm', 'Çağdaş Türkiye Yolunda Adımlar',
    'Demokratikleşme Çabaları', 'Atatürk Dönemi Dış Politika',
    'Atatürk\'ün Ölümü ve Sonrası',
  ]),
  CurriculumSubject(key: 'din', displayName: 'Din Kültürü ve Ahlak Bilgisi', emoji: '🕌', topics: [
    'Kader İnancı', 'Zekat, Sadaka ve Hac', 'Din ve Hayat',
    'Hz. Muhammed\'in Örnekliği', 'Kur\'an\'a Göre Doğru Bilgi',
  ]),
  CurriculumSubject(key: 'ingilizce', displayName: 'İngilizce', emoji: '🇬🇧', topics: [
    'Friendship', 'Teen Life', 'In the Kitchen', 'On the Phone',
    'The Internet', 'Adventures', 'Tourism', 'Chores', 'Science',
    'Natural Forces',
  ]),
];

const _tytSubjects = <CurriculumSubject>[
  CurriculumSubject(key: 'turkce', displayName: 'Türkçe', emoji: '📖', topics: [
    'Sözcükte Anlam', 'Cümlede Anlam', 'Paragraf', 'Ses Bilgisi',
    'Yazım Kuralları', 'Noktalama İşaretleri', 'Sözcükte Yapı ve Ekler',
    'Sözcük Türleri', 'Cümlenin Öğeleri', 'Cümle Türleri',
    'Anlatım Bozuklukları',
  ]),
  CurriculumSubject(key: 'sosyal', displayName: 'Sosyal Bilimler', emoji: '🌍', topics: [
    'Tarih: İlk Uygarlıklar', 'Tarih: Türk-İslam Tarihi',
    'Tarih: Osmanlı Kuruluş-Yükselme', 'Tarih: Osmanlı Duraklama-Gerileme',
    'Tarih: İnkılap Tarihi', 'Coğrafya: Doğa ve İnsan',
    'Coğrafya: Dünya\'nın Şekli ve Hareketleri', 'Coğrafya: İklim Tipleri',
    'Coğrafya: Nüfus ve Yerleşme', 'Coğrafya: Ekonomik Faaliyetler',
    'Felsefe: Felsefeye Giriş', 'Felsefe: Bilgi ve Varlık Felsefesi',
    'Din Kültürü: İnanç, İbadet, Ahlak',
  ]),
  CurriculumSubject(key: 'matematik', displayName: 'Matematik', emoji: '🔢', topics: [
    'Temel Kavramlar', 'Sayı Basamakları', 'Bölme ve Bölünebilme',
    'OBEB-OKEK', 'Rasyonel Sayılar', 'Ondalık Sayılar', 'Basit Eşitsizlikler',
    'Mutlak Değer', 'Üslü Sayılar', 'Köklü Sayılar', 'Çarpanlara Ayırma',
    'Oran-Orantı', 'Problemler (Sayı, Yaş, Hareket, İşçi, Yüzde, Kar-Zarar, Karışım)',
    'Kümeler', 'Fonksiyonlar', 'Permütasyon-Kombinasyon-Olasılık',
    'Veri ve İstatistik', 'Doğruda ve Üçgende Açılar', 'Çokgenler',
    'Dörtgenler', 'Çember ve Daire', 'Analitik Geometri', 'Katı Cisimler',
  ]),
  CurriculumSubject(key: 'fen', displayName: 'Fen Bilimleri', emoji: '🔬', topics: [
    'Fizik: Fizik Bilimine Giriş', 'Fizik: Madde ve Özellikleri',
    'Fizik: Hareket ve Kuvvet', 'Fizik: İş-Güç-Enerji',
    'Fizik: Isı ve Sıcaklık', 'Fizik: Elektrostatik',
    'Kimya: Kimya Bilimi', 'Kimya: Atom ve Periyodik Sistem',
    'Kimya: Kimyasal Türler Arası Etkileşim', 'Kimya: Maddenin Halleri',
    'Kimya: Karışımlar', 'Kimya: Asit-Baz-Tuz',
    'Biyoloji: Canlıların Ortak Özellikleri', 'Biyoloji: Hücre',
    'Biyoloji: Canlıların Sınıflandırılması', 'Biyoloji: Hücre Bölünmeleri',
    'Biyoloji: Kalıtım', 'Biyoloji: Ekosistem Ekolojisi',
  ]),
];

const _aytMatematik = CurriculumSubject(key: 'matematik', displayName: 'Matematik', emoji: '🔢', topics: [
  'Fonksiyonlar', 'Polinomlar', '2. Dereceden Denklemler', 'Karmaşık Sayılar',
  'Parabol', 'Trigonometri', 'Logaritma', 'Diziler', 'Limit ve Süreklilik',
  'Türev', 'İntegral', 'Analitik Geometri', 'Uzayda Doğru ve Düzlem',
  'Çemberin Analitik İncelemesi',
]);
const _aytFizik = CurriculumSubject(key: 'fizik', displayName: 'Fizik', emoji: '⚛️', topics: [
  'Elektrik ve Manyetizma', 'Basit Harmonik Hareket', 'Dalgalar',
  'Atom Fiziği ve Radyoaktivite', 'Modern Fizik', 'Çembersel Hareket',
  'Elektrik Yükleri ve Elektrik Alan', 'İtme-Momentum',
]);
const _aytKimya = CurriculumSubject(key: 'kimya', displayName: 'Kimya', emoji: '🧪', topics: [
  'Modern Atom Teorisi', 'Gazlar', 'Sıvı Çözeltiler',
  'Kimyasal Tepkimelerde Enerji', 'Tepkime Hızları', 'Kimyasal Denge',
  'Asit-Baz Dengesi', 'Çözünürlük Dengesi', 'Elektrokimya', 'Organik Kimya',
]);
const _aytBiyoloji = CurriculumSubject(key: 'biyoloji', displayName: 'Biyoloji', emoji: '🧬', topics: [
  'Sinir Sistemi', 'Endokrin Sistem', 'Duyu Organları',
  'Destek ve Hareket Sistemi', 'Sindirim Sistemi',
  'Dolaşım ve Bağışıklık Sistemi', 'Solunum Sistemi', 'Boşaltım Sistemi',
  'Üreme Sistemi ve Embriyonik Gelişim', 'Komünite ve Popülasyon Ekolojisi',
  'Genden Proteine', 'Canlılarda Enerji Dönüşümleri', 'Bitki Biyolojisi',
]);
const _aytEdebiyat = CurriculumSubject(key: 'edebiyat', displayName: 'Türk Dili ve Edebiyatı', emoji: '📚', topics: [
  'Anlam Bilgisi', 'Dil Bilgisi', 'Şiir Bilgisi', 'Edebi Sanatlar',
  'İslamiyet Öncesi Türk Edebiyatı', 'Halk Edebiyatı', 'Divan Edebiyatı',
  'Tanzimat Edebiyatı', 'Servet-i Fünun Edebiyatı', 'Milli Edebiyat',
  'Cumhuriyet Dönemi Türk Edebiyatı', 'Dünya Edebiyatı',
]);
const _aytTarih = CurriculumSubject(key: 'tarih', displayName: 'Tarih', emoji: '🏺', topics: [
  'Türk-İslam Tarihi', 'Beylikten Devlete Osmanlı', 'Dünya Gücü Osmanlı',
  'Arayış Yılları', '20. Yüzyıl Başlarında Osmanlı', 'I. Dünya Savaşı',
  'Kurtuluş Savaşı Hazırlık Dönemi', 'TBMM Dönemi', 'Türk İnkılabı',
  'Atatürkçülük', 'Atatürk Dönemi Dış Politika', 'İkinci Dünya Savaşı',
  'Soğuk Savaş Dönemi', 'Yumuşama Dönemi ve Sonrası',
]);
const _aytCografya = CurriculumSubject(key: 'cografya', displayName: 'Coğrafya', emoji: '🗺️', topics: [
  'Biyoçeşitlilik', 'Nüfus Politikaları', 'Şehirleşme',
  'Ekonomik Faaliyetler ve Doğal Kaynaklar',
  'Küresel Ortam: Bölgeler ve Ülkeler', 'Çevre ve Toplum', 'Doğal Afetler',
]);
const _aytFelsefeGrubu = CurriculumSubject(key: 'felsefe_grubu', displayName: 'Felsefe Grubu (Felsefe/Din Kültürü)', emoji: '🧠', topics: [
  'Bilgi Felsefesi', 'Bilim Felsefesi', 'Varlık Felsefesi', 'Ahlak Felsefesi',
  'Sanat Felsefesi', 'Din Felsefesi', 'Siyaset Felsefesi',
  'İslam Düşüncesinde Yorumlar', 'Güncel Dini Meseleler', 'Yaşayan Dinler',
]);

const _dgsSayisal = CurriculumSubject(key: 'matematik', displayName: 'Matematik', emoji: '🔢', topics: [
  'Temel Kavramlar', 'Sayı Basamakları', 'Bölme ve Bölünebilme',
  'Rasyonel Sayılar', 'Problemler', 'Fonksiyonlar', 'Kümeler',
  'Permütasyon-Kombinasyon-Olasılık', 'Geometri (Üçgen, Çokgen, Çember)',
  'Analitik Geometri',
]);
const _dgsSozel = CurriculumSubject(key: 'turkce', displayName: 'Türkçe', emoji: '📖', topics: [
  'Sözcükte Anlam', 'Cümlede Anlam', 'Paragrafta Anlam', 'Dil Bilgisi',
  'Anlatım Bozuklukları', 'Yazım ve Noktalama',
]);

const _kpssGenelYetenek = CurriculumSubject(key: 'genel_yetenek', displayName: 'Genel Yetenek', emoji: '🧩', topics: [
  'Sözcükte Anlam', 'Cümlede Anlam', 'Paragraf', 'Dil Bilgisi',
  'Anlatım Bozuklukları', 'Temel Matematik', 'Problemler', 'Geometri',
  'Veri Yorumlama',
]);
const _kpssGenelKultur = CurriculumSubject(key: 'genel_kultur', displayName: 'Genel Kültür', emoji: '🏛️', topics: [
  'Osmanlı Tarihi', 'İnkılap Tarihi', 'Cumhuriyet Tarihi',
  'Türkiye Coğrafyası', 'Dünya Coğrafyası', 'Anayasa', 'Temel Hak ve Özgürlükler',
  'Yasama-Yürütme-Yargı', 'Güncel Bilgiler',
]);
const _kpssEgitimBilimleri = CurriculumSubject(key: 'egitim_bilimleri', displayName: 'Eğitim Bilimleri', emoji: '🎓', topics: [
  'Gelişim Psikolojisi', 'Öğrenme Psikolojisi', 'Öğretim İlke ve Yöntemleri',
  'Ölçme ve Değerlendirme', 'Rehberlik', 'Sınıf Yönetimi',
  'Program Geliştirme', 'Öğretim Teknolojileri',
  'Türk Eğitim Tarihi ve Eğitim Sistemi', 'Özel Eğitim',
]);

// ── Hindistan/Pakistan/Bangladeş: Fizik/Kimya paylaşımlı dersler ────────────
const _inPhysics = CurriculumSubject(key: 'physics', displayName: 'Physics', emoji: '⚛️', topics: [
  'Mechanics', 'Thermodynamics', 'Electrostatics', 'Current Electricity',
  'Magnetism', 'Optics', 'Modern Physics', 'Waves and Oscillations',
]);
const _inChemistry = CurriculumSubject(key: 'chemistry', displayName: 'Chemistry', emoji: '🧪', topics: [
  'Atomic Structure', 'Chemical Bonding', 'Thermodynamics', 'Equilibrium',
  'Organic Chemistry Basics', 'Periodic Table', 'Electrochemistry',
]);
const _inMathematics = CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: [
  'Algebra', 'Calculus', 'Coordinate Geometry', 'Trigonometry',
  'Probability and Statistics', 'Vectors and 3D Geometry',
]);
const _inBiology = CurriculumSubject(key: 'biology', displayName: 'Biology', emoji: '🧬', topics: [
  'Cell Biology', 'Genetics', 'Human Physiology', 'Plant Physiology',
  'Ecology', 'Evolution', 'Reproduction',
]);
const _inEnglish = CurriculumSubject(key: 'english', displayName: 'English', emoji: '🇬🇧', topics: [
  'Reading Comprehension', 'Grammar', 'Vocabulary', 'Verbal Reasoning',
]);

const kExamCatalog = <String, List<ExamGroup>>{
  'TR': [
    ExamGroup(
      key: 'lgs', displayName: 'LGS', emoji: '🎒',
      description: 'Liseye Geçiş Sınavı (8. sınıf)',
      variants: [ExamDefinition(key: 'lgs', displayName: 'LGS', subjects: _lgsSubjects)],
    ),
    ExamGroup(
      key: 'tyt', displayName: 'TYT', emoji: '📘',
      description: 'Temel Yeterlilik Testi',
      variants: [ExamDefinition(key: 'tyt', displayName: 'TYT', subjects: _tytSubjects)],
    ),
    ExamGroup(
      key: 'ayt', displayName: 'AYT', emoji: '📗',
      description: 'Alan Yeterlilik Testi — alanına göre seç',
      variants: [
        ExamDefinition(key: 'ayt_sayisal', displayName: 'AYT (Sayısal)',
            subjects: [_aytMatematik, _aytFizik, _aytKimya, _aytBiyoloji]),
        ExamDefinition(key: 'ayt_ea', displayName: 'AYT (Eşit Ağırlık)',
            subjects: [_aytMatematik, _aytEdebiyat, _aytTarih, _aytCografya]),
        ExamDefinition(key: 'ayt_sozel', displayName: 'AYT (Sözel)',
            subjects: [_aytEdebiyat, _aytTarih, _aytCografya, _aytFelsefeGrubu]),
      ],
    ),
    ExamGroup(
      key: 'dgs', displayName: 'DGS', emoji: '🎓',
      description: 'Dikey Geçiş Sınavı (Önlisans → Lisans)',
      variants: [
        ExamDefinition(key: 'dgs', displayName: 'DGS', subjects: [_dgsSozel, _dgsSayisal]),
      ],
    ),
    ExamGroup(
      key: 'kpss', displayName: 'KPSS', emoji: '📝',
      description: 'Kamu Personeli Seçme Sınavı — türünü seç',
      variants: [
        ExamDefinition(key: 'kpss_ortaogretim', displayName: 'KPSS Ortaöğretim (Lise)',
            subjects: [_kpssGenelYetenek, _kpssGenelKultur]),
        ExamDefinition(key: 'kpss_onlisans', displayName: 'KPSS Önlisans',
            subjects: [_kpssGenelYetenek, _kpssGenelKultur]),
        ExamDefinition(key: 'kpss_lisans', displayName: 'KPSS Lisans',
            subjects: [_kpssGenelYetenek, _kpssGenelKultur]),
        ExamDefinition(key: 'kpss_ogretmenlik', displayName: 'KPSS Öğretmenlik (Eğitim Bilimleri)',
            subjects: [_kpssGenelYetenek, _kpssGenelKultur, _kpssEgitimBilimleri]),
      ],
    ),
  ],

  // ── AMERİKA ────────────────────────────────────────────────────────────
  'US': [
    ExamGroup(
      key: 'college_admission', displayName: 'SAT / ACT', emoji: '🎓',
      description: 'Üniversiteye giriş sınavları',
      variants: [
        ExamDefinition(key: 'sat', displayName: 'SAT', subjects: [
          CurriculumSubject(key: 'reading_writing', displayName: 'Reading and Writing', emoji: '📖', topics: [
            'Information and Ideas', 'Craft and Structure',
            'Expression of Ideas', 'Standard English Conventions',
          ]),
          CurriculumSubject(key: 'math', displayName: 'Math', emoji: '🔢', topics: [
            'Algebra', 'Advanced Math', 'Problem-Solving and Data Analysis',
            'Geometry and Trigonometry',
          ]),
        ]),
        ExamDefinition(key: 'act', displayName: 'ACT', subjects: [
          CurriculumSubject(key: 'english', displayName: 'English', emoji: '📖', topics: [
            'Usage and Mechanics', 'Rhetorical Skills', 'Grammar and Punctuation',
          ]),
          CurriculumSubject(key: 'math', displayName: 'Mathematics', emoji: '🔢', topics: [
            'Pre-Algebra', 'Elementary Algebra', 'Intermediate Algebra',
            'Coordinate Geometry', 'Plane Geometry', 'Trigonometry',
          ]),
          CurriculumSubject(key: 'reading', displayName: 'Reading', emoji: '📚', topics: [
            'Social Studies Passages', 'Prose Fiction', 'Humanities', 'Natural Sciences',
          ]),
          CurriculumSubject(key: 'science', displayName: 'Science', emoji: '🔬', topics: [
            'Data Representation', 'Research Summaries', 'Conflicting Viewpoints',
          ]),
        ]),
      ],
    ),
  ],
  'MX': [
    ExamGroup(
      key: 'exani_ii', displayName: 'EXANI-II', emoji: '🎓',
      description: "Meksika'nın ulusal yükseköğretime giriş sınavı",
      variants: [ExamDefinition(key: 'exani_ii', displayName: 'EXANI-II', subjects: [
        CurriculumSubject(key: 'pensamiento_matematico', displayName: 'Pensamiento Matemático', emoji: '🔢', topics: [
          'Álgebra', 'Aritmética', 'Geometría', 'Probabilidad y Estadística',
        ]),
        CurriculumSubject(key: 'pensamiento_analitico', displayName: 'Pensamiento Analítico', emoji: '🧩', topics: [
          'Razonamiento Verbal', 'Razonamiento Lógico',
        ]),
        CurriculumSubject(key: 'estructura_lengua', displayName: 'Estructura de la Lengua', emoji: '📖', topics: [
          'Comprensión Lectora', 'Gramática', 'Vocabulario',
        ]),
        CurriculumSubject(key: 'ciencias', displayName: 'Ciencias Naturales y Sociales', emoji: '🔬', topics: [
          'Biología', 'Química', 'Física', 'Historia de México',
        ]),
      ])],
    ),
  ],
  'BR': [
    ExamGroup(
      key: 'enem', displayName: 'ENEM', emoji: '🎓',
      description: "Brezilya'nın ulusal lise bitirme / üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'enem', displayName: 'ENEM', subjects: [
        CurriculumSubject(key: 'linguagens', displayName: 'Linguagens e Códigos', emoji: '📖', topics: [
          'Interpretação de Texto', 'Literatura', 'Gramática', 'Língua Estrangeira',
        ]),
        CurriculumSubject(key: 'humanas', displayName: 'Ciências Humanas', emoji: '🏛️', topics: [
          'História do Brasil', 'História Geral', 'Geografia', 'Filosofia', 'Sociologia',
        ]),
        CurriculumSubject(key: 'natureza', displayName: 'Ciências da Natureza', emoji: '🔬', topics: [
          'Física', 'Química', 'Biologia',
        ]),
        CurriculumSubject(key: 'matematica', displayName: 'Matemática', emoji: '🔢', topics: [
          'Álgebra', 'Geometria', 'Estatística e Probabilidade', 'Funções',
        ]),
        CurriculumSubject(key: 'redacao', displayName: 'Redação', emoji: '✍️', topics: [
          'Dissertação Argumentativa', 'Proposta de Intervenção',
        ]),
      ])],
    ),
  ],
  'CO': [
    ExamGroup(
      key: 'saber11', displayName: 'Saber 11 (ICFES)', emoji: '🎓',
      description: "Kolombiya'nın ulusal lise bitirme sınavı",
      variants: [ExamDefinition(key: 'saber11', displayName: 'Saber 11', subjects: [
        CurriculumSubject(key: 'lectura_critica', displayName: 'Lectura Crítica', emoji: '📖', topics: [
          'Comprensión de Textos', 'Análisis Argumentativo',
        ]),
        CurriculumSubject(key: 'matematicas', displayName: 'Matemáticas', emoji: '🔢', topics: [
          'Álgebra', 'Geometría', 'Estadística',
        ]),
        CurriculumSubject(key: 'sociales', displayName: 'Sociales y Ciudadanas', emoji: '🏛️', topics: [
          'Historia de Colombia', 'Constitución Política', 'Geografía',
        ]),
        CurriculumSubject(key: 'ciencias_naturales', displayName: 'Ciencias Naturales', emoji: '🔬', topics: [
          'Biología', 'Física', 'Química',
        ]),
        CurriculumSubject(key: 'ingles', displayName: 'Inglés', emoji: '🇬🇧', topics: [
          'Comprensión de Lectura', 'Gramática',
        ]),
      ])],
    ),
  ],
  'CL': [
    ExamGroup(
      key: 'paes', displayName: 'PAES', emoji: '🎓',
      description: "Şili'nin üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'paes', displayName: 'PAES', subjects: [
        CurriculumSubject(key: 'competencia_lectora', displayName: 'Competencia Lectora', emoji: '📖', topics: [
          'Comprensión de Textos', 'Vocabulario en Contexto',
        ]),
        CurriculumSubject(key: 'matematica1', displayName: 'Competencia Matemática 1', emoji: '🔢', topics: [
          'Números', 'Álgebra', 'Geometría',
        ]),
        CurriculumSubject(key: 'matematica2', displayName: 'Competencia Matemática 2', emoji: '🔢', topics: [
          'Funciones', 'Probabilidad y Estadística',
        ]),
        CurriculumSubject(key: 'historia', displayName: 'Historia y Ciencias Sociales', emoji: '🏛️', topics: [
          'Historia de Chile', 'Formación Ciudadana', 'Geografía',
        ]),
        CurriculumSubject(key: 'ciencias', displayName: 'Ciencias', emoji: '🔬', topics: [
          'Biología', 'Física', 'Química',
        ]),
      ])],
    ),
  ],

  // ── AVRUPA ─────────────────────────────────────────────────────────────
  'DE': [
    ExamGroup(
      key: 'abitur', displayName: 'Abitur', emoji: '🎓',
      description: "Almanya'nın üniversiteye giriş yeterlilik sınavı",
      variants: [ExamDefinition(key: 'abitur', displayName: 'Abitur', subjects: [
        CurriculumSubject(key: 'deutsch', displayName: 'Deutsch', emoji: '📖', topics: [
          'Textanalyse', 'Erörterung', 'Literaturgeschichte',
        ]),
        CurriculumSubject(key: 'mathematik', displayName: 'Mathematik', emoji: '🔢', topics: [
          'Analysis', 'Analytische Geometrie', 'Stochastik',
        ]),
        CurriculumSubject(key: 'englisch', displayName: 'Englisch', emoji: '🇬🇧', topics: [
          'Textverständnis', 'Grammatik', 'Textproduktion',
        ]),
        CurriculumSubject(key: 'naturwissenschaften', displayName: 'Naturwissenschaften', emoji: '🔬', topics: [
          'Biologie', 'Chemie', 'Physik',
        ]),
        CurriculumSubject(key: 'gesellschaft', displayName: 'Gesellschaftswissenschaften', emoji: '🏛️', topics: [
          'Geschichte', 'Politik', 'Erdkunde',
        ]),
      ])],
    ),
  ],
  'FR': [
    ExamGroup(
      key: 'baccalaureat', displayName: 'Baccalauréat', emoji: '🎓',
      description: "Fransa'nın lise bitirme / üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'bac', displayName: 'Baccalauréat', subjects: [
        CurriculumSubject(key: 'philosophie', displayName: 'Philosophie', emoji: '🧠', topics: [
          'La Conscience', 'La Liberté', 'Le Devoir', 'La Vérité',
        ]),
        CurriculumSubject(key: 'francais', displayName: 'Français', emoji: '📖', topics: [
          'Commentaire de Texte', 'Dissertation', 'Histoire Littéraire',
        ]),
        CurriculumSubject(key: 'mathematiques', displayName: 'Mathématiques', emoji: '🔢', topics: [
          'Analyse', 'Géométrie', 'Probabilités',
        ]),
        CurriculumSubject(key: 'histoire_geo', displayName: 'Histoire-Géographie', emoji: '🏛️', topics: [
          'Histoire du XXe Siècle', 'Géopolitique', 'Géographie de la France',
        ]),
        CurriculumSubject(key: 'sciences', displayName: 'Sciences (Physique-Chimie/SVT)', emoji: '🔬', topics: [
          'Physique-Chimie', 'Sciences de la Vie et de la Terre',
        ]),
      ])],
    ),
  ],
  'UK': [
    ExamGroup(
      key: 'gcse_alevel', displayName: 'GCSE / A-Level', emoji: '🎓',
      description: "İngiltere'nin ortaöğretim yeterlilik sınavları",
      variants: [
        ExamDefinition(key: 'gcse', displayName: 'GCSE', subjects: [
          CurriculumSubject(key: 'english', displayName: 'English Language', emoji: '📖', topics: [
            'Reading Comprehension', 'Creative Writing', 'Transactional Writing',
          ]),
          CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: [
            'Number', 'Algebra', 'Geometry', 'Statistics and Probability',
          ]),
          CurriculumSubject(key: 'combined_science', displayName: 'Combined Science', emoji: '🔬', topics: [
            'Biology', 'Chemistry', 'Physics',
          ]),
          CurriculumSubject(key: 'history', displayName: 'History', emoji: '🏛️', topics: [
            'Modern World History', 'British History', 'Source Analysis',
          ]),
        ]),
        ExamDefinition(key: 'alevel', displayName: 'A-Level', subjects: [
          CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: [
            'Pure Mathematics', 'Statistics', 'Mechanics',
          ]),
          CurriculumSubject(key: 'physics', displayName: 'Physics', emoji: '⚛️', topics: [
            'Mechanics', 'Electricity', 'Waves', 'Nuclear Physics',
          ]),
          CurriculumSubject(key: 'chemistry', displayName: 'Chemistry', emoji: '🧪', topics: [
            'Physical Chemistry', 'Organic Chemistry', 'Inorganic Chemistry',
          ]),
          CurriculumSubject(key: 'economics', displayName: 'Economics', emoji: '💰', topics: [
            'Microeconomics', 'Macroeconomics', 'Market Failure',
          ]),
        ]),
      ],
    ),
  ],
  'ES': [
    ExamGroup(
      key: 'evau', displayName: 'EvAU / Selectividad', emoji: '🎓',
      description: "İspanya'nın üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'evau', displayName: 'EvAU', subjects: [
        CurriculumSubject(key: 'lengua', displayName: 'Lengua Castellana y Literatura', emoji: '📖', topics: [
          'Comentario de Texto', 'Gramática', 'Literatura Española',
        ]),
        CurriculumSubject(key: 'historia_espana', displayName: 'Historia de España', emoji: '🏛️', topics: [
          'Siglo XIX', 'Segunda República y Guerra Civil', 'España Contemporánea',
        ]),
        CurriculumSubject(key: 'matematicas', displayName: 'Matemáticas', emoji: '🔢', topics: [
          'Álgebra', 'Análisis', 'Geometría', 'Probabilidad',
        ]),
        CurriculumSubject(key: 'fisica_quimica', displayName: 'Física y Química', emoji: '🔬', topics: [
          'Mecánica', 'Electromagnetismo', 'Química Orgánica',
        ]),
        CurriculumSubject(key: 'biologia', displayName: 'Biología', emoji: '🧬', topics: [
          'Genética', 'Fisiología', 'Ecología',
        ]),
      ])],
    ),
  ],
  'IT': [
    ExamGroup(
      key: 'maturita', displayName: 'Esame di Maturità', emoji: '🎓',
      description: "İtalya'nın lise bitirme devlet sınavı",
      variants: [ExamDefinition(key: 'maturita', displayName: 'Maturità', subjects: [
        CurriculumSubject(key: 'italiano', displayName: 'Italiano', emoji: '📖', topics: [
          'Analisi del Testo', 'Testo Argomentativo', 'Storia della Letteratura',
        ]),
        CurriculumSubject(key: 'matematica', displayName: 'Matematica', emoji: '🔢', topics: [
          'Analisi Matematica', 'Geometria', 'Probabilità',
        ]),
        CurriculumSubject(key: 'lingua_straniera', displayName: 'Lingua Straniera (Inglese)', emoji: '🇬🇧', topics: [
          'Comprensione del Testo', 'Grammatica',
        ]),
        CurriculumSubject(key: 'scienze', displayName: 'Scienze', emoji: '🔬', topics: [
          'Fisica', 'Chimica', 'Biologia',
        ]),
      ])],
    ),
  ],
  'NL': [
    ExamGroup(
      key: 'eindexamen', displayName: 'Eindexamen (VWO/HAVO)', emoji: '🎓',
      description: "Hollanda'nın merkezi lise bitirme sınavı",
      variants: [ExamDefinition(key: 'eindexamen', displayName: 'Eindexamen', subjects: [
        CurriculumSubject(key: 'nederlands', displayName: 'Nederlands', emoji: '📖', topics: [
          'Tekstbegrip', 'Betoog Schrijven',
        ]),
        CurriculumSubject(key: 'engels', displayName: 'Engels', emoji: '🇬🇧', topics: [
          'Reading Comprehension', 'Grammar',
        ]),
        CurriculumSubject(key: 'wiskunde', displayName: 'Wiskunde', emoji: '🔢', topics: [
          'Algebra', 'Meetkunde', 'Statistiek',
        ]),
        CurriculumSubject(key: 'natuurwetenschappen', displayName: 'Natuurwetenschappen', emoji: '🔬', topics: [
          'Natuurkunde', 'Scheikunde',
        ]),
      ])],
    ),
  ],
  'PL': [
    ExamGroup(
      key: 'matura', displayName: 'Matura', emoji: '🎓',
      description: "Polonya'nın lise bitirme / üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'matura', displayName: 'Matura', subjects: [
        CurriculumSubject(key: 'jezyk_polski', displayName: 'Język Polski', emoji: '📖', topics: [
          'Analiza Tekstu', 'Wypracowanie', 'Historia Literatury',
        ]),
        CurriculumSubject(key: 'matematyka', displayName: 'Matematyka', emoji: '🔢', topics: [
          'Algebra', 'Geometria', 'Rachunek Prawdopodobieństwa',
        ]),
        CurriculumSubject(key: 'jezyk_angielski', displayName: 'Język Angielski', emoji: '🇬🇧', topics: [
          'Rozumienie Tekstu', 'Gramatyka',
        ]),
        CurriculumSubject(key: 'fizyka', displayName: 'Fizyka', emoji: '⚛️', topics: [
          'Mechanika', 'Elektryczność',
        ]),
      ])],
    ),
  ],
  'RU': [
    ExamGroup(
      key: 'ege', displayName: 'ЕГЭ', emoji: '🎓',
      description: "Rusya'nın birleşik devlet sınavı",
      variants: [ExamDefinition(key: 'ege', displayName: 'ЕГЭ', subjects: [
        CurriculumSubject(key: 'russkiy', displayName: 'Русский язык', emoji: '📖', topics: [
          'Орфография', 'Пунктуация', 'Сочинение',
        ]),
        CurriculumSubject(key: 'matematika', displayName: 'Математика', emoji: '🔢', topics: [
          'Алгебра', 'Геометрия', 'Начала анализа',
        ]),
        CurriculumSubject(key: 'fizika', displayName: 'Физика', emoji: '⚛️', topics: [
          'Механика', 'Электродинамика', 'Квантовая физика',
        ]),
        CurriculumSubject(key: 'obshestvoznanie', displayName: 'Обществознание', emoji: '🏛️', topics: [
          'Право', 'Экономика', 'Политика',
        ]),
        CurriculumSubject(key: 'istoria', displayName: 'История', emoji: '🏺', topics: [
          'История России', 'Всемирная история',
        ]),
      ])],
    ),
  ],
  'PT': [
    ExamGroup(
      key: 'exame_nacional', displayName: 'Exame Nacional', emoji: '🎓',
      description: "Portekiz'in ulusal lise bitirme sınavları",
      variants: [ExamDefinition(key: 'exame_nacional', displayName: 'Exame Nacional', subjects: [
        CurriculumSubject(key: 'portugues', displayName: 'Português', emoji: '📖', topics: [
          'Interpretação de Texto', 'Gramática', 'Literatura Portuguesa',
        ]),
        CurriculumSubject(key: 'matematica_a', displayName: 'Matemática A', emoji: '🔢', topics: [
          'Funções', 'Geometria Analítica', 'Estatística',
        ]),
        CurriculumSubject(key: 'fisica_quimica', displayName: 'Física e Química', emoji: '🔬', topics: [
          'Mecânica', 'Química Orgânica',
        ]),
        CurriculumSubject(key: 'biologia_geologia', displayName: 'Biologia e Geologia', emoji: '🧬', topics: [
          'Genética', 'Geologia',
        ]),
      ])],
    ),
  ],
  'GR': [
    ExamGroup(
      key: 'panellinies', displayName: 'Πανελλήνιες Εξετάσεις', emoji: '🎓',
      description: "Yunanistan'ın ulusal üniversiteye giriş sınavları",
      variants: [ExamDefinition(key: 'panellinies', displayName: 'Πανελλήνιες', subjects: [
        CurriculumSubject(key: 'nea_ellinika', displayName: 'Νέα Ελληνικά', emoji: '📖', topics: [
          'Κατανόηση Κειμένου', 'Παραγωγή Λόγου',
        ]),
        CurriculumSubject(key: 'mathimatika', displayName: 'Μαθηματικά', emoji: '🔢', topics: [
          'Άλγεβρα', 'Ανάλυση', 'Γεωμετρία',
        ]),
        CurriculumSubject(key: 'fysiki', displayName: 'Φυσική', emoji: '⚛️', topics: [
          'Μηχανική', 'Ηλεκτρισμός',
        ]),
        CurriculumSubject(key: 'istoria', displayName: 'Ιστορία', emoji: '🏛️', topics: [
          'Νεότερη Ελληνική Ιστορία', 'Ευρωπαϊκή Ιστορία',
        ]),
      ])],
    ),
  ],
  'RO': [
    ExamGroup(
      key: 'bacalaureat', displayName: 'Bacalaureat', emoji: '🎓',
      description: "Romanya'nın lise bitirme sınavı",
      variants: [ExamDefinition(key: 'bac', displayName: 'Bacalaureat', subjects: [
        CurriculumSubject(key: 'limba_romana', displayName: 'Limba Română', emoji: '📖', topics: [
          'Analiză de Text', 'Eseu Argumentativ',
        ]),
        CurriculumSubject(key: 'matematica', displayName: 'Matematică', emoji: '🔢', topics: [
          'Algebră', 'Geometrie', 'Analiză Matematică',
        ]),
        CurriculumSubject(key: 'istorie', displayName: 'Istorie', emoji: '🏛️', topics: [
          'Istoria României', 'Istorie Universală',
        ]),
      ])],
    ),
  ],
  'UA': [
    ExamGroup(
      key: 'nmt', displayName: 'НМТ / ЗНО', emoji: '🎓',
      description: "Ukrayna'nın ulusal çok konulu test sınavı",
      variants: [ExamDefinition(key: 'nmt', displayName: 'НМТ', subjects: [
        CurriculumSubject(key: 'ukrainska', displayName: 'Українська мова', emoji: '📖', topics: [
          'Орфографія', 'Пунктуація', 'Стилістика',
        ]),
        CurriculumSubject(key: 'matematyka', displayName: 'Математика', emoji: '🔢', topics: [
          'Алгебра', 'Геометрія',
        ]),
        CurriculumSubject(key: 'istoria_ukrainy', displayName: 'Історія України', emoji: '🏛️', topics: [
          'Новітня історія', 'Історія державності',
        ]),
      ])],
    ),
  ],
  'SE': [
    ExamGroup(
      key: 'hogskoleprovet', displayName: 'Högskoleprovet', emoji: '🎓',
      description: "İsveç'in üniversiteye giriş yetenek sınavı",
      variants: [ExamDefinition(key: 'hogskoleprovet', displayName: 'Högskoleprovet', subjects: [
        CurriculumSubject(key: 'verbal', displayName: 'Verbal Del', emoji: '📖', topics: [
          'Ordförståelse', 'Läsförståelse', 'Meningskomplettering',
        ]),
        CurriculumSubject(key: 'kvantitativ', displayName: 'Kvantitativ Del', emoji: '🔢', topics: [
          'Matematisk Problemlösning', 'Kvantitativa Jämförelser', 'Diagram och Tabeller',
        ]),
      ])],
    ),
  ],
  'CZ': [
    ExamGroup(
      key: 'maturita', displayName: 'Maturita', emoji: '🎓',
      description: "Çekya'nın lise bitirme sınavı",
      variants: [ExamDefinition(key: 'maturita', displayName: 'Maturita', subjects: [
        CurriculumSubject(key: 'cesky_jazyk', displayName: 'Český Jazyk', emoji: '📖', topics: [
          'Rozbor Textu', 'Sloh',
        ]),
        CurriculumSubject(key: 'matematika', displayName: 'Matematika', emoji: '🔢', topics: [
          'Algebra', 'Geometrie',
        ]),
        CurriculumSubject(key: 'anglicky_jazyk', displayName: 'Anglický Jazyk', emoji: '🇬🇧', topics: [
          'Porozumění Textu', 'Gramatika',
        ]),
      ])],
    ),
  ],
  'HU': [
    ExamGroup(
      key: 'erettsegi', displayName: 'Érettségi', emoji: '🎓',
      description: "Macaristan'ın lise bitirme sınavı",
      variants: [ExamDefinition(key: 'erettsegi', displayName: 'Érettségi', subjects: [
        CurriculumSubject(key: 'magyar', displayName: 'Magyar Nyelv és Irodalom', emoji: '📖', topics: [
          'Szövegértés', 'Irodalomtörténet',
        ]),
        CurriculumSubject(key: 'matematika', displayName: 'Matematika', emoji: '🔢', topics: [
          'Algebra', 'Geometria',
        ]),
        CurriculumSubject(key: 'tortenelem', displayName: 'Történelem', emoji: '🏛️', topics: [
          'Magyar Történelem', 'Egyetemes Történelem',
        ]),
      ])],
    ),
  ],

  // ── ORTA DOĞU / KUZEY AFRİKA ──────────────────────────────────────────
  'SA': [
    ExamGroup(
      key: 'qudurat_tahsili', displayName: 'قدرات / تحصيلي', emoji: '🎓',
      description: "Suudi Arabistan'ın üniversiteye giriş yetenek ve başarı sınavları",
      variants: [
        ExamDefinition(key: 'qudurat', displayName: 'اختبار القدرات (GAT)', subjects: [
          CurriculumSubject(key: 'verbal', displayName: 'القسم اللفظي', emoji: '📖', topics: [
            'استيعاب المقروء', 'التناظر اللفظي', 'إكمال الجمل',
          ]),
          CurriculumSubject(key: 'quantitative', displayName: 'القسم الكمي', emoji: '🔢', topics: [
            'المسائل الحسابية', 'الهندسة', 'الجبر',
          ]),
        ]),
        ExamDefinition(key: 'tahsili', displayName: 'الاختبار التحصيلي', subjects: [
          CurriculumSubject(key: 'physics', displayName: 'الفيزياء', emoji: '⚛️', topics: ['الميكانيكا', 'الكهرباء']),
          CurriculumSubject(key: 'chemistry', displayName: 'الكيمياء', emoji: '🧪', topics: ['الكيمياء العضوية', 'الاتزان الكيميائي']),
          CurriculumSubject(key: 'biology', displayName: 'الأحياء', emoji: '🧬', topics: ['الخلية', 'الوراثة']),
          CurriculumSubject(key: 'math', displayName: 'الرياضيات', emoji: '🔢', topics: ['الجبر', 'حساب المثلثات']),
        ]),
      ],
    ),
  ],
  'AE': [
    ExamGroup(
      key: 'emsat', displayName: 'EmSAT', emoji: '🎓',
      description: "BAE'nin standart üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'emsat', displayName: 'EmSAT', subjects: [
        CurriculumSubject(key: 'english', displayName: 'English', emoji: '🇬🇧', topics: ['Reading', 'Grammar', 'Writing']),
        CurriculumSubject(key: 'math', displayName: 'Math', emoji: '🔢', topics: ['Algebra', 'Geometry', 'Calculus']),
        CurriculumSubject(key: 'physics', displayName: 'Physics', emoji: '⚛️', topics: ['Mechanics', 'Electricity']),
        CurriculumSubject(key: 'arabic', displayName: 'Arabic', emoji: '📖', topics: ['استيعاب المقروء', 'القواعد']),
      ])],
    ),
  ],
  'EG': [
    ExamGroup(
      key: 'thanaweya_amma', displayName: 'الثانوية العامة', emoji: '🎓',
      description: "Mısır'ın lise bitirme sınavı",
      variants: [ExamDefinition(key: 'thanaweya_amma', displayName: 'الثانوية العامة', subjects: [
        CurriculumSubject(key: 'arabic', displayName: 'اللغة العربية', emoji: '📖', topics: ['النحو', 'الأدب', 'البلاغة']),
        CurriculumSubject(key: 'math', displayName: 'الرياضيات', emoji: '🔢', topics: ['الجبر', 'التفاضل والتكامل', 'الهندسة']),
        CurriculumSubject(key: 'physics', displayName: 'الفيزياء', emoji: '⚛️', topics: ['الميكانيكا', 'الكهرباء والمغناطيسية']),
        CurriculumSubject(key: 'chemistry', displayName: 'الكيمياء', emoji: '🧪', topics: ['الكيمياء العضوية', 'الكيمياء الكهربية']),
        CurriculumSubject(key: 'biology', displayName: 'الأحياء', emoji: '🧬', topics: ['الوراثة', 'وظائف الأعضاء']),
        CurriculumSubject(key: 'history', displayName: 'التاريخ', emoji: '🏺', topics: ['تاريخ مصر الحديث']),
      ])],
    ),
  ],
  'IR': [
    ExamGroup(
      key: 'konkur', displayName: 'کنکور', emoji: '🎓',
      description: "İran'ın üniversiteye giriş sınavı — alanını seç",
      variants: [
        ExamDefinition(key: 'konkur_riyazi', displayName: 'کنکور ریاضی فیزیک', subjects: [
          CurriculumSubject(key: 'riyazi', displayName: 'ریاضی', emoji: '🔢', topics: ['جبر', 'هندسه', 'حسابان']),
          CurriculumSubject(key: 'fizik', displayName: 'فیزیک', emoji: '⚛️', topics: ['مکانیک', 'الکتریسیته']),
          CurriculumSubject(key: 'shimi', displayName: 'شیمی', emoji: '🧪', topics: ['شیمی آلی', 'تعادل شیمیایی']),
        ]),
        ExamDefinition(key: 'konkur_tajrobi', displayName: 'کنکور علوم تجربی', subjects: [
          CurriculumSubject(key: 'zist', displayName: 'زیست‌شناسی', emoji: '🧬', topics: ['ژنتیک', 'فیزیولوژی']),
          CurriculumSubject(key: 'shimi', displayName: 'شیمی', emoji: '🧪', topics: ['شیمی آلی', 'تعادل شیمیایی']),
          CurriculumSubject(key: 'fizik', displayName: 'فیزیک', emoji: '⚛️', topics: ['مکانیک', 'الکتریسیته']),
        ]),
        ExamDefinition(key: 'konkur_ensani', displayName: 'کنکور علوم انسانی', subjects: [
          CurriculumSubject(key: 'adabiyat', displayName: 'ادبیات فارسی', emoji: '📖', topics: ['دستور زبان', 'آرایه‌های ادبی']),
          CurriculumSubject(key: 'tarikh', displayName: 'تاریخ', emoji: '🏺', topics: ['تاریخ ایران', 'تاریخ جهان']),
          CurriculumSubject(key: 'joghrafia', displayName: 'جغرافیا', emoji: '🗺️', topics: ['جغرافیای ایران', 'جغرافیای طبیعی']),
        ]),
      ],
    ),
  ],
  'MA': [
    ExamGroup(
      key: 'bac_maroc', displayName: 'البكالوريا المغربية', emoji: '🎓',
      description: "Fas'ın lise bitirme / üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'bac_maroc', displayName: 'البكالوريا', subjects: [
        CurriculumSubject(key: 'arabic', displayName: 'اللغة العربية', emoji: '📖', topics: ['النحو', 'الأدب']),
        CurriculumSubject(key: 'french', displayName: 'الفرنسية', emoji: '🇫🇷', topics: ['Compréhension', 'Grammaire']),
        CurriculumSubject(key: 'math', displayName: 'الرياضيات', emoji: '🔢', topics: ['الجبر', 'التحليل']),
        CurriculumSubject(key: 'physics_chem', displayName: 'الفيزياء والكيمياء', emoji: '⚛️', topics: ['الميكانيكا', 'الكيمياء العضوية']),
        CurriculumSubject(key: 'svt', displayName: 'علوم الحياة والأرض', emoji: '🧬', topics: ['الوراثة', 'علوم الأرض']),
      ])],
    ),
  ],
  'DZ': [
    ExamGroup(
      key: 'bac_algerie', displayName: 'البكالوريا الجزائرية', emoji: '🎓',
      description: "Cezayir'in lise bitirme / üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'bac_algerie', displayName: 'البكالوريا', subjects: [
        CurriculumSubject(key: 'arabic', displayName: 'اللغة العربية وآدابها', emoji: '📖', topics: ['النحو', 'الأدب']),
        CurriculumSubject(key: 'math', displayName: 'الرياضيات', emoji: '🔢', topics: ['الجبر', 'التحليل']),
        CurriculumSubject(key: 'physics', displayName: 'الفيزياء', emoji: '⚛️', topics: ['الميكانيكا', 'الكهرباء']),
        CurriculumSubject(key: 'natural_sciences', displayName: 'العلوم الطبيعية', emoji: '🧬', topics: ['الوراثة', 'علوم الأرض']),
        CurriculumSubject(key: 'history_geo', displayName: 'التاريخ والجغرافيا', emoji: '🏛️', topics: ['تاريخ الجزائر', 'الجغرافيا']),
      ])],
    ),
  ],
  'TN': [
    ExamGroup(
      key: 'bac_tunisie', displayName: 'البكالوريا التونسية', emoji: '🎓',
      description: "Tunus'un lise bitirme / üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'bac_tunisie', displayName: 'البكالوريا', subjects: [
        CurriculumSubject(key: 'arabic', displayName: 'العربية', emoji: '📖', topics: ['النحو', 'الأدب']),
        CurriculumSubject(key: 'math', displayName: 'الرياضيات', emoji: '🔢', topics: ['الجبر', 'التحليل']),
        CurriculumSubject(key: 'svt', displayName: 'علوم الحياة والأرض', emoji: '🧬', topics: ['الوراثة', 'علوم الأرض']),
        CurriculumSubject(key: 'french', displayName: 'الفرنسية', emoji: '🇫🇷', topics: ['Compréhension', 'Grammaire']),
      ])],
    ),
  ],
  'JO': [
    ExamGroup(
      key: 'tawjihi', displayName: 'التوجيهي', emoji: '🎓',
      description: "Ürdün'ün lise bitirme sınavı",
      variants: [ExamDefinition(key: 'tawjihi', displayName: 'التوجيهي', subjects: [
        CurriculumSubject(key: 'arabic', displayName: 'اللغة العربية', emoji: '📖', topics: ['النحو', 'الأدب']),
        CurriculumSubject(key: 'english', displayName: 'اللغة الإنجليزية', emoji: '🇬🇧', topics: ['Reading', 'Grammar']),
        CurriculumSubject(key: 'math', displayName: 'الرياضيات', emoji: '🔢', topics: ['الجبر', 'الهندسة']),
        CurriculumSubject(key: 'physics', displayName: 'الفيزياء', emoji: '⚛️', topics: ['الميكانيكا', 'الكهرباء']),
      ])],
    ),
  ],

  // ── ASYA ───────────────────────────────────────────────────────────────
  'CN': [
    ExamGroup(
      key: 'gaokao', displayName: '高考 (Gaokao)', emoji: '🎓',
      description: "Çin'in ulusal üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'gaokao', displayName: '高考', subjects: [
        CurriculumSubject(key: 'yuwen', displayName: '语文 (Çince)', emoji: '📖', topics: ['阅读理解', '作文', '古诗文']),
        CurriculumSubject(key: 'shuxue', displayName: '数学 (Matematik)', emoji: '🔢', topics: ['代数', '几何', '概率统计']),
        CurriculumSubject(key: 'yingyu', displayName: '英语 (İngilizce)', emoji: '🇬🇧', topics: ['阅读', '语法', '写作']),
        CurriculumSubject(key: 'wuli', displayName: '物理 (Fizik)', emoji: '⚛️', topics: ['力学', '电磁学']),
        CurriculumSubject(key: 'huaxue', displayName: '化学 (Kimya)', emoji: '🧪', topics: ['有机化学', '化学反应']),
        CurriculumSubject(key: 'lishi', displayName: '历史 (Tarih)', emoji: '🏺', topics: ['中国历史', '世界历史']),
      ])],
    ),
  ],
  'JP': [
    ExamGroup(
      key: 'kyotsu_test', displayName: '共通テスト', emoji: '🎓',
      description: "Japonya'nın ortak üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'kyotsu_test', displayName: '共通テスト', subjects: [
        CurriculumSubject(key: 'kokugo', displayName: '国語', emoji: '📖', topics: ['現代文', '古文', '漢文']),
        CurriculumSubject(key: 'sugaku', displayName: '数学', emoji: '🔢', topics: ['数学I・A', '数学II・B']),
        CurriculumSubject(key: 'eigo', displayName: '英語', emoji: '🇬🇧', topics: ['リーディング', 'リスニング']),
        CurriculumSubject(key: 'rika', displayName: '理科', emoji: '🔬', topics: ['物理', '化学', '生物']),
        CurriculumSubject(key: 'chirekishi', displayName: '地理歴史・公民', emoji: '🏛️', topics: ['日本史', '世界史', '地理']),
      ])],
    ),
  ],
  'KR': [
    ExamGroup(
      key: 'suneung', displayName: '수능 (CSAT)', emoji: '🎓',
      description: "Güney Kore'nin üniversiteye giriş yeterlilik sınavı",
      variants: [ExamDefinition(key: 'suneung', displayName: '수능', subjects: [
        CurriculumSubject(key: 'gugeo', displayName: '국어', emoji: '📖', topics: ['독서', '문학', '화법과 작문']),
        CurriculumSubject(key: 'suhak', displayName: '수학', emoji: '🔢', topics: ['대수', '미적분', '확률과 통계']),
        CurriculumSubject(key: 'yeongeo', displayName: '영어', emoji: '🇬🇧', topics: ['독해', '듣기', '문법']),
        CurriculumSubject(key: 'hangugsa', displayName: '한국사', emoji: '🏺', topics: ['근현대사', '전근대사']),
        CurriculumSubject(key: 'tamgu', displayName: '탐구영역 (사회/과학)', emoji: '🔬', topics: ['사회탐구', '과학탐구']),
      ])],
    ),
  ],
  'IN': [
    ExamGroup(
      key: 'jee', displayName: 'JEE', emoji: '🛠️',
      description: "Hindistan'ın mühendislik fakültelerine giriş sınavı",
      variants: [ExamDefinition(key: 'jee', displayName: 'JEE', subjects: [_inPhysics, _inChemistry, _inMathematics])],
    ),
    ExamGroup(
      key: 'neet', displayName: 'NEET', emoji: '⚕️',
      description: "Hindistan'ın tıp fakültelerine giriş sınavı",
      variants: [ExamDefinition(key: 'neet', displayName: 'NEET', subjects: [_inPhysics, _inChemistry, _inBiology])],
    ),
    ExamGroup(
      key: 'upsc', displayName: 'UPSC', emoji: '🏛️',
      description: "Hindistan'ın kamu personeli seçme sınavı",
      variants: [ExamDefinition(key: 'upsc', displayName: 'UPSC CSE', subjects: [
        CurriculumSubject(key: 'general_studies', displayName: 'General Studies', emoji: '🌍', topics: [
          'Indian History', 'Indian Polity', 'Geography', 'Economy',
          'Environment and Ecology', 'Science and Technology',
        ]),
        CurriculumSubject(key: 'csat', displayName: 'CSAT', emoji: '🧩', topics: [
          'Comprehension', 'Logical Reasoning', 'Basic Numeracy',
        ]),
        CurriculumSubject(key: 'current_affairs', displayName: 'Current Affairs', emoji: '📰', topics: [
          'National Affairs', 'International Affairs', 'Government Schemes',
        ]),
      ])],
    ),
  ],
  'PK': [
    ExamGroup(
      key: 'ecat', displayName: 'ECAT', emoji: '🛠️',
      description: "Pakistan'ın mühendislik fakültelerine giriş sınavı",
      variants: [ExamDefinition(key: 'ecat', displayName: 'ECAT', subjects: [_inPhysics, _inChemistry, _inMathematics, _inEnglish])],
    ),
    ExamGroup(
      key: 'mcat', displayName: 'MDCAT', emoji: '⚕️',
      description: "Pakistan'ın tıp/diş hekimliği fakültelerine giriş sınavı",
      variants: [ExamDefinition(key: 'mdcat', displayName: 'MDCAT', subjects: [_inPhysics, _inChemistry, _inBiology, _inEnglish])],
    ),
    ExamGroup(
      key: 'css', displayName: 'CSS', emoji: '🏛️',
      description: "Pakistan'ın kamu personeli seçme sınavı",
      variants: [ExamDefinition(key: 'css', displayName: 'CSS', subjects: [
        CurriculumSubject(key: 'general_knowledge', displayName: 'General Knowledge', emoji: '🌍', topics: [
          'Pakistan Affairs', 'Current Affairs', 'General Science',
        ]),
        CurriculumSubject(key: 'english_essay', displayName: 'English Essay', emoji: '✍️', topics: [
          'Essay Writing', 'Précis Writing',
        ]),
        CurriculumSubject(key: 'islamic_studies', displayName: 'Islamic Studies', emoji: '🕌', topics: [
          'Islamic History', 'Islamic Principles',
        ]),
      ])],
    ),
  ],
  'BD': [
    ExamGroup(
      key: 'engineering_admission', displayName: 'Engineering Admission', emoji: '🛠️',
      description: "Bangladeş'in mühendislik fakültelerine giriş sınavı",
      variants: [ExamDefinition(key: 'engineering', displayName: 'Engineering Admission', subjects: [_inPhysics, _inChemistry, _inMathematics, _inEnglish])],
    ),
    ExamGroup(
      key: 'medical_admission', displayName: 'Medical Admission', emoji: '⚕️',
      description: "Bangladeş'in tıp fakültelerine giriş sınavı",
      variants: [ExamDefinition(key: 'medical', displayName: 'Medical Admission', subjects: [_inPhysics, _inChemistry, _inBiology, _inEnglish])],
    ),
    ExamGroup(
      key: 'bcs', displayName: 'BCS', emoji: '🏛️',
      description: "Bangladeş'in kamu personeli seçme sınavı",
      variants: [ExamDefinition(key: 'bcs', displayName: 'BCS', subjects: [
        CurriculumSubject(key: 'bangla', displayName: 'বাংলা', emoji: '📖', topics: ['ব্যাকরণ', 'সাহিত্য']),
        CurriculumSubject(key: 'english', displayName: 'English', emoji: '🇬🇧', topics: ['Grammar', 'Comprehension']),
        CurriculumSubject(key: 'bangladesh_affairs', displayName: 'Bangladesh Affairs', emoji: '🇧🇩', topics: ['History', 'Constitution']),
        CurriculumSubject(key: 'general_science', displayName: 'General Science', emoji: '🔬', topics: ['Physics', 'Chemistry', 'Biology basics']),
        CurriculumSubject(key: 'math_reasoning', displayName: 'Mathematical Reasoning', emoji: '🔢', topics: ['Arithmetic', 'Logical Reasoning']),
      ])],
    ),
  ],
  'ID': [
    ExamGroup(
      key: 'utbk_snbt', displayName: 'UTBK-SNBT', emoji: '🎓',
      description: "Endonezya'nın bilgisayar tabanlı üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'utbk_snbt', displayName: 'UTBK-SNBT', subjects: [
        CurriculumSubject(key: 'potensi_skolastik', displayName: 'Tes Potensi Skolastik', emoji: '🧩', topics: ['Penalaran Umum', 'Pengetahuan Kuantitatif']),
        CurriculumSubject(key: 'literasi_indonesia', displayName: 'Literasi Bahasa Indonesia', emoji: '📖', topics: ['Pemahaman Bacaan', 'Tata Bahasa']),
        CurriculumSubject(key: 'literasi_inggris', displayName: 'Literasi Bahasa Inggris', emoji: '🇬🇧', topics: ['Reading Comprehension', 'Grammar']),
        CurriculumSubject(key: 'penalaran_matematika', displayName: 'Penalaran Matematika', emoji: '🔢', topics: ['Aljabar', 'Statistika']),
      ])],
    ),
  ],
  'VN': [
    ExamGroup(
      key: 'thpt', displayName: 'Kỳ thi tốt nghiệp THPT', emoji: '🎓',
      description: "Vietnam'ın ulusal lise bitirme sınavı",
      variants: [ExamDefinition(key: 'thpt', displayName: 'THPT', subjects: [
        CurriculumSubject(key: 'toan', displayName: 'Toán', emoji: '🔢', topics: ['Đại số', 'Hình học', 'Giải tích']),
        CurriculumSubject(key: 'ngu_van', displayName: 'Ngữ Văn', emoji: '📖', topics: ['Đọc hiểu', 'Nghị luận văn học']),
        CurriculumSubject(key: 'ngoai_ngu', displayName: 'Ngoại Ngữ (Tiếng Anh)', emoji: '🇬🇧', topics: ['Reading', 'Grammar']),
        CurriculumSubject(key: 'vat_ly', displayName: 'Vật Lý', emoji: '⚛️', topics: ['Cơ học', 'Điện học']),
        CurriculumSubject(key: 'hoa_hoc', displayName: 'Hóa Học', emoji: '🧪', topics: ['Hóa hữu cơ', 'Hóa vô cơ']),
        CurriculumSubject(key: 'sinh_hoc', displayName: 'Sinh Học', emoji: '🧬', topics: ['Di truyền học', 'Sinh thái học']),
      ])],
    ),
  ],
  'TH': [
    ExamGroup(
      key: 'gat_pat', displayName: 'GAT/PAT', emoji: '🎓',
      description: "Tayland'ın genel ve alan yetenek sınavı",
      variants: [ExamDefinition(key: 'gat_pat', displayName: 'GAT/PAT', subjects: [
        CurriculumSubject(key: 'gat', displayName: 'GAT (ความสามารถทั่วไป)', emoji: '🧩', topics: ['การอ่านและเขียน', 'การสื่อสารภาษาอังกฤษ']),
        CurriculumSubject(key: 'pat1', displayName: 'PAT1 (คณิตศาสตร์)', emoji: '🔢', topics: ['พีชคณิต', 'เรขาคณิต']),
        CurriculumSubject(key: 'pat2', displayName: 'PAT2 (วิทยาศาสตร์)', emoji: '🔬', topics: ['ฟิสิกส์', 'เคมี', 'ชีววิทยา']),
      ])],
    ),
  ],
  'PH': [
    ExamGroup(
      key: 'upcat', displayName: 'UPCAT', emoji: '🎓',
      description: "Filipinler'in üniversiteye giriş sınavı",
      variants: [ExamDefinition(key: 'upcat', displayName: 'UPCAT', subjects: [
        CurriculumSubject(key: 'language_proficiency', displayName: 'Language Proficiency', emoji: '📖', topics: ['Filipino', 'English Grammar']),
        CurriculumSubject(key: 'reading_comprehension', displayName: 'Reading Comprehension', emoji: '📚', topics: ['Critical Reading', 'Inference']),
        CurriculumSubject(key: 'science', displayName: 'Science', emoji: '🔬', topics: ['Biology', 'Chemistry', 'Physics']),
        CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: ['Algebra', 'Geometry']),
      ])],
    ),
  ],
  'MY': [
    ExamGroup(
      key: 'spm', displayName: 'SPM', emoji: '🎓',
      description: "Malezya'nın lise bitirme sertifika sınavı",
      variants: [ExamDefinition(key: 'spm', displayName: 'SPM', subjects: [
        CurriculumSubject(key: 'bahasa_melayu', displayName: 'Bahasa Melayu', emoji: '📖', topics: ['Tatabahasa', 'Karangan']),
        CurriculumSubject(key: 'english', displayName: 'English', emoji: '🇬🇧', topics: ['Grammar', 'Comprehension']),
        CurriculumSubject(key: 'matematik', displayName: 'Matematik', emoji: '🔢', topics: ['Algebra', 'Geometri']),
        CurriculumSubject(key: 'sains', displayName: 'Sains', emoji: '🔬', topics: ['Fizik', 'Kimia', 'Biologi']),
      ])],
    ),
  ],
  'SG': [
    ExamGroup(
      key: 'gce_o_a_level', displayName: 'GCE O-Level / A-Level', emoji: '🎓',
      description: "Singapur'un Cambridge tabanlı ortaöğretim sınavları",
      variants: [
        ExamDefinition(key: 'o_level', displayName: 'O-Level', subjects: [
          CurriculumSubject(key: 'english', displayName: 'English', emoji: '📖', topics: ['Comprehension', 'Composition']),
          CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: ['Algebra', 'Geometry']),
          CurriculumSubject(key: 'combined_science', displayName: 'Combined Science', emoji: '🔬', topics: ['Physics', 'Chemistry', 'Biology']),
        ]),
        ExamDefinition(key: 'a_level', displayName: 'A-Level', subjects: [
          CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: ['Calculus', 'Statistics']),
          CurriculumSubject(key: 'physics', displayName: 'Physics', emoji: '⚛️', topics: ['Mechanics', 'Electromagnetism']),
          CurriculumSubject(key: 'general_paper', displayName: 'General Paper', emoji: '📰', topics: ['Essay Writing', 'Comprehension']),
        ]),
      ],
    ),
  ],
  'KZ': [
    ExamGroup(
      key: 'ent', displayName: 'ЕНТ (UNT)', emoji: '🎓',
      description: "Kazakistan'ın birleşik ulusal test sınavı",
      variants: [ExamDefinition(key: 'ent', displayName: 'ЕНТ', subjects: [
        CurriculumSubject(key: 'kazakh_russian', displayName: 'Қазақ тілі / Русский язык', emoji: '📖', topics: ['Грамматика', 'Понимание текста']),
        CurriculumSubject(key: 'matematika', displayName: 'Математика', emoji: '🔢', topics: ['Алгебра', 'Геометрия']),
        CurriculumSubject(key: 'istoria_kz', displayName: 'История Казахстана', emoji: '🏛️', topics: ['Древняя история', 'Новейшая история']),
      ])],
    ),
  ],

  // ── AFRİKA (MENA hariç) ──────────────────────────────────────────────
  'NG': [
    ExamGroup(
      key: 'jamb', displayName: 'JAMB / WAEC', emoji: '🎓',
      description: "Nijerya'nın üniversiteye giriş / lise bitirme sınavları",
      variants: [
        ExamDefinition(key: 'jamb_utme', displayName: 'JAMB UTME', subjects: [
          CurriculumSubject(key: 'english', displayName: 'English Language', emoji: '📖', topics: ['Comprehension', 'Grammar', 'Lexis and Structure']),
          CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: ['Algebra', 'Geometry', 'Statistics']),
          CurriculumSubject(key: 'physics', displayName: 'Physics', emoji: '⚛️', topics: ['Mechanics', 'Electricity']),
          CurriculumSubject(key: 'chemistry', displayName: 'Chemistry', emoji: '🧪', topics: ['Organic Chemistry', 'Chemical Bonding']),
          CurriculumSubject(key: 'biology', displayName: 'Biology', emoji: '🧬', topics: ['Genetics', 'Ecology']),
          CurriculumSubject(key: 'economics', displayName: 'Economics', emoji: '💰', topics: ['Micro Economics', 'Macro Economics']),
        ]),
        ExamDefinition(key: 'waec_ssce', displayName: 'WAEC / SSCE', subjects: [
          CurriculumSubject(key: 'english', displayName: 'English Language', emoji: '📖', topics: ['Comprehension', 'Essay Writing']),
          CurriculumSubject(key: 'mathematics', displayName: 'Mathematics (Core)', emoji: '🔢', topics: ['Algebra', 'Geometry']),
          CurriculumSubject(key: 'basic_science', displayName: 'Basic Science', emoji: '🔬', topics: ['Physics Basics', 'Chemistry Basics', 'Biology Basics']),
          CurriculumSubject(key: 'social_studies', displayName: 'Social Studies', emoji: '🌍', topics: ['Civics', 'Nigerian History']),
        ]),
      ],
    ),
  ],
  'GH': [
    ExamGroup(
      key: 'wassce', displayName: 'WASSCE', emoji: '🎓',
      description: "Gana'nın Batı Afrika lise bitirme sınavı",
      variants: [ExamDefinition(key: 'wassce', displayName: 'WASSCE', subjects: [
        CurriculumSubject(key: 'english', displayName: 'English Language', emoji: '📖', topics: ['Comprehension', 'Essay Writing']),
        CurriculumSubject(key: 'mathematics', displayName: 'Mathematics (Core)', emoji: '🔢', topics: ['Algebra', 'Geometry']),
        CurriculumSubject(key: 'integrated_science', displayName: 'Integrated Science', emoji: '🔬', topics: ['Physics Basics', 'Chemistry Basics', 'Biology Basics']),
        CurriculumSubject(key: 'social_studies', displayName: 'Social Studies', emoji: '🌍', topics: ['Civics', 'Ghanaian History']),
      ])],
    ),
  ],
  'KE': [
    ExamGroup(
      key: 'kcse', displayName: 'KCSE', emoji: '🎓',
      description: "Kenya'nın lise bitirme sertifika sınavı",
      variants: [ExamDefinition(key: 'kcse', displayName: 'KCSE', subjects: [
        CurriculumSubject(key: 'english', displayName: 'English', emoji: '📖', topics: ['Comprehension', 'Composition']),
        CurriculumSubject(key: 'kiswahili', displayName: 'Kiswahili', emoji: '📖', topics: ['Ufahamu', 'Insha']),
        CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: ['Algebra', 'Geometry']),
        CurriculumSubject(key: 'biology', displayName: 'Biology', emoji: '🧬', topics: ['Genetics', 'Ecology']),
        CurriculumSubject(key: 'chemistry', displayName: 'Chemistry', emoji: '🧪', topics: ['Organic Chemistry', 'Acids and Bases']),
        CurriculumSubject(key: 'physics', displayName: 'Physics', emoji: '⚛️', topics: ['Mechanics', 'Electricity']),
      ])],
    ),
  ],
  'ZA': [
    ExamGroup(
      key: 'nsc', displayName: 'NSC (Matric)', emoji: '🎓',
      description: "Güney Afrika'nın ulusal lise bitirme sertifikası",
      variants: [ExamDefinition(key: 'nsc', displayName: 'NSC', subjects: [
        CurriculumSubject(key: 'home_language', displayName: 'Home Language (English)', emoji: '📖', topics: ['Comprehension', 'Essay Writing']),
        CurriculumSubject(key: 'mathematics', displayName: 'Mathematics', emoji: '🔢', topics: ['Algebra', 'Geometry', 'Calculus']),
        CurriculumSubject(key: 'life_sciences', displayName: 'Life Sciences', emoji: '🧬', topics: ['Genetics', 'Human Physiology']),
        CurriculumSubject(key: 'physical_sciences', displayName: 'Physical Sciences', emoji: '⚛️', topics: ['Mechanics', 'Chemical Change']),
        CurriculumSubject(key: 'geography', displayName: 'Geography', emoji: '🗺️', topics: ['Climatology', 'Geomorphology']),
      ])],
    ),
  ],
};

/// Bir ülke için tanımlı sınav grupları — yoksa null (UI'da "Sınav modu"
/// girişi gizlenir).
List<ExamGroup>? examGroupsFor(String? countryCode) {
  final cc = (countryCode ?? '').toUpperCase();
  return kExamCatalog[cc];
}
