#!/bin/zsh

set -euo pipefail

readonly WORKSPACE_DIR="${0:A:h}"
readonly INSTALL_ROOT="/Users/d8vjork/ComfyUI-Installs/ComfyUI"
readonly COMFY_DIR="$INSTALL_ROOT/ComfyUI"
readonly SHARED_MODELS="/Users/d8vjork/ComfyUI-Shared/models"
readonly WORKFLOW_DIR="$COMFY_DIR/user/default/workflows"
readonly INPUT_DIR="$COMFY_DIR/input"

readonly MODEL_NAME="krea2_turbo_int8_convrot.safetensors"
readonly TEXT_ENCODER_NAME="qwen3vl_4b_fp8_scaled.safetensors"
readonly VAE_NAME="qwen_image_vae.safetensors"
readonly STYLE_LORA_NAME="krea2_style_reference.safetensors"

readonly MODEL_SHA256="8e4eeda70dd5037ab1ba2bef6b417f9f901e26093117cf397f741fc1fdaaf3f1"
readonly TEXT_ENCODER_SHA256="54bd5144df0bbc25dd6ccadfcb826b521445a1b06ae5a42570bdd2974ca87094"
readonly VAE_SHA256="a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f"
readonly STYLE_LORA_SHA256="f50df5a9e62e4be8aa926a63dd5bb1a64770c4004f763c1208007ae13daa82b8"

readonly HF_BASE="https://huggingface.co/Comfy-Org/Krea-2/resolve/main"
readonly ICON_REFERENCE_SOURCE="${KREA2_ICON_REFERENCE:-/Users/d8vjork/Projects/D8vjork/Uniplay/games/orbion-tactics/art/icons/items/resonant-robe.png}"
readonly PORTRAIT_REFERENCE_SOURCE="${KREA2_PORTRAIT_REFERENCE:-/Users/d8vjork/Projects/D8vjork/Uniplay/games/orbion-tactics/art/portraits/maren-vael/neutral.png}"

require_path() {
  if [[ ! -e "$1" ]]; then
    print -u2 "Required path is missing: $1"
    exit 1
  fi
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]]
}

download_model() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"

  mkdir -p "${destination:h}"
  if [[ -f "$destination" ]]; then
    if verify_sha256 "$destination" "$expected_sha"; then
      print "Already downloaded and verified: ${destination:t}"
      return
    fi
    print -u2 "Existing file failed its published SHA-256 check: $destination"
    print -u2 "Move or remove it, then run this installer again."
    exit 1
  fi

  local partial="$destination.partial"
  print "Downloading ${destination:t} ..."
  curl --fail --location --retry 5 --retry-all-errors --continue-at - \
    --output "$partial" "$url"
  if ! verify_sha256 "$partial" "$expected_sha"; then
    print -u2 "SHA-256 verification failed for $partial"
    exit 1
  fi
  mv "$partial" "$destination"
  print "Verified: ${destination:t}"
}

require_path "$COMFY_DIR/.git"
require_path "$WORKSPACE_DIR/workflows/krea2_orbion_icon_style_reference.json"
require_path "$WORKSPACE_DIR/workflows/krea2_orbion_portrait_style_reference.json"

if ! rg -q 'class TextEncodeQwenImageEditPlus' "$COMFY_DIR/comfy_extras/nodes_qwen.py" || \
   ! rg -q 'class ModelSamplingFlux' "$COMFY_DIR/comfy_extras/nodes_model_advanced.py"; then
  print -u2 "This ComfyUI build is too old for the native Krea 2 workflow."
  print -u2 "Update ComfyUI, then run this installer again."
  exit 1
fi

download_model "$HF_BASE/diffusion_models/$MODEL_NAME?download=true" \
  "$SHARED_MODELS/diffusion_models/$MODEL_NAME" "$MODEL_SHA256"
download_model "$HF_BASE/text_encoders/$TEXT_ENCODER_NAME?download=true" \
  "$SHARED_MODELS/text_encoders/$TEXT_ENCODER_NAME" "$TEXT_ENCODER_SHA256"
download_model "$HF_BASE/vae/$VAE_NAME?download=true" \
  "$SHARED_MODELS/vae/$VAE_NAME" "$VAE_SHA256"
download_model "$HF_BASE/loras/$STYLE_LORA_NAME?download=true" \
  "$SHARED_MODELS/loras/$STYLE_LORA_NAME" "$STYLE_LORA_SHA256"

mkdir -p "$WORKFLOW_DIR" "$INPUT_DIR"
install -m 0644 "$WORKSPACE_DIR/workflows/krea2_orbion_icon_style_reference.json" "$WORKFLOW_DIR/"
install -m 0644 "$WORKSPACE_DIR/workflows/krea2_orbion_portrait_style_reference.json" "$WORKFLOW_DIR/"

if [[ -f "$ICON_REFERENCE_SOURCE" ]]; then
  install -m 0644 "$ICON_REFERENCE_SOURCE" "$INPUT_DIR/orbion_resonant_robe_reference.png"
else
  print -u2 "Icon reference not found; upload one in the workflow: $ICON_REFERENCE_SOURCE"
fi

if [[ -f "$PORTRAIT_REFERENCE_SOURCE" ]]; then
  install -m 0644 "$PORTRAIT_REFERENCE_SOURCE" "$INPUT_DIR/orbion_maren_vael_reference.png"
else
  print -u2 "Portrait reference not found; upload one in the workflow: $PORTRAIT_REFERENCE_SOURCE"
fi

print
print "Krea 2 game-art setup complete. Restart ComfyUI, then open either:"
print "  $WORKFLOW_DIR/krea2_orbion_icon_style_reference.json"
print "  $WORKFLOW_DIR/krea2_orbion_portrait_style_reference.json"
print
print "Model download size is approximately 19.5 GB (18.1 GiB)."
print "Krea 2 is governed by the Krea 2 Community License; review it before commercial use."
