#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def build_filter_single(spec):
    public = spec.get("publicPathBase", "/plugin/params").rstrip("/")
    internal = spec.get("internalPathBase", "/midi/synth/rack/filter/1").rstrip("/")
    return [
        {
            "path": f"{public}/type",
            "internalPath": f"{internal}/type",
            "type": "f",
            "min": 0,
            "max": 3,
            "default": 0,
            "hostParamId": "type",
            "hostParamName": "Type",
            "hostParamKind": "choice",
            "choices": ["Low Pass", "Band Pass", "High Pass", "Notch"],
            "description": "Filter type",
        },
        {
            "path": f"{public}/cutoff",
            "internalPath": f"{internal}/cutoff",
            "type": "f",
            "min": 80,
            "max": 16000,
            "default": 3200,
            "skew": 0.35,
            "hostParamId": "cutoff",
            "hostParamName": "Cutoff",
            "hostParamKind": "float",
            "description": "Filter cutoff",
        },
        {
            "path": f"{public}/resonance",
            "internalPath": f"{internal}/resonance",
            "type": "f",
            "min": 0.1,
            "max": 2.0,
            "default": 0.75,
            "hostParamId": "resonance",
            "hostParamName": "Resonance",
            "hostParamKind": "float",
            "description": "Filter resonance",
        },
    ]


def build_eq8_single(spec):
    public = spec.get("publicPathBase", "/plugin/params").rstrip("/")
    internal = spec.get("internalPathBase", "/midi/synth/rack/eq/1").rstrip("/")
    choices = ["Bell", "Low Shelf", "High Shelf", "Low Pass", "High Pass", "Notch", "Band Pass"]
    freqs = [60, 120, 250, 500, 1000, 2500, 6000, 12000]
    params = []

    for idx in range(1, 9):
        default_type = 1 if idx == 1 else 2 if idx == 8 else 0
        default_q = 0.8 if idx in (1, 8) else 1.0
        band_public = f"{public}/band/{idx}"
        band_internal = f"{internal}/band/{idx}"
        params.extend([
            {
                "path": f"{band_public}/enabled",
                "internalPath": f"{band_internal}/enabled",
                "type": "f",
                "min": 0,
                "max": 1,
                "default": 0,
                "hostParamId": f"band_{idx}_enabled",
                "hostParamName": f"Band {idx} Enabled",
                "hostParamKind": "bool",
                "description": f"EQ band {idx} enabled",
            },
            {
                "path": f"{band_public}/type",
                "internalPath": f"{band_internal}/type",
                "type": "i",
                "min": 0,
                "max": 6,
                "default": default_type,
                "hostParamId": f"band_{idx}_type",
                "hostParamName": f"Band {idx} Type",
                "hostParamKind": "choice",
                "choices": choices,
                "description": f"EQ band {idx} type",
            },
            {
                "path": f"{band_public}/freq",
                "internalPath": f"{band_internal}/freq",
                "type": "f",
                "min": 20,
                "max": 20000,
                "default": freqs[idx - 1],
                "skew": 0.35,
                "hostParamId": f"band_{idx}_freq",
                "hostParamName": f"Band {idx} Frequency",
                "hostParamKind": "float",
                "description": f"EQ band {idx} frequency",
            },
            {
                "path": f"{band_public}/gain",
                "internalPath": f"{band_internal}/gain",
                "type": "f",
                "min": -24,
                "max": 24,
                "default": 0,
                "hostParamId": f"band_{idx}_gain",
                "hostParamName": f"Band {idx} Gain",
                "hostParamKind": "float",
                "description": f"EQ band {idx} gain in dB",
            },
            {
                "path": f"{band_public}/q",
                "internalPath": f"{band_internal}/q",
                "type": "f",
                "min": 0.1,
                "max": 24,
                "default": default_q,
                "hostParamId": f"band_{idx}_q",
                "hostParamName": f"Band {idx} Q",
                "hostParamKind": "float",
                "description": f"EQ band {idx} Q factor",
            },
        ])

    params.extend([
        {
            "path": f"{public}/output",
            "internalPath": f"{internal}/output",
            "type": "f",
            "min": -24,
            "max": 24,
            "default": 0,
            "hostParamId": "output",
            "hostParamName": "Output Gain",
            "hostParamKind": "float",
            "description": "EQ output gain",
        },
        {
            "path": f"{public}/mix",
            "internalPath": f"{internal}/mix",
            "type": "f",
            "min": 0,
            "max": 1,
            "default": 1,
            "hostParamId": "mix",
            "hostParamName": "Mix",
            "hostParamKind": "float",
            "description": "EQ dry/wet mix",
        },
    ])
    return params


def build_fx_single(spec):
    public = spec.get("publicPathBase", "/plugin/params").rstrip("/")
    internal = spec.get("internalPathBase", "/midi/synth/rack/fx/1").rstrip("/")
    choices = [
        "Chorus",
        "Phaser",
        "WaveShaper",
        "Compressor",
        "StereoWidener",
        "Filter",
        "SVF Filter",
        "Reverb",
        "Stereo Delay",
        "Multitap",
        "Pitch Shift",
        "Granulator",
        "Ring Mod",
        "Formant",
        "EQ",
        "Limiter",
        "Transient",
        "Bitcrusher",
        "Shimmer",
        "Reverse Delay",
        "Stutter",
    ]
    defaults = [0.5, 0.5, 0.2, 0.6, 0.4]
    params = [
        {
            "path": f"{public}/type",
            "internalPath": f"{internal}/type",
            "type": "f",
            "min": 0,
            "max": len(choices) - 1,
            "default": 0,
            "hostParamId": "type",
            "hostParamName": "Type",
            "hostParamKind": "choice",
            "choices": choices,
            "description": "Effect type",
        },
        {
            "path": f"{public}/mix",
            "internalPath": f"{internal}/mix",
            "type": "f",
            "min": 0,
            "max": 1,
            "default": 0,
            "hostParamId": "mix",
            "hostParamName": "Mix",
            "hostParamKind": "float",
            "description": "Effect dry/wet mix",
        },
    ]

    for idx in range(5):
        params.append(
            {
                "path": f"{public}/p/{idx}",
                "internalPath": f"{internal}/p/{idx}",
                "type": "f",
                "min": 0,
                "max": 1,
                "default": defaults[idx],
                "hostParamId": f"param_{idx + 1}",
                "hostParamName": f"Param {idx + 1}",
                "hostParamKind": "float",
                "description": f"Context-sensitive effect parameter {idx + 1}",
            }
        )

    return params


GENERATORS = {
    "filter_single": build_filter_single,
    "eq8_single": build_eq8_single,
    "fx_single": build_fx_single,
}


def build_manifest(spec):
    manifest = dict(spec)
    plugin = dict(manifest.get("plugin", {}))
    params_spec = plugin.pop("paramsSpec", None)
    if params_spec is None:
        raise ValueError("plugin.paramsSpec is required")

    generator_name = params_spec.get("generator")
    if generator_name == "static":
        plugin["params"] = params_spec.get("entries", [])
    else:
        generator = GENERATORS.get(generator_name)
        if generator is None:
            raise ValueError(f"unsupported params generator: {generator_name}")
        plugin["params"] = generator(params_spec)

    manifest["plugin"] = plugin
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    spec_path = Path(args.spec)
    output_path = Path(args.output)

    with spec_path.open("r", encoding="utf-8") as handle:
        spec = json.load(handle)

    manifest = build_manifest(spec)
    content = json.dumps(manifest, indent=2) + "\n"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        existing = output_path.read_text(encoding="utf-8")
        if existing == content:
            return
    output_path.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
