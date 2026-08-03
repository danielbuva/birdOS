#!/usr/bin/env python3
"""Prove the fixed H700 profile matches pinned ROCKNIX mkcontroller output."""

from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
XML = ROOT / "kernel/work/rocknix-system-exact-20260701/usr/config/emulationstation/es_input.cfg"
PROFILE = ROOT / "kernel/rocknix/stock-root/bird-controller-profile"

root = ET.parse(XML).getroot()
configs = [node for node in root.findall("inputConfig") if node.get("deviceName") == "H700 Gamepad"]
assert len(configs) == 1

values: dict[str, str] = {}
for node in configs[0].findall("input"):
    name = node.get("name", "")
    input_type = node.get("type", "")
    ident = node.get("id", "")
    value = node.get("value", "")
    if input_type == "axis":
        ident += "+" if value[:1].isdigit() else "-"
    elif input_type == "hat":
        ident = f"h{ident}{name}"
    name = {
        "pagedown": "leftshoulder",
        "pageup": "rightshoulder",
        "l2": "lefttrigger",
        "r2": "righttrigger",
        "l3": "leftthumb",
        "r3": "rightthumb",
    }.get(name, name)
    values[name] = ident

def opposite(value: str) -> str:
    if value.endswith("-"):
        return value[:-1] + "+"
    if value.endswith("+"):
        return value[:-1] + "-"
    return ""

fields = [
    ("SOUTH", "b"), ("EAST", "a"), ("NORTH", "x"), ("WEST", "y"),
    ("TL", "leftshoulder"), ("TR", "rightshoulder"),
    ("TL2", "lefttrigger"), ("TR2", "righttrigger"),
]
expected = [f'DEVICE_BTN_{label}="{values[name]}"' for label, name in fields]
expected.extend([
    f'DEVICE_BTN_TL2_MINUS="{opposite(values["lefttrigger"])}"',
    f'DEVICE_BTN_TR2_MINUS="{opposite(values["righttrigger"])}"',
])
fields = [
    ("SELECT", "select"), ("START", "start"), ("MODE", "hotkeyenable"),
    ("THUMBL", "leftthumb"), ("THUMBR", "rightthumb"),
    ("DPAD_UP", "up"), ("DPAD_DOWN", "down"),
    ("DPAD_LEFT", "left"), ("DPAD_RIGHT", "right"),
    ("AL_DOWN", "leftanalogdown"), ("AL_UP", "leftanalogup"),
    ("AL_LEFT", "leftanalogleft"), ("AL_RIGHT", "leftanalogright"),
    ("AR_DOWN", "rightanalogdown"), ("AR_UP", "rightanalogup"),
    ("AR_LEFT", "rightanalogleft"), ("AR_RIGHT", "rightanalogright"),
]
expected.extend(f'DEVICE_BTN_{label}="{values[name]}"' for label, name in fields)

assert PROFILE.read_text().splitlines() == expected
print("fixed H700 controller profile tests: PASS")
