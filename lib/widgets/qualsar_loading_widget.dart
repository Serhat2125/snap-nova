// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsarLoadingWidget — Tüm yükleme süreçleri için tek standart loader.
//
//  3 boyutta evrensel:
//  • Görsel kimlik: Logo + dönen disk birlikte (yakın aralık), küçük puntolu
//    gri metin, mavi tik ile aşama tamamlama, en altta motivasyon cümlesi.
//  • Konu alanı (KonuAlani): Sayısal → matematik/fizik/kimya sembolleri akışı;
//    Sözel → kitap, kalem, dünya, sütun gibi ikonografik semboller akışı.
//  • İşlem türü (IslemTuru): summary / solution / test / contest — her biri
//    konu adına yedirilen 3 aşama metni.
//
//  Aşağıdaki QuAlsarNumericLoader zaten görsel altyapıyı sağlıyor; bu widget
//  yalnızca "hangi tip + hangi alan + hangi konu" eşlemesini yönetir ve
//  uygun aşama listesini + sembol varyantını seçer.
//
//  Kullanım:
//    QuAlsarLoadingWidget(type: solution, domain: SubjectDomain.verbal,
//                         topic: 'Tarih')
//    QuAlsarLoadingWidget(type: summary, domain: SubjectDomain.numeric,
//                         topic: 'Türev')
//    QuAlsarLoadingWidget(type: contest, domain: SubjectDomain.numeric)
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../services/runtime_translator.dart';
import 'qualsar_numeric_loader.dart';

/// İşlem türü — hangi sürecin yükleniyor olduğunu belirtir.
enum QuAlsarLoadingType {
  /// Konu özeti üretimi.
  summary,

  /// Soru çözümü (fotoğraftan veya elle).
  solution,

  /// Test/sınav sorusu üretimi.
  test,

  /// Yarışma başlatma (arena giriş hazırlığı).
  contest,
}

/// Konu alanı — sembol akışını ve görsel kimliği belirler.
/// • numeric: matematik/fizik/kimya/biyoloji sembolleri (+, −, √, π, ∫, atom).
/// • verbal: edebiyat/tarih/coğrafya/felsefe ikonları (📖, 🖋️, 🌍, 🏛️).
enum SubjectDomain { numeric, verbal }

class QuAlsarLoadingWidget extends StatelessWidget {
  /// İşlem türü — aşama metinlerini belirler.
  final QuAlsarLoadingType type;

  /// Konu adı (Türev, Mitokondri, Tarih...). Boşsa anlam bozulmasın diye
  /// jenerik fallback metni kullanılır ("Sorunuz analiz ediliyor" gibi).
  final String topic;

  /// Konu alanı (Sayısal/Sözel) — sembol akışını ayarlar.
  final SubjectDomain domain;

  /// Aşamalar arası gecikme — varsayılan 3 sn (kullanıcı talebine uygun).
  final Duration stageInterval;

  const QuAlsarLoadingWidget({
    super.key,
    required this.type,
    this.topic = '',
    this.domain = SubjectDomain.numeric,
    this.stageInterval = const Duration(seconds: 3),
  });

  /// Verilen tip + konu için 3-aşamalı metin listesi üretir.
  /// Konu boşsa placeholder atlanır.
  static List<String> stagesFor(QuAlsarLoadingType type, String topic) {
    final t = topic.trim();
    switch (type) {
      case QuAlsarLoadingType.summary:
        return [
          t.isEmpty
              ? 'Konunuz analiz ediliyor'.tr()
              : '$t ${'konusu analiz ediliyor'.tr()}',
          'Konunuzun özeti oluşturuluyor'.tr(),
          'Özetiniz neredeyse hazır'.tr(),
        ];
      case QuAlsarLoadingType.solution:
        return [
          t.isEmpty
              ? 'Sorunuz analiz ediliyor'.tr()
              : '$t ${'sorusu analiz ediliyor'.tr()}',
          'Çözüm adımları yapılandırılıyor'.tr(),
          'Çözümün neredeyse hazır'.tr(),
        ];
      case QuAlsarLoadingType.test:
        return [
          t.isEmpty
              ? 'Konu içeriği taranıyor'.tr()
              : '$t ${'içeriği taranıyor'.tr()}',
          'Kaliteli sorular ve şıklar üretiliyor'.tr(),
          'Testiniz neredeyse hazır'.tr(),
        ];
      case QuAlsarLoadingType.contest:
        return [
          t.isEmpty
              ? 'Yarışma alanı hazırlanıyor'.tr()
              : '$t ${'arenası hazırlanıyor'.tr()}',
          'Sorular ve rakipler eşleştiriliyor'.tr(),
          'Yarışma başlamak üzere'.tr(),
        ];
    }
  }

  /// SubjectDomain → QuAlsarLoaderVariant — alttaki numeric/verbal sembol
  /// havuzunu seçer.
  static QuAlsarLoaderVariant variantFor(SubjectDomain d) =>
      d == SubjectDomain.verbal
          ? QuAlsarLoaderVariant.verbal
          : QuAlsarLoaderVariant.numeric;

  @override
  Widget build(BuildContext context) {
    return QuAlsarNumericLoader(
      stages: stagesFor(type, topic),
      variant: variantFor(domain),
      stageInterval: stageInterval,
    );
  }
}
