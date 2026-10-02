#!/usr/bin/env python3
"""Speaker diarization sidecar.

Reads one JSON request per line on stdin, writes one JSON response per line on stdout:
  in : {"id":"<turn id>", "wav":"/abs/path.wav", "channel":"mic"|"sys"}
  out: {"id":"...", "cluster":<int|null>, "score":<float>, "reason":"<why null>"}

Design notes
  * The model is loaded ONCE and the process stays resident: a per-turn cold load would cost more
    than the embedding itself and would show up as live latency.
  * It NEVER raises. Every failure path answers with cluster:null and a reason, because a diarizer
    that crashes must degrade to channel-based attribution, not take the call down with it.
  * Clustering is online (no second pass): a call is coached live, so there is no end of stream to
    cluster over. Centroids only absorb a turn we are confident about, so one bad assignment cannot
    drag a speaker's centroid onto someone else's voice.
"""
import sys, json, os, wave

MIN_SEC     = 1.2      # shorter than this and the embedding is mostly noise
RMS_FLOOR   = 0.004    # near-silence: whisper hallucinates here, so can the embedder
MATCH       = 0.65     # cosine at/above which a turn joins an existing speaker
UPDATE      = 0.70     # only fold into a centroid when comfortably above MATCH
MAX_SPEAKERS = 8       # a discovery call has a handful of people, not forty
CENTROID_CAP = 20      # keep adapting, but stop letting turn 200 outvote the first 20

HERE = os.path.dirname(os.path.abspath(__file__))

def reply(**kw):
    sys.stdout.write(json.dumps(kw) + "\n"); sys.stdout.flush()

try:
    import numpy as np
    import sherpa_onnx
    _ex = sherpa_onnx.SpeakerEmbeddingExtractor(
        sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=os.path.join(HERE, "speaker.onnx"), num_threads=2))
except Exception as e:                      # no model, no runtime: stay alive and answer honestly
    _ex = None
    sys.stderr.write(f"[diarize] disabled: {e}\n"); sys.stderr.flush()

clusters = []          # list of {"c": centroid vec, "n": times merged}

def read_wav(path):
    with wave.open(path) as w:
        if w.getsampwidth() != 2:
            raise ValueError("expected 16-bit pcm")
        raw = w.readframes(w.getnframes())
        sr, ch = w.getframerate(), w.getnchannels()
    a = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if ch > 1:                              # the app writes mono, but never trust that
        a = a.reshape(-1, ch).mean(axis=1)
    return a, sr

def embed(a, sr):
    s = _ex.create_stream()
    s.accept_waveform(sr, a)                # sherpa resamples to the model's rate internally
    s.input_finished()
    v = np.array(_ex.compute(s), dtype=np.float32)
    n = float(np.linalg.norm(v))
    if n == 0.0:
        raise ValueError("zero embedding")
    return v / n

def assign(v, allow_new=True, allow_update=True):
    """Nearest centroid above MATCH, else a new speaker. Returns (index, score)."""
    best, best_i, second = -1.0, -1, -1.0
    for i, c in enumerate(clusters):
        s = float(v @ c["c"])
        if s > best:
            second = best
            best, best_i = s, i
        elif s > second:
            second = s
    if best >= MATCH and best - second < 0.08:
        return None, best
    if best >= MATCH:
        c = clusters[best_i]
        if allow_update and best >= UPDATE:                  # confident: let it refine the centroid
            n = min(c["n"] + 1, CENTROID_CAP)
            c["c"] = (c["c"] * (n - 1) + v) / n
            c["c"] /= float(np.linalg.norm(c["c"]))
            c["n"] = n
        return best_i, best
    if not allow_new:
        return None, max(best, 0.0)
    if len(clusters) >= MAX_SPEAKERS:       # cap reached: best effort rather than unbounded growth
        return None, max(best, 0.0)
    clusters.append({"c": v, "anchor": v.copy(), "n": 1})
    return len(clusters) - 1, 1.0

# Second line of defence: if the engine dies without closing our stdin, we are reparented to init.
# A background watchdog notices and exits, so an abandoned sidecar cannot outlive the call.
def _watchdog():
    import time
    while True:
        time.sleep(5)
        if os.getppid() == 1:
            os._exit(0)
try:
    import threading
    threading.Thread(target=_watchdog, daemon=True).start()
except Exception:
    pass

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
    except Exception:
        continue                            # malformed line: skip, never die
    tid = (req or {}).get("id")
    if req.get("cmd") == "reset":
        clusters.clear(); reply(id=tid, ok=True, reason="reset"); continue
    wav = req.get("wav") or ""
    if _ex is None:
        reply(id=tid, cluster=None, score=0.0, reason="disabled"); continue
    try:
        if not os.path.isfile(wav):
            reply(id=tid, cluster=None, score=0.0, reason="no_audio"); continue
        a, sr = read_wav(wav)
        if len(a) < MIN_SEC * sr:
            reply(id=tid, cluster=None, score=0.0, reason="short"); continue
        if float(np.sqrt(np.mean(a * a))) < RMS_FLOOR:
            reply(id=tid, cluster=None, score=0.0, reason="silent"); continue
        # Different confidently known voices inside one transcript turn must not get one name.
        window_clusters = set()
        voice_windows = []
        checked_windows = 0
        uncertain_windows = 0
        # Overlapping windows include the tail, which non-overlapping scans missed.
        # Bound work so a long segment cannot hold the live attribution queue forever.
        if "--legacy" not in sys.argv and len(clusters) >= 2 and len(a) >= 4.8 * sr:
            width = int(2.4 * sr)
            offsets = list(range(0, len(a) - width + 1, int(1.2 * sr)))
            if offsets[-1] != len(a) - width:
                offsets.append(len(a) - width)
            if len(offsets) > 12:
                offsets = [offsets[round(i * (len(offsets) - 1) / 11)] for i in range(12)]
            for offset in offsets:
                chunk = a[offset:offset + width]
                if float(np.sqrt(np.mean(chunk * chunk))) < RMS_FLOOR:
                    continue
                vector = embed(chunk, sr)
                scores = sorted([(float(vector @ c["c"]), i) for i, c in enumerate(clusters)], reverse=True)
                checked_windows += 1
                if scores[0][0] >= MATCH and scores[0][0] - scores[1][0] >= 0.08:
                    window_clusters.add(scores[0][1])
                    voice_windows.append({"start":offset/sr,"end":(offset+width)/sr,"cluster":scores[0][1]})
                else:
                    uncertain_windows += 1
                    voice_windows.append({"start":offset/sr,"end":(offset+width)/sr,"cluster":None})
            if len(window_clusters) > 1:
                reply(id=tid, cluster=None, score=0.0, reason="mixed", mixed=True, windows=voice_windows)
                continue
        # A partly unresolved segment may be labeled using the whole turn, but must
        # never train an established reference voice. A wholly unknown voice must
        # still be allowed to join the call; unresolved known/unknown mixtures cannot.
        clean_segment = not checked_windows or uncertain_windows == 0
        vector = embed(a, sr)
        if "--legacy" not in sys.argv and len(clusters) >= 2:
            anchor_scores = sorted([float(vector @ c["anchor"]) for c in clusters], reverse=True)
            # Updating centroids must not erase competition between the original voices.
            # This also catches a mixture which drifts toward the dominant participant.
            if anchor_scores[1] >= MATCH and anchor_scores[0] - anchor_scores[1] < 0.08:
                reply(id=tid, cluster=None, score=round(anchor_scores[0], 4), reason="ambiguous")
                continue
        idx, score = assign(vector, allow_new=len(a) >= 3.2 * sr and (clean_segment or not window_clusters),
                            allow_update=clean_segment)
        reply(id=tid, cluster=idx, score=round(score, 4), reason="" if idx is not None else "ambiguous")
    except Exception as e:
        reply(id=tid, cluster=None, score=0.0, reason=f"error:{type(e).__name__}")
