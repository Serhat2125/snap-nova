/**
 * QuAlsar Cloud Functions — Entry point.
 * Tüm exported function'lar buradan re-export edilir.
 */

import { initializeApp, getApps } from "firebase-admin/app";

// Admin SDK'yı bir kez initialize et (hot-reload duplikatına karşı guard).
if (getApps().length === 0) {
  initializeApp();
}

export { geminiProxy } from "./gemini_proxy";
export { aiProxy } from "./ai_proxy";
export {
  onSummaryCandidateCreated,
  triggerSummaryJudge,
} from "./summary_judge";
export {
  onQuestionPoolCreated,
  scheduledPoolFill,
  triggerPoolBatch,
  refreshOldPools,
} from "./question_pool_generator";
export {
  onQuestionInserted,
  rejudgeUnchecked,
} from "./question_judge";
export { pushOnNotificationCreated } from "./push_on_notification";
export { pushOnTeacherNote } from "./push_on_teacher_note";
export {
  fanoutChildNotifToParents,
  notifyParentsOnSubmission,
} from "./parent_fanout";
export { weeklyParentSummary } from "./weekly_parent_summary";
export { publishScheduledHomeworks } from "./publish_scheduled_homeworks";
export { publishScheduledAnnouncements } from "./publish_scheduled_announcements";
export { pushOnRankPassed } from "./rank_passed";
export { onDueloInviteAccepted } from "./duelo_invite_accepted";
export { onReferralCompleted } from "./referral_reward";
export { deleteAccount } from "./delete_account";
export { verifyPurchase } from "./verify_purchase";
export { rtdnWebhook } from "./rtdn_webhook";
