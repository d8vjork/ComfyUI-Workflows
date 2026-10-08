[CmdletBinding()]
param(
    [string]$ComfyRoot = "",
    [string]$ModelsRoot = "",
    [string]$WorkflowRoot = "",
    [string]$InputRoot = "",
    [string]$IconReference = "",
    [string]$PortraitReference = "",
    [switch]$SkipModels
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ModelName = "krea2_turbo_int8_convrot.safetensors"
$TextEncoderName = "qwen3vl_4b_fp8_scaled.safetensors"
$VaeName = "qwen_image_vae.safetensors"
$StyleLoraName = "krea2_style_reference.safetensors"

$ModelSha256 = "8e4eeda70dd5037ab1ba2bef6b417f9f901e26093117cf397f741fc1fdaaf3f1"
$TextEncoderSha256 = "54bd5144df0bbc25dd6ccadfcb826b521445a1b06ae5a42570bdd2974ca87094"
$VaeSha256 = "a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f"
$StyleLoraSha256 = "f50df5a9e62e4be8aa926a63dd5bb1a64770c4004f763c1208007ae13daa82b8"

$HuggingFaceBase = "https://huggingface.co/Comfy-Org/Krea-2/resolve/main"
$IconWorkflowName = "krea2_orbion_icon_style_reference.json"
$PortraitWorkflowName = "krea2_orbion_portrait_style_reference.json"

function Test-ComfyRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (
        (Test-Path -LiteralPath (Join-Path $Path "comfy_extras")) -and
        (Test-Path -LiteralPath (Join-Path $Path "models"))
    )
}

function Resolve-ComfyRoot {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        $requested = [System.IO.Path]::GetFullPath($RequestedPath)
        if (Test-ComfyRoot -Path $requested) {
            return $requested
        }

        $nested = Join-Path $requested "ComfyUI"
        if (Test-ComfyRoot -Path $nested) {
            return $nested
        }

        throw "ComfyUI was not found at '$RequestedPath'. Pass the folder that contains comfy_extras and models, or its portable parent folder."
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:COMFYUI_DIR) {
        $candidates.Add($env:COMFYUI_DIR)
    }
    $candidates.Add((Join-Path $PSScriptRoot "ComfyUI"))
    $candidates.Add((Join-Path (Split-Path $PSScriptRoot -Parent) "ComfyUI"))
    if ($env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE "ComfyUI"))
        $candidates.Add((Join-Path $env:USERPROFILE "ComfyUI_windows_portable\ComfyUI"))
        $candidates.Add((Join-Path $env:USERPROFILE "Documents\ComfyUI"))
    }

    foreach ($candidate in $candidates) {
        if (Test-ComfyRoot -Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw "Could not auto-detect ComfyUI. Re-run with -ComfyRoot 'C:\path\to\ComfyUI'."
}

function Test-NativeKreaSupport {
    param([Parameter(Mandatory = $true)][string]$Root)

    $qwenNodes = Join-Path $Root "comfy_extras\nodes_qwen.py"
    $advancedNodes = Join-Path $Root "comfy_extras\nodes_model_advanced.py"
    if (-not (Test-Path -LiteralPath $qwenNodes) -or -not (Test-Path -LiteralPath $advancedNodes)) {
        return $false
    }

    $hasQwenEdit = Select-String -LiteralPath $qwenNodes -SimpleMatch "class TextEncodeQwenImageEditPlus" -Quiet
    $hasFluxSampling = Select-String -LiteralPath $advancedNodes -SimpleMatch "class ModelSamplingFlux" -Quiet
    return ($hasQwenEdit -and $hasFluxSampling)
}

function Test-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return $actual -eq $Expected.ToLowerInvariant()
}

function Get-VerifiedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    $destinationDirectory = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

    if (Test-Path -LiteralPath $Destination) {
        if (Test-Sha256 -Path $Destination -Expected $ExpectedSha256) {
            Write-Host "Already downloaded and verified: $(Split-Path $Destination -Leaf)"
            return
        }

        throw "Existing file failed its published SHA-256 check: $Destination`nMove or remove it, then run this installer again."
    }

    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw "curl.exe is required for resumable downloads. It is included with supported Windows 10 and Windows 11 installations."
    }

    $partial = "$Destination.partial"
    Write-Host "Downloading $(Split-Path $Destination -Leaf) ..."
    & $curl.Source --fail --location --retry 5 --retry-all-errors --continue-at - --output $partial $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed with curl exit code $LASTEXITCODE. Re-run the command to resume the partial file."
    }

    if (-not (Test-Sha256 -Path $partial -Expected $ExpectedSha256)) {
        throw "SHA-256 verification failed for $partial"
    }

    Move-Item -LiteralPath $partial -Destination $Destination
    Write-Host "Verified: $(Split-Path $Destination -Leaf)"
}

function Install-ReferenceImage {
    param(
        [string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Source) {
        Write-Warning "$Label reference was not supplied. Upload it from the workflow, or re-run with the corresponding reference parameter."
        return
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "$Label reference image does not exist: $Source"
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host "Installed $Label reference: $Destination"
}

$resolvedComfyRoot = Resolve-ComfyRoot -RequestedPath $ComfyRoot
if (-not (Test-NativeKreaSupport -Root $resolvedComfyRoot)) {
    throw "This ComfyUI build is too old for the native Krea 2 workflow. Update ComfyUI, restart it, and run this installer again."
}

if (-not $ModelsRoot) {
    $ModelsRoot = Join-Path $resolvedComfyRoot "models"
}
if (-not $WorkflowRoot) {
    $WorkflowRoot = Join-Path $resolvedComfyRoot "user\default\workflows"
}
if (-not $InputRoot) {
    $InputRoot = Join-Path $resolvedComfyRoot "input"
}

$iconWorkflowSource = Join-Path $PSScriptRoot "workflows\$IconWorkflowName"
$portraitWorkflowSource = Join-Path $PSScriptRoot "workflows\$PortraitWorkflowName"
if (-not (Test-Path -LiteralPath $iconWorkflowSource -PathType Leaf)) {
    throw "Required workflow is missing: $iconWorkflowSource"
}
if (-not (Test-Path -LiteralPath $portraitWorkflowSource -PathType Leaf)) {
    throw "Required workflow is missing: $portraitWorkflowSource"
}

Write-Host "ComfyUI:  $resolvedComfyRoot"
Write-Host "Models:   $ModelsRoot"
Write-Host "Workflows: $WorkflowRoot"

if (-not $SkipModels) {
    Get-VerifiedFile `
        -Url "$HuggingFaceBase/diffusion_models/$ModelName`?download=true" `
        -Destination (Join-Path $ModelsRoot "diffusion_models\$ModelName") `
        -ExpectedSha256 $ModelSha256
    Get-VerifiedFile `
        -Url "$HuggingFaceBase/text_encoders/$TextEncoderName`?download=true" `
        -Destination (Join-Path $ModelsRoot "text_encoders\$TextEncoderName") `
        -ExpectedSha256 $TextEncoderSha256
    Get-VerifiedFile `
        -Url "$HuggingFaceBase/vae/$VaeName`?download=true" `
        -Destination (Join-Path $ModelsRoot "vae\$VaeName") `
        -ExpectedSha256 $VaeSha256
    Get-VerifiedFile `
        -Url "$HuggingFaceBase/loras/$StyleLoraName`?download=true" `
        -Destination (Join-Path $ModelsRoot "loras\$StyleLoraName") `
        -ExpectedSha256 $StyleLoraSha256
} else {
    Write-Host "Skipping model downloads."
}

New-Item -ItemType Directory -Force -Path $WorkflowRoot | Out-Null
New-Item -ItemType Directory -Force -Path $InputRoot | Out-Null
Copy-Item -LiteralPath $iconWorkflowSource -Destination (Join-Path $WorkflowRoot $IconWorkflowName) -Force
Copy-Item -LiteralPath $portraitWorkflowSource -Destination (Join-Path $WorkflowRoot $PortraitWorkflowName) -Force

Install-ReferenceImage `
    -Source $IconReference `
    -Destination (Join-Path $InputRoot "orbion_resonant_robe_reference.png") `
    -Label "icon"
Install-ReferenceImage `
    -Source $PortraitReference `
    -Destination (Join-Path $InputRoot "orbion_maren_vael_reference.png") `
    -Label "portrait"

Write-Host ""
Write-Host "Krea 2 game-art setup complete. Restart ComfyUI, then open either:"
Write-Host "  $(Join-Path $WorkflowRoot $IconWorkflowName)"
Write-Host "  $(Join-Path $WorkflowRoot $PortraitWorkflowName)"
if (-not $SkipModels) {
    Write-Host "Model download size is approximately 19.5 GB (18.1 GiB)."
}
Write-Host "Krea 2 is governed by the Krea 2 Community License; review it before commercial use."
