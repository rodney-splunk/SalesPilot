// Transcript-boundary heuristics, not a claim of detecting live silence.
export function completedThought(text) {
 const value=String(text||'').trim();
 if(!value)return false;
 if(/\b(?:uh|um|like the|the the)\b.+\bi mean[.,\s]*$/i.test(value))return false;
 if(/(?:--|[—–])\s*$/.test(value)||/\b(?:what|which) kind of[.\s-]*$/i.test(value))return false;
 if(/\b(?:question.{0,50}(?:was|is)|in terms of|the method is|in charge of(?: the)?)[,.…\s]*$/i.test(value))return false;
 return !/\b(?:and|but|because|so that|such as|for example|including|which means|in order to|with the|we need to)[,.…\s]*$/i.test(value);
}
export function currentCoachTurn(turn, latest) { return !!turn && turn.id===latest?.id && completedThought(turn.text); }
