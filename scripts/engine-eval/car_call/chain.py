"""The car-call signal chain (#303): what happens to the caller's voice between their phone and Seal Speak's mic.

    caller (16 kHz clip) -> 8 kHz telephone band, 300-3,400 Hz -> codec (AMR-NB if ffmpeg has it, else G.711 mu-law)
      -> back to 16 kHz -> small car speaker -> cabin reflections            = the far stem
    a live talker in the car (16 kHz clip) -> short near-field room response = the near stem, full band, louder
    synthetic road noise (rumble, engine harmonics, tyre band, slow swells)  = the noise stem

Everything is synthetic and seeded; nothing here plays or records sound. All signals are float32 in [-1, 1].
"""
from __future__ import annotations

import functools
import subprocess
from dataclasses import dataclass

import numpy as np
from scipy import signal

TEL_SR = 8000
CODECS = ("amrnb", "mulaw", "none")
FAR_RMS = 0.05  # about -26 dBFS: a comfortable call level at the phone mic, leaves headroom for the near talker


# --- telephone ------------------------------------------------------------------------------------------------

@functools.lru_cache(maxsize=1)
def _ffmpeg_encoders_cached() -> str:
    try:
        return subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True,
                              check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return ""


def _ffmpeg_encoders() -> str:
    return _ffmpeg_encoders_cached()


def best_codec() -> str:
    """AMR-NB is what a 2G/3G/VoLTE-fallback narrowband call uses; G.711 mu-law is the fallback (gentler, so
    results on it are an optimistic bound on a real AMR-NB call)."""
    enc = _ffmpeg_encoders()
    if "libopencore_amrnb" in enc:
        return "amrnb"
    if "pcm_mulaw" in enc:
        return "mulaw"
    return "none"


def check_codec(codec: str) -> None:
    if codec not in CODECS:
        raise ValueError(f"unknown codec {codec!r}; one of {CODECS}")
    need = {"amrnb": "libopencore_amrnb", "mulaw": "pcm_mulaw"}.get(codec)
    if need and need not in _ffmpeg_encoders():
        raise RuntimeError(f"this ffmpeg has no {need} encoder; use --codec {best_codec()}")


def _ffmpeg(args: list[str], data: bytes) -> bytes:
    return subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", *args], input=data,
                          capture_output=True, check=True).stdout


def _codec_roundtrip(x8: np.ndarray, codec: str) -> np.ndarray:
    if codec == "none":
        return x8
    pcm = (np.clip(x8, -1, 1) * 32767).astype("<i2").tobytes()
    raw_in = ["-f", "s16le", "-ar", str(TEL_SR), "-ac", "1", "-i", "pipe:0"]
    raw_out = ["-f", "s16le", "-ar", str(TEL_SR), "-ac", "1", "pipe:1"]
    if codec == "mulaw":
        coded = _ffmpeg([*raw_in, "-c:a", "pcm_mulaw", "-f", "mulaw", "pipe:1"], pcm)
        back = _ffmpeg(["-f", "mulaw", "-ar", str(TEL_SR), "-ac", "1", "-i", "pipe:0", *raw_out], coded)
    else:  # amrnb, 12.2 kbit/s, the top AMR-NB mode
        coded = _ffmpeg([*raw_in, "-c:a", "libopencore_amrnb", "-b:a", "12.2k", "-f", "amr", "pipe:1"], pcm)
        back = _ffmpeg(["-f", "amr", "-i", "pipe:0", *raw_out], coded)
    y = np.frombuffer(back, dtype="<i2").astype(np.float32) / 32767
    out = np.zeros_like(x8)
    out[: min(len(y), len(x8))] = y[: len(x8)]
    return out


def telephone(x: np.ndarray, sr: int, codec: str = "mulaw") -> np.ndarray:
    """Narrowband call: down to 8 kHz, 300-3,400 Hz band, codec round trip, back to sr. Same length as x."""
    check_codec(codec)
    if sr % TEL_SR:
        raise ValueError(f"sample rate {sr} is not a multiple of {TEL_SR}")
    k = sr // TEL_SR
    x8 = signal.resample_poly(x.astype(np.float64), 1, k)
    band = signal.butter(6, [300, 3400], btype="bandpass", fs=TEL_SR, output="sos")
    x8 = signal.sosfilt(band, x8).astype(np.float32)
    y8 = _codec_roundtrip(x8, codec).astype(np.float64)
    y = signal.resample_poly(y8, k, 1)
    # The handset/car DAC's reconstruction filter: nothing of the 8 kHz path survives above 4 kHz.
    y = signal.sosfilt(signal.butter(10, 3700, fs=sr, output="sos"), y)
    out = np.zeros(len(x), np.float32)
    out[: min(len(y), len(x))] = y[: len(x)]
    return out


# --- car speaker, cabin, near talker --------------------------------------------------------------------------

def _peaking(f0: float, gain_db: float, q: float, sr: int) -> np.ndarray:
    """RBJ peaking biquad as an SOS row."""
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / sr
    alpha = np.sin(w) / (2 * q)
    b = np.array([1 + alpha * a, -2 * np.cos(w), 1 - alpha * a])
    den = np.array([1 + alpha / a, -2 * np.cos(w), 1 - alpha / a])
    return np.concatenate([b / den[0], den / den[0]])[None, :]


def car_speaker(x: np.ndarray, sr: int) -> np.ndarray:
    """A door speaker heard from the passenger seat: no deep bass (high-pass at 150 Hz), a cone resonance near
    2.5 kHz, a dip around 800 Hz. Linear on purpose: distortion would leak energy above the call band."""
    sos = np.vstack([signal.butter(4, 150, btype="highpass", fs=sr, output="sos"),
                     _peaking(2500, 4.0, 1.2, sr), _peaking(800, -3.0, 1.0, sr)])
    return signal.sosfilt(sos, x.astype(np.float64)).astype(np.float32)


def cabin_ir(sr: int, rng: np.random.Generator, rt60: float = 0.12, direct: float = 1.0,
             length_s: float = 0.2) -> np.ndarray:
    """Synthetic car-cabin impulse response: a direct path, a few early reflections off glass and dash (2-9 ms),
    then an exponentially decaying diffuse tail (energy down 60 dB at rt60). Car cabins measure about
    0.05-0.15 s."""
    n = int(length_s * sr)
    t = np.arange(n) / sr
    tail = rng.standard_normal(n) * 10 ** (-3 * t / rt60) * 0.3
    tail[: int(0.002 * sr)] = 0
    ir = tail
    ir[0] += direct
    for _ in range(5):
        d = int(rng.uniform(0.002, 0.009) * sr)
        ir[d] += rng.uniform(0.2, 0.5) * rng.choice([-1, 1])
    return (ir / np.sqrt(np.sum(ir ** 2))).astype(np.float32)


def _convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    return signal.fftconvolve(x.astype(np.float64), ir.astype(np.float64))[: len(x) + len(ir) - 1].astype(np.float32)


# --- road noise -----------------------------------------------------------------------------------------------

def _pink(n: int, rng: np.random.Generator) -> np.ndarray:
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(len(spec), dtype=np.float64)
    f[0] = 1
    return np.fft.irfft(spec / np.sqrt(f), n)


def road_noise(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Interior road noise, synthetic: brown rumble (tyres on asphalt, most energy under 200 Hz), engine
    harmonics around 30-40 Hz with drifting RPM, a pink mid layer and a 600-1,200 Hz tyre band that lands in the
    call band, all under slow swells (0.2-0.6 Hz) like a road surface changing. Unit RMS."""
    t = np.arange(n) / sr
    brown = np.cumsum(rng.standard_normal(n))
    brown = signal.sosfilt(signal.butter(2, 20, btype="highpass", fs=sr, output="sos"), brown)
    brown = signal.sosfilt(signal.butter(2, 400, fs=sr, output="sos"), brown)
    pink = _pink(n, rng)
    tyre = signal.sosfilt(signal.butter(2, [600, 1200], btype="bandpass", fs=sr, output="sos"),
                          rng.standard_normal(n))
    f0 = rng.uniform(28, 40) * (1 + 0.05 * np.sin(2 * np.pi * rng.uniform(0.05, 0.15) * t + rng.uniform(0, 6.3)))
    phase = 2 * np.pi * np.cumsum(f0) / sr
    engine = sum((0.6 / h) * np.sin(h * phase + rng.uniform(0, 6.3)) for h in range(1, 7))

    def unit(v):
        return v / (np.sqrt(np.mean(v ** 2)) + 1e-12)

    bed = unit(brown) + 0.5 * unit(engine) + 0.25 * unit(pink) + 0.12 * unit(tyre)
    swell = 1 + 0.35 * np.sin(2 * np.pi * rng.uniform(0.2, 0.6) * t + rng.uniform(0, 6.3))
    return unit(bed * swell).astype(np.float32)


# --- the scene ------------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Scene:
    mix: np.ndarray
    far_stem: np.ndarray
    near_stem: np.ndarray
    noise_stem: np.ndarray
    far_span: tuple[int, int]   # samples, end exclusive
    near_span: tuple[int, int]  # empty (a == b) when there is no near talker
    gain: float                 # the peak guard's gain: mix = (far + near + noise) * gain


def _rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x.astype(np.float64) ** 2))) if len(x) else 0.0


def mix_scene(far: np.ndarray, near: np.ndarray | None, sr: int, rng: np.random.Generator, *,
              snr_db: float | None, near_gain_db: float = 6.0, gap_s: float = 0.4, lead_s: float = 0.3,
              tail_s: float = 0.3, codec: str = "mulaw") -> Scene:
    """Caller first, then the person in the car answers (turns, no overlap). snr_db is far-voice power over
    road-noise power across the far voice's span (None = no noise); the near talker sits near_gain_db above the
    far voice, each measured over its own span."""
    if _rms(far) < 1e-6:
        raise ValueError("far voice is silent")
    far_p = _convolve(car_speaker(telephone(far, sr, codec=codec), sr), cabin_ir(sr, rng, rt60=0.12))
    far_p *= FAR_RMS / _rms(far_p)
    lead, gap, tail = int(lead_s * sr), int(gap_s * sr), int(tail_s * sr)
    f0, f1 = lead, lead + len(far_p)
    if near is not None:
        if _rms(near) < 1e-6:
            raise ValueError("near voice is silent")
        near_p = _convolve(near, cabin_ir(sr, rng, rt60=0.08, direct=3.0))
        near_p *= FAR_RMS * 10 ** (near_gain_db / 20) / _rms(near_p)
        n0, n1 = f1 + gap, f1 + gap + len(near_p)
    else:
        near_p = np.zeros(0, np.float32)
        n0 = n1 = f1
    total = n1 + tail
    far_stem = np.zeros(total, np.float32)
    far_stem[f0:f1] = far_p
    near_stem = np.zeros(total, np.float32)
    near_stem[n0:n1] = near_p
    if snr_db is None:
        noise = np.zeros(total, np.float32)
    else:
        noise = road_noise(total, sr, rng)
        noise *= _rms(far_stem[f0:f1]) / (_rms(noise[f0:f1]) * 10 ** (snr_db / 20))
    s = far_stem + near_stem + noise
    peak = float(np.max(np.abs(s)))
    gain = min(1.0, 0.99 / peak) if peak > 0 else 1.0
    return Scene(mix=(s * gain).astype(np.float32), far_stem=far_stem, near_stem=near_stem,
                 noise_stem=noise.astype(np.float32), far_span=(f0, f1), near_span=(n0, n1), gain=gain)
