"""Source-only D15 StopEffect frame-job and material-write contract.

This is not an App effect, a scheduler, a particle simulation, or a clock.
Every evaluation needs an explicitly observed original Int32 frame counter
and current renderer/object liveness. It never derives frames from elapsed
seconds, render calls, cast phases, erlangLiveTick, or Avatar logical time.
The returned commands describe native calls, not completed GPU writes.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import struct
from typing import Sequence


TRANSPARENCY_PROPERTY = "_Transparent"
SWORD_RECEIPT_BYTES = 113_605
SWORD_RECEIPT_SHA256 = "245d64669edd31d5e7e5707ad60a4081d2e91424b235c6ddc67ed2a5a2e3af86"
SWORD_EFFECTS = (
    "D15_fx_sword_model", "D15_fx_sword_model_retext",
    "D15_fx_sword_jian_glow(weapon_r)",
    "D15_fx_sword_jian_glow(weapon_r)_retext",
)


def _int32(value: int, name: str) -> int:
    if type(value) is not int or not -(1 << 31) <= value < (1 << 31):
        raise ValueError(f"{name} must be an observed Int32, not an inferred clock")
    return value


def _wrap32(value: int) -> int:
    return ((value + (1 << 31)) & 0xFFFFFFFF) - (1 << 31)


def _float32(value: float) -> float:
    """Round one FP operation to Float32; preserve IEEE NaN/infinity values.

    Finite job inputs cannot produce NaN: its duration is a positive Int32.
    Direct callback observations can contain nonfinite Float32 values. Native
    FFIBMLOOMPN does not clamp or reject them. NaN payload/FPSCR behavior is
    outside this model; it preserves NaN classification only.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("A numeric Float32 callback value is required")
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except (OverflowError, struct.error):
        return math.copysign(math.inf, value)


def callback_transparency(progress: float) -> float:
    """Method 34452: one Float32 subtraction, without saturation."""
    return _float32(1.0 - _float32(progress))


class SourceNullReference(RuntimeError):
    """A selected native null-reference branch, not a fallback renderer."""


@dataclass(frozen=True)
class RendererObservation:
    renderer_id: str
    renderer_alive: bool
    material_id: str | None
    exact_particle_system_renderer: bool = False
    trail_material_id: str | None = None
    trail_material_alive: bool = False


@dataclass(frozen=True)
class SetFloat:
    renderer_id: str
    material_id: str
    property_name: str
    value: float


@dataclass(frozen=True)
class SetInactive:
    effect_object_id: str


@dataclass(frozen=True)
class CallbackResult:
    observed_frame: int
    progress: float
    transparency: float
    completed: bool
    commands: tuple[SetFloat | SetInactive, ...]


@dataclass(frozen=True)
class FrameStopJob:
    effect_object_id: str
    start_frame: int
    duration_frames: int

    def __post_init__(self):
        if not self.effect_object_id:
            raise ValueError("An observed effect identity is required")
        _int32(self.start_frame, "start_frame")
        if _int32(self.duration_frames, "duration_frames") < 1:
            raise ValueError("Nonpositive stop frames take the immediate branch")

    @property
    def end_frame(self) -> int:
        # 35944 uses ADD W; do not silently widen the source integer.
        return _wrap32(self.start_frame + self.duration_frames)

    def evaluate(self, *, observed_frame: int,
                 renderers: Sequence[RendererObservation] | None,
                 effect_object_alive: bool) -> CallbackResult:
        """Evaluate one already-selected normal scheduler callback.

        No queue mutation, cancellation, implicit start callback, or completion
        removal happens here. The caller must stop selecting a completed job.
        An unchanged frame still causes a write if this callback is invoked.
        Material IDs are observations of native getters, not mesh-name guesses.
        """
        frame = _int32(observed_frame, "observed_frame")
        remaining = _float32(_wrap32(self.end_frame - frame))
        duration = _float32(_wrap32(self.end_frame - self.start_frame))
        ratio = _float32(remaining / duration)
        progress = _float32(1.0 - ratio)
        value = callback_transparency(progress)
        if renderers is None:
            raise SourceNullReference("Native material enumeration received null")
        commands: list[SetFloat | SetInactive] = []
        for renderer in renderers:
            if not renderer.renderer_alive:
                continue
            if renderer.material_id is None:
                raise SourceNullReference("Native Renderer.material getter returned null")
            commands.append(SetFloat(renderer.renderer_id, renderer.material_id,
                                     TRANSPARENCY_PROPERTY, value))
            # Native 34435 compares the exact runtime class pointer. It does
            # not treat every Renderer/subclass as a ParticleSystemRenderer.
            if renderer.exact_particle_system_renderer and renderer.trail_material_alive:
                if renderer.trail_material_id is None:
                    raise SourceNullReference("Native trail material getter returned null")
                commands.append(SetFloat(renderer.renderer_id, renderer.trail_material_id,
                                         TRANSPARENCY_PROPERTY, value))
        # Native writes first, then compares signed Int32 end <= frame. No
        # clamping is inserted for an observation beyond the nominal end.
        completed = self.end_frame <= frame
        if completed and effect_object_alive:
            commands.append(SetInactive(self.effect_object_id))
        return CallbackResult(frame, progress, value, completed, tuple(commands))


@dataclass(frozen=True)
class StopRequest:
    job: FrameStopJob | None
    commands: tuple[SetInactive, ...]


def request_stop(*, effect_object_id: str, frames: int,
                 renderer_count: int | None, effect_object_alive: bool,
                 observed_frame: int | None = None) -> StopRequest:
    """Native 34436 branches before reading a frame or calling a uniform.

    A null/empty collection stops immediately. A nonempty collection of dead
    Unity renderer objects still takes the job branch; its later writes skip
    those objects. No renderer substitute or pool/parent lifetime is inferred.
    """
    if not effect_object_id:
        raise ValueError("An observed effect identity is required")
    count = 0 if renderer_count is None else _int32(renderer_count, "renderer_count")
    if count < 0:
        raise ValueError("A renderer collection count cannot be negative")
    if _int32(frames, "frames") < 1 or count == 0:
        return StopRequest(None, (SetInactive(effect_object_id),) if effect_object_alive else ())
    frame = _int32(observed_frame, "observed_frame")
    # 35905 enqueues/starts the job without invoking progress at zero.
    return StopRequest(FrameStopJob(effect_object_id, frame, frames), ())


@dataclass(frozen=True)
class SwordStopAction:
    source_lock: int
    source_trigger: int
    source_action_index: int
    effect_name: str
    duration_frames: int
    has_separate_model_delete_action: bool


def load_sword_stop_contract(receipt_path: Path) -> tuple[SwordStopAction, ...]:
    """Read the exact existing recovered source receipt, not an App manifest.

    This authenticates the receipt's source-lock views. It does not claim the
    original lock bytes were restored here, execute their conditions, activate
    the retext variants, or order the separate model deletion against fades.
    """
    if receipt_path.stat().st_size != SWORD_RECEIPT_BYTES:
        raise ValueError("Sword source receipt identity differs")
    raw = receipt_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SWORD_RECEIPT_SHA256:
        raise ValueError("Sword source receipt identity differs")
    document = json.loads(raw)
    if (document["schema"] != "original-d15-sword-source-only-recovery-receipt-v1"
            or document["inputFormat"] != "recovered-v1"
            or document["sourceOnly"] is not True or document["runtimeBound"] is not False):
        raise ValueError("Expected an independent source-only receipt")
    lifecycle = next(r for r in document["sourceLifecycle"] if r["sourceLock"] == 1449)
    expected = (
        (11, 10, [{"a44": ["enum65539", "D15_HIDE_SWORDS"]}]),
        (12, 5, [{"a37": ["RoundFightEnd"]},
                 {"a17": ["enum65537", "D15_Sword_Destroy"]}]),
    )
    result = []
    for index, frames, events in expected:
        trigger = next(t for t in lifecycle["triggers"] if t["triggerIndex"] == index)
        if trigger["events"] != events or trigger["conditions"] is not None:
            raise ValueError("Original sword stop trigger differs")
        actions = trigger["actions"]
        if actions[:4] != [{"a49": [effect, "enum65537", frames, None, None]}
                           for effect in SWORD_EFFECTS]:
            raise ValueError("Original sword stop effects or frames differ")
        for action_index, effect in enumerate(SWORD_EFFECTS):
            result.append(SwordStopAction(1449, index, action_index, effect, frames,
                                         {"a50": [None, None]} in actions))
    return tuple(result)
