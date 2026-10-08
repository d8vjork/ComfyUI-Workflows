#!/usr/bin/env python3
"""Replace the stock prompt-enhancer branch with the Heretic GGUF rewriter."""

from __future__ import annotations

import json
import sys
from pathlib import Path


PE_MODEL = "pe_t2i_heretic-Q4_K_M.gguf"
REWRITE_NODE_ID = 471
REMOVED_NODE_IDS = {473, 475}
REMOVED_INPUT_NAMES = {"thinking", "max_length", "clip_name_1"}

PE_NOTE = """## Prompt Enhancer — Heretic GGUF

This workflow uses **pe_t2i_heretic-Q4_K_M.gguf** from pottokao/Qwen-Image-2.1-PE-T2I-Heretic-GGUF through **Qwen Image 2.1 PE Rewrite T8**.

- `refine_prompt`: on (the default) rewrites the prompt; off passes it through unchanged and does not load the PE model.
- The enhancer runs locally through `llama-server`, extracts `rewritten_prompt` from the model's JSON response, and then unloads the model.
- The model-selected aspect ratio is reported by the enhancer, but this workflow continues to use the size selected in ResolutionSelector.
- The checkpoint is licensed for non-commercial research/evaluation under the Qwen Research License. Commercial use requires a separate Qwen licence.
"""


def rewrite_node() -> dict:
    image_inputs = [
        {
            "localized_name": f"image_{index}",
            "name": f"image_{index}",
            "shape": 7,
            "type": "IMAGE",
            "link": None,
        }
        for index in range(1, 11)
    ]
    widget_specs = [
        ("user_prompt", "STRING", 711),
        ("task", "COMBO", None),
        ("aspect_ratio", "COMBO", None),
        ("output_language", "COMBO", None),
        ("transparent_rgba", "BOOLEAN", None),
        ("t2i_model", "COMBO", None),
        ("edit_model", "COMBO", None),
        ("vision_model", "COMBO", None),
        ("model_lifetime", "COMBO", None),
        ("seed", "INT", 697),
    ]
    widget_inputs = [
        {
            "localized_name": name,
            "name": name,
            "type": value_type,
            "widget": {"name": name},
            "link": link,
        }
        for name, value_type, link in widget_specs
    ]
    values = [
        "",
        "t2i",
        "auto",
        "English",
        False,
        PE_MODEL,
        PE_MODEL,
        "Auto",
        "after_run",
        0,
        "fixed",
    ]
    return {
        "id": REWRITE_NODE_ID,
        "type": "QwenPERewriteT8",
        "title": "Heretic prompt enhancer",
        "pos": [350, -520],
        "size": [480, 590],
        "flags": {},
        "order": 8,
        "mode": 0,
        "inputs": image_inputs + widget_inputs,
        "outputs": [
            {
                "localized_name": "rewritten_prompt",
                "name": "rewritten_prompt",
                "type": "STRING",
                "links": [712],
            },
            {
                "localized_name": "pe_result",
                "name": "pe_result",
                "type": "PE_RESULT",
                "links": None,
            },
            {
                "localized_name": "diagnostics",
                "name": "diagnostics",
                "type": "STRING",
                "links": None,
            },
        ],
        "properties": {"Node name for S&R": "QwenPERewriteT8"},
        "widgets_values": values,
        "widgets_values_named": {
            "user_prompt": "",
            "task": "t2i",
            "aspect_ratio": "auto",
            "output_language": "English",
            "transparent_rgba": False,
            "t2i_model": PE_MODEL,
            "edit_model": PE_MODEL,
            "vision_model": "Auto",
            "model_lifetime": "after_run",
            "seed": 0,
        },
    }


def update_note(workflow: dict, node_id: int, text: str) -> None:
    node = next(node for node in workflow["nodes"] if node["id"] == node_id)
    node["widgets_values"] = [text]
    node["widgets_values_named"] = {"text": text}


def transform(workflow: dict) -> None:
    subgraph = workflow["definitions"]["subgraphs"][0]
    existing = next((node for node in subgraph["nodes"] if node["id"] == REWRITE_NODE_ID), None)

    if existing and existing.get("type") != "QwenPERewriteT8":
        old_inputs = subgraph["inputs"]
        kept_inputs = [item for item in old_inputs if item["name"] not in REMOVED_INPUT_NAMES]
        slot_map = {}
        new_slot = 0
        for old_slot, item in enumerate(old_inputs):
            if item["name"] in REMOVED_INPUT_NAMES:
                continue
            slot_map[old_slot] = new_slot
            new_slot += 1
        subgraph["inputs"] = kept_inputs

        links = []
        for link in subgraph["links"]:
            if link["origin_id"] in REMOVED_NODE_IDS or link["target_id"] in REMOVED_NODE_IDS:
                continue
            if link["origin_id"] == -10:
                if link["origin_slot"] not in slot_map:
                    continue
                link["origin_slot"] = slot_map[link["origin_slot"]]
            if link["target_id"] == REWRITE_NODE_ID:
                if link["id"] == 711:
                    link["target_slot"] = 10
                elif link["id"] == 697:
                    link["target_slot"] = 19
                else:
                    continue
            links.append(link)
        subgraph["links"] = links

        subgraph["nodes"] = [
            node for node in subgraph["nodes"] if node["id"] not in REMOVED_NODE_IDS | {REWRITE_NODE_ID}
        ]
        subgraph["nodes"].append(rewrite_node())

        outer = next(node for node in workflow["nodes"] if node["type"] == subgraph["id"])
        old_outer_inputs = outer["inputs"]
        kept_outer_inputs = [
            item for item in old_outer_inputs if item["name"] not in {"thinking", "clip_name_1"}
        ]
        outer_slot_map = {}
        new_slot = 0
        for old_slot, item in enumerate(old_outer_inputs):
            if item["name"] in {"thinking", "clip_name_1"}:
                continue
            outer_slot_map[old_slot] = new_slot
            new_slot += 1
        outer["inputs"] = kept_outer_inputs

        for link in workflow["links"]:
            if link[3] == outer["id"]:
                link[4] = outer_slot_map[link[4]]

        outer["widgets_values"] = [
            value
            for index, value in enumerate(outer["widgets_values"])
            if index not in {2, 3, 15}
        ]
        outer["widgets_values"][1] = True
        for name in REMOVED_INPUT_NAMES:
            outer["widgets_values_named"].pop(name, None)
        outer["widgets_values_named"]["switch"] = True
    elif existing:
        replacement = rewrite_node()
        existing.clear()
        existing.update(replacement)
        outer = next(node for node in workflow["nodes"] if node["type"] == subgraph["id"])
        outer["widgets_values"][1] = True
        outer["widgets_values_named"]["switch"] = True
    else:
        raise ValueError("Expected stock TextGenerate node 471 was not found")

    subgraph["name"] = "Text / Reference to Image (Qwen Image 2.1 Uncensored GGUF + Heretic PE)"
    update_note(workflow, 483, PE_NOTE)

    model_note = next(node for node in workflow["nodes"] if node["id"] == 463)
    text = model_note["widgets_values"][0].rstrip()
    if PE_MODEL not in text:
        text += (
            "\n\nPrompt enhancement adds:\n\n"
            f"- prompt enhancer/{PE_MODEL}\n"
            "- Comfyui-Qwen-Image-Prompt-Rewrite-T8\n"
            "- llama-server (llama.cpp)\n"
        )
    update_note(workflow, 463, text)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} WORKFLOW.json")
    path = Path(sys.argv[1])
    workflow = json.loads(path.read_text(encoding="utf-8"))
    transform(workflow)
    path.write_text(json.dumps(workflow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
