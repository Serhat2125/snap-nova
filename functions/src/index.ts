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
// İleride: export { onLeagueAttemptCreated } from "./league_aggregate";
