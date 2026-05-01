// Unit tests for UsageQuota — daily/monthly counter + soft block.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_nova/services/usage_quota.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UsageQuota.resetAll();
    UsageQuota.limits = QuotaLimits.free;
  });

  test('İlk kullanım — sayaç 0, exhausted değil', () async {
    final usage = await UsageQuota.get(QuotaKind.topicSummary);
    expect(usage.dailyUsed, 0);
    expect(usage.monthlyUsed, 0);
    expect(usage.isExhausted, isFalse);
  });

  test('increment — daily + monthly artar', () async {
    await UsageQuota.increment(QuotaKind.topicSummary);
    await UsageQuota.increment(QuotaKind.topicSummary);
    final usage = await UsageQuota.get(QuotaKind.topicSummary);
    expect(usage.dailyUsed, 2);
    expect(usage.monthlyUsed, 2);
  });

  test('Farklı kind\'lar bağımsız sayaçlar', () async {
    await UsageQuota.increment(QuotaKind.topicSummary);
    await UsageQuota.increment(QuotaKind.testQuestions);
    await UsageQuota.increment(QuotaKind.testQuestions);
    final summary = await UsageQuota.get(QuotaKind.topicSummary);
    final test = await UsageQuota.get(QuotaKind.testQuestions);
    expect(summary.dailyUsed, 1);
    expect(test.dailyUsed, 2);
  });

  test('tryConsume — quota varsa true + artar', () async {
    final ok = await UsageQuota.tryConsume(QuotaKind.solution);
    expect(ok, isTrue);
    final usage = await UsageQuota.get(QuotaKind.solution);
    expect(usage.dailyUsed, 1);
  });

  test('tryConsume — daily limite ulaşınca false döner', () async {
    final dailyLimit =
        QuotaLimits.free.daily[QuotaKind.topicSummary]!; // 20
    for (var i = 0; i < dailyLimit; i++) {
      await UsageQuota.increment(QuotaKind.topicSummary);
    }
    final ok = await UsageQuota.tryConsume(QuotaKind.topicSummary);
    expect(ok, isFalse,
        reason: 'Daily limit dolduğunda tryConsume false dönmeli');
    // Sayaç değişmemeli
    final usage = await UsageQuota.get(QuotaKind.topicSummary);
    expect(usage.dailyUsed, dailyLimit);
  });

  test('tryConsume(force=true) — limit dolu olsa bile artar', () async {
    final dailyLimit =
        QuotaLimits.free.daily[QuotaKind.topicSummary]!;
    for (var i = 0; i < dailyLimit; i++) {
      await UsageQuota.increment(QuotaKind.topicSummary);
    }
    final ok = await UsageQuota.tryConsume(
      QuotaKind.topicSummary,
      force: true,
    );
    expect(ok, isTrue);
    final usage = await UsageQuota.get(QuotaKind.topicSummary);
    expect(usage.dailyUsed, dailyLimit + 1);
  });

  test('reset — tek bir kind sıfırlanır', () async {
    await UsageQuota.increment(QuotaKind.topicSummary);
    await UsageQuota.increment(QuotaKind.testQuestions);
    await UsageQuota.reset(QuotaKind.topicSummary);
    final summary = await UsageQuota.get(QuotaKind.topicSummary);
    final test = await UsageQuota.get(QuotaKind.testQuestions);
    expect(summary.dailyUsed, 0);
    expect(test.dailyUsed, 1);
  });

  test('QuotaUsage helpers — isExhausted, remaining', () {
    const u = QuotaUsage(
      dailyUsed: 18,
      monthlyUsed: 100,
      dailyLimit: 20,
      monthlyLimit: 200,
    );
    expect(u.isDailyExhausted, isFalse);
    expect(u.dailyRemaining, 2);
    expect(u.monthlyRemaining, 100);
    expect(u.isExhausted, isFalse);
  });

  test('QuotaUsage — daily exhausted ama monthly değil', () {
    const u = QuotaUsage(
      dailyUsed: 20,
      monthlyUsed: 50,
      dailyLimit: 20,
      monthlyLimit: 200,
    );
    expect(u.isDailyExhausted, isTrue);
    expect(u.isExhausted, isTrue);
    expect(u.dailyRemaining, 0);
  });

  test('Premium limits — daha yüksek', () {
    expect(QuotaLimits.premium.daily[QuotaKind.topicSummary]!,
        greaterThan(QuotaLimits.free.daily[QuotaKind.topicSummary]!));
  });
}
