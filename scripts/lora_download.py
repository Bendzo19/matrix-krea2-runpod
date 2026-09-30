#!/usr/bin/env python3
"""Stiahne LoRA súbory z LORA_URLS do priečinka loras.

LORA_URLS: odkazy oddelené čiarkou, medzerou alebo novým riadkom. Podporované:
  - Civitai stránka modelu:  https://civitai.com/models/12345  (najnovšia verzia)
                             https://civitai.com/models/12345?modelVersionId=67890
  - Civitai priamy download: https://civitai.com/api/download/models/67890
  - Hugging Face:            https://huggingface.co/<user>/<repo>/resolve/main/lora.safetensors
                             https://huggingface.co/<user>/<repo>/blob/main/lora.safetensors
  - akýkoľvek priamy odkaz na .safetensors
  - vlastný názov súboru:    moja_postava.safetensors=https://...
Tokeny (voliteľné): CIVITAI_TOKEN, HF_TOKEN — posielajú sa iba v hlavičke na príslušnú doménu.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

UA = "matrix-krea2-runpod/1.1"


def log(msg: str) -> None:
    print(f"[lora] {msg}", flush=True)


def headers_for(url: str) -> dict[str, str]:
    h = {"User-Agent": UA}
    host = urllib.parse.urlsplit(url).hostname or ""
    if host.endswith("civitai.com") and os.environ.get("CIVITAI_TOKEN"):
        h["Authorization"] = "Bearer " + os.environ["CIVITAI_TOKEN"].strip()
    if host.endswith("huggingface.co") and os.environ.get("HF_TOKEN"):
        h["Authorization"] = "Bearer " + os.environ["HF_TOKEN"].strip()
    return h


class StripAuthOnRedirect(urllib.request.HTTPRedirectHandler):
    """Civitai/HF presmerujú na CDN — token tam neposielame."""

    def redirect_request(self, req, fp, code, msg, hdrs, newurl):
        new = super().redirect_request(req, fp, code, msg, hdrs, newurl)
        if new is not None and urllib.parse.urlsplit(newurl).hostname != urllib.parse.urlsplit(req.full_url).hostname:
            new.headers.pop("Authorization", None)
            new.unredirected_hdrs.pop("Authorization", None)
        return new


OPENER = urllib.request.build_opener(StripAuthOnRedirect)


def resolve(url: str) -> str:
    p = urllib.parse.urlsplit(url)
    host = p.hostname or ""
    if host.endswith("civitai.com"):
        q = urllib.parse.parse_qs(p.query)
        if "modelVersionId" in q:
            return f"https://civitai.com/api/download/models/{q['modelVersionId'][0]}"
        m = re.match(r"^/models/(\d+)", p.path)
        if m:
            req = urllib.request.Request(f"https://civitai.com/api/v1/models/{m.group(1)}", headers=headers_for(url))
            data = json.load(OPENER.open(req, timeout=60))
            version = data["modelVersions"][0]
            log(f"Civitai: {data.get('name')} — version {version.get('name')}")
            return f"https://civitai.com/api/download/models/{version['id']}"
    if host.endswith("huggingface.co") and "/blob/" in p.path:
        return url.replace("/blob/", "/resolve/", 1)
    return url


def filename_from(resp, url: str) -> str:
    cd = resp.headers.get("Content-Disposition", "")
    m = re.search(r"filename\*=UTF-8''([^;]+)", cd) or re.search(r'filename="?([^";]+)"?', cd)
    name = urllib.parse.unquote(m.group(1)) if m else os.path.basename(urllib.parse.urlsplit(resp.geturl()).path)
    name = os.path.basename(name.strip()) or "lora.safetensors"
    return re.sub(r"[^\w.\-+ ()]", "_", name)


def download(entry: str, dest_dir: Path, done: dict[str, str]) -> bool:
    custom = None
    if "=" in entry and not entry.startswith("http"):
        custom, entry = entry.split("=", 1)
        custom = os.path.basename(custom.strip())
    if entry in done and (dest_dir / done[entry]).exists():
        log(f"already downloaded: {done[entry]}")
        return True
    try:
        url = resolve(entry)
        req = urllib.request.Request(url, headers=headers_for(url))
        with OPENER.open(req, timeout=120) as resp:
            name = custom or filename_from(resp, url)
            target = dest_dir / name
            if target.exists():
                log(f"exists, skipping: {name}")
            else:
                total = int(resp.headers.get("Content-Length") or 0)
                log(f"downloading {name} ({total / 2**20:.0f} MB)" if total else f"downloading {name}")
                tmp = target.with_suffix(target.suffix + ".part")
                with open(tmp, "wb") as f:
                    while chunk := resp.read(8 * 2**20):
                        f.write(chunk)
                tmp.rename(target)
                log(f"OK  {name}")
        done[entry] = name
        return True
    except Exception as exc:  # noqa: BLE001 — jeden zlý odkaz nesmie zastaviť štart
        hint = " (Civitai usually requires CIVITAI_TOKEN)" if "civitai" in entry and "401" in str(exc) else ""
        log(f"ERROR {entry}: {exc}{hint}")
        return False


def main() -> int:
    dest = Path(sys.argv[1])
    dest.mkdir(parents=True, exist_ok=True)
    raw = os.environ.get("LORA_URLS", "")
    entries = [e for e in re.split(r"[\s,]+", raw) if e]
    if not entries:
        return 0
    state = dest / ".downloaded.json"
    try:
        done = dict(json.loads(state.read_text()))
    except Exception:
        done = {}
    ok = all([download(e, dest, done) for e in entries])
    state.write_text(json.dumps(done, indent=1))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
