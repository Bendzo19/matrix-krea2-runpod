#!/usr/bin/env bash
# Installation check on a running pod:  /opt/scripts/check.sh
# Verifies versions, the 20 MATRIX registrations, missing workflow nodes and models.
# Runs nothing (no generation, no xAI call).
set -uo pipefail
COMFYUI_DIR="${COMFYUI_DIR:-/opt/ComfyUI}"
DATA="${DATA_DIR:-/workspace/matrix-krea2}"
URL="${COMFY_URL:-http://127.0.0.1:8188}"

python - "$COMFYUI_DIR" "$DATA" "$URL" <<'PY'
import json, os, subprocess, sys, urllib.request
comfy, data, url = sys.argv[1:4]
ok = True
def res(cond, msg):
    global ok
    ok &= bool(cond)
    print(("  OK   " if cond else "  FAIL ") + msg)

def head(path):
    return subprocess.run(["git", "-C", path, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()

print("== Versions")
import torch
res(torch.__version__.startswith("2.8.0"), f"PyTorch {torch.__version__}, CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    p = torch.cuda.get_device_properties(0)
    print(f"       GPU: {p.name}, {p.total_memory/2**30:.1f} GB VRAM")
res(head(comfy) == "4da9e2dbead52fc1e68beae33fe3d7ad63b63241", "ComfyUI v0.33.3 (4da9e2db)")
mx = os.path.join(comfy, "custom_nodes", "MATRIX-LAB-Nodes")
res(head(mx) == "27c48f36b0ad871b301d9cb848c0f4484c2850f5", "MATRIX-LAB-Nodes 0.4.0 (27c48f36)")
res(head(os.path.join(comfy, "custom_nodes", "rgthree-comfy")) == "2c5342a8cb0eaecaabf61435a5f37dd594c510ba", "rgthree-comfy (2c5342a8)")
for mod, ver in (("onnxruntime", "1.29.0"), ("ultralytics", "8.4.142")):
    try:
        v = __import__(mod).__version__; res(v == ver, f"{mod} {v}")
    except Exception as e:
        res(False, f"{mod}: {e}")

print("== Live nodes (ComfyUI /object_info)")
try:
    info = json.load(urllib.request.urlopen(url + "/object_info", timeout=30))
except Exception as e:
    print(f"  FAIL ComfyUI is not running at {url}: {e}"); sys.exit(1)
manifest = json.load(open(os.path.join(mx, "MANIFEST.json")))
want = manifest["nodes"]
res(len(want) == 20 and manifest["version"] == "0.4.0", f"manifest 0.4.0 with {len(want)} registrations")
missing = [n for n in want if n not in info]
res(not missing, "all 20 MATRIX IDs registered" + (f" — missing: {missing}" if missing else ""))
wrong = [n for n in want if n in info and "MATRIX-LAB-Nodes" not in str(info[n].get("python_module", ""))]
res(not wrong, "all MATRIX IDs come from the unified MATRIX-LAB-Nodes pack" + (f" — other source: {wrong}" if wrong else ""))

wf_path = os.path.join(data, "user/default/workflows/MATRIX-Krea2-V1.json")
wf = json.load(open(wf_path, encoding="utf-8"))
virtual = {"Note", "MarkdownNote", "Fast Groups Bypasser (rgthree)", "Reroute", "PrimitiveNode"}
types = sorted({n["type"] for n in wf["nodes"]} - virtual)
miss = [t for t in types if t not in info]
res(not miss, f"workflow: {len(types)} node types, missing: {miss or 'none'}")

print("== Models in dropdowns")
def choices(node, inp):
    try: return info[node]["input"]["required"][inp][0]
    except Exception: return []
res("krea2_turbo_fp8_scaled.safetensors" in choices("UNETLoader", "unet_name"), "UNET krea2_turbo_fp8_scaled")
res("wan_2.1_vae.safetensors" in choices("VAELoader", "vae_name"), "VAE wan_2.1_vae")
res("qwen3vl_4b_bf16.safetensors" in str(info.get("MATRIX_Krea2CLIPLoader", {}).get("input", {})), "CLIP qwen3vl_4b_bf16")
verified = os.path.join(data, "models/.verified")
n = len(os.listdir(verified)) if os.path.isdir(verified) else 0
res(n >= 7, f"SHA-256 verified files: {n}/7")

print("\nRESULT:", "ALL OK — ready to generate" if ok else "something is missing, see FAIL lines above")
sys.exit(0 if ok else 1)
PY
