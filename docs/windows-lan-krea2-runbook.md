# Krea 2 on Windows — LAN runbook

This runbook operates a Windows ComfyUI machine as a Krea 2 generator for
trusted clients on the same private LAN. It does not expose ComfyUI to the
public internet.

## Scope

- Windows 10 or Windows 11
- ComfyUI Desktop, a Git installation, or Windows Portable
- Krea 2 item-icon and fantasy-portrait workflows from this repository
- Remote access from trusted machines on the same LAN
- Default TCP port `8188`

Do not configure router port forwarding for `8188`. ComfyUI should remain
reachable only from the local private subnet.

## Files in this repository

- `setup_krea2_game_art.ps1` — installs and verifies the Krea 2 models and
  copies the workflows into ComfyUI
- `workflows/krea2_orbion_icon_style_reference.json` — UI workflow for item
  icons
- `workflows/krea2_orbion_portrait_style_reference.json` — UI workflow for
  character portraits

The two supplied JSON files are UI-format workflows. They work interactively in
ComfyUI, but they are not sent directly to `POST /prompt`. Remote automation
requires API-format exports; see **Prepare API workflows** below.

## 1. Prepare the Windows host

1. Connect the machine by Ethernet when possible.
2. In Windows network settings, mark the active network as **Private**.
3. Reserve a stable IPv4 address for the machine in the router's DHCP settings.
   The examples below use `192.168.1.50`; replace it with the reserved address.
4. Install or update ComfyUI. Open it locally once and confirm that a basic
   workflow can run.
5. Confirm at least 20 GB of free model storage, plus space for generated
   images and temporary files.

Check the network profile in PowerShell:

```powershell
Get-NetConnectionProfile
```

If necessary, change the active connection to Private from an elevated
PowerShell:

```powershell
Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
```

Use the actual interface name reported by `Get-NetConnectionProfile`.

## 2. Install the Krea 2 assets

Open PowerShell in this repository. For Windows Portable:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

./setup_krea2_game_art.ps1 `
  -ComfyRoot "C:\AI\ComfyUI_windows_portable" `
  -IconReference "C:\game-art\resonant-robe.png" `
  -PortraitReference "C:\game-art\neutral.png"
```

`-ComfyRoot` may point either to the directory containing `comfy_extras` and
`models`, or to a Windows Portable parent directory containing a nested
`ComfyUI` directory.

For shared model storage:

```powershell
./setup_krea2_game_art.ps1 `
  -ComfyRoot "C:\AI\ComfyUI" `
  -ModelsRoot "D:\ComfyUI-Shared\models" `
  -IconReference "C:\game-art\resonant-robe.png" `
  -PortraitReference "C:\game-art\neutral.png"
```

The reference arguments are optional. If omitted, select the reference images
in the `LoadImage` nodes after opening each workflow.

The installer downloads approximately 19.5 GB (18.1 GiB), resumes partial
downloads, and verifies each file with its published SHA-256 digest. Restart
ComfyUI after installation.

## 3. Restrict Windows Firewall to the LAN

Run this once from an elevated PowerShell:

```powershell
New-NetFirewallRule `
  -DisplayName "ComfyUI Krea2 LAN API" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8188 `
  -RemoteAddress LocalSubnet `
  -Profile Private `
  -Action Allow
```

Confirm the rule:

```powershell
Get-NetFirewallRule -DisplayName "ComfyUI Krea2 LAN API" |
  Format-List DisplayName, Enabled, Profile, Direction, Action
```

This rule applies only while Windows considers the connection Private and only
to clients Windows identifies as part of `LocalSubnet`.

## 4. Start ComfyUI for LAN access

### Windows Portable

From the Windows Portable directory:

```powershell
./python_embeded/python.exe -s ComfyUI/main.py `
  --windows-standalone-build `
  --listen 192.168.1.50 `
  --port 8188 `
  --disable-auto-launch
```

Binding to the reserved LAN address is preferable to listening on every
interface. If the address cannot be reserved, use `--listen 0.0.0.0`; the
Windows Firewall rule remains the network boundary.

### Python or Git installation

From the ComfyUI directory, using its activated virtual environment:

```powershell
python main.py `
  --listen 192.168.1.50 `
  --port 8188 `
  --disable-auto-launch
```

Leave this terminal running. Closing it stops the server and any active job.

## 5. Verify LAN connectivity

On the Windows host:

```powershell
Invoke-RestMethod "http://192.168.1.50:8188/system_stats"
```

On another Windows machine on the same LAN:

```powershell
Test-NetConnection -ComputerName 192.168.1.50 -Port 8188
Invoke-RestMethod "http://192.168.1.50:8188/system_stats"
```

`TcpTestSucceeded` should be `True`. Opening
`http://192.168.1.50:8188` in a browser should show ComfyUI.

If the UI opens but a browser application cannot call the API, that is normally
a CORS issue. Backend clients do not require CORS. For a browser client, start
ComfyUI with an explicit trusted origin:

```powershell
python main.py `
  --listen 192.168.1.50 `
  --port 8188 `
  --enable-cors-header "http://192.168.1.25:3000"
```

Avoid an unrestricted `*` origin.

## 6. Validate the interactive workflows

Before enabling automation:

1. Open `krea2_orbion_icon_style_reference.json` in ComfyUI.
2. Confirm the expected reference image appears in `LoadImage`.
3. Change the prompt in the orange subgraph node and queue one image.
4. Confirm a PNG appears under the ComfyUI output directory.
5. Repeat with `krea2_orbion_portrait_style_reference.json`.

Do not continue to API integration until both workflows run locally. This
separates model or GPU problems from networking and client problems.

## 7. Prepare API workflows

For each validated workflow:

1. Open it in ComfyUI.
2. Use **File → Export (API)**.
3. Save the exports with distinct names, such as:
   - `krea2_orbion_icon_api.json`
   - `krea2_orbion_portrait_api.json`
4. Inspect the exported JSON and record the node IDs containing:
   - prompt text
   - random seed
   - reference-image filename
   - output filename prefix

Subgraphs are flattened or converted as part of the API export. Node IDs in the
API workflow may therefore differ from those visible in the UI workflow.

Keep the exported API workflows under version control. When the UI graph is
changed, export and test its API version again.

## 8. Remote request lifecycle

A remote client follows this sequence:

1. If using a new reference, upload it as multipart form data to
   `POST /upload/image` with `type=input`.
2. Load the appropriate API workflow JSON.
3. Replace the prompt, seed, reference filename, and output prefix inputs.
4. Submit `{"prompt": <api-workflow>, "client_id": <unique-id>}` to
   `POST /prompt`.
5. Store the returned `prompt_id`.
6. Monitor `/ws?clientId=<unique-id>` or poll
   `GET /history/<prompt_id>` until the output is present.
7. Download the generated file from `GET /view` using the filename, subfolder,
   and type returned in the history result.

The fixed Orbion reference images can remain in the ComfyUI `input` directory;
they do not need to be uploaded with every prompt.

Queue one request per intended image. ComfyUI serializes work on a single GPU,
so client-side concurrency should normally add jobs to the queue rather than
expect parallel inference.

## 9. Daily operating procedure

1. Confirm the Windows host is on the Private LAN and has its reserved address.
2. Start ComfyUI with the LAN command from section 4.
3. Call `/system_stats` from the client machine.
4. Submit one smoke-test prompt.
5. Confirm the output is retrievable before starting a batch.
6. Monitor GPU memory, free disk space, the ComfyUI terminal, and the queue.
7. Stop accepting new requests before maintenance or shutdown.
8. Let the active job finish, then close ComfyUI.

## 10. Troubleshooting

### Connection refused

- Confirm ComfyUI is still running.
- Confirm the `--listen` address matches the Windows machine's current address.
- Run `ipconfig` and compare the IPv4 address.
- Test locally with `/system_stats`.
- Confirm the firewall rule is enabled and the network profile is Private.

### The browser works locally but not from another machine

- Confirm `--listen` is present; the default binds only to `127.0.0.1`.
- Run `Test-NetConnection` from the client.
- Check for guest Wi-Fi or wireless client isolation in the router.
- Confirm both machines are on the same subnet or adjust the firewall's
  `RemoteAddress` to the precise trusted subnet.

### `POST /prompt` returns HTTP 400

- Confirm the body contains an API-format workflow under the `prompt` key.
- Do not send the UI workflow JSON directly.
- Check `node_errors` in the response.
- Confirm every model and LoRA filename exists on the Windows host.
- Re-export the API workflow after changing the UI graph.

### `LoadImage` validation error

- Upload the file to `/upload/image` before submitting the prompt, or copy it
  into the ComfyUI `input` directory.
- Set the API workflow's `LoadImage.image` input to the uploaded filename.
- Use only the server-side filename returned by the upload response.

### Out-of-memory or process termination

- Stop submitting new jobs and allow the current job to fail or finish.
- Keep the workflow at 1024×1024 and batch size 1.
- Close other GPU applications.
- Restart ComfyUI to release stale allocations.
- Do not lower the number of Krea 2 Turbo steps below the preset merely to
  address memory; resolution and concurrent workloads are the first controls.

### The result exists but the client cannot download it

- Query `GET /history/<prompt_id>` and use the returned filename, subfolder,
  and type exactly.
- URL-encode query parameters passed to `/view`.
- Confirm the output directory is writable and has free space.

## 11. Disable LAN access

Stop ComfyUI, then disable the firewall rule from an elevated PowerShell:

```powershell
Disable-NetFirewallRule -DisplayName "ComfyUI Krea2 LAN API"
```

For local-only use, restart ComfyUI without `--listen`, or explicitly use:

```powershell
python main.py --listen 127.0.0.1 --port 8188
```

To remove the firewall rule completely:

```powershell
Remove-NetFirewallRule -DisplayName "ComfyUI Krea2 LAN API"
```

## 12. Operational safety

- Never forward port `8188` on the router.
- Do not run the firewall rule on a Public network profile.
- Treat anyone on the allowed subnet as capable of submitting work to the
  ComfyUI queue.
- Keep ComfyUI and its dependencies updated during a maintenance window, then
  rerun the interactive and API smoke tests.
- Keep prompts and generated images free of secrets; both can be retained in
  workflow files, queue history, logs, and output metadata.
- Review the Krea 2 Community License before commercial use.

## References

- [ComfyUI API example](https://github.com/Comfy-Org/ComfyUI/blob/master/script_examples/basic_api_example.py)
- [ComfyUI startup flags](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy/cli_args.py)
- [ComfyUI server routes](https://github.com/Comfy-Org/ComfyUI/blob/master/server.py)
- [Krea 2 Community License](https://www.krea.ai/krea-2-licensing)
