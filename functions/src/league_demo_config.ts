/**
 * league_demo_config — Bilgi Ligi demo dolgusunun uzaktan kontrolü.
 *
 * KARAR (2026-07-10): Demo öğrenci dolgusu, gerçek kullanıcı tabanı
 * 10.000 kişiye ulaşana kadar AÇIK kalır; eşik aşılınca APK güncellemesi
 * GEREKMEDEN arka planda kapatılır.
 *
 * Mekanizma:
 *   • Bu scheduled function her gece users koleksiyonunu aggregate count()
 *     ile sayar.
 *   • Eşik (10.000) aşıldıysa app_config/league.demoEnabled=false yazar.
 *   • İstemci (LeagueDemoStudents.refreshEnabledFromCloud) bu dokümanı
 *     Bilgi Ligi açılışında okur; doküman yoksa varsayılan AÇIK.
 *   • Manuel müdahale her zaman mümkün: Console'dan demoEnabled elle
 *     değiştirilebilir; function yalnızca false'a ÇEKER, asla geri açmaz
 *     (elle kapatılmışsa eşik altında bile açmaz).
 *
 * Firestore rules: app_config okuma herkese açık, yazma admin-only.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

/** Demo dolgunun otomatik kapanacağı gerçek kullanıcı eşiği. */
const DEMO_OFF_USER_THRESHOLD = 10000;

export const autoDisableLeagueDemo = onSchedule(
  {
    schedule: "30 3 * * *", // her gece 03:30 (Europe/Istanbul)
    timeZone: "Europe/Istanbul",
    region: "us-central1",
    memory: "256MiB",
  },
  async () => {
    const db = getFirestore();
    const cfgRef = db.collection("app_config").doc("league");

    const cfgSnap = await cfgRef.get();
    const demoEnabled = cfgSnap.data()?.demoEnabled;
    if (demoEnabled === false) {
      // Zaten kapalı (otomatik veya elle) — sayım yapmaya gerek yok.
      return;
    }

    const agg = await db.collection("users").count().get();
    const userCount = agg.data().count;
    logger.info(`[leagueDemo] userCount=${userCount} threshold=${DEMO_OFF_USER_THRESHOLD}`);

    if (userCount >= DEMO_OFF_USER_THRESHOLD) {
      await cfgRef.set(
        {
          demoEnabled: false,
          demoAutoDisabledAt: FieldValue.serverTimestamp(),
          demoAutoDisabledUserCount: userCount,
        },
        { merge: true }
      );
      logger.info("[leagueDemo] eşik aşıldı — demo dolgu kapatıldı");
    } else {
      // Gözlemlenebilirlik: son sayım dokümanda dursun (yoksa oluştur).
      await cfgRef.set(
        {
          demoEnabled: true,
          demoLastUserCount: userCount,
          demoLastCheckAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  }
);
