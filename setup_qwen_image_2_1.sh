#!/bin/zsh

set -euo pipefail

readonly WORKSPACE_DIR="${0:A:h}"
readonly INSTALL_ROOT="/Users/d8vjork/ComfyUI-Installs/ComfyUI"
readonly COMFY_DIR="$INSTALL_ROOT/ComfyUI"
readonly PYTHON="$COMFY_DIR/.venv/bin/python3"
readonly UV="$INSTALL_ROOT/standalone-env/bin/uv"
readonly CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
readonly GGUF_DIR="$CUSTOM_NODES_DIR/ComfyUI-GGUF"
readonly PROMPT_REWRITE_DIR="$CUSTOM_NODES_DIR/Comfyui-Qwen-Image-Prompt-Rewrite-T8"
readonly SHARED_MODELS="/Users/d8vjork/ComfyUI-Shared/models"
readonly WORKFLOW_DIR="$COMFY_DIR/user/default/workflows"
readonly DESKTOP_CONFIG="/Users/d8vjork/Library/Application Support/Comfy Desktop/installations.json"
readonly EXTRA_MODEL_PATHS="/Users/d8vjork/Library/Application Support/Comfy Desktop/shared_model_paths.yaml"

readonly MODEL_NAME="qwen-image-2.1-UC-Q4_K_M.gguf"
readonly TEXT_ENCODER_NAME="qwen3vl_8b_int8_convrot.safetensors"
readonly VAE_NAME="qwen_image_2.1_vae_bf16.safetensors"
readonly PE_MODEL_NAME="pe_t2i_heretic-Q4_K_M.gguf"
readonly WORKFLOW_NAME="qwen_image_2.1_uncensored_gguf_q4km.json"

readonly MODEL_SHA256="e79c8a009f2ecbdb6c70fd663d9aea9ee304a0d91f347e4169a756b8ad141b41"
readonly TEXT_ENCODER_SHA256="8bfd0f6e12abf2d2d697ecc888e5e90b0d6741d6708f05799f53afa560452e8f"
readonly VAE_SHA256="bb21f7473051e1ac368515dd3f2e15cd44d7a11748ee8823e1ddca3e4876b7c9"
readonly PE_MODEL_SHA256="fe176ded062942ac8858290a33c9303a6e9c09c31405020a22ad0d47fa7b9b69"

readonly HF_BASE="https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF/resolve/main"
readonly PE_MODEL_URL="https://huggingface.co/pottokao/Qwen-Image-2.1-PE-T2I-Heretic-GGUF/resolve/e24aa32689780a6d34bdc30d401cb68771e41c02/$PE_MODEL_NAME"
readonly PROMPT_REWRITE_REPO="https://github.com/T8mars/Comfyui-Qwen-Image-Prompt-Rewrite-T8.git"
readonly PROMPT_REWRITE_COMMIT="8d6575982c13b5971cd38118f1ab2399c7337492"
readonly WORKFLOW_URL="https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/image_qwen_image_2_1_t2i.json"

TMP_DIR="$(mktemp -d /tmp/comfy-qwen-image-2.1.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

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
    print -u2 "Move or remove that file, then run this installer again."
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
require_path "$PYTHON"
require_path "$UV"
require_path "$DESKTOP_CONFIG"
require_path "$EXTRA_MODEL_PATHS"

if [[ -n "$(git -C "$COMFY_DIR" status --porcelain --untracked-files=no)" ]]; then
  print -u2 "ComfyUI core has local tracked changes; refusing to overwrite them."
  exit 1
fi

print "Updating ComfyUI core to the current upstream version ..."
git -C "$COMFY_DIR" fetch --tags origin master
git -C "$COMFY_DIR" checkout --detach origin/master

if ! rg -q 'TextEncodeQwenImage21' "$COMFY_DIR/comfy_extras/nodes_qwen.py"; then
  print -u2 "The fetched ComfyUI revision does not contain Qwen-Image 2.1 support."
  exit 1
fi

print "Synchronizing ComfyUI Python dependencies ..."
"$UV" pip install --python "$PYTHON" --requirement "$COMFY_DIR/requirements.txt"

if [[ -d "$GGUF_DIR/.git" ]]; then
  if [[ -n "$(git -C "$GGUF_DIR" status --porcelain)" ]]; then
    print -u2 "ComfyUI-GGUF has local changes; refusing to overwrite them."
    exit 1
  fi
  print "Updating ComfyUI-GGUF ..."
  git -C "$GGUF_DIR" fetch origin main
  git -C "$GGUF_DIR" checkout --detach origin/main
else
  print "Installing the maintained ComfyUI-GGUF node ..."
  git clone --depth 1 https://github.com/leejet/ComfyUI-GGUF.git "$GGUF_DIR"
fi

if [[ -f "$GGUF_DIR/requirements.txt" ]]; then
  "$UV" pip install --python "$PYTHON" --requirement "$GGUF_DIR/requirements.txt"
fi

download_model "$HF_BASE/$MODEL_NAME?download=true" \
  "$SHARED_MODELS/diffusion_models/$MODEL_NAME" "$MODEL_SHA256"
download_model "$HF_BASE/text_encoders/$TEXT_ENCODER_NAME?download=true" \
  "$SHARED_MODELS/text_encoders/$TEXT_ENCODER_NAME" "$TEXT_ENCODER_SHA256"
download_model "$HF_BASE/vae/$VAE_NAME?download=true" \
  "$SHARED_MODELS/vae/$VAE_NAME" "$VAE_SHA256"

if [[ -d "$PROMPT_REWRITE_DIR/.git" ]]; then
  if [[ -n "$(git -C "$PROMPT_REWRITE_DIR" status --porcelain --untracked-files=no)" ]]; then
    print -u2 "Prompt Rewrite T8 has local tracked changes; refusing to overwrite them."
    exit 1
  fi
  print "Updating the Qwen Image 2.1 prompt-rewrite node ..."
  git -C "$PROMPT_REWRITE_DIR" fetch origin "$PROMPT_REWRITE_COMMIT"
else
  print "Installing the Qwen Image 2.1 prompt-rewrite node ..."
  git clone --no-checkout "$PROMPT_REWRITE_REPO" "$PROMPT_REWRITE_DIR"
  git -C "$PROMPT_REWRITE_DIR" fetch origin "$PROMPT_REWRITE_COMMIT"
fi
git -C "$PROMPT_REWRITE_DIR" checkout --detach "$PROMPT_REWRITE_COMMIT"

if ! command -v llama-server >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    print -u2 "llama-server is required. Install llama.cpp, then run this installer again."
    exit 1
  fi
  print "Installing llama.cpp for the local prompt enhancer ..."
  brew install llama.cpp
fi

mkdir -p "$PROMPT_REWRITE_DIR/runtime"
ln -sfn "$(command -v llama-server)" "$PROMPT_REWRITE_DIR/runtime/llama-server.exe"
download_model "$PE_MODEL_URL?download=true" \
  "$PROMPT_REWRITE_DIR/models/llm/qwenimage-pe/$PE_MODEL_NAME" "$PE_MODEL_SHA256"

print "Building the GGUF workflow from Comfy-Org's official template ..."
curl --fail --location --retry 5 --retry-all-errors \
  --output "$TMP_DIR/official-workflow.json" "$WORKFLOW_URL"

jq --arg model "$MODEL_NAME" \
   --arg model_url "$HF_BASE/$MODEL_NAME" \
   --arg encoder "$TEXT_ENCODER_NAME" \
   --arg vae "$VAE_NAME" '
  (.nodes[] | select(.id == 459) | .widgets_values[12]) = $model |
  (.nodes[] | select(.id == 459) | .widgets_values_named.unet_name) = $model |
  (.nodes[] | select(.id == 461) | .widgets_values[0]) = "Qwen_Image_2.1_UC_GGUF" |
  (.nodes[] | select(.id == 461) | .widgets_values_named.filename_prefix) = "Qwen_Image_2.1_UC_GGUF" |
  (.nodes[] | select(.id == 463) | .widgets_values[0]) =
    ("## Installed local model\n\nThis workflow uses **" + $model + "** from abenzerps/Qwen-Image-2.1-Uncensored-GGUF with the maintained leejet/ComfyUI-GGUF loader.\n\nFiles are installed in the shared Desktop model folders:\n\n- diffusion_models/" + $model + "\n- text_encoders/" + $encoder + "\n- vae/" + $vae + "\n\nThe optional prompt enhancer is off by default and is not required.") |
  (.nodes[] | select(.id == 463) | .widgets_values_named.text) =
    (.nodes[] | select(.id == 463) | .widgets_values[0]) |
  (.definitions.subgraphs[0].name) = "Text to Image (Qwen Image 2.1 Uncensored GGUF)" |
  (.definitions.subgraphs[0].nodes[] | select(.id == 451)) |= (
    .type = "UnetLoaderGGUF" |
    .properties["Node name for S&R"] = "UnetLoaderGGUF" |
    .properties.models = [{"name": $model, "url": $model_url, "directory": "diffusion_models"}] |
    .widgets_values = [$model] |
    .widgets_values_named = {"unet_name": $model}
  )
' "$TMP_DIR/official-workflow.json" > "$TMP_DIR/$WORKFLOW_NAME"

"$PYTHON" "$WORKSPACE_DIR/tools/add_reference_inputs.py" "$TMP_DIR/$WORKFLOW_NAME"
"$PYTHON" "$WORKSPACE_DIR/tools/add_heretic_prompt_enhancer.py" "$TMP_DIR/$WORKFLOW_NAME"
jq empty "$TMP_DIR/$WORKFLOW_NAME"
mkdir -p "$WORKSPACE_DIR/workflows" "$WORKFLOW_DIR"
install -m 0644 "$TMP_DIR/$WORKFLOW_NAME" "$WORKSPACE_DIR/workflows/$WORKFLOW_NAME"
install -m 0644 "$TMP_DIR/$WORKFLOW_NAME" "$WORKFLOW_DIR/$WORKFLOW_NAME"

print "Setting this Desktop instance to the Latest update channel ..."
config_backup="$DESKTOP_CONFIG.qwen-setup-backup"
if [[ ! -f "$config_backup" ]]; then
  cp -p "$DESKTOP_CONFIG" "$config_backup"
fi
jq 'map(if .id == "inst-1780992232172" then .updateChannel = "latest" else . end)' \
  "$DESKTOP_CONFIG" > "$TMP_DIR/installations.json"
install -m 0644 "$TMP_DIR/installations.json" "$DESKTOP_CONFIG"

print
print "Installation complete."
print "ComfyUI commit: $(git -C "$COMFY_DIR" rev-parse --short=12 HEAD)"
print "ComfyUI-GGUF commit: $(git -C "$GGUF_DIR" rev-parse --short=12 HEAD)"
print "Prompt Rewrite T8 commit: $(git -C "$PROMPT_REWRITE_DIR" rev-parse --short=12 HEAD)"
print "Prompt enhancer: $PROMPT_REWRITE_DIR/models/llm/qwenimage-pe/$PE_MODEL_NAME"
print "Workflow: $WORKFLOW_DIR/$WORKFLOW_NAME"
