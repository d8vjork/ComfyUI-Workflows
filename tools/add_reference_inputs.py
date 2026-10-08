#!/usr/bin/env python3
"""Add an optional multi-image reference branch to the Qwen Image 2.1 workflow."""

from __future__ import annotations

import json
import sys
from pathlib import Path


TOP_LOAD_IMAGE_ID = 484
IMAGE_SWITCH_IDS = [486, 487, 488, 489]
LATENT_SWITCH_ID = 490

TOP_IMAGE_LINK = 714
MODE_LINKS = [715, 716, 717, 718, 719]
REFERENCE_INPUT_LINKS = [720, 721, 722, 723]
REFERENCE_OUTPUT_LINKS = [724, 725, 726, 727]
VAE_TO_ENCODER_LINK = 728
ENCODER_LATENT_LINK = 729
EMPTY_LATENT_LINK = 730


def find_node(nodes: list[dict], node_id: int) -> dict:
    return next(node for node in nodes if node["id"] == node_id)


def switch_node(
    node_id: int,
    title: str,
    value_type: str,
    pos: list[int],
    false_link: int | None,
    true_link: int,
    mode_link: int,
    output_link: int,
) -> dict:
    return {
        "id": node_id,
        "type": "ComfySwitchNode",
        "pos": pos,
        "size": [300, 130],
        "flags": {},
        "order": 5,
        "mode": 0,
        "inputs": [
            {
                "localized_name": "on_false",
                "name": "on_false",
                "shape": 7,
                "type": value_type,
                "link": false_link,
            },
            {
                "localized_name": "on_true",
                "name": "on_true",
                "shape": 7,
                "type": value_type,
                "link": true_link,
            },
            {
                "localized_name": "switch",
                "name": "switch",
                "type": "BOOLEAN",
                "widget": {"name": "switch"},
                "link": mode_link,
            },
        ],
        "outputs": [
            {
                "localized_name": "output",
                "name": "output",
                "type": value_type,
                "links": [output_link],
            }
        ],
        "title": title,
        "properties": {"Node name for S&R": "ComfySwitchNode"},
        "widgets_values": [False],
        "widgets_values_named": {"switch": False},
    }


def add_reference_branch(workflow: dict) -> dict:
    subgraph = workflow["definitions"]["subgraphs"][0]
    if any(item.get("name") == "reference_mode" for item in subgraph["inputs"]):
        return workflow

    top_nodes = workflow["nodes"]
    sub_nodes = subgraph["nodes"]
    top_node = find_node(top_nodes, 459)
    encoder = find_node(sub_nodes, 452)
    vae_loader = find_node(sub_nodes, 454)
    empty_latent = find_node(sub_nodes, 456)

    reserved_node_ids = {TOP_LOAD_IMAGE_ID, *IMAGE_SWITCH_IDS, LATENT_SWITCH_ID}
    assert not reserved_node_ids.intersection({node["id"] for node in top_nodes + sub_nodes})

    mode_input_index = len(subgraph["inputs"])
    image_input_start = mode_input_index + 1
    input_y = 994
    subgraph["inputs"].append(
        {
            "id": "46e81d08-43a5-48de-b9bc-8e3fa03ff2b1",
            "name": "reference_mode",
            "type": "BOOLEAN",
            "linkIds": MODE_LINKS,
            "label": "use_reference_images",
            "pos": [-540.955078125, input_y],
        }
    )
    for index, link_id in enumerate(REFERENCE_INPUT_LINKS, start=1):
        subgraph["inputs"].append(
            {
                "id": f"a893977d-3f17-4e78-9c52-31eb0b9850{index}",
                "name": f"reference_image_{index}",
                "type": "IMAGE",
                "linkIds": [link_id],
                "label": f"reference_image_{index}",
                "pos": [-540.955078125, input_y + index * 20],
            }
        )
    subgraph["inputNode"]["bounding"][3] = 520

    original_inputs = {item["name"]: item for item in encoder["inputs"]}
    image_inputs = []
    for index, link_id in enumerate(REFERENCE_OUTPUT_LINKS, start=1):
        image_inputs.append(
            {
                "localized_name": f"image_{index}",
                "name": f"images.image_{index}",
                "shape": 7,
                "type": "IMAGE",
                "link": link_id,
            }
        )
    vae_input = original_inputs["vae"]
    vae_input["link"] = VAE_TO_ENCODER_LINK
    encoder["inputs"] = [
        original_inputs["clip"],
        *image_inputs,
        vae_input,
        original_inputs["prompt"],
        original_inputs["negative_prompt"],
    ]
    encoder["outputs"][2]["links"] = [ENCODER_LATENT_LINK]

    for link in subgraph["links"]:
        if link["id"] == 687:
            link["target_slot"] = 6
        elif link["id"] == 657:
            link["target_slot"] = 7
        elif link["id"] == 654:
            link["origin_id"] = LATENT_SWITCH_ID
            link["origin_slot"] = 0

    vae_loader["outputs"][0]["links"].append(VAE_TO_ENCODER_LINK)
    empty_latent["outputs"][0]["links"] = [EMPTY_LATENT_LINK]

    image_switch_positions = [[250, 1140], [250, 1300], [250, 1460], [250, 1620]]
    for index in range(4):
        sub_nodes.append(
            switch_node(
                IMAGE_SWITCH_IDS[index],
                f"Reference image {index + 1} gate",
                "IMAGE",
                image_switch_positions[index],
                None,
                REFERENCE_INPUT_LINKS[index],
                MODE_LINKS[index],
                REFERENCE_OUTPUT_LINKS[index],
            )
        )
    sub_nodes.append(
        switch_node(
            LATENT_SWITCH_ID,
            "Text / reference latent",
            "LATENT",
            [620, 1140],
            EMPTY_LATENT_LINK,
            ENCODER_LATENT_LINK,
            MODE_LINKS[4],
            654,
        )
    )

    for index, link_id in enumerate(MODE_LINKS[:4]):
        subgraph["links"].append(
            {
                "id": link_id,
                "origin_id": -10,
                "origin_slot": mode_input_index,
                "target_id": IMAGE_SWITCH_IDS[index],
                "target_slot": 2,
                "type": "BOOLEAN",
            }
        )
    subgraph["links"].append(
        {
            "id": MODE_LINKS[4],
            "origin_id": -10,
            "origin_slot": mode_input_index,
            "target_id": LATENT_SWITCH_ID,
            "target_slot": 2,
            "type": "BOOLEAN",
        }
    )
    for index, link_id in enumerate(REFERENCE_INPUT_LINKS):
        subgraph["links"].append(
            {
                "id": link_id,
                "origin_id": -10,
                "origin_slot": image_input_start + index,
                "target_id": IMAGE_SWITCH_IDS[index],
                "target_slot": 1,
                "type": "IMAGE",
            }
        )
    for index, link_id in enumerate(REFERENCE_OUTPUT_LINKS):
        subgraph["links"].append(
            {
                "id": link_id,
                "origin_id": IMAGE_SWITCH_IDS[index],
                "origin_slot": 0,
                "target_id": 452,
                "target_slot": index + 1,
                "type": "IMAGE",
            }
        )
    subgraph["links"].extend(
        [
            {
                "id": VAE_TO_ENCODER_LINK,
                "origin_id": 454,
                "origin_slot": 0,
                "target_id": 452,
                "target_slot": 5,
                "type": "VAE",
            },
            {
                "id": ENCODER_LATENT_LINK,
                "origin_id": 452,
                "origin_slot": 2,
                "target_id": LATENT_SWITCH_ID,
                "target_slot": 1,
                "type": "LATENT",
            },
            {
                "id": EMPTY_LATENT_LINK,
                "origin_id": 456,
                "origin_slot": 0,
                "target_id": LATENT_SWITCH_ID,
                "target_slot": 0,
                "type": "LATENT",
            },
        ]
    )

    top_nodes.append(
        {
            "id": TOP_LOAD_IMAGE_ID,
            "type": "LoadImage",
            "pos": [450, 3160],
            "size": [400, 360],
            "flags": {},
            "order": 4,
            "mode": 0,
            "inputs": [
                {
                    "localized_name": "image",
                    "name": "image",
                    "type": "COMBO",
                    "widget": {"name": "image"},
                    "link": None,
                },
                {
                    "localized_name": "choose file to upload",
                    "name": "upload",
                    "type": "IMAGEUPLOAD",
                    "widget": {"name": "upload"},
                    "link": None,
                },
            ],
            "outputs": [
                {
                    "localized_name": "IMAGE",
                    "name": "IMAGE",
                    "type": "IMAGE",
                    "links": [TOP_IMAGE_LINK],
                },
                {
                    "localized_name": "MASK",
                    "name": "MASK",
                    "type": "MASK",
                    "links": None,
                },
            ],
            "title": "Reference image 1",
            "properties": {"Node name for S&R": "LoadImage"},
            "widgets_values": ["", "image"],
        }
    )

    top_node["size"] = [510, 760]
    top_node["order"] = 5
    find_node(top_nodes, 461)["order"] = 6
    top_node["inputs"].extend(
        [
            {
                "label": "use_reference_images",
                "name": "reference_mode",
                "type": "BOOLEAN",
                "widget": {"name": "reference_mode"},
                "link": None,
            },
            {
                "label": "reference_image_1",
                "name": "reference_image_1",
                "shape": 7,
                "type": "IMAGE",
                "link": TOP_IMAGE_LINK,
            },
            {
                "label": "reference_image_2",
                "name": "reference_image_2",
                "shape": 7,
                "type": "IMAGE",
                "link": None,
            },
            {
                "label": "reference_image_3",
                "name": "reference_image_3",
                "shape": 7,
                "type": "IMAGE",
                "link": None,
            },
            {
                "label": "reference_image_4",
                "name": "reference_image_4",
                "shape": 7,
                "type": "IMAGE",
                "link": None,
            },
        ]
    )
    top_node["widgets_values"].append(False)
    top_node["widgets_values_named"]["reference_mode"] = False
    workflow["links"].append(
        [TOP_IMAGE_LINK, TOP_LOAD_IMAGE_ID, 0, 459, len(top_node["inputs"]) - 4, "IMAGE"]
    )

    usage = find_node(top_nodes, 468)
    reference_help = (
        "\n\n## Reference images\n"
        "Upload an image in **Reference image 1**, then turn on "
        "**use_reference_images** in the main Qwen node. The generated image "
        "uses the reference image's dimensions and visual content. Describe "
        "what to preserve or change in the prompt. Three additional image "
        "sockets are exposed on the main node; connect more Load Image nodes "
        "to use up to four references in this workflow. Turn reference mode "
        "off to return to ordinary text-to-image generation."
    )
    usage["widgets_values"][0] += reference_help
    usage["widgets_values_named"]["text"] += reference_help

    workflow["last_node_id"] = LATENT_SWITCH_ID
    workflow["last_link_id"] = EMPTY_LATENT_LINK
    subgraph["state"]["lastNodeId"] = LATENT_SWITCH_ID
    subgraph["state"]["lastLinkId"] = EMPTY_LATENT_LINK
    subgraph["name"] = "Text / Reference to Image (Qwen Image 2.1 Uncensored GGUF)"
    return workflow


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} WORKFLOW.json")
    path = Path(sys.argv[1])
    workflow = json.loads(path.read_text())
    updated = add_reference_branch(workflow)
    path.write_text(json.dumps(updated, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
