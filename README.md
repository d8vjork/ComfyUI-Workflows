# ComfyUI workflows for game art

## Krea 2: Orbion icons and fantasy portraits

Two Krea 2 Turbo presets are included:

- `workflows/krea2_orbion_icon_style_reference.json` generates centered,
  readable inventory-item masters using an item icon as a style reference.
- `workflows/krea2_orbion_portrait_style_reference.json` generates square
  fantasy anime character portraits using a portrait as a style reference.

Both start from Comfy-Org's official Krea 2 style-reference graph and use only
native ComfyUI nodes. They run at 1024×1024 with eight Euler/Simple steps,
CFG 1, the official style-reference LoRA at strength 1, and prompt enhancement
off. The long natural-language prompts follow Krea's prompting guidance and are
meant to be edited in the orange subgraph node.

Install the four model files, both workflows, and the two supplied reference
images into this machine's Comfy Desktop instance on macOS with:

```zsh
./setup_krea2_game_art.sh
```

On Windows PowerShell, pass either the ComfyUI directory or the parent portable
directory. Reference-image arguments are optional; when omitted, select images
in the two `LoadImage` nodes after opening the workflows.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./setup_krea2_game_art.ps1 `
  -ComfyRoot "C:\AI\ComfyUI_windows_portable" `
  -IconReference "C:\game-art\resonant-robe.png" `
  -PortraitReference "C:\game-art\neutral.png"
```

For a ComfyUI Desktop or shared-model arrangement, override the destinations:

```powershell
./setup_krea2_game_art.ps1 `
  -ComfyRoot "C:\path\to\ComfyUI" `
  -ModelsRoot "D:\ComfyUI-Shared\models"
```

Use `-SkipModels` to install only the workflows and optional references. The
Windows installer requires `curl.exe`, included with supported Windows 10 and
Windows 11 systems, so interrupted downloads can resume.

For operating the Windows machine as a generator for trusted clients on the
same LAN, follow the
[Windows LAN runbook](docs/windows-lan-krea2-runbook.md). It covers private
firewall rules, startup, connectivity checks, API workflow export, request
lifecycle, troubleshooting, and disabling LAN access.

The download is approximately 19.5 GB (18.1 GiB) and resumes interrupted files.
Published SHA-256 hashes are checked before installation. Restart ComfyUI after
setup, then open either workflow from **Workflows**.

The item workflow saves an RGB master on a uniform charcoal background. Krea 2
does not generate true alpha; remove the background during asset cleanup or add
an RMBG/BiRefNet node before `SaveImage`. Downsample the cleaned 1024 px master
to the game's shipping icon size.

Style-reference conditioning guides appearance but does not lock a recurring
character's identity. Once a design is approved, train a character LoRA on
Krea 2 RAW and use it for repeated production work with Turbo.

Krea 2 is covered by the
[Krea 2 Community License](https://www.krea.ai/krea-2-licensing). Review its
commercial-use threshold and operational requirements before using generated
assets in a released game.

## Qwen-Image 2.1 GGUF

This workspace contains a reproducible setup for the local macOS Comfy Desktop
installation. It uses the recommended lower-memory combination from
`abenzerps/Qwen-Image-2.1-Uncensored-GGUF`:

- `qwen-image-2.1-UC-Q4_K_M.gguf`
- `qwen3vl_8b_int8_convrot.safetensors`
- `qwen_image_2.1_vae_bf16.safetensors`

The installer updates the selected ComfyUI Desktop instance to the `latest`
channel because the previously installed v0.24.1 predates Qwen-Image 2.1
support. It also installs the maintained `leejet/ComfyUI-GGUF` custom node, the
`T8mars/Comfyui-Qwen-Image-Prompt-Rewrite-T8` integration, and `llama.cpp`. It
verifies all model files against published SHA-256 checksums and places a
GGUF-adapted copy of Comfy-Org's official workflow in the Desktop workflow
folder. The prompt enhancer is
`pottokao/Qwen-Image-2.1-PE-T2I-Heretic-GGUF` (`Q4_K_M`).

Run:

```zsh
./setup_qwen_image_2_1.sh
```

The download is approximately 20.5 GB. Interrupted model downloads resume from
their `.partial` files.

## Use the workflow

1. Quit and relaunch Comfy Desktop so it starts the updated backend.
2. Open the local `ComfyUI` instance.
3. Load `qwen_image_2.1_uncensored_gguf_q4km.json` from **Workflows**.
4. Replace the example prompt and queue the workflow.

Keep CFG at `1`. The supplied workflow starts at 1024×1024, 25 steps, Euler,
and the Simple scheduler. The Heretic prompt enhancer starts on: it expands the
prompt locally, extracts the model's `rewritten_prompt` JSON field, feeds that
text to Qwen Image, and unloads the enhancer before image generation. Turn off
`refine_prompt` on the main Qwen node to pass the prompt through unchanged and
skip loading the enhancer.

The enhancer's suggested aspect ratio is intentionally not applied. Canvas size
continues to come from `ResolutionSelector`, so enabling prompt enhancement does
not unexpectedly change the selected output dimensions.

For reference-guided generation, upload a photo in **Reference image 1** and
turn on **use_reference_images** in the main Qwen node. The graph exposes three
additional reference-image sockets; connect more Load Image nodes when needed.
Reference mode follows the first image's dimensions. Turn it off to return to
normal text-to-image generation.

The prompt-enhancer checkpoint is covered by the Qwen Research License and is
for non-commercial research/evaluation. Commercial use requires a separate
licence from Qwen.

`workflows/qwen_image_2.1_uncensored_gguf_smoke_api.json` is the small API-format
workflow used for the successful local execution test.
