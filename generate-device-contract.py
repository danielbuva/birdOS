#!/usr/bin/env python3
"""Generate the compiled subset of birdOS's fixed-device TSV contract."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex


REQUIRED = {
    "schema": ("string", "BIRD_DEVICE_CONTRACT_SCHEMA"),
    "device.model": ("string", "BIRD_DEVICE_MODEL"),
    "device.soc": ("string", "BIRD_DEVICE_SOC"),
    "kernel.release": ("string", "BIRD_DEVICE_KERNEL_RELEASE"),
    "dtb.compatible": ("string", "BIRD_DEVICE_DTB_COMPATIBLE"),
    "system.provider": ("string", "BIRD_DEVICE_SYSTEM_PROVIDER"),
    "panel.compatible": ("string", "BIRD_DEVICE_PANEL_COMPATIBLE"),
    "framebuffer.node": ("string", "BIRD_DEVICE_FRAMEBUFFER_NODE"),
    "framebuffer.width": ("u32", "BIRD_DEVICE_FB_WIDTH"),
    "framebuffer.height": ("u32", "BIRD_DEVICE_FB_HEIGHT"),
    "framebuffer.bytes_per_pixel": ("u32", "BIRD_DEVICE_FB_BYTES_PER_PIXEL"),
    "framebuffer.stride": ("u32", "BIRD_DEVICE_FB_STRIDE"),
    "framebuffer.mapping_bytes": ("u32", "BIRD_DEVICE_FB_MAPPING_BYTES"),
    "framebuffer.pixel_format": ("string", "BIRD_DEVICE_FB_PIXEL_FORMAT"),
    "input.preferred_event": ("u32", "BIRD_DEVICE_INPUT_PREFERRED_EVENT"),
    "input.scan_count": ("u32", "BIRD_DEVICE_INPUT_SCAN_COUNT"),
    "input.name": ("string", "BIRD_DEVICE_INPUT_NAME"),
    "input.module": ("string", "BIRD_DEVICE_INPUT_MODULE"),
    "input.bus": ("u32", "BIRD_DEVICE_INPUT_BUS"),
    "input.vendor": ("u32", "BIRD_DEVICE_INPUT_VENDOR"),
    "input.product": ("u32", "BIRD_DEVICE_INPUT_PRODUCT"),
    "input.version": ("u32", "BIRD_DEVICE_INPUT_VERSION"),
    "input.ev_bitmap": ("hex", "BIRD_DEVICE_INPUT_EV_BITMAP"),
    "input.key_bitmap": ("bitmap64", "BIRD_DEVICE_INPUT_KEY_BITMAP"),
    "input.abs_bitmap": ("hex", "BIRD_DEVICE_INPUT_ABS_BITMAP"),
    "input.ff_bitmap": ("bitmap64", "BIRD_DEVICE_INPUT_FF_BITMAP"),
    "rumble.enable_path": ("string", "BIRD_DEVICE_RUMBLE_ENABLE_PATH"),
    "rumble.default_enabled": ("bool", "BIRD_DEVICE_RUMBLE_DEFAULT_ENABLED"),
    "performance.cpu_count": ("u32", "BIRD_DEVICE_CPU_COUNT"),
    "performance.cpu_policy_path": ("string", "BIRD_DEVICE_CPU_POLICY_PATH"),
    "performance.cpu_min_khz": ("u32", "BIRD_DEVICE_CPU_MIN_KHZ"),
    "performance.cpu_max_khz": ("u32", "BIRD_DEVICE_CPU_MAX_KHZ"),
    "performance.cpu_governors": ("string", "BIRD_DEVICE_CPU_GOVERNORS"),
    "performance.cpu_default_governor": (
        "string",
        "BIRD_DEVICE_CPU_DEFAULT_GOVERNOR",
    ),
    "performance.gpu_devfreq_path": ("string", "BIRD_DEVICE_GPU_DEVFREQ_PATH"),
    "performance.gpu_min_hz": ("u32", "BIRD_DEVICE_GPU_MIN_HZ"),
    "performance.gpu_max_hz": ("u32", "BIRD_DEVICE_GPU_MAX_HZ"),
    "performance.gpu_overclock_hz": ("u32", "BIRD_DEVICE_GPU_OVERCLOCK_HZ"),
    "performance.gpu_governors": ("string", "BIRD_DEVICE_GPU_GOVERNORS"),
    "performance.gpu_default_governor": (
        "string",
        "BIRD_DEVICE_GPU_DEFAULT_GOVERNOR",
    ),
    "performance.turbo_path": ("string", "BIRD_DEVICE_TURBO_PATH"),
    "backlight.directory": ("string", "BIRD_DEVICE_BACKLIGHT_DIRECTORY"),
    "backlight.maximum_raw": ("u32", "BIRD_DEVICE_BACKLIGHT_MAXIMUM_RAW"),
    "backlight.cold_percent": ("u32", "BIRD_DEVICE_BACKLIGHT_COLD_PERCENT"),
    "backlight.wake_strike_percent": ("u32", "BIRD_DEVICE_BACKLIGHT_WAKE_STRIKE_PERCENT"),
    "backlight.wake_strike_ms": ("u32", "BIRD_DEVICE_BACKLIGHT_WAKE_STRIKE_MS"),
    "suspend.retained_cpu": ("u32", "BIRD_DEVICE_SUSPEND_RETAINED_CPU"),
    "suspend.parked_cpu_mask": ("u32", "BIRD_DEVICE_SUSPEND_PARKED_CPU_MASK"),
    "suspend.core_parking_required": (
        "u32",
        "BIRD_DEVICE_SUSPEND_CORE_PARKING_REQUIRED",
    ),
    "suspend.provider_mode": (
        "string",
        "BIRD_DEVICE_SUSPEND_PROVIDER_MODE",
    ),
    "suspend.fake_enabled": (
        "u32",
        "BIRD_DEVICE_SUSPEND_FAKE_ENABLED",
    ),
    "suspend.timed_shutdown_enabled": (
        "u32",
        "BIRD_DEVICE_SUSPEND_TIMED_SHUTDOWN_ENABLED",
    ),
    "suspend.systemd_allow_suspend": (
        "bool",
        "BIRD_DEVICE_SUSPEND_SYSTEMD_ALLOW_SUSPEND",
    ),
    "suspend.logind_handle_power_key": (
        "string",
        "BIRD_DEVICE_SUSPEND_LOGIND_HANDLE_POWER_KEY",
    ),
    "suspend.logind_handle_suspend_key": (
        "string",
        "BIRD_DEVICE_SUSPEND_LOGIND_HANDLE_SUSPEND_KEY",
    ),
    "suspend.logind_handle_lid_switch": (
        "string",
        "BIRD_DEVICE_SUSPEND_LOGIND_HANDLE_LID_SWITCH",
    ),
    "audio.card_name": ("string", "BIRD_DEVICE_AUDIO_CARD_NAME"),
    "audio.card_index": ("u32", "BIRD_DEVICE_AUDIO_CARD_INDEX"),
    "audio.device_index": ("u32", "BIRD_DEVICE_AUDIO_DEVICE_INDEX"),
    "audio.route": ("string", "BIRD_DEVICE_AUDIO_ROUTE"),
    "policy.locale": ("string", "BIRD_DEVICE_POLICY_LOCALE"),
    "policy.timezone": ("string", "BIRD_DEVICE_POLICY_TIMEZONE"),
    "policy.uid": ("u32", "BIRD_DEVICE_POLICY_UID"),
    "policy.gid": ("u32", "BIRD_DEVICE_POLICY_GID"),
    "policy.home": ("string", "BIRD_DEVICE_POLICY_HOME"),
    "policy.network_at_boot": ("bool", "BIRD_DEVICE_NETWORK_AT_BOOT"),
    "storage.boot_device": ("string", "BIRD_DEVICE_BOOT_DEVICE"),
    "storage.root_device": ("string", "BIRD_DEVICE_ROOT_DEVICE"),
    "storage.content_device": ("string", "BIRD_DEVICE_CONTENT_DEVICE"),
    "storage.boot_filesystem": ("string", "BIRD_DEVICE_BOOT_FILESYSTEM"),
    "storage.root_filesystem": ("string", "BIRD_DEVICE_ROOT_FILESYSTEM"),
    "storage.content_filesystem": ("string", "BIRD_DEVICE_CONTENT_FILESYSTEM"),
    "mount.flash": ("string", "BIRD_DEVICE_FLASH_ROOT"),
    "mount.runtime_storage": ("string", "BIRD_DEVICE_RUNTIME_STORAGE"),
    "mount.application_roms": ("string", "BIRD_DEVICE_APPLICATION_ROMS"),
    "mount.application_media": ("string", "BIRD_DEVICE_APPLICATION_MEDIA"),
    "mount.catalog_root": ("string", "BIRD_DEVICE_CATALOG_ROOT"),
}


def c_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_contract(path: pathlib.Path) -> dict[str, tuple[str, str]]:
    result: dict[str, tuple[str, str]] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3:
            raise SystemExit(f"{path}:{line_number}: expected key, type, value")
        key, kind, value = fields
        if key in result:
            raise SystemExit(f"{path}:{line_number}: duplicate key: {key}")
        if not re.fullmatch(r"[a-z][a-z0-9_.]*", key):
            raise SystemExit(f"{path}:{line_number}: invalid key: {key}")
        if kind not in {"string", "u32", "hex", "bool", "bitmap64"}:
            raise SystemExit(f"{path}:{line_number}: invalid type: {kind}")
        if "\r" in value or "\n" in value or not value:
            raise SystemExit(f"{path}:{line_number}: invalid value")
        result[key] = kind, value
    missing = sorted(set(REQUIRED) - set(result))
    extra = sorted(set(result) - set(REQUIRED))
    if missing or extra:
        raise SystemExit(f"contract key mismatch; missing={missing}, extra={extra}")
    return result


def render(contract: dict[str, tuple[str, str]]) -> str:
    lines = [
        "/* Generated by generate-device-contract.py; do not edit manually. */",
        "#ifndef BIRD_DEVICE_CONTRACT_H",
        "#define BIRD_DEVICE_CONTRACT_H",
        "",
    ]
    for key, (expected_kind, macro) in REQUIRED.items():
        kind, value = contract[key]
        if kind != expected_kind:
            raise SystemExit(f"{key}: expected type {expected_kind}, found {kind}")
        if kind == "string":
            rendered = c_string(value)
        elif kind == "u32":
            number = int(value, 10)
            if number < 0 or number > 0xFFFFFFFF or str(number) != value:
                raise SystemExit(f"{key}: invalid canonical u32: {value}")
            rendered = f"{number}U"
        elif kind == "hex":
            if not re.fullmatch(r"0x[0-9a-f]+", value):
                raise SystemExit(f"{key}: invalid canonical hex: {value}")
            rendered = f"{value}UL"
        elif kind == "bool":
            if value not in {"true", "false"}:
                raise SystemExit(f"{key}: invalid bool: {value}")
            rendered = "1U" if value == "true" else "0U"
        else:
            words = value.split(",")
            if not words or any(
                not re.fullmatch(r"0x[0-9a-f]{16}", word) for word in words
            ):
                raise SystemExit(f"{key}: invalid canonical bitmap64: {value}")
            lines.append(f"#define {macro}_WORD_COUNT {len(words)}U")
            rendered_words = ", ".join(f"{word}UL" for word in words)
            lines.append(f"#define {macro}_WORDS {{ {rendered_words} }}")
            continue
        lines.append(f"#define {macro} {rendered}")
    lines.extend(
        [
            "",
            "#if BIRD_DEVICE_FB_STRIDE != (BIRD_DEVICE_FB_WIDTH * BIRD_DEVICE_FB_BYTES_PER_PIXEL)",
            '#error "fixed framebuffer stride is inconsistent"',
            "#endif",
            "#if BIRD_DEVICE_FB_MAPPING_BYTES != (BIRD_DEVICE_FB_STRIDE * BIRD_DEVICE_FB_HEIGHT)",
            '#error "fixed framebuffer mapping size is inconsistent"',
            "#endif",
            "",
            "#endif",
            "",
        ]
    )
    return "\n".join(lines)


def render_suspend_policy(contract: dict[str, tuple[str, str]]) -> str:
    """Render the small shell subset consumed before final-root systemd."""
    allow_suspend = "yes" if contract["suspend.systemd_allow_suspend"][1] == "true" else "no"
    values = (
        ("BIRD_SUSPEND_PROVIDER_MODE", contract["suspend.provider_mode"][1]),
        ("BIRD_SUSPEND_FAKE_ENABLED", contract["suspend.fake_enabled"][1]),
        (
            "BIRD_SUSPEND_TIMED_SHUTDOWN_ENABLED",
            contract["suspend.timed_shutdown_enabled"][1],
        ),
        (
            "BIRD_SUSPEND_CORE_PARKING_REQUIRED",
            contract["suspend.core_parking_required"][1],
        ),
        ("BIRD_SUSPEND_SYSTEMD_ALLOW_SUSPEND", allow_suspend),
        (
            "BIRD_SUSPEND_LOGIND_HANDLE_POWER_KEY",
            contract["suspend.logind_handle_power_key"][1],
        ),
        (
            "BIRD_SUSPEND_LOGIND_HANDLE_SUSPEND_KEY",
            contract["suspend.logind_handle_suspend_key"][1],
        ),
        (
            "BIRD_SUSPEND_LOGIND_HANDLE_LID_SWITCH",
            contract["suspend.logind_handle_lid_switch"][1],
        ),
    )
    lines = [
        "# Generated by generate-device-contract.py; do not edit manually.",
    ]
    lines.extend(f"{name}={shlex.quote(value)}" for name, value in values)
    lines.append("")
    return "\n".join(lines)


def render_sleep_policy(contract: dict[str, tuple[str, str]]) -> str:
    allow_suspend = "yes" if contract["suspend.systemd_allow_suspend"][1] == "true" else "no"
    return (
        "# Generated by generate-device-contract.py; do not edit manually.\n"
        "[Sleep]\n"
        f"AllowSuspend={allow_suspend}\n"
    )


def render_logind_policy(contract: dict[str, tuple[str, str]]) -> str:
    power = contract["suspend.logind_handle_power_key"][1]
    suspend = contract["suspend.logind_handle_suspend_key"][1]
    lid = contract["suspend.logind_handle_lid_switch"][1]
    return (
        "# Generated by generate-device-contract.py; do not edit manually.\n"
        "[Login]\n"
        f"HandlePowerKey={power}\n"
        f"HandleSuspendKey={suspend}\n"
        f"HandleLidSwitch={lid}\n"
        f"HandleLidSwitchExternalPower={lid}\n"
        f"HandleLidSwitchDocked={lid}\n"
    )


def emit(path: pathlib.Path, content: str, check: bool, description: str) -> None:
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != content:
            raise SystemExit(f"generated {description} is stale: {path}")
        return
    path.write_text(content, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("contract", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--suspend-policy-output", type=pathlib.Path)
    parser.add_argument("--sleep-policy-output", type=pathlib.Path)
    parser.add_argument("--logind-policy-output", type=pathlib.Path)
    args = parser.parse_args()
    policy_outputs = (
        args.suspend_policy_output,
        args.sleep_policy_output,
        args.logind_policy_output,
    )
    if any(policy_outputs) and not all(policy_outputs):
        parser.error("all three suspend policy outputs must be provided together")

    contract = parse_contract(args.contract)
    emit(args.output, render(contract), args.check, "device contract")
    if all(policy_outputs):
        emit(
            args.suspend_policy_output,
            render_suspend_policy(contract),
            args.check,
            "suspend shell policy",
        )
        emit(
            args.sleep_policy_output,
            render_sleep_policy(contract),
            args.check,
            "systemd sleep policy",
        )
        emit(
            args.logind_policy_output,
            render_logind_policy(contract),
            args.check,
            "systemd logind policy",
        )


if __name__ == "__main__":
    main()
