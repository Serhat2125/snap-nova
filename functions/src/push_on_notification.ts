/**
 * push_on_notification — notifications/{uid}/items/{nid} koleksiyonuna
 * yeni doc yazılınca FCM push gönderir.
 *
 * Akış:
 *   1. Yeni notification doc oluşur (örn. arkadaşlık isteği, düello daveti).
 *   2. Trigger: hedef uid'nin fcmTokens alt koleksiyonundan tüm token'ları çek.
 *   3. Tüm token'lara multicast push gönder (title/body type'a göre üretilir).
 *   4. Geçersiz/inactive token'lar (FCM not-registered hatası dönen) silinir.
 *
 * Bağımlılık:
 *   • firebase-functions v2 onDocumentCreated
 *   • firebase-admin messaging
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging, MulticastMessage } from "firebase-admin/messaging";

interface NotifData {
  type?: string;
  fromUid?: string;
  fromUsername?: string;
  fromDisplayName?: string;
  targetUsername?: string;
  subjectKey?: string;
  subjectName?: string;
  topic?: string;
  // Grup yarışı daveti — tıklamada yarışmayı doğrudan açmak için.
  contestId?: string;
  groupId?: string;
  milestone?: string;
  rewardDays?: number;
  // Öğretmen paneli bildirimleri (homework_service.dart / class_service.dart)
  homeworkTitle?: string;
  className?: string;
  message?: string;
  subject?: string;
  // Dinamik bildirimler (örn. haftalık ebeveyn özeti) title/body'yi doc'a
  // doğrudan yazar; buildContent bunları olduğu gibi kullanır.
  title?: string;
  body?: string;
  // homework_assigned: öğretmen adı + ders + konu (kişisel bildirim metni).
  teacherName?: string;
}

/**
 * Bildirim türünü, kullanıcı ayarlarındaki kategori anahtarına eşler.
 * (Bkz. PreferencesSyncService._notifKeys + bildirim ayarları sheet'i.)
 * null dönerse → kategorisiz/sistem bildirimi, her zaman gönderilir.
 */
function categoryForType(type?: string): string | null {
  switch (type) {
    case "friend_request":
    case "friend_accepted":
    case "referral_joined":
    case "referral_complete":
      return "friend_request";
    case "duelo_invite":
      return "duello_invite";
    case "rank_passed":
      return "league_update";
    case "streak_milestone":
      return "streak_alert";
    // ── Pazarlama kategorileri — ileride kampanya push'u eklenirse toggle'lar
    //    gate'lesin diye eşleme hazır (şu an aktif gönderen yok). ──
    case "premium_offer":
      return "premium_offer";
    case "newsletter":
      return "newsletter";
    // ── Öğretmen kategorileri (panel ayarındaki toggle'ları gerçekten gate'le) ──
    case "homework_submission": // öğrenci ödevi teslim etti → öğretmene
      return "homework_submission";
    case "student_joined": // yeni öğrenci sınıfa katıldı → öğretmene
    case "student_join_request": // kodla katılma isteği (onay bekliyor) → öğretmene
      return "student_joined";
    case "class_activity":
    case "class_announcement":
    case "announcement":
    case "homework_published":
    case "homework_all_done":
    case "homework_graded":
    case "material":
      return "class_activity";
    case "homework_assigned":
    case "homework_reminder":
    case "class_invite":
    case "class_join_approved":
    case "class_join_rejected":
    case "homework_answers_shared":
      return "class_activity";
    default:
      return null;
  }
}

function buildContent(data: NotifData): { title: string; body: string } {
  // Doc'a doğrudan yazılmış dinamik metin varsa onu kullan.
  if (data.title && data.body) {
    return { title: data.title, body: data.body };
  }
  const who = data.fromDisplayName || data.fromUsername || "Birisi";
  // İsim + @kullanıcıadı birlikte — alıcı kimin yazdığını NET görsün.
  // displayName username ile aynıysa (eski kayıtlar) tekrar yazma.
  const whoFull =
    data.fromUsername && who !== data.fromUsername
      ? `${who} (${data.fromUsername})`
      : who;
  switch (data.type) {
    case "friend_request":
      return {
        title: "Yeni arkadaşlık isteği",
        body: `${whoFull} sana arkadaşlık isteği gönderdi`,
      };
    case "friend_accepted":
      return {
        title: "İsteğin kabul edildi",
        body: `${whoFull} arkadaşlık isteğini kabul etti`,
      };
    case "duelo_invite": {
      // Davet ders+konu taşır — alıcı neyde yarışacağını push'tan görsün.
      const st = [data.subjectKey, data.topic].filter(Boolean).join(" • ");
      return {
        title: "Düello daveti ⚔️",
        body: st
          ? `${whoFull} seninle "${st}" konusunda yarışmak istiyor — kabul et, aynı sorular ikinize aynı anda gelsin`
          : `${whoFull} seninle yarışmak istiyor`,
      };
    }
    case "rank_passed":
      return {
        title: "Sıralamada geçildin",
        body: `${who} seni sıralamada geçti — geri al!`,
      };
    case "streak_milestone":
      return {
        title: "Streak ödülü",
        body: `Üst üste günlerin yeni rekor`,
      };
    case "referral_joined": {
      const progress = data.subjectKey || "";
      return {
        title: "Arkadaşın QuAlsar'a katıldı!",
        body: `Davet hedefin: ${progress} — devam et!`,
      };
    }
    case "referral_complete":
      return {
        title: "Tebrikler! 30 gün Premium kazandın",
        body: "3 arkadaşını davet ettin — Premium ödülün aktif!",
      };
    case "group_contest_invite": {
      const t = [data.subjectName, data.topic].filter(Boolean).join(" • ");
      return {
        title: "Grup yarışı daveti 🏆",
        body: t
          ? `${who} seni "${t}" yarışına davet etti`
          : `${who} seni grup yarışına davet etti`,
      };
    }
    // ── Öğretmen paneli — client-side notifications_inbox_screen.dart
    //    _titleFor/_subtitleFor ile aynı metinler. ──
    // NOT: homework_assigned/homework_reminder yazımında hw başlığı
    // 'fromDisplayName' alanına konuyor (homeworkTitle DEĞİL) — bkz.
    // homework_service.dart assignHomework/checkPendingReminders.
    case "homework_assigned": {
      // "Ayşe Yılmaz öğretmenin Fizik dersinden 'Dalgalar' konulu yeni bir
      // ödev gönderdi — başarılar!" Eski kayıtlarda (alanlar yoksa) genel metin.
      const tName = (data.teacherName || "").trim();
      const subj = (data.subject || "").trim();
      const top = (data.topic || "").trim();
      const hwTitle = data.homeworkTitle || data.fromDisplayName || "";
      if (tName || subj || top) {
        const body = [
          tName ? `${tName} öğretmenin` : "Öğretmenin",
          subj ? `${subj} dersinden` : "",
          top ? `"${top}" konulu` : "",
          "yeni bir ödev gönderdi — başarılar! 🍀",
        ].filter(Boolean).join(" ");
        return { title: `Yeni ödev 📚: ${hwTitle}`, body };
      }
      return {
        title: "Yeni ödev",
        body: `Sınıfa yeni ödev geldi: ${who}`,
      };
    }
    case "homework_reminder":
      return {
        title: "Ödev hatırlatma",
        body: `${who} — bitişine 2 saatten az kaldı`,
      };
    case "class_invite":
      return {
        title: `Sınıf daveti: ${data.className || ""}`,
        body: `${who} seni ${data.subject || data.className || ""} dersine davet etti`,
      };
    case "class_announcement":
      return {
        title: `Duyuru: ${data.className || ""}`,
        body: data.message || `${who} yeni bir duyuru paylaştı`,
      };
    case "homework_submission": {
      // "Zeynep (zeynep123), 'Dalgalar' konulu 'kolay odev' ödevini teslim etti"
      const subTopic = (data.topic || "").trim();
      return {
        title: "Ödev teslim edildi",
        body: subTopic
          ? `${whoFull}, "${subTopic}" konulu "${data.homeworkTitle || ""}" ödevini teslim etti`
          : `${whoFull}, "${data.homeworkTitle || ""}" ödevini teslim etti`,
      };
    }
    case "student_joined":
      return {
        title: "Yeni öğrenci",
        body: `${data.className || ""} sınıfından ${whoFull} katıldı`,
      };
    case "student_join_request":
      // Ad Soyad (kullanıcıadı) — öğretmen kimin katılmak istediğini push'tan
      // görsün; kod yabancının eline geçtiyse tanımadığını reddedebilsin.
      return {
        title: "Katılma isteği",
        body: `${whoFull} "${data.className || ""}" sınıfına katılmak istiyor — onayla`,
      };
    case "class_join_approved":
      return {
        title: "Sınıfa kabul edildin 🎉",
        body: `"${data.className || ""}" sınıfına katılımın onaylandı — ödevlerini gör`,
      };
    case "class_join_rejected":
      return {
        title: "Katılma isteğin onaylanmadı",
        body: `"${data.className || ""}" sınıfına katılma isteğin reddedildi`,
      };
    case "parent_link_request":
      return {
        title: "Ebeveyn bağlantı isteği",
        body: `${who} senin için izin istedi — Profil sekmesinden onaylayabilirsin`,
      };
    case "parent_message":
      return {
        title: `Ebeveyn mesajı: ${data.className || ""}`,
        body: data.message
          ? `${who} adlı öğrencinin ebeveyni: "${data.message}"`
          : `${who} adlı öğrencinin ebeveyninden mesajın var`,
      };
    case "homework_published":
      return {
        title: "Ödev yayınlandı",
        body: `"${data.homeworkTitle || ""}" ödevin ${data.className || ""} sınıfında yayınlandı`,
      };
    case "homework_all_done":
      return {
        title: "Herkes ödevini bitirdi 🎉",
        body: `${data.className || ""} sınıfındaki tüm öğrenciler "${data.homeworkTitle || ""}" ödevini tamamladı`,
      };
    case "homework_graded":
      return {
        title: "Ödevin değerlendirildi",
        body: `"${data.homeworkTitle || ""}" ödevin notlandırıldı — sonucunu görmek için dokun`,
      };
    case "homework_answers_shared":
      return {
        title: "Cevaplar paylaşıldı 🔑",
        body: `"${data.homeworkTitle || ""}" ödevinin cevapları ve çözümleri açıldı — incele`,
      };
    default:
      return {
        title: "QuAlsar",
        body: "Yeni bir bildirimin var",
      };
  }
}

export const pushOnNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{uid}/items/{nid}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("notification doc snap yok");
      return;
    }
    const uid = event.params.uid;
    const data = snap.data() as NotifData;
    const db = getFirestore();

    // 0) Kullanıcının bildirim tercihlerini oku — kapalı kategoriye veya
    //    ana anahtar kapalıyken HİÇ push gönderme. (İn-app inbox doc'u yine
    //    durur; sadece push pop-up bastırılır.) Tercih okunamazsa gönder.
    try {
      const prefSnap = await db
        .collection("users")
        .doc(uid)
        .collection("preferences")
        .doc("main")
        .get();
      const prefData = prefSnap.data();
      const notif =
        (prefData?.notifications as Record<string, boolean>) || {};
      if (notif.master === false) {
        logger.info(`[push] master kapalı uid=${uid} — atlandı`);
        return;
      }
      const cat = categoryForType(data.type);
      if (cat) {
        // Pref hiç yazılmamışsa kategori varsayılanına düş — pazarlama
        // kategorileri (premium_offer/newsletter) varsayılan KAPALI.
        const defaultOn = cat !== "premium_offer" && cat !== "newsletter";
        const allowed = notif[cat] ?? defaultOn;
        if (!allowed) {
          logger.info(`[push] '${cat}' kategorisi kapalı uid=${uid} — atlandı`);
          return;
        }
      }
      // Sessiz Saatler — client PreferencesSyncService 'quiet' alanını yazar.
      // Kullanıcının YEREL saati tzOffsetMin ile hesaplanır; pencere içindeyse
      // push gönderilmez ("bu aralıkta hiç bildirim gelmez" sözü).
      const quiet = prefData?.quiet as
        | { enabled?: boolean; startMin?: number; endMin?: number;
            tzOffsetMin?: number }
        | undefined;
      if (quiet?.enabled === true) {
        const start = Number(quiet.startMin ?? 23 * 60);
        const end = Number(quiet.endMin ?? 7 * 60);
        const off = Number(quiet.tzOffsetMin ?? 0);
        const localMin =
          ((Math.floor(Date.now() / 60000) + off) % 1440 + 1440) % 1440;
        const inQuiet = start === end
          ? false
          : start < end
            ? localMin >= start && localMin < end
            : localMin >= start || localMin < end;
        if (inQuiet) {
          logger.info(`[push] sessiz saatler uid=${uid} — atlandı`);
          return;
        }
      }
    } catch (e) {
      logger.warn("[push] tercih okunamadı, yine de gönderiliyor", e);
    }

    // 1) Hedefin fcmTokens'larını çek
    const tokensSnap = await db
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .get();

    if (tokensSnap.empty) {
      logger.info(`[push] no tokens for uid=${uid}`);
      return;
    }

    const tokens = tokensSnap.docs.map((d) => d.id);
    const { title, body } = buildContent(data);

    // 2) Multicast push gönder
    const message: MulticastMessage = {
      tokens,
      notification: { title, body },
      data: {
        type: data.type || "unknown",
        fromUid: data.fromUid || "",
        fromUsername: data.fromUsername || "",
        targetUsername: data.targetUsername || "",
        // Grup yarışı daveti: tıklamada yarışmanın DOĞRUDAN açılabilmesi
        // için hedef id'ler payload'a eklenir (main.dart onTap yönlendirir).
        contestId: data.contestId || "",
        groupId: data.groupId || "",
        nid: event.params.nid,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "qualsar_default",
          // Tek renk QuAlsar silüeti (res/drawable/ic_notification) + marka
          // yeşili boyama — renkli launcher ikonu gri kare görünüyordu.
          icon: "ic_notification",
          color: "#00DC3C",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const res = await getMessaging().sendEachForMulticast(message);
      logger.info(
        `[push] uid=${uid} sent=${res.successCount}/${tokens.length}`
      );

      // 3) Geçersiz token'ları temizle
      const toDelete: Promise<unknown>[] = [];
      res.responses.forEach((r, i) => {
        if (!r.success) {
          const err = r.error?.code || "";
          if (
            err === "messaging/invalid-registration-token" ||
            err === "messaging/registration-token-not-registered"
          ) {
            toDelete.push(
              db
                .collection("users")
                .doc(uid)
                .collection("fcmTokens")
                .doc(tokens[i])
                .delete()
            );
          }
        }
      });
      if (toDelete.length > 0) {
        await Promise.allSettled(toDelete);
        logger.info(`[push] cleaned ${toDelete.length} stale tokens`);
      }
    } catch (e) {
      logger.error("[push] send fail", e);
    }

    // 4) Bildirim doc'una "pushed" işareti — debug ve analytics için
    try {
      await snap.ref.update({ pushedAt: FieldValue.serverTimestamp() });
    } catch (_) {/* yok say */}
  }
);
