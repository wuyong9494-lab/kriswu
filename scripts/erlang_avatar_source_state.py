"""Source-only D15 Avatar uniform timing and authenticated action metadata.

This module does not select renderers, create materials, infer a game clock,
evaluate trigger conditions, load shaders, or connect to App / ShiftCore.
The caller must supply the actual captured material values and observed shared
logical clock. A logical clock unit is not asserted to be a source frame,
display frame, second, or fixed-step tick.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import struct
from typing import Callable, Collection, Sequence


NORMAL_MATERIAL = "mtl_Erlang_triplanar_Avatar"
RETEXT_MATERIAL = NORMAL_MATERIAL + "_retext"

# These are the restored original lock bytes and their lossless field views.
# They do not replace the different historical compact-JSON identities.
SOURCE_LOCKS = {
    "1432": {
        "raw_bytes": 44283,
        "raw_sha256": "74917b81d2e8e0bae60123a7bb2a42f15d7ce4dc9f90f57a62c787c66dc4dde7",
        "fields_bytes": 488554,
        "fields_sha256": "816ef8d4b733788a957d10f3d379e60b9dfe7fbcf9ea4ed483576baf1bc2068a",
    },
    "1454": {
        "raw_bytes": 35276,
        "raw_sha256": "0bf4ae016ff582b8dc8e4753cd94aca3cd98027c03151820b575dff2b83d605d",
        "fields_bytes": 366517,
        "fields_sha256": "5afba1dc0698488b68c26c5329a02d91f56b4ee98c3042d0a9f39d46cd19ee0e",
    },
}


@dataclass(frozen=True)
class PassCommand:
    operation: str
    material_name: str
    mesh_type: int
    mesh_name_prefix: str | None
    target_value: float | None
    duration_logical_units: int | None
    duration_was_source_null: bool


@dataclass(frozen=True)
class TriggerContract:
    source_lock: str
    trigger_index: int
    variant: str
    priority: int | None
    events_sha256: str
    conditions_sha256: str
    commands: tuple[PassCommand, ...]


def _identity(path: Path, byte_count: int, sha256: str) -> bytes:
    if path.stat().st_size != byte_count:
        raise ValueError(f"Source identity differs: {path.name}")
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != sha256:
        raise ValueError(f"Source identity differs: {path.name}")
    return data


def _value_digest(value: object) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=False, allow_nan=False).encode()
    return hashlib.sha256(raw).hexdigest()


def load_source_contract(directory: Path) -> tuple[TriggerContract, ...]:
    """Read only the two pinned original locks and their pinned field views.

    The returned selectors describe original Unity renderer selection. They
    deliberately provide no GLTF-node substitution for the ``head_`` prefix.
    Events / conditions are fingerprinted, not evaluated or silently dropped.
    Retext entries are metadata only; this does not authorize its GPU program.
    """
    result = []
    for lock, pins in SOURCE_LOCKS.items():
        _identity(directory / f"lock_{lock}.bytes", pins["raw_bytes"], pins["raw_sha256"])
        fields = json.loads(_identity(
            directory / f"d15-lock-{lock}-source-fields-private.json",
            pins["fields_bytes"], pins["fields_sha256"]))
        if (fields["schema"] != "restored-d15-original-trigger-fields-v1"
                or fields["sourceLock"] != int(lock)
                or fields["source"] != {"file": f"lock_{lock}.bytes",
                                         "bytes": pins["raw_bytes"],
                                         "sha256": pins["raw_sha256"]}
                or len(fields["sets"]) != 1):
            raise ValueError("Original source field identity differs")
        found = {}
        for trigger in fields["sets"][0]["triggers"]:
            actions = [a["a167"] for a in (trigger["actions"] or []) if "a167" in a]
            if actions:
                found[trigger["triggerIndex"]] = (trigger, actions)
        expected = (2, 3, 26, 27) if lock == "1432" else (59, 60, 61, 62)
        if tuple(found) != expected:
            raise ValueError("Unreviewed Avatar trigger set")
        for index, (trigger, actions) in found.items():
            normal = index in (2, 26, 59, 61)
            name = NORMAL_MATERIAL if normal else RETEXT_MATERIAL
            append = lock == "1432"
            duration = None if index in (2, 3) else 20
            selectors = (2, 1, 0, 3) if append else (1, 2, 0, 3)
            commands = []
            if len(actions) != len(selectors):
                raise ValueError("Original selector count differs")
            for row, mesh_type in zip(actions, selectors):
                prefix = "head_" if mesh_type == 0 else None
                original = ["enum65537", f"enum{mesh_type}" if mesh_type else None,
                            [name, 1.0, duration] if append else None,
                            None if append else name, prefix]
                if row != original:
                    raise ValueError("Original Avatar action differs")
                commands.append(PassCommand(
                    "append_or_reuse" if append else "remove", name, mesh_type,
                    prefix, 1.0 if append else None,
                    (0 if duration is None else duration) if append else None,
                    append and duration is None))
            result.append(TriggerContract(
                lock, index, "normal" if normal else "retext", trigger["priority"],
                _value_digest(trigger["events"]), _value_digest(trigger["conditions"]),
                tuple(commands)))
    return tuple(result)


def _float32(value: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("A finite numeric source value is required")
    try:
        result = struct.unpack("<f", struct.pack("<f", value))[0]
    except (OverflowError, struct.error) as error:
        raise ValueError("Source value is outside finite Float32") from error
    if not math.isfinite(result):
        raise ValueError("Source value is outside finite Float32")
    return result


def _clock_integer(shared_clock: float) -> int:
    value = _float32(shared_clock)
    integer = math.trunc(value)  # Original FCVTZS, not round or floor.
    if not -(2**31) <= integer < 2**31:
        raise ValueError("Clock is outside the reviewed finite Int32 branch")
    return integer


@dataclass(frozen=True)
class MaterialCapture:
    material_id: str
    value: float


@dataclass(frozen=True)
class UniformWrite:
    material_id: str
    value: float
    job_id: int | None


@dataclass(frozen=True)
class UpdateResult:
    clock_integer: int
    writes: tuple[UniformWrite, ...]
    completed_jobs: tuple[int, ...]
    discarded_pending_job_ids: tuple[int, ...]


@dataclass(frozen=True)
class _Tween:
    job_id: int
    captures: tuple[MaterialCapture, ...]
    target: float
    start: int
    end: int


class AvatarUniformScheduler:
    """Restricted source-only model of 30607/30608 and the selected job queue.

    Timed enqueue starts the job but emits no initial write. Enqueue inside a
    callback goes to the pending queue and cannot run in that same pass. In
    this particular original update/tail path, those pending entries are then
    discarded, not retained for the next pass. The result reports their IDs.
    Each update receives an observed clock; it never advances that clock.

    Removing a renderer's additional pass is a separate command. It is not a
    reverse tween, cancellation, or destruction of the material instance.
    ``live_material_ids`` represents Unity object liveness, not attachment.
    No job is implicitly cancelled when a later action targets the same ID.
    """
    def __init__(self) -> None:
        self._active: list[_Tween] = []
        self._pending: list[_Tween] = []
        self._updating = False
        self._failed = False
        self._next_id = 1

    @property
    def active_job_count(self) -> int:
        return len(self._active)

    @property
    def pending_job_count(self) -> int:
        return len(self._pending)

    def enqueue(self, *, captures: Sequence[MaterialCapture], shared_clock: float,
                target_value: float, duration_logical_units: int) -> tuple[UniformWrite, ...]:
        if self._failed:
            raise RuntimeError("A callback failed; the source-only state is no longer usable")
        start = _clock_integer(shared_clock)
        target = _float32(target_value)
        duration = duration_logical_units
        if type(duration) is not int or not 0 <= duration < 2**31 or start + duration >= 2**31:
            raise ValueError("Only nonnegative, nonoverflowing source durations are supported")
        captured = []
        for item in captures:
            if not isinstance(item, MaterialCapture) or not isinstance(item.material_id, str) or not item.material_id:
                raise ValueError("Explicit material identity and captured value are required")
            captured.append(MaterialCapture(item.material_id, _float32(item.value)))
        # Preserve source enumeration order and repeated references. An empty
        # selection stays empty; it never substitutes a personal head / body.
        if duration == 0:
            return tuple(UniformWrite(item.material_id, target, None) for item in captured)
        job = _Tween(self._next_id, tuple(captured), target, start, start + duration)
        self._next_id += 1
        (self._pending if self._updating else self._active).append(job)
        return ()

    def update(self, *, shared_clock: float, pause_flag: bool, suspended_flag: bool,
               live_material_ids: Collection[str],
               on_write: Callable[[UniformWrite], None] | None = None) -> UpdateResult:
        if self._failed or self._updating:
            raise RuntimeError("A nested or failed update is outside the reviewed normal branch")
        if type(pause_flag) is not bool or type(suspended_flag) is not bool:
            raise ValueError("Both original pause flags must be explicit booleans")
        current = _clock_integer(shared_clock)
        if isinstance(live_material_ids, (str, bytes)):
            raise ValueError("Live material identities must be an explicit collection")
        live = frozenset(live_material_ids)
        if any(not isinstance(identity, str) or not identity for identity in live):
            raise ValueError("Explicit live material identities are required")
        writes: list[UniformWrite] = []
        completed: list[int] = []
        surviving: list[_Tween] = []
        self._updating = True
        try:
            for job in self._active:
                if pause_flag or suspended_flag:
                    surviving.append(job)
                    continue
                # Preserve original float operation order; clamp progress only.
                if not -(2**31) <= job.end - current < 2**31:
                    raise ValueError("Clock subtraction exceeds the reviewed Int32 branch")
                remaining = _float32(job.end - current)
                duration = _float32(job.end - job.start)
                progress = _float32(1.0 - _float32(remaining / duration))
                progress = min(1.0, max(0.0, progress))
                for item in job.captures:
                    if item.material_id not in live:
                        continue
                    difference = _float32(job.target - item.value)
                    product = _float32(difference * progress)
                    write = UniformWrite(item.material_id, _float32(item.value + product), job.job_id)
                    writes.append(write)
                    if on_write is not None:
                        on_write(write)
                # Source invokes the uniform callback before reporting completion.
                if current >= job.end:
                    completed.append(job.job_id)
                else:
                    surviving.append(job)
        except BaseException:
            # No claim about original exceptional-path recovery. Do not retry
            # a partially delivered callback pass as if no writes had happened.
            self._failed = True
            raise
        finally:
            self._updating = False
        # Original 35915 first appends pending to active and clears pending.
        # Its tail 0x70c34b0 then clears active, copies only survivors back, and
        # clears survivors. Completed jobs AND new pending entries are absent
        # from the resulting queue. This is not a claim about other schedulers.
        discarded_pending = tuple(job.job_id for job in self._pending)
        self._active.extend(self._pending)
        self._pending = []
        self._active.clear()
        self._active.extend(surviving)
        return UpdateResult(current, tuple(writes), tuple(completed), discarded_pending)
