#!/usr/bin/env bash
# Štart podu: SSH -> Jupyter -> perzistentné priečinky -> modely -> ComfyUI
set -uo pipefail

COMFYUI_DIR="${COMFYUI_DIR:-/opt/ComfyUI}"
WORKSPACE="${WORKSPACE:-/workspace}"
DATA="${DATA_DIR:-$WORKSPACE/matrix-krea2}"
LOGS="$DATA/logs"
mkdir -p "$LOGS"

log() { echo "[start] $(date '+%H:%M:%S') $*"; }

echo "================================================================"
echo " MATRIX Krea 2 V1.1.0 — RunPod"
echo " ComfyUI 0.33.3 · MATRIX-LAB-Nodes 0.4.0 · PyTorch $(python -c 'import torch;print(torch.__version__)' 2>/dev/null)"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/ GPU: /'
echo " Data: $DATA"
echo "================================================================"

# ---------- SSH (RunPod: env PUBLIC_KEY) ----------
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    grep -qxF "$PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    ssh-keygen -A >/dev/null 2>&1
    /usr/sbin/sshd && log "SSH running (port 22)"
fi

# ---------- JupyterLab (port 8888) ----------
if [ "${ENABLE_JUPYTER:-1}" = 1 ]; then
    JTOKEN="${JUPYTER_PASSWORD:-}"
    if [ -z "$JTOKEN" ]; then
        JTOKEN="$(python -c 'import secrets;print(secrets.token_urlsafe(18))')"
        log "JUPYTER_PASSWORD not set -> generated token: $JTOKEN"
    fi
    nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
        --ServerApp.token="$JTOKEN" --ServerApp.root_dir="$WORKSPACE" \
        --ServerApp.allow_origin='*' --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        > "$LOGS/jupyter.log" 2>&1 &
    log "JupyterLab running (port 8888)"
fi

# ---------- Perzistentné priečinky na /workspace ----------
for d in models input output user; do
    mkdir -p "$DATA/$d"
    if [ ! -L "$COMFYUI_DIR/$d" ]; then
        [ -d "$COMFYUI_DIR/$d" ] && rsync -a --ignore-existing "$COMFYUI_DIR/$d/" "$DATA/$d/"
        rm -rf "${COMFYUI_DIR:?}/$d"
        ln -s "$DATA/$d" "$COMFYUI_DIR/$d"
    fi
done

# Workflow + nastavenia frontendu (neprepisuje tvoje úpravy)
WF_DIR="$DATA/user/default/workflows"
mkdir -p "$WF_DIR" "$DATA/api"
cp -n /opt/defaults/workflows/*.json "$WF_DIR/"
cp -n /opt/defaults/MATRIX-Krea2-V1.api.json "$DATA/api/"
python - "$DATA/user/default/comfy.settings.json" /opt/defaults/comfy.settings.json <<'PY'
import json, sys, os
path, defaults = sys.argv[1], json.load(open(sys.argv[2]))
cur = {}
if os.path.exists(path):
    try: cur = json.load(open(path))
    except Exception: cur = {}
for k, v in defaults.items():
    cur.setdefault(k, v)          # doplní iba chýbajúce kľúče (Classic canvas)
json.dump(cur, open(path, "w"), indent=2)
PY

# ---------- Modely ----------
if [ "${DOWNLOAD_MODELS:-1}" = 1 ]; then
    log "Checking/downloading models (~22.3 GB on first start) -> $LOGS/models.log"
    if /opt/scripts/download_models.sh "$DATA/models" 2>&1 | tee "$LOGS/models.log"; then
        log "All models present and SHA-256 verified."
    else
        log "WARNING: some models are missing or failed the hash check — see $LOGS/models.log"
    fi
fi

# ---------- LoRA: LORA_URLS (Civitai / Hugging Face odkazy) ----------
mkdir -p "$DATA/models/loras"
if [ -n "${LORA_URLS:-}" ]; then
    log "Downloading LoRAs from LORA_URLS -> $DATA/models/loras"
    python /opt/scripts/lora_download.py "$DATA/models/loras" 2>&1 | tee "$LOGS/lora.log"         || log "WARNING: some LoRA downloads failed — see $LOGS/lora.log"
fi

# Skratky pre JupyterLab: sem nahraj LoRA / odtiaľto stiahni fotky
ln -sfn "$DATA/models/loras" "$WORKSPACE/LORAS"
ln -sfn "$DATA/output" "$WORKSPACE/OUTPUTS"

# ---------- Voliteľný vlastný skript ----------
if [ -x "$DATA/on_start.sh" ]; then
    log "Running $DATA/on_start.sh"
    "$DATA/on_start.sh" || log "on_start.sh failed"
fi

# ---------- ComfyUI (port 8188) ----------
# MATRIX Auto Prompter: XAI_API_KEY (RunPod secret). RunPod proxy origin
# https://<POD_ID>-8188.proxy.runpod.net je v MATRIX nodoch povolený automaticky.
cd "$COMFYUI_DIR"
ARGS=(--listen 0.0.0.0 --port 8188 --preview-method "${PREVIEW_METHOD:-auto}")
# Klik na "HTTP Service" v console.runpod.io je cross-site navigácia na *.proxy.runpod.net
# (Sec-Fetch-Site: cross-site) a ComfyUI origin middleware by vrátil 403. CORS režim
# obmedzený na vlastnú proxy doménu podu tento middleware nahradí.
if [ -n "${RUNPOD_POD_ID:-}" ]; then
    ARGS+=(--enable-cors-header "https://${RUNPOD_POD_ID}-8188.proxy.runpod.net")
fi
# shellcheck disable=SC2206
[ -n "${COMFYUI_EXTRA_ARGS:-}" ] && ARGS+=(${COMFYUI_EXTRA_ARGS})

if [ -n "${RUNPOD_POD_ID:-}" ]; then
    echo "================================================================"
    echo " ComfyUI:    https://${RUNPOD_POD_ID}-8188.proxy.runpod.net"
    echo " JupyterLab: https://${RUNPOD_POD_ID}-8888.proxy.runpod.net  (LORAS/ = upload LoRAs, OUTPUTS/ = your images)"
    echo "================================================================"
fi

while true; do
    log "Starting ComfyUI: python main.py ${ARGS[*]}"
    python main.py "${ARGS[@]}" 2>&1 | tee -a "$LOGS/comfyui.log"
    log "ComfyUI exited (code ${PIPESTATUS[0]}), restarting in 5 s…"
    sleep 5
done
