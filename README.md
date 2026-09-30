# MATRIX Krea 2 V1.1.0 — RunPod template

Docker image + RunPod Pod template pre workflow **MATRIX Krea 2 V1** (release 1.1.0) od MATRIX LAB.
Zostaví presne to prostredie, na ktorom autor workflow overil (2K/4K, Photo Finisher ON/OFF, RTX 5090):

| Komponent | Verzia (pripnuté) |
| --- | --- |
| ComfyUI | 0.33.3 — `4da9e2dbead52fc1e68beae33fe3d7ad63b63241`, frontend 1.49.6 |
| PyTorch | 2.8.0+cu128, Python 3.12 |
| MATRIX-LAB-Nodes | 0.4.0 — `27c48f36b0ad871b301d9cb848c0f4484c2850f5` (20 registrácií) |
| rgthree-comfy | `2c5342a8cb0eaecaabf61435a5f37dd594c510ba` |
| Detektory | onnxruntime 1.29.0, ultralytics 8.4.142, segment-anything 1.0 |
| Workflow | `MATRIX-Krea2-V1.json` + API verzia z release v1.1.0 |

Modely (7 súborov, ~22.3 GB) sa stiahnu pri **prvom** štarte na `/workspace` a overia sa cez SHA-256.
Pri ďalších štartoch sa už nesťahujú ani znovu nehashujú.

---

## 1. Zostav a nahraj image

Image sa builduje cez GitHub Actions (lokálny Docker netreba):

1. Nahraj tento priečinok do GitHub repozitára (napr. `matrix-krea2-runpod`).
2. Push na `main` spustí workflow **Build & push RunPod image** (~15–25 min).
3. Image je v `ghcr.io/<tvoj-github-login>/matrix-krea2-runpod:v1.1.0`.
4. GitHub → tvoj profil → **Packages** → `matrix-krea2-runpod` → *Package settings* →
   **Change visibility → Public** (alebo nechaj Private a v RunPode pridaj *Container Registry Credentials*
   s GitHub tokenom so scope `read:packages`).

Ak máš Docker lokálne: `docker build -t <user>/matrix-krea2-runpod:v1.1.0 . && docker push …`

## 2. Vytvor template v RunPode

RunPod → **Templates → New Template**:

| Pole | Hodnota |
| --- | --- |
| Template Name | `MATRIX Krea 2 V1.1.0` |
| Template Type | Pod |
| Container Image | `ghcr.io/<user>/matrix-krea2-runpod:v1.1.0` |
| Container Disk | **30 GB** |
| Volume Disk | **60 GB** (modely 22.3 GB + výstupy), mount path **`/workspace`** |
| Expose HTTP Ports | `8188,8888` |
| Expose TCP Ports | `22` |

Environment variables:

| Premenná | Hodnota | Načo |
| --- | --- | --- |
| `JUPYTER_PASSWORD` | tvoje heslo | prihlásenie do JupyterLab (8888). Bez neho sa vygeneruje token do logu. |
| `XAI_API_KEY` | `{{ RUNPOD_SECRET_xai_api_key }}` | *voliteľné* — iba pre Auto Prompter (tlačidlo **Generate Prompt**, platené xAI). Kľúč si ulož v RunPod → Secrets. |
| `HF_TOKEN` | `{{ RUNPOD_SECRET_hf_token }}` | *voliteľné* — modely sú verejné, token len obíde rate-limit HF. |
| `LORA_URLS` | *(prázdne)* | odkazy na LoRA (Civitai stránka/verzia, Hugging Face, priamy link), oddelené čiarkou. Stiahnu sa do `models/loras` pri štarte. |
| `CIVITAI_TOKEN` | *(prázdne)* | API kľúč z civitai.com (väčšina Civitai downloadov ho vyžaduje). |
| `DOWNLOAD_GROUPS` | `core,eye,skin` | ktoré modely sťahovať (default všetky). |
| `COMFYUI_EXTRA_ARGS` | *(prázdne)* | extra argumenty pre `main.py`. |

> Pri **Network Volume** (odporúčané) zostanú modely aj výstupy medzi podmi — nový pod štartuje za ~1 min.

### Aký GPU

| GPU | Poznámka |
| --- | --- |
| **RTX 5090 (32 GB)** | ✅ presne na tomto autor overoval 2K aj 4K — najlepší pomer cena/výkon |
| RTX PRO 6000 / L40S / A6000 (48 GB) | viac VRAM rezervy pre 4K + LoRA |
| H100 / H200 | najrýchlejšie, drahé |
| RTX 4090 (24 GB) | neoverené; 2K by malo ísť, pri 4K môže byť OOM |

Pri vytváraní podu nastav filter **CUDA 12.8+** (image používa cu128) a vyber pod s aspoň **~48 GB RAM** (Krea2 model guard si pri načítaní robí dočasnú kópiu v RAM).

## 3. Prvé spustenie

1. Deploy pod so šablónou. V **Logs** uvidíš sťahovanie modelov (`[models] …`).
2. Keď sa objaví `Starting ComfyUI`, klikni **Connect → HTTP 8188**.
3. Vľavo **Workflows** → otvor `MATRIX-Krea2-V1.json` (už je predinštalovaný, Classic canvas je zapnutý).
4. Voliteľná kontrola (JupyterLab terminál alebo SSH): `/opt/scripts/check.sh` → má skončiť *ALL OK*.

## 4. Najlepšie nastavenia (podľa autora + dokumentácie)

Autor vo videu výslovne hovorí: **FP8 model a všetko nechať na defaulte**. Workflow je naladený — nemeň sampler, kroky ani shift.

| Časť | Default vo workflow | Odporúčanie |
| --- | --- | --- |
| **00 Resolution** | `3:4`, `4K` | na skúšanie promptov **2K** (rýchlejšie), finálne **4K**. 4K sa generuje správne: začne v 2K (Krea 2 je trénovaná max. na 2048 px) a posledné kroky dokončí na 4K. |
| **01 Models** | krea2_turbo_fp8 · qwen3vl_4b_bf16 · wan_2.1_vae | nemeniť |
| **02 Prompt** | prázdny, prepínač **OFF / Manual** | napíš vlastný prompt do hlavného *CLIP Text Encode* — **bez promptu nespúšťaj**. Štýl: „realistic casual amateur snapshot…“ (ako v Auto Prompter inštrukciách). |
| **03 Generation** | 8 krokov, `simple`, shift 3.158, Spectral Sampler | nemeniť; seed je `randomize` |
| **04 Skin Detailer** | ON | autor ho vo videu **vypína** (Krea 2 má dobrú pleť sama). Skús oboje cez *Fast Groups Bypasser*. |
| **05 Eye Detailer** | ON | **nechaj ON** — najväčší rozdiel v kvalite (iris, catchlight). Ak nenájde oči, obrázok nechá tak. |
| **06 Photo Finisher** | `Everyday Capture`, mix 1, texture 1, detail 1 | `Clean Digital` = čistejší, `Low Light` = večer/noc. Jemné doladenie: `texture` 0.6–1.2, `detail` 0.5–1. |
| **07 Save** | Metadata Killer (PNG) + Save Image | `MATRIX-Krea2_*` = čistý obrázok bez metadát (na zdieľanie), `MATRIX-Krea2-Standard_*` = s workflow v metadátach. |

Ďalej:
- **Nepoužívaj** `--fast`, SageAttention a pod. v `COMFYUI_EXTRA_ARGS` — FP8 cesta s MATRIX model guardom bola overená len bez nich.
- **Nodes 2.0** nie je podporovaný — template ho vypína (`Comfy.VueNodes.Enabled=false`). Nezapínaj ho.
- LoRA: `LORA_URLS` alebo upload do `/workspace/LORAS`, potom **R** v ComfyUI a *Power Lora Loader → ➕ Add Lora* (sila 0.8–1.0, trigger slovo na začiatok promptu). Ak hlási chybu o encoder/protected patch, nastav v loaderi *Separate Model & Clip* a clip = 0 (MATRIX guard odmieta LoRA patche na text encoder).
- Auto Prompter: vlož referenčné obrázky → **Generate Prompt** (pár centov cez xAI) → skopíruj výsledok do manuálneho promptu.

## 5. Zverejnenie pre zákazníkov (public template)

Cieľ: zákazník nájde template v RunPod → **Explore**, klikne **Deploy**, pridá LoRA a generuje.

1. Image v GHCR musí byť **Public** (krok 1.4) — inak ho cudzí pod nestiahne.
2. RunPod → **Templates → New Template** vyplň podľa kroku 2, ale:
   - **Visibility: Public**
   - **Template Name:** napr. `Krea 2 AI Influencer 2K/4K (ComfyUI)` — názvy „MATRIX LAB“ / „MATRIX Krea 2“
     nie sú súčasťou Apache licencie, používaj ich iba ako uvedenie pôvodu („based on MATRIX Krea 2 workflow by MATRIX LAB“).
   - **README:** vlož celý obsah [TEMPLATE_README.md](TEMPLATE_README.md) (anglický návod pre zákazníkov).
   - Env premenné pridaj **s prázdnou hodnotou** (`LORA_URLS`, `CIVITAI_TOKEN`, `JUPYTER_PASSWORD`, `XAI_API_KEY`) —
     zákazník ich vyplní pri deployi. **Nevkladaj tam svoje tokeny ani `{{ RUNPOD_SECRET_… }}`** — tie fungujú len na tvojom účte.
3. Po uložení skopíruj odkaz na template (`https://console.runpod.io/deploy?template=<id>`) a pošli ho zákazníkom.
   Pridaním `&ref=<tvoj-referral-kód>` získaš aj referral odmenu od RunPodu.
4. RunPod má program odmien pre autorov verejných template (podiel z výdavkov na podoch s tvojím template) — skontroluj aktuálne podmienky v RunPod → *Referrals*.

Zákazník potom: **Deploy → (voliteľne vloží link na LoRA do `LORA_URLS`) → Connect 8188 → Workflows → prompt → Run.**
LoRA môže aj len pretiahnuť do priečinka `LORAS` v JupyterLab (port 8888) a v ComfyUI stlačiť **R**.

## Priečinky na pode

```
/workspace/matrix-krea2/
├── models/        # všetky modely (+ .verified/ značky SHA-256)
├── output/        # vygenerované obrázky
├── input/
├── user/default/workflows/MATRIX-Krea2-V1.json
├── api/MATRIX-Krea2-V1.api.json   # pre automatizáciu cez /prompt API
├── logs/          # comfyui.log, models.log, jupyter.log
└── on_start.sh    # (voliteľné) tvoj skript, spustí sa pred ComfyUI
/workspace/LORAS   -> models/loras   (skratka pre upload v JupyterLab)
/workspace/OUTPUTS -> output         (skratka pre stiahnutie fotiek)
```

Výstupy stiahneš cez JupyterLab (port 8888 → pravý klik → Download) alebo priamo v ComfyUI.

## Riešenie problémov

| Problém | Riešenie |
| --- | --- |
| Model chýba v dropdowne | pozri `logs/models.log`; reštartuj pod (sťahovanie pokračuje / znovu overí). |
| `SHA-256 NESEDÍ` | súbor sa zmaže a stiahne znova; ak to zlyhá 3×, je problém so zdrojom/sieťou. |
| Červené nody | `/opt/scripts/check.sh`; nepridávaj staré `matrix-krea2-adapter` / `MATRIXLAB-*` balíky. |
| OOM na 4K | prepni na 2K alebo vypni Skin Detailer; vyber GPU s viac VRAM. |
| `CUDA driver too old` | pri vytváraní podu filtruj CUDA 12.8+. |

## Licencie

Workflow aj MATRIX-LAB-Nodes sú od 2026-09-29 pod **Apache 2.0** (vrátane release 1.1.0 / 0.4.0, viď NOTICE v ich repozitároch).
Názvy „MATRIX LAB“ / „MATRIX Krea 2“ a logá licencované nie sú. Modely a detektory majú vlastné licencie
(pozri `MODELS.md` a `docs/detector-setup.md` v pôvodnom balíku; ultralytics je AGPL-3.0).
Image nič nesťahuje z tvojho účtu a nevolá xAI bez tvojho kliknutia.
