"""Streaming Sortformer host for ONNX graphs, ported from FluidAudio 0.17.5 (the version the app pins) so an ONNX
model sees exactly what the app's Core ML model sees (#160).

- `MelFrontend`        = AudioMelSpectrogram (NeMo-style: preemphasis 0.97, symmetric Hann 400 in a 512 FFT, hop 160,
                         128 Slaney mels, log(x + 2^-24), no normalisation). Streaming emits a frame only once its
                         window is covered, so frames don't depend on how audio is batched.
- `StreamingSortformer` = SortformerDiarizer's streaming path + LiveDiarizer's merge (finalized segments kept,
                         tentative replaced every update). Chunks: 6 frames core, 1 left, 7 right (fastV2_1).
- `StateUpdater`       = SortformerStateUpdater: FIFO, speaker cache, silence profile, Arrival-Order cache compression.
- `Timeline`           = DiarizerTimeline.updateSegments with `.sortformerDefault` (0.5 thresholds, no padding).

The model is any callable `(chunk[L,128], spkcache[n,512], fifo[m,512]) -> (preds[n+m+T, S], chunk_embs[T,512])`.
"""
from __future__ import annotations

import copy
import math
from dataclasses import dataclass, field

import numpy as np

from .live_path import Seg


@dataclass(frozen=True)
class Config:
    num_speakers: int = 4
    chunk_len: int = 6
    chunk_left_context: int = 1
    chunk_right_context: int = 7
    fifo_len: int = 40
    spkcache_len: int = 188
    spkcache_update_period: int = 31
    sil_frames_per_spk: int = 3
    subsampling: int = 8
    emb_dim: int = 512
    silence_threshold: float = 0.2
    pred_score_threshold: float = 0.25
    scores_boost_latest: float = 0.05
    strong_boost_rate: float = 0.75
    weak_boost_rate: float = 1.5
    min_pos_scores_rate: float = 0.5
    onset: float = 0.5
    offset: float = 0.5
    frame_seconds: float = 0.08


# ---- mel ---------------------------------------------------------------------------------------------------------

N_FFT, WIN, HOP, N_MELS, SR, PREEMPH = 512, 400, 160, 128, 16000, 0.97
LOG_FLOOR = 2.0 ** -24


def available_mel_frames(received: int) -> int:
    """Frames whose window [k*160-200, k*160+200) is covered by `received` samples."""
    return 0 if received < WIN // 2 else (received - WIN // 2) // HOP + 1


def _slaney_filterbank() -> tuple[np.ndarray, np.ndarray]:
    f_sp, min_log_hz = 200.0 / 3.0, 1000.0
    min_log_mel, log_step = min_log_hz / f_sp, math.log(6.4) / 27.0

    def hz_to_mel(hz):
        return min_log_mel + math.log(hz / min_log_hz) / log_step if hz >= min_log_hz else hz / f_sp

    def mel_to_hz(m):
        return min_log_hz * math.exp(log_step * (m - min_log_mel)) if m >= min_log_mel else f_sp * m

    lo, hi = hz_to_mel(0.0), hz_to_mel(SR / 2)
    pts = np.array([mel_to_hz(lo + i * (hi - lo) / (N_MELS + 1)) for i in range(N_MELS + 2)])
    freqs = np.arange(N_FFT // 2 + 1) * SR / N_FFT
    fb = np.zeros((N_MELS, N_FFT // 2 + 1))
    for m in range(N_MELS):
        l, c, r = pts[m], pts[m + 1], pts[m + 2]
        norm = 2.0 / (r - l)
        rise = (freqs >= l) & (freqs < c)
        fall = (freqs >= c) & (freqs <= r)
        fb[m, rise] = norm * (freqs[rise] - l) / (c - l)
        fb[m, fall] = norm * (r - freqs[fall]) / (r - c)
    return fb, pts[1:-1]


class MelFrontend:
    def __init__(self):
        self.window = 0.5 * (1 - np.cos(2 * np.pi * np.arange(WIN) / (WIN - 1)))   # symmetric, as NeMo
        self.fb, self.center_hz = _slaney_filterbank()

    def frames(self, y: np.ndarray, count: int, block: int = 4096) -> np.ndarray:
        """Mel frames j = 0..count-1 of preemphasised samples `y`, frame j windowing y[j*160 : j*160+400]."""
        out = np.empty((count, N_MELS), np.float32)
        view = np.lib.stride_tricks.sliding_window_view(y, WIN)[::HOP]
        for a in range(0, count, block):
            b = min(count, a + block)
            spec = np.fft.rfft(view[a:b] * self.window, n=N_FFT)
            power = spec.real ** 2 + spec.imag ** 2
            out[a:b] = np.log(power @ self.fb.T + LOG_FLOOR)
        return out

    def __call__(self, x: np.ndarray) -> np.ndarray:
        """Batch (center-padded) mel of a whole recording: what streaming plus the end-of-session pad produces."""
        y = np.empty(len(x), np.float64)
        y[0] = x[0]
        y[1:] = x[1:] - PREEMPH * x[:-1].astype(np.float64)
        count = 1 + (len(x) + N_FFT - WIN) // HOP
        padded = np.concatenate([np.zeros(WIN // 2), y, np.zeros(N_FFT)])
        return self.frames(padded, count)


# ---- state update (Arrival-Order Speaker Cache) ------------------------------------------------------------------

@dataclass
class State:
    spkcache: np.ndarray
    fifo: np.ndarray
    mean_silence: np.ndarray
    spkcache_preds: np.ndarray | None = None
    fifo_preds: np.ndarray | None = None
    silence_count: int = 0


class StateUpdater:
    def __init__(self, cfg: Config):
        self.cfg = cfg

    def new_state(self) -> State:
        d, s = self.cfg.emb_dim, self.cfg.num_speakers
        return State(spkcache=np.zeros((0, d), np.float32), fifo=np.zeros((0, d), np.float32),
                     mean_silence=np.zeros(d, np.float32))

    def update(self, st: State, chunk_embs: np.ndarray, preds: np.ndarray, lc: int, rc: int):
        c = self.cfg
        sc_len, ff_len = len(st.spkcache), len(st.fifo)
        if ff_len > 0:
            st.fifo_preds = preds[sc_len:sc_len + ff_len].copy()
        core = len(chunk_embs) - lc - rc
        embs = chunk_embs[lc:lc + core]
        start = sc_len + ff_len + lc
        if start + core + rc > len(preds):
            raise ValueError(f"model gave {len(preds)} prediction frames, need {start + core + rc}")
        confirmed, tentative = preds[start:start + core].copy(), preds[start + core:start + core + rc].copy()
        st.fifo = np.vstack([st.fifo, embs])
        st.fifo_preds = confirmed.copy() if st.fifo_preds is None else np.vstack([st.fifo_preds, confirmed])
        context = core + ff_len
        if context > c.fifo_len:
            pop = min(max(c.spkcache_update_period, context - c.fifo_len), context)
            pop_embs, pop_preds = st.fifo[:pop], st.fifo_preds[:pop]
            self.update_silence(st, pop_embs, pop_preds)
            st.fifo, st.fifo_preds = st.fifo[pop:], st.fifo_preds[pop:]
            st.spkcache = np.vstack([st.spkcache, pop_embs])
            if st.spkcache_preds is not None:
                st.spkcache_preds = np.vstack([st.spkcache_preds, pop_preds])
            if len(st.spkcache) > c.spkcache_len:
                if st.spkcache_preds is None:
                    st.spkcache_preds = np.vstack([preds[:sc_len], pop_preds]) if sc_len else pop_preds.copy()
                self.compress(st)
        return confirmed, tentative

    def update_silence(self, st: State, embs: np.ndarray, preds: np.ndarray) -> None:
        for e, p in zip(embs, preds):
            if float(p.sum()) < self.cfg.silence_threshold:
                n = st.silence_count
                st.mean_silence = ((st.mean_silence * n + e) / (n + 1)).astype(np.float32)
                st.silence_count += 1

    def _log_scores(self, p: np.ndarray) -> np.ndarray:
        t = self.cfg.pred_score_threshold
        log1p_neg = np.log1p(-np.clip(p, 0, 1 - t))
        s = np.log(np.maximum(p, t)) - log1p_neg + math.log(2)
        return s + log1p_neg.sum(axis=1, keepdims=True)

    @staticmethod
    def _boost_topk(scores: np.ndarray, k: int, scale: float) -> np.ndarray:
        n = len(scores)
        k = min(k, n)
        if n == 0 or k <= 0:
            return scores
        out = scores.copy()
        delta = -scale * math.log(0.5)
        frames = np.arange(n)
        for spk in range(scores.shape[1]):
            v = scores[:, spk]
            ok = v != -np.inf
            idx = frames[ok][np.lexsort((frames[ok], -v[ok]))][:k]   # highest first, earlier frame on a tie
            out[idx, spk] += delta
        return out

    def compress(self, st: State) -> None:
        c = self.cfg
        S, cap, sil = c.num_speakers, c.spkcache_len, c.sil_frames_per_spk
        preds = st.spkcache_preds
        n = len(st.spkcache)
        per_spk = cap // S - sil
        strong, weak, min_pos = int(per_spk * c.strong_boost_rate), int(per_spk * c.weak_boost_rate), int(per_spk * c.min_pos_scores_rate)
        scores = self._log_scores(preds)
        pos = ((preds > 0.5) & (scores > 0)).sum(axis=0)
        scores = np.where(preds <= 0.5, -np.inf, scores)
        scores = np.where((scores <= 0) & (pos >= min_pos)[None, :], -np.inf, scores)
        if n > cap:
            scores[cap:] += c.scores_boost_latest
        scores = self._boost_topk(scores, strong, 2.0)
        scores = self._boost_topk(scores, weak, 1.0)
        total = n + sil
        scores = np.vstack([scores, np.full((sil, S), np.inf)])
        flat = scores.T.reshape(-1)                       # permuted index = spk * total + frame
        perm = np.arange(flat.size)
        order = np.lexsort((perm, -flat))[:cap]           # highest first, smaller index on a tie
        top = np.where(flat[order] == -np.inf, -1, order)
        top = np.concatenate([top, np.full(cap - len(top), -1)])      # fewer candidates than slots: pad, as Swift
        top = np.sort(np.where(top < 0, np.iinfo(np.int64).max, top))
        disabled = top == np.iinfo(np.int64).max
        frame = np.where(disabled, 0, top % total)
        disabled |= frame >= n
        new_cache = np.where(disabled[:, None], st.mean_silence[None, :], st.spkcache[np.where(disabled, 0, frame)])
        new_preds = np.where(disabled[:, None], 0.0, preds[np.where(disabled, 0, frame)]).astype(np.float32)
        st.spkcache, st.spkcache_preds = new_cache.astype(np.float32), new_preds


# ---- timeline ----------------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class FrameSeg:
    speaker: int
    start_frame: int
    end_frame: int


@dataclass
class _Scratch:
    speaking: bool = False
    has_segment: bool = False
    start_frame: int = -(2 ** 62)
    end_frame: int = -(2 ** 62)
    unmerged_start: int = -(2 ** 62)


@dataclass
class Update:
    finalized: list = field(default_factory=list)
    tentative: list = field(default_factory=list)


class Timeline:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.cursor = 0
        self.scratch = [_Scratch() for _ in range(cfg.num_speakers)]

    def add(self, finalized: np.ndarray, tentative: np.ndarray) -> Update:
        u = Update()
        self._segments(finalized, True, False, u)
        self.cursor += len(finalized)
        self._segments(tentative, False, True, u)
        return u

    def _segments(self, preds: np.ndarray, is_final: bool, trailing: bool, u: Update) -> None:
        if len(preds) == 0 and not trailing:
            return
        c = self.cfg
        off0, n = self.cursor, len(preds)
        end_frame = off0 + n
        fin_end = end_frame if is_final else -(2 ** 63)   # minFramesOff = pads = 0 in .sortformerDefault

        def commit(aux, spk, final):
            if not aux.has_segment:
                return
            (u.finalized if final else u.tentative).append(FrameSeg(spk, aux.start_frame, aux.end_frame))
            aux.has_segment = False

        for spk in range(c.num_speakers):
            aux = copy.copy(self.scratch[spk])
            col = preds[:, spk] if n else ()
            for i, a in enumerate(col):
                frame = off0 + i
                if aux.speaking:
                    if a >= c.offset:
                        continue
                    aux.speaking = False
                    end = frame
                    if not end >= aux.unmerged_start:
                        aux.has_segment = aux.end_frame >= aux.start_frame
                        continue
                    aux.end_frame, aux.has_segment = end, True
                elif a > c.onset:
                    aux.speaking, aux.unmerged_start = True, frame
                    if aux.has_segment and not frame > aux.end_frame:
                        aux.has_segment = False
                        continue
                    commit(aux, spk, is_final)
                    aux.start_frame = frame
            if aux.has_segment and (not is_final or aux.end_frame < fin_end):
                commit(aux, spk, is_final and aux.end_frame < fin_end)
            if is_final:
                self.scratch[spk] = aux
                continue
            if not (trailing and aux.speaking) or not end_frame >= aux.start_frame:
                continue
            aux.has_segment = True
            if end_frame >= aux.unmerged_start:
                aux.end_frame = end_frame
            commit(aux, spk, False)


# ---- the streaming diarizer --------------------------------------------------------------------------------------

class StreamingSortformer:
    """feed() = LiveDiarizer.feed + drain: add audio, run every chunk now available, merge the update."""

    def __init__(self, model, cfg: Config = Config()):
        self.model, self.cfg = model, cfg
        self.mel = MelFrontend()
        self.updater = StateUpdater(cfg)
        self.state = self.updater.new_state()
        self.timeline = Timeline(cfg)
        self.chunk_index = 0
        self.received = 0
        self._last = 0.0                           # last raw sample, for preemphasis across feeds
        self._y = np.zeros(0, np.float64)          # preemphasised samples from absolute index _y0
        self._y0 = 0
        self._feats = np.zeros((0, N_MELS), np.float32)   # mel frames from absolute frame _f0
        self._f0 = 0
        self._start = 0                            # next chunk's core start (absolute mel frame)
        self._finalized: list[Seg] = []
        self._tentative: list[Seg] = []

    @property
    def segments(self) -> list[Seg]:
        return self._finalized + self._tentative

    def finish(self) -> None:
        """LiveDiarizer.finish discards finalizeSession's update, so the app's segments stop at the last feed."""

    def feed(self, samples: np.ndarray) -> None:
        x = np.asarray(samples, np.float64)
        if not len(x):
            return
        y = np.empty(len(x))
        y[0] = x[0] - PREEMPH * self._last
        y[1:] = x[1:] - PREEMPH * x[:-1]
        self._last = float(x[-1])
        self._y = np.concatenate([self._y, y])
        self.received += len(x)
        self._emit_mel()
        self._process()

    def _emit_mel(self) -> None:
        have = self._f0 + len(self._feats)
        avail = available_mel_frames(self.received)
        if avail <= have:
            return
        lo = have * HOP - WIN // 2                 # absolute sample where frame `have`'s window starts
        left = max(0, self._y0 - lo)
        seg = np.concatenate([np.zeros(left), self._y[max(0, lo - self._y0):]])
        new = self.mel.frames(seg, avail - have)
        self._feats = np.vstack([self._feats, new])
        keep_from = avail * HOP - WIN // 2         # the next frame's window start
        if keep_from > self._y0:
            self._y = self._y[keep_from - self._y0:]
            self._y0 = keep_from

    def _process(self) -> None:
        c = self.cfg
        core, lcf, rcf = c.chunk_len * c.subsampling, c.chunk_left_context * c.subsampling, c.chunk_right_context * c.subsampling
        fin, ten, ran = [], None, False
        while True:
            total = self._f0 + len(self._feats)
            end = min(self._start + core, total)
            if not (end > self._start and end + rcf <= total):
                break
            left = min(lcf, self._start)
            a, b = self._start - left - self._f0, end + rcf - self._f0
            chunk = self._feats[a:b]
            lc = c.chunk_left_context if self.chunk_index > 0 else 0
            preds, embs = self.model(chunk, self.state.spkcache, self.state.fifo)
            conf, tent = self.updater.update(self.state, embs, preds, lc, c.chunk_right_context)
            fin.append(conf); ten = tent; ran = True
            self.chunk_index += 1
            self._start = end
            drop = max(0, self._start - lcf) - self._f0
            if drop > 0:
                self._feats = self._feats[drop:]
                self._f0 += drop
        if not ran:
            return
        u = self.timeline.add(np.vstack(fin), ten)
        fs = c.frame_seconds
        self._finalized += [Seg(s.speaker, s.start_frame * fs, s.end_frame * fs) for s in u.finalized]
        self._tentative = [Seg(s.speaker, s.start_frame * fs, s.end_frame * fs) for s in u.tentative]


# ---- ONNX ---------------------------------------------------------------------------------------------------------

class OnnxSortformer:
    """An ONNX Sortformer step graph (inputs chunk/spkcache/fifo + lengths). `pad_to` pads to a static graph's shapes."""

    def __init__(self, path: str, threads: int = 2, pad_to: tuple[int, int, int] | None = None):
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        so.inter_op_num_threads = 1
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        self.sess = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])
        self.pad_to = pad_to
        self.calls = 0

    @staticmethod
    def _pad(x: np.ndarray, n: int) -> np.ndarray:
        if len(x) > n:
            raise ValueError(f"{len(x)} frames do not fit a static input of {n}")
        return np.vstack([x, np.zeros((n - len(x), x.shape[1]), np.float32)])

    def __call__(self, chunk, spkcache, fifo):
        lens = [len(chunk), len(spkcache), len(fifo)]
        if self.pad_to:
            chunk, spkcache, fifo = (self._pad(a, n) for a, n in zip((chunk, spkcache, fifo), self.pad_to))
        f = {"chunk": chunk[None].astype(np.float32), "chunk_lengths": np.array([lens[0]], np.int64),
             "spkcache": spkcache[None].astype(np.float32), "spkcache_lengths": np.array([lens[1]], np.int64),
             "fifo": fifo[None].astype(np.float32), "fifo_lengths": np.array([lens[2]], np.int64)}
        preds, embs, emb_len = self.sess.run(None, f)
        self.calls += 1
        return preds[0], embs[0][:int(emb_len[0])]
