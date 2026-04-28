// ═══════════════════════════════════════════════════════════════════════════════
//  Seed — örnek müfredat verisi (JSON-as-Dart-const)
//
//  Anahtar: UserPreference.signature ('country|levelKey|gradeKey|branchKey').
//  Örnek senaryolar (kullanıcı isteği gereği test edilir):
//    • "tr|exam_prep|YKS|"           → Matematik · Türev · Polinomlar
//    • "tr|university|3|insaat_muh"  → Mukavemet · Gerilme · Eksenel Yükler
//
//  Yeni profil eklemek için bu haritaya entry yazmak yeterli — kod
//  değişmez. Production'da Firestore / asset JSON ile genişletilir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../domain/curriculum_node.dart';

const String _seedCurriculumJson = r'''
{
  "tr|high|10|": {
    "subjects": [
      {
        "key": "matematik",
        "name": "Matematik",
        "emoji": "📐",
        "topics": [
          {
            "key": "fonksiyonlar",
            "name": "Fonksiyonlar",
            "subtopics": [
              "Fonksiyon Tanımı",
              "Bire Bir / Örten Fonksiyonlar",
              "Bileşke Fonksiyon",
              "Ters Fonksiyon"
            ]
          },
          {
            "key": "polinomlar",
            "name": "Polinomlar",
            "subtopics": [
              "Polinom Tanımı ve Derecesi",
              "Bölme",
              "Çarpanlara Ayırma",
              "Kalan Bulma"
            ]
          }
        ]
      },
      {
        "key": "fizik",
        "name": "Fizik",
        "emoji": "⚛️",
        "topics": [
          {
            "key": "elektrik_temel",
            "name": "Elektrostatik",
            "subtopics": [
              "Elektrik Yükü",
              "Coulomb Kanunu",
              "Elektrik Alan",
              "Potansiyel"
            ]
          }
        ]
      }
    ]
  },
  "de|high|10|": {
    "subjects": [
      {
        "key": "mathematik",
        "name": "Mathematik",
        "emoji": "📐",
        "topics": [
          {
            "key": "funktionen",
            "name": "Funktionen",
            "subtopics": [
              "Lineare Funktionen",
              "Quadratische Funktionen",
              "Umkehrfunktion",
              "Verkettung"
            ]
          },
          {
            "key": "polynome",
            "name": "Polynome",
            "subtopics": [
              "Polynomdivision",
              "Faktorisierung",
              "Nullstellen"
            ]
          }
        ]
      },
      {
        "key": "physik",
        "name": "Physik",
        "emoji": "⚛️",
        "topics": [
          {
            "key": "elektrostatik",
            "name": "Elektrostatik",
            "subtopics": [
              "Elektrische Ladung",
              "Coulomb-Gesetz",
              "Elektrisches Feld",
              "Spannung und Potential"
            ]
          }
        ]
      }
    ]
  },
  "de|high|11|": {
    "subjects": [
      {
        "key": "mathematik",
        "name": "Mathematik",
        "emoji": "📐",
        "topics": [
          {
            "key": "differential",
            "name": "Differentialrechnung",
            "subtopics": [
              "Ableitungsregeln",
              "Kettenregel",
              "Produktregel",
              "Quotientenregel",
              "Extremwertaufgaben"
            ]
          },
          {
            "key": "integral_de",
            "name": "Integralrechnung",
            "subtopics": [
              "Stammfunktion",
              "Hauptsatz",
              "Flächenberechnung"
            ]
          }
        ]
      },
      {
        "key": "physik",
        "name": "Physik",
        "emoji": "⚛️",
        "topics": [
          {
            "key": "mechanik_de",
            "name": "Mechanik",
            "subtopics": [
              "Kreisbewegung",
              "Schwingungen",
              "Wellen"
            ]
          },
          {
            "key": "elektrizitaet_de",
            "name": "Elektrizitätslehre",
            "subtopics": [
              "Ohm'sches Gesetz",
              "Schaltungen",
              "Kondensatoren",
              "Magnetfeld"
            ]
          }
        ]
      },
      {
        "key": "chemie",
        "name": "Chemie",
        "emoji": "🧪",
        "topics": [
          {
            "key": "organik",
            "name": "Organische Chemie",
            "subtopics": [
              "Alkane",
              "Alkene",
              "Alkohole",
              "Carbonsäuren"
            ]
          }
        ]
      }
    ]
  },
  "tr|exam_prep|YKS|": {
    "subjects": [
      {
        "key": "matematik",
        "name": "Matematik",
        "emoji": "📐",
        "topics": [
          {
            "key": "turev",
            "name": "Türev",
            "subtopics": [
              "Polinomlar",
              "Trigonometrik Türev",
              "Logaritmik Türev",
              "Zincir Kuralı",
              "Maksimum-Minimum Problemleri"
            ]
          },
          {
            "key": "integral",
            "name": "İntegral",
            "subtopics": [
              "Belirsiz İntegral",
              "Belirli İntegral",
              "Alan ve Hacim",
              "Trigonometrik İntegral"
            ]
          },
          {
            "key": "limit",
            "name": "Limit ve Süreklilik",
            "subtopics": [
              "Soldan ve Sağdan Limit",
              "Sonsuzda Limit",
              "Süreklilik",
              "Belirsizlik Durumları"
            ]
          }
        ]
      },
      {
        "key": "fizik",
        "name": "Fizik",
        "emoji": "⚛️",
        "topics": [
          {
            "key": "kuvvet_hareket",
            "name": "Kuvvet ve Hareket",
            "subtopics": [
              "Newton'ın Hareket Yasaları",
              "Sürtünme Kuvveti",
              "Eğik Atış",
              "Dairesel Hareket"
            ]
          },
          {
            "key": "elektrik",
            "name": "Elektrik",
            "subtopics": [
              "Coulomb Yasası",
              "Elektrik Alanı",
              "Potansiyel ve Potansiyel Fark",
              "Direnç ve Akım"
            ]
          }
        ]
      },
      {
        "key": "turkce",
        "name": "Türkçe",
        "emoji": "📖",
        "topics": [
          {
            "key": "paragraf",
            "name": "Paragraf",
            "subtopics": [
              "Anlatım Biçimleri",
              "Düşünceyi Geliştirme Yolları",
              "Konu, Ana Düşünce, Yardımcı Düşünce"
            ]
          },
          {
            "key": "anlam_bilgisi",
            "name": "Anlam Bilgisi",
            "subtopics": [
              "Sözcükte Anlam",
              "Cümlede Anlam",
              "Söz Sanatları"
            ]
          }
        ]
      }
    ]
  },
  "tr|university|3|insaat_muh": {
    "subjects": [
      {
        "key": "mukavemet",
        "name": "Mukavemet",
        "emoji": "💪",
        "topics": [
          {
            "key": "gerilme",
            "name": "Gerilme",
            "subtopics": [
              "Eksenel Yüklerde Gerilme",
              "Burulma (Torsion)",
              "Eğilme Gerilmesi",
              "Bileşik Gerilme",
              "Mohr Çemberi"
            ]
          },
          {
            "key": "sekil_degistirme",
            "name": "Şekil Değiştirme",
            "subtopics": [
              "Hooke Yasası",
              "Poisson Oranı",
              "Esneklik Modülü",
              "Termal Şekil Değiştirme"
            ]
          }
        ]
      },
      {
        "key": "statik",
        "name": "Statik",
        "emoji": "⚖️",
        "topics": [
          {
            "key": "vektorler",
            "name": "Vektörler",
            "subtopics": [
              "Vektörel Toplama",
              "Skaler ve Vektörel Çarpım",
              "Bileşkeler"
            ]
          },
          {
            "key": "kuvvet_ciftleri",
            "name": "Kuvvet Çiftleri",
            "subtopics": [
              "Moment",
              "Couple",
              "Denge Koşulları"
            ]
          }
        ]
      },
      {
        "key": "yapi_statigi",
        "name": "Yapı Statiği",
        "emoji": "🏛️",
        "topics": [
          {
            "key": "kafes_sistemler",
            "name": "Kafes Sistemler",
            "subtopics": [
              "Düğüm Noktaları Yöntemi",
              "Kesim Yöntemi",
              "Statik Belirsizlik"
            ]
          },
          {
            "key": "kiriş_analizi",
            "name": "Kiriş Analizi",
            "subtopics": [
              "Mesnet Tepkileri",
              "Kesme Kuvveti Diyagramı",
              "Eğilme Momenti Diyagramı"
            ]
          }
        ]
      }
    ]
  }
}
''';

/// Seed JSON'u parse edip `Map<signature, List<CurriculumSubject>>`'e çevirir.
/// Subtopic ID'si `{gradeSig}:{courseKey}:{topicKey}:{idx}` formatında üretilir.
Map<String, List<CurriculumSubject>> loadSeedCurriculum() {
  final raw = jsonDecode(_seedCurriculumJson) as Map<String, dynamic>;
  final out = <String, List<CurriculumSubject>>{};
  raw.forEach((sig, value) {
    final m = value as Map<String, dynamic>;
    final subjects = (m['subjects'] as List)
        .whereType<Map<String, dynamic>>()
        .map((s) {
          final courseKey = (s['key'] ?? '').toString();
          return CurriculumSubject(
            key: courseKey,
            name: (s['name'] ?? '').toString(),
            emoji: (s['emoji'] ?? '📚').toString(),
            topics: ((s['topics'] as List?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map((t) {
                  final topicKey = (t['key'] ?? '').toString();
                  final subRaw = (t['subtopics'] as List?) ?? const [];
                  final subs = <CurriculumSubtopic>[];
                  for (var i = 0; i < subRaw.length; i++) {
                    final name = subRaw[i].toString();
                    if (name.isEmpty) continue;
                    subs.add(CurriculumSubtopic(
                      id: '$sig:$courseKey:$topicKey:$i',
                      name: name,
                    ));
                  }
                  return CurriculumTopic(
                    key: topicKey,
                    name: (t['name'] ?? '').toString(),
                    subtopics: subs,
                  );
                })
                .toList(),
          );
        })
        .toList();
    out[sig] = subjects;
  });
  return out;
}
