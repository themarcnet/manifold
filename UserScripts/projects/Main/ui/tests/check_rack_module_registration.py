#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
MIDISYNTH_PATH = SCRIPT_DIR.parent / "behaviors" / "midisynth.lua"
MIDISYNTH_VIEW_PATH = SCRIPT_DIR.parent / "components" / "midisynth_view.ui.lua"

KNOWN_MODULES = [
    {
        "module_id": "adsr",
        "spawn_kind": "adsr-module",
        "component_id": "envelopeComponent",
        "card_id": "paletteAdsrCard",
        "nav_id": "utilityNavVoiceAdsr",
    },
    {
        "module_id": "arp",
        "spawn_kind": "arp-module",
        "component_id": "arpComponent",
        "card_id": "paletteArpCard",
        "nav_id": "utilityNavVoiceArp",
    },
    {
        "module_id": "transpose",
        "spawn_kind": "transpose-module",
        "component_id": "transposeComponent",
        "card_id": "paletteTransposeCard",
        "nav_id": "utilityNavVoiceTranspose",
    },
    {
        "module_id": "velocity_mapper",
        "spawn_kind": "velocity-mapper-module",
        "component_id": "velocityMapperComponent",
        "card_id": "paletteVelocityMapperCard",
        "nav_id": "utilityNavVoiceVelocityMapper",
        "status_text": "No free Velocity slots",
    },
    {
        "module_id": "scale_quantizer",
        "spawn_kind": "scale-quantizer-module",
        "component_id": "scaleQuantizerComponent",
        "card_id": "paletteScaleQuantizerCard",
        "nav_id": "utilityNavVoiceScaleQuantizer",
    },
    {
        "module_id": "note_filter",
        "spawn_kind": "note-filter-module",
        "component_id": "noteFilterComponent",
        "card_id": "paletteNoteFilterCard",
        "nav_id": "utilityNavVoiceNoteFilter",
        "status_text": "No free Note Filter slots",
    },
    {
        "module_id": "rack_oscillator",
        "spawn_kind": "oscillator-module",
        "component_id": "rackOscillatorComponent",
        "card_id": "paletteRackOscillatorCard",
        "nav_id": "utilityNavAudioOsc",
    },
    {
        "module_id": "filter",
        "spawn_kind": "filter-module",
        "component_id": "filterComponent",
        "card_id": "paletteFilterCard",
        "nav_id": "utilityNavAudioFilter",
    },
    {
        "module_id": "eq",
        "spawn_kind": "eq-module",
        "component_id": "eqComponent",
        "card_id": "paletteEqCard",
        "nav_id": "utilityNavFxEq",
    },
    {
        "module_id": "fx",
        "spawn_kind": "fx-module",
        "component_id": "fx1Component",
        "card_id": "paletteFxCard",
        "nav_id": "utilityNavFxFx",
    },
    {
        "module_id": "attenuverter_bias",
        "spawn_kind": "attenuverter-bias-module",
        "component_id": "attenuverterBiasComponent",
        "card_id": "paletteAttenuverterBiasCard",
        "nav_id": "utilityNavModAttenuverterBias",
        "status_text": "No free ATV / Bias slots",
    },
    {
        "module_id": "lfo",
        "spawn_kind": "lfo-module",
        "component_id": "lfoComponent",
        "card_id": "paletteLfoCard",
        "nav_id": "utilityNavModLfo",
        "status_text": "No free LFO slots",
    },
    {
        "module_id": "slew",
        "spawn_kind": "slew-module",
        "component_id": "slewComponent",
        "card_id": "paletteSlewCard",
        "nav_id": "utilityNavModSlew",
        "status_text": "No free Slew slots",
    },
    {
        "module_id": "sample_hold",
        "spawn_kind": "sample-hold-module",
        "component_id": "sampleHoldComponent",
        "card_id": "paletteSampleHoldCard",
        "nav_id": "utilityNavModSampleHold",
        "status_text": "No free Sample Hold slots",
    },
    {
        "module_id": "compare",
        "spawn_kind": "compare-module",
        "component_id": "compareComponent",
        "card_id": "paletteCompareCard",
        "nav_id": "utilityNavModCompare",
        "status_text": "No free Compare slots",
    },
    {
        "module_id": "cv_mix",
        "spawn_kind": "cv-mix-module",
        "component_id": "cvMixComponent",
        "card_id": "paletteCvMixCard",
        "nav_id": "utilityNavModCvMix",
        "status_text": "No free CV Mix slots",
    },
    {
        "module_id": "range_mapper",
        "spawn_kind": "range_mapper-module",
        "component_id": "rangeMapperComponent",
        "card_id": "paletteRangeMapperCard",
        "nav_id": "utilityNavFxRange",
        "status_text": "No free Range slots",
    },
]


def load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"ERROR reading {path}: {exc}") from exc


def build_descriptor_from_args(args: argparse.Namespace) -> dict[str, str]:
    required = ["module_id", "spawn_kind", "component_id", "card_id", "nav_id"]
    missing = [name for name in required if getattr(args, name) in (None, "")]
    if missing:
        raise SystemExit("ERROR missing required args for custom module check: " + ", ".join(missing))
    descriptor = {
        "module_id": args.module_id,
        "spawn_kind": args.spawn_kind,
        "component_id": args.component_id,
        "card_id": args.card_id,
        "nav_id": args.nav_id,
    }
    if args.status_text:
        descriptor["status_text"] = args.status_text
    return descriptor


def checks_for(descriptor: dict[str, str]) -> list[tuple[str, str, str]]:
    module_id = descriptor["module_id"]
    spawn_kind = descriptor["spawn_kind"]
    component_id = descriptor["component_id"]
    card_id = descriptor["card_id"]
    nav_id = descriptor["nav_id"]
    checks = [
        ("midisynth", f'makePaletteEntry("{module_id}", {{', "palette entry registration"),
        ("midisynth", f'cardId = "{card_id}"', "palette card binding"),
        ("midisynth", f'spawnKind = "{spawn_kind}"', "palette spawn kind"),
        ("midisynth", f'componentId = "{component_id}"', "palette component id"),
        ("midisynth", f'spawnKind == "{spawn_kind}"', "spawn-kind branch"),
        ("midisynth", f'RackModuleFactory.nextAvailableSlot(ctx, "{module_id}")', "availability check"),
        ("midisynth", f'RackModuleFactory.createDynamicSpawnMeta(ctx, "{module_id}"', "dynamic spawn wiring"),
        ("midisynth", f'{module_id} = "{nav_id}"', "nav browse mapping"),
        ("midisynth", f'bindButton(".{nav_id}", function()', "nav button binding"),
        ("midisynth", f'M._selectPaletteEntry(ctx, "{module_id}")', "palette selection binding"),
        ("midisynth_view", f'id = "{card_id}"', "fixed palette card widget"),
        ("midisynth_view", f'id = "{nav_id}"', "fixed nav widget"),
    ]
    status_text = descriptor.get("status_text")
    if status_text:
        checks.append(("midisynth", status_text, "module-specific status text"))
    return checks


def run_checks(descriptor: dict[str, str], texts: dict[str, str]) -> list[str]:
    missing: list[str] = []
    for source_key, snippet, label in checks_for(descriptor):
        if snippet not in texts[source_key]:
            missing.append(f"{descriptor['module_id']}: missing {label} -> {snippet}")
    return missing


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Static registration-surface checker for rack modules")
    parser.add_argument("--module-id")
    parser.add_argument("--spawn-kind")
    parser.add_argument("--component-id")
    parser.add_argument("--card-id")
    parser.add_argument("--nav-id")
    parser.add_argument("--status-text")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    texts = {
        "midisynth": load_text(MIDISYNTH_PATH),
        "midisynth_view": load_text(MIDISYNTH_VIEW_PATH),
    }

    if args.module_id:
        descriptors = [build_descriptor_from_args(args)]
    else:
        descriptors = KNOWN_MODULES

    failures: list[str] = []
    for descriptor in descriptors:
        failures.extend(run_checks(descriptor, texts))

    if failures:
        for failure in failures:
            print("ERROR", failure)
        return 1

    print(f"OK rack_module_registration {len(descriptors)} modules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
