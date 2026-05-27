import 'package:flutter/material.dart';

import '../models/topic_3d_model.dart';

/// Hangi konuların 3D modeli olduğunu tutan merkezi kayıt.
///
/// Özet/çözüm ekranları `Topic3DRegistry.findByKeywords(text)` ile sorular ve
/// bir model döndüğünde "3D modelde gör" butonunu otomatik gösterir.
class Topic3DRegistry {
  Topic3DRegistry._();

  static const Map<String, Topic3DModel> _models = {
    'hucre': Topic3DModel(
      id: 'hucre',
      name: 'Hücre',
      subject: 'Biyoloji',
      description:
          'Canlıların yapı ve görev birimi. Çekirdek, sitoplazma ve organellerden '
          'oluşur. Eukaryot hücrelerin temel parçalarını 3D olarak incele.',
      glbUrl: 'https://modelviewer.dev/shared-assets/models/Astronaut.glb',
      hasCrossSection: true,
      compareWithId: 'bitki_hucresi',
      parts: [
        Topic3DPart(
          id: 'cekirdek',
          name: 'Çekirdek',
          info:
              'Hücrenin yönetim merkezi. DNA\'yı barındırır, gen ifadesini '
              'denetler ve mRNA üretimini başlatır. Çift katlı zar ile çevrilidir.',
          hotspotPosition: '0m 1.2m 0m',
          color: Color(0xFFE91E63),
        ),
        Topic3DPart(
          id: 'mitokondri',
          name: 'Mitokondri',
          info:
              'Hücrenin enerji santrali. Oksijenli solunum ile ATP üretir. '
              'Çift katlı zarı vardır; iç zar kıvrımlarına krista denir. Kendi '
              'DNA\'sı vardır.',
          hotspotPosition: '0.4m 0.8m 0m',
          color: Color(0xFFFF5722),
        ),
        Topic3DPart(
          id: 'ribozom',
          name: 'Ribozom',
          info:
              'Protein sentezi yapılan yapı. Sitoplazmada serbest veya '
              'endoplazmik retikuluma bağlı bulunur. rRNA ve proteinden oluşur.',
          hotspotPosition: '-0.3m 0.5m 0m',
          color: Color(0xFF9C27B0),
        ),
        Topic3DPart(
          id: 'lizozom',
          name: 'Lizozom',
          info:
              'Sindirim organeli. İçindeki sindirim enzimleri ile hücre içi '
              'sindirim yapar. Yaşlanmış organelleri ve dış kaynaklı parçaları '
              'parçalar.',
          hotspotPosition: '0.5m 0.2m -0.2m',
          color: Color(0xFFFFEB3B),
        ),
        Topic3DPart(
          id: 'golgi',
          name: 'Golgi Aygıtı',
          info:
              'Hücrenin paketleme ve sevkiyat merkezi. Endoplazmik retikulumdan '
              'gelen proteinleri işler, paketler ve hücre içi/dışı hedeflere yollar.',
          hotspotPosition: '-0.4m -0.1m 0m',
          color: Color(0xFF4CAF50),
        ),
        Topic3DPart(
          id: 'er',
          name: 'Endoplazmik Retikulum',
          info:
              'Hücre içi taşıma ağı. Granüllü (ribozomlu) ER protein sentezi, '
              'düz ER lipit sentezi ve detoksifikasyon yapar. Zarlardan oluşan '
              'kanal sistemi.',
          hotspotPosition: '0m -0.3m 0.3m',
          color: Color(0xFF03A9F4),
        ),
        Topic3DPart(
          id: 'membran',
          name: 'Hücre Zarı',
          info:
              'Hücrenin dış sınırı. Çift katlı fosfolipit yapısındadır. '
              'Seçici geçirgen — madde alışverişini kontrol eder. Üzerindeki '
              'proteinler reseptör görevi yapar.',
          hotspotPosition: '0m -1.0m 0m',
          color: Color(0xFF00BCD4),
        ),
      ],
    ),
    'gunes_sistemi': Topic3DModel(
      id: 'gunes_sistemi',
      name: 'Güneş Sistemi',
      subject: 'Astronomi / Fen',
      description:
          'Güneş\'in çekim etkisiyle yörüngede dolanan 8 gezegen, cüce '
          'gezegenler, asteroitler ve kuyruklu yıldızlardan oluşan sistem.',
      glbUrl: 'https://modelviewer.dev/shared-assets/models/Astronaut.glb',
      animationName: 'orbit',
      parts: [
        Topic3DPart(
          id: 'gunes',
          name: 'Güneş',
          info:
              'Sistemin merkezindeki yıldız. Çapı ~1.4 milyon km. Çekirdeğinde '
              'hidrojen helyuma dönüşür (füzyon). Sistemin enerji kaynağı.',
          hotspotPosition: '0m 0m 0m',
          color: Color(0xFFFFC107),
        ),
        Topic3DPart(
          id: 'merkur',
          name: 'Merkür',
          info:
              'Güneş\'e en yakın gezegen. Atmosferi yok denecek kadar incedir. '
              'Bir günü ~58 Dünya günü, bir yılı 88 gün sürer. Yüzeyi kraterlidir.',
          hotspotPosition: '0.3m 0m 0m',
          color: Color(0xFF9E9E9E),
        ),
        Topic3DPart(
          id: 'venus',
          name: 'Venüs',
          info:
              'Sistemin en sıcak gezegeni (~465°C). Kalın CO₂ atmosferi nedeniyle '
              'sera etkisi aşırı yüksek. Ters yönde döner.',
          hotspotPosition: '0.6m 0m 0m',
          color: Color(0xFFFFB74D),
        ),
        Topic3DPart(
          id: 'dunya',
          name: 'Dünya',
          info:
              'Yaşamın bilinen tek evi. Yüzeyinin ~%71\'i suyla kaplı. '
              'Atmosfer (%78 N, %21 O), manyetik alan ve uydusu Ay vardır.',
          hotspotPosition: '0.9m 0m 0m',
          color: Color(0xFF2196F3),
        ),
        Topic3DPart(
          id: 'mars',
          name: 'Mars',
          info:
              'Kızıl gezegen. Yüzey demir oksit nedeniyle kırmızıdır. İnce '
              'CO₂ atmosferi, kutuplarında buz kalıntıları ve Olympus Mons '
              '(sistemin en büyük volkanı) bulunur.',
          hotspotPosition: '1.2m 0m 0m',
          color: Color(0xFFE53935),
        ),
        Topic3DPart(
          id: 'jupiter',
          name: 'Jüpiter',
          info:
              'Sistemin en büyük gezegeni — gaz devi. Hidrojen ve helyumdan '
              'oluşur. Büyük Kızıl Leke yüzyıllardır süren fırtınadır. 95+ uydusu var.',
          hotspotPosition: '1.6m 0m 0m',
          color: Color(0xFFFF9800),
        ),
        Topic3DPart(
          id: 'saturn',
          name: 'Satürn',
          info:
              'Halkaları en belirgin gaz devi. Halkalar buz ve kaya '
              'parçacıklarından oluşur. Yoğunluğu sudan az — teorik olarak suda '
              'yüzer.',
          hotspotPosition: '2.0m 0m 0m',
          color: Color(0xFFFFD54F),
        ),
        Topic3DPart(
          id: 'uranus',
          name: 'Uranüs',
          info:
              'Buz devi. Yanlamasına döner (eksen eğikliği ~98°). Mavi rengi '
              'metan gazından gelir. İnce halkaları vardır.',
          hotspotPosition: '2.4m 0m 0m',
          color: Color(0xFF4FC3F7),
        ),
        Topic3DPart(
          id: 'neptun',
          name: 'Neptün',
          info:
              'En uzak gezegen. Buz devi. Sistemin en hızlı rüzgârları (~2.000 km/s) '
              'burada eser. Büyük Karanlık Leke fırtınalarına ev sahipliği yapar.',
          hotspotPosition: '2.8m 0m 0m',
          color: Color(0xFF1565C0),
        ),
      ],
    ),
    'yer_sekilleri': Topic3DModel(
      id: 'yer_sekilleri',
      name: 'Yer Şekilleri',
      subject: 'Coğrafya',
      description:
          'Dünya yüzeyini oluşturan iç ve dış kuvvetlerin (tektonik, erozyon, '
          'volkanizma) ortaya çıkardığı şekiller — dağ, plato, ova, vadi, göl, nehir.',
      glbUrl: 'https://modelviewer.dev/shared-assets/models/Astronaut.glb',
      parts: [
        Topic3DPart(
          id: 'dag',
          name: 'Dağ',
          info:
              'Çevresine göre yüksek, eğimli yer şekli. İç kuvvetlerle '
              '(orojenez, volkanizma) oluşur. Türleri: kıvrım, kırık, volkanik. '
              'Örnek: Toroslar (kıvrım), Erciyes (volkanik).',
          hotspotPosition: '0.5m 1m 0m',
          color: Color(0xFF795548),
        ),
        Topic3DPart(
          id: 'plato',
          name: 'Plato',
          info:
              'Akarsular tarafından derin vadilerle yarılmış, çevresine göre '
              'yüksek düzlük. Türkiye\'de İç Anadolu, Doğu Anadolu, Taşeli platoları örnektir.',
          hotspotPosition: '-0.5m 0.5m 0m',
          color: Color(0xFFA1887F),
        ),
        Topic3DPart(
          id: 'ova',
          name: 'Ova',
          info:
              'Çevresine göre alçak, geniş ve düz yer şekli. Akarsuların '
              'taşıdığı alüvyonla oluşan ovalar (Çukurova), kıyı ovaları, '
              'tektonik ovalar (Bursa) çeşitleri vardır.',
          hotspotPosition: '0m 0m 0.5m',
          color: Color(0xFFCDDC39),
        ),
        Topic3DPart(
          id: 'vadi',
          name: 'Vadi',
          info:
              'Akarsuların aşındırmasıyla oluşan uzun çukur. V şeklinde '
              '(genç vadi), tabanlı (olgun) veya kanyon vadi olabilir. Vadiler '
              'akarsuyun yaşına göre şekil alır.',
          hotspotPosition: '0.3m -0.3m 0.3m',
          color: Color(0xFF8BC34A),
        ),
        Topic3DPart(
          id: 'gol',
          name: 'Göl',
          info:
              'Karalar üzerindeki çanaklarda biriken su kütlesi. Tektonik '
              '(Van), volkanik (Nemrut Krater), karstik (Salda), buzul, set '
              'gölleri olabilir.',
          hotspotPosition: '-0.3m -0.5m 0m',
          color: Color(0xFF00BCD4),
        ),
        Topic3DPart(
          id: 'nehir',
          name: 'Nehir',
          info:
              'Bir kaynaktan denize veya göle akan büyük akarsu. Aşındırma, '
              'taşıma ve biriktirme yapar — yer şekillerini değiştirir. '
              'Türkiye\'de Kızılırmak en uzun nehirdir.',
          hotspotPosition: '0m -0.7m 0.4m',
          color: Color(0xFF03A9F4),
        ),
      ],
    ),
  };

  /// Eklenmiş tüm modeller (UI listeleme için).
  static List<Topic3DModel> all() => _models.values.toList(growable: false);

  /// Direkt id ile sorgu (snake_case).
  static Topic3DModel? byId(String id) => _models[id];

  /// Konu adı veya serbest metinden eşleştirme.
  /// "Hücre yapısı" → 'hucre', "Solar system planets" → 'gunes_sistemi'.
  static Topic3DModel? findByKeywords(String input) {
    final n = _normalize(input);
    for (final m in _models.values) {
      if (n.contains(_normalize(m.id)) || n.contains(_normalize(m.name))) {
        return m;
      }
      for (final part in m.parts) {
        if (n.contains(_normalize(part.id)) || n.contains(_normalize(part.name))) {
          return m;
        }
      }
    }
    return _aliasMap[n];
  }

  static const Map<String, String> _aliasIds = {
    'cell': 'hucre',
    'hucre yapisi': 'hucre',
    'solar': 'gunes_sistemi',
    'gezegen': 'gunes_sistemi',
    'planet': 'gunes_sistemi',
    'landform': 'yer_sekilleri',
    'cografya': 'yer_sekilleri',
  };

  static Map<String, Topic3DModel> get _aliasMap => {
        for (final e in _aliasIds.entries) e.key: _models[e.value]!,
      };

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ğ', 'g')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .trim();
}
