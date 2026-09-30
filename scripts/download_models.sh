#!/usr/bin/env bash
# Stiahne a overí (SHA-256) modely pre MATRIX Krea 2 V1.1.0.
# Použitie: download_models.sh <ComfyUI models dir>
# ENV:
#   DOWNLOAD_GROUPS   čiarkou oddelené skupiny z models.txt (default: core,eye,skin)
#   HF_TOKEN          voliteľný Hugging Face token (iba proti rate-limitom; modely sú verejné)
#   FORCE_REHASH=1    znova prepočíta SHA-256 aj pre už overené súbory
set -uo pipefail

MODELS_DIR="${1:?models dir required}"
MANIFEST="${MODELS_MANIFEST:-/opt/models.txt}"
GROUPS_WANTED=",${DOWNLOAD_GROUPS:-core,eye,skin},"
VERIFIED_DIR="$MODELS_DIR/.verified"
mkdir -p "$VERIFIED_DIR"

log() { echo "[models] $*"; }

ARIA_CONF=""
if [ -n "${HF_TOKEN:-}" ]; then
    # token ide cez konfiguračný súbor (600), nie cez príkazový riadok
    ARIA_CONF="$(mktemp)"
    chmod 600 "$ARIA_CONF"
    printf 'header=Authorization: Bearer %s\n' "$HF_TOKEN" > "$ARIA_CONF"
    trap 'rm -f "$ARIA_CONF"' EXIT
fi

marker_for() { echo "$VERIFIED_DIR/$(echo "$1" | tr '/' '_').sha256"; }

verify() {  # verify <file> <sha> <bytes> <rel>
    local file="$1" sha="$2" bytes="$3" rel="$4" marker
    marker="$(marker_for "$rel")"
    [ -f "$file" ] || return 1
    [ "$(stat -c %s "$file")" = "$bytes" ] || { log "zlá veľkosť: $rel"; return 1; }
    if [ -z "${FORCE_REHASH:-}" ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "$sha" ]; then
        return 0
    fi
    log "overujem SHA-256: $rel"
    if [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$sha" ]; then
        echo "$sha" > "$marker"
        return 0
    fi
    log "SHA-256 NESEDÍ: $rel"
    rm -f "$marker"
    return 1
}

download() {  # download <url> <dest file> <is_hf>
    local url="$1" dest="$2" is_hf="$3" args
    args=(-c -x 16 -s 16 -k 16M --max-tries=5 --retry-wait=5 --console-log-level=warn
          --summary-interval=30 --file-allocation=none --auto-file-renaming=false --allow-overwrite=true
          -d "$(dirname "$dest")" -o "$(basename "$dest").download")
    if [ "$is_hf" = 1 ] && [ -n "$ARIA_CONF" ]; then
        args+=(--conf-path="$ARIA_CONF")
    else
        args+=(--no-conf=true)
    fi
    aria2c "${args[@]}" "$url" && mv -f "$dest.download" "$dest"
}

FAILED=0
while IFS='|' read -r group rel url sha bytes; do
    [ -z "${group// }" ] && continue
    case "$group" in \#*) continue ;; esac
    case "$GROUPS_WANTED" in *",$group,"*) ;; *) log "preskakujem ($group): $rel"; continue ;; esac

    dest="$MODELS_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    if verify "$dest" "$sha" "$bytes" "$rel"; then
        log "OK  $rel"
        continue
    fi
    rm -f "$dest"
    is_hf=0; case "$url" in https://huggingface.co/*) is_hf=1 ;; esac
    ok=0
    for attempt in 1 2 3; do
        log "sťahujem ($attempt/3): $rel  [$(numfmt --to=iec "$bytes")]"
        if download "$url" "$dest" "$is_hf" && verify "$dest" "$sha" "$bytes" "$rel"; then
            ok=1; break
        fi
        rm -f "$dest" "$dest.download" "$dest.download.aria2"
    done
    if [ "$ok" = 1 ]; then
        log "OK  $rel"
    else
        log "CHYBA: $rel sa nepodarilo stiahnuť/overiť"
        FAILED=1
    fi
done < "$MANIFEST"

exit "$FAILED"
