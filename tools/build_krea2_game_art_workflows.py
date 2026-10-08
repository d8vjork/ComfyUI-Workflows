#!/usr/bin/env python3
"""Build Orbion game-art presets from Comfy-Org's Krea 2 style template."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


PRESETS = {
    "icon": {
        "workflow_id": "e08da194-e086-4cbe-b0e6-74b87da58656",
        "subgraph_name": "Orbion Item Icon (Krea-2 Turbo + Style Reference)",
        "node_title": "ITEM ICON — EDIT PROMPT HERE",
        "reference_title": "Item icon style reference",
        "reference": "orbion_resonant_robe_reference.png",
        "prefix": "Orbion/Krea2_Item_Icon",
        "prompt": (
            "Game inventory icon of a single arcane desert-mage robe, made from layered "
            "weathered sand-colored linen with wide sleeves, an aged brown leather sash, "
            "small bronze fasteners, and one luminous cyan crystal clasp. The garment is "
            "centered and isolated, full object visible, three-quarter front view, with a "
            "clean readable silhouette and generous empty margin. Hand-painted high-fantasy "
            "anime RPG concept art, tactile cloth fibers, restrained ornament, crisp edges, "
            "warm rim light, subtle contact shadow, production-ready game asset. Plain uniform "
            "deep charcoal background; no scene, no character, no body, no mannequin, no "
            "hands, no pedestal, no border, no frame, no interface, no text, no letters, no "
            "watermark. Square composition."
        ),
        "note": """# Orbion — Krea 2 item-icon preset

1. Load an item icon whose **rendering style** you want to follow.
2. Edit the prompt in the orange node. Replace the subject/material details, but keep the composition constraints.
3. Keep **prompt_enhance off** for predictable isolated assets. Queue several random seeds and curate.
4. The 1024 px result is a master; downsample to the shipping icon size after cleanup.

## Transparency

Krea 2 outputs RGB, not true alpha. This preset requests a uniform charcoal background so it is easy to remove in an image editor or an RMBG/BiRefNet node. Inspect hems, hair-like fibers, holes, and translucent materials before shipping.

## Reference behavior

The reference controls style more reliably than exact shape. Describe silhouette, view, material, color, and exclusions in the prompt. A reference image must exist in ComfyUI's `input` folder under the filename selected in the Load Image node.

## Prompt skeleton

`Game inventory icon of a single [ITEM], made from [MATERIALS], [VIEW], centered and isolated, full object visible, clean readable silhouette, generous empty margin. Hand-painted high-fantasy anime RPG concept art, tactile materials, crisp edges, production-ready game asset. Plain uniform deep charcoal background; no scene, no character, no body, no mannequin, no hands, no pedestal, no border, no frame, no interface, no text, no watermark. Square composition.`

Models: `krea2_turbo_int8_convrot.safetensors`, `qwen3vl_4b_fp8_scaled.safetensors`, `qwen_image_vae.safetensors`, and `krea2_style_reference.safetensors`.
""",
    },
    "portrait": {
        "workflow_id": "f9dd3cd2-260d-4e30-9270-feea46a2408c",
        "subgraph_name": "Orbion Fantasy Portrait (Krea-2 Turbo + Style Reference)",
        "node_title": "CHARACTER PORTRAIT — EDIT PROMPT HERE",
        "reference_title": "Fantasy portrait style reference",
        "reference": "orbion_maren_vael_reference.png",
        "prefix": "Orbion/Krea2_Character_Portrait",
        "prompt": (
            "Square chest-up fantasy character portrait of Maren Vael, a confident young "
            "crystal prospector, in three-quarter view looking slightly over her shoulder. "
            "She has wind-tossed auburn hair gathered in a loose messy bun, grey-green eyes, "
            "natural freckles, and subtle angular mineral-dust markings on one cheek. She wears "
            "a weathered slate-blue hooded cloak over practical cream clothing, crossed brown "
            "leather harness straps, bronze buckles, and a small luminous cyan crystal pendant. "
            "Behind her is a mountain mining settlement with timber cranes, warm work lights, "
            "snowy blue peaks, and clusters of glowing blue crystals. Polished fantasy anime "
            "game key art, painterly texture, expressive realistic face, crisp eyes, detailed "
            "strands of hair, cinematic warm rim light against cool daylight, rich blue and "
            "amber color contrast, shallow atmospheric depth, no text, no logo, no watermark."
        ),
        "note": """# Orbion — Krea 2 fantasy-portrait preset

1. Load a portrait whose **rendering style, palette, and framing** you want to follow.
2. Edit the prompt in the orange node: identity, expression, costume, props, location, and lighting should all be explicit.
3. Keep **prompt_enhance off** while locking a character design. Queue several seeds, then keep the seed of the strongest face.
4. For recurring characters, style reference alone is not an identity lock. Train a character LoRA on Krea 2 RAW once the design is approved, then use it with Turbo.

## Prompt skeleton

`Square chest-up fantasy character portrait of [NAME/ROLE], [POSE AND GAZE]. [FACE, HAIR, DISTINCTIVE MARKS]. Wearing [COSTUME, MATERIALS, ACCESSORIES]. Behind them is [LOCATION]. Polished fantasy anime game key art, painterly texture, expressive realistic face, crisp eyes, cinematic warm rim light against cool daylight, rich color contrast, atmospheric depth, no text, no logo, no watermark.`

The reference image must exist in ComfyUI's `input` folder under the filename selected in the Load Image node.

Models: `krea2_turbo_int8_convrot.safetensors`, `qwen3vl_4b_fp8_scaled.safetensors`, `qwen_image_vae.safetensors`, and `krea2_style_reference.safetensors`.
""",
    },
}


def exactly_one(items: list[dict], node_type: str) -> dict:
    matches = [node for node in items if node.get("type") == node_type]
    if len(matches) != 1:
        raise ValueError(f"Expected one {node_type} node, found {len(matches)}")
    return matches[0]


def build(template: dict, preset: dict) -> dict:
    graph = copy.deepcopy(template)
    graph["id"] = preset["workflow_id"]
    graph["revision"] = 0

    save = exactly_one(graph["nodes"], "SaveImage")
    save["title"] = "SAVE PNG"
    save["widgets_values"][0] = preset["prefix"]

    reference = exactly_one(graph["nodes"], "LoadImage")
    reference["title"] = preset["reference_title"]
    reference["widgets_values"][0] = preset["reference"]

    resolution = exactly_one(graph["nodes"], "ResolutionSelector")
    resolution["title"] = "MASTER SIZE — 1:1 / 1 MP"
    resolution["widgets_values"] = ["1:1 (Square)", 1, 8]

    note = exactly_one(graph["nodes"], "MarkdownNote")
    note["title"] = "READ ME — preset guide"
    note["widgets_values"][0] = preset["note"]

    subgraph = graph["definitions"]["subgraphs"][0]
    subgraph["name"] = preset["subgraph_name"]
    wrapper = exactly_one(graph["nodes"], subgraph["id"])
    wrapper["title"] = preset["node_title"]
    values = wrapper["widgets_values"]
    values[0] = preset["prompt"]
    values[1] = False  # prompt enhancement
    values[2] = False  # LLM thinking mode
    values[3] = 512
    values[4] = 1024
    values[5] = 1024
    values[7] = "krea2_style_reference.safetensors"
    values[8] = 1.0
    values[9] = "krea2_turbo_int8_convrot.safetensors"
    values[10] = "qwen3vl_4b_fp8_scaled.safetensors"
    values[11] = "qwen_image_vae.safetensors"
    return graph


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("template", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    template = json.loads(args.template.read_text())
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for name, preset in PRESETS.items():
        output = args.output_dir / f"krea2_orbion_{name}_style_reference.json"
        output.write_text(json.dumps(build(template, preset), indent=2) + "\n")
        print(output)


if __name__ == "__main__":
    main()
