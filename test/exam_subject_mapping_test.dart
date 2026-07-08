// Evrensel sınav→ders eşleyici testleri — onboarding'in 130+ ülkelik sınav
// listelerinden gerçek adlarla: her sınav adı DOLU bir ders seti üretmeli,
// meslek sınavları doğru kategoriye düşmeli.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/services/education_profile.dart';

void main() {
  test('dünyadaki her sınav adı dolu ders listesi üretir', () {
    // Onboarding _examsByCountry'den gerçek örnekler — her alfabe/dil.
    const worldExams = [
      // Türkiye
      'YKS (Yükseköğretim Kurumları Sınavı)', 'LGS (Liselere Geçiş Sınavı)',
      'TUS (Tıpta Uzmanlık Sınavı)', 'DUS (Diş Hekimliğinde Uzmanlık Sınavı)',
      'EUS (Eczacılıkta Uzmanlık Sınavı)', 'KPSS ÖABT', 'SMMM Sınavları',
      // Avrupa
      'Abitur', 'Baccalauréat', 'Esame di Maturità', 'EBAU / Selectividad',
      'Matura', 'Érettségi', 'Bacalaureat', 'Højskoleprovet',
      'Ylioppilastutkinto', 'Πανελλαδικές Εξετάσεις', 'Státna Maturita',
      // Amerika
      'SAT', 'ACT', 'ENEM', 'Vestibular FUVEST', 'ICFES Saber 11',
      'PAES (Prueba de Acceso)', 'EXANI-II',
      // Asya / Afrika / Orta Doğu
      'ЕГЭ (Единый госэкзамен)', '高考 Gaokao', '수능 (Suneung / CSAT)',
      'UTBK-SNBT', 'HSC', 'JAMB UTME', 'WASSCE', 'KCSE',
      'الثانوية العامة', 'التوجيهي (Tawjihi)', 'کنکور سراسری (Konkur)',
      'ҰБТ (UNT)', 'HKDSE', '學測 GSAT', 'בגרות (Bagrut)',
      'Kỳ thi tốt nghiệp THPT', 'TGAT', 'SPM', 'GCE A-Level', 'GCE O-Level',
      // Meslek sınavları
      'MIR (Médicos)', 'Residência Médica', 'ENARM (Médico)',
      'Квалификационный экзамен врачей', '의사국가시험', 'Лікарський іспит',
      'Atestační zkouška (Lékaři)', 'Internat Médecine', 'UCAT ANZ',
      'OAB (Direito)', 'Bar Examination', 'Адвокатский экзамен',
      '변호사시험 (Bar)', 'Pravosudni ispit', 'نقابة المحامين الأردنيين',
      "Examen d'avocat", 'Provimi i Jurispudencës',
      'CPA Board', 'SAICA Board (CA)', '注册会计师 CICPA', 'CA Pakistan',
      '公务员考试', '국가공무원 5급', 'CPNS', 'Oposiciones (Profesorado)',
      'IELTS / TOEFL', 'DELE (Español)', 'TestDaF / DSH (Deutsch)',
      '考研 Kaoyan (研究生入学)', 'Аспирантура (вступительные)',
      'Dottorato (concorso)', 'GMAT / GRE',
    ];
    for (final exam in worldExams) {
      final keys = examSubjectKeysForGrade(exam);
      expect(keys, isNotNull, reason: 'null döndü: $exam');
      expect(keys, isNotEmpty, reason: 'boş döndü: $exam');
    }
  });

  test('meslek sınavları doğru kategoriye düşer', () {
    // Tıp → anatomi içermeli
    for (final e in [
      'MIR (Médicos)', 'Квалификационный экзамен врачей', '의사국가시험',
      'Residência Médica', 'TUS (Tıpta Uzmanlık Sınavı)',
    ]) {
      expect(examSubjectKeysForGrade(e), contains('anatomi'), reason: e);
    }
    // Hukuk → anayasa içermeli
    for (final e in [
      'OAB (Direito)', 'Адвокатский экзамен', '변호사시험 (Bar)',
      'Bar Examination', 'Pravosudni ispit',
    ]) {
      expect(examSubjectKeysForGrade(e), contains('anayasa'), reason: e);
    }
    // Muhasebe → muhasebe içermeli
    for (final e in ['CPA Board', '注册会计师 CICPA', 'CA Pakistan']) {
      expect(examSubjectKeysForGrade(e), contains('muhasebe'), reason: e);
    }
    // Dil → ingilizce içermeli
    for (final e in ['IELTS / TOEFL', 'DELE (Español)']) {
      expect(examSubjectKeysForGrade(e), contains('ingilizce'), reason: e);
    }
    // DUS diş odaklı, TUS klinik tıp odaklı — ayrıştılar
    expect(examSubjectKeysForGrade('DUS (Diş Hekimliğinde Uzmanlık Sınavı)'),
        contains('restoratif'));
    expect(examSubjectKeysForGrade('EUS (Eczacılıkta Uzmanlık Sınavı)'),
        contains('farmakognozi'));
    // Bilinmeyen yerel ad → üniversite giriş jenerik seti (asla boş değil)
    expect(examSubjectKeysForGrade('Tamamen Bilinmeyen Yerel Sınav'),
        contains('math'));
  });
}
