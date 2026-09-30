# Krea 2 AI Influencer — 2K / 4K (ComfyUI)

Realistic AI-influencer photos in **real 4K** with Krea 2 Turbo (FP8), automatic **eye detailer**, skin detailer and photo finishing.
Everything is preinstalled — deploy, open ComfyUI, type a prompt, press **Run**.

Based on the free **MATRIX Krea 2 V1.1.0** workflow by MATRIX LAB (Apache 2.0).

---

## 1. Deploy (2 minutes)

1. Click **Deploy** and pick a GPU — **RTX 5090** recommended (tested for 2K and 4K). 48 GB cards (L40S, A6000, RTX PRO 6000) work great too.
2. Keep the default disk sizes. For repeated use attach a **Network Volume** (60 GB+) — models and your LoRAs stay there and the next pod starts in ~1 minute.
3. *(Optional)* In **Environment Variables** fill in:
   - `LORA_URLS` – your LoRA link(s), see below
   - `CIVITAI_TOKEN` – needed for most Civitai downloads (civitai.com → Account settings → API Keys)
   - `JUPYTER_PASSWORD` – password for the file manager
4. The first start downloads the models (~22 GB, usually 2–5 min). Watch **Logs** until you see `Starting ComfyUI` and the ComfyUI link.

## 2. Open the workflow

**Connect → HTTP Service [Port 8188]** → left sidebar **Workflows** → **MATRIX-Krea2-V1.json**.

## 3. Add your LoRA (character / style)

Pick one:

- **Link (easiest):** put the link into `LORA_URLS` before deploying (or edit the pod and restart). Several links separated by commas.
  - Civitai: `https://civitai.com/models/12345` or `…?modelVersionId=67890`
  - Hugging Face: `https://huggingface.co/user/repo/blob/main/my_lora.safetensors`
  - Custom file name: `anna.safetensors=https://…`
- **Upload:** **Connect → Port 8888** (JupyterLab) → open folder **LORAS** → drag & drop your `.safetensors` file.

Then in ComfyUI press **R** (refresh), find **Power Lora Loader** in group *01 Models + Character* → **➕ Add Lora** → choose your file.

- Strength **0.8 – 1.0** is a good start.
- Put your **trigger word** at the beginning of your prompt.
- Use LoRAs trained for **Krea 2**. If you get an error about a protected/encoder patch, right-click Power Lora Loader → *Show Strengths: Separate Model & Clip* and set **clip = 0**.

## 4. Generate

1. **00 Resolution** – aspect ratio (1:1, 9:16, 3:4 …) and **2K** or **4K**. Use 2K while testing prompts (faster), 4K for final images.
2. **02 Manual Prompt** – write your prompt in the main text box (it ships empty — never run with an empty prompt). Keep the switch on **OFF / Manual**.
   Tip: describe it like a real phone photo: *"casual amateur snapshot of …, natural light, candid, slightly imperfect framing"*.
3. Press **Run** (Queue).

Your images are in **OUTPUTS** (JupyterLab, port 8888) or right-click → *Save image* in ComfyUI:
- `MATRIX-Krea2_…png` – clean image, metadata removed (for posting)
- `MATRIX-Krea2-Standard_…png` – contains the workflow

## Best settings

The workflow is already tuned — **leave the sampler, steps and models on default**.

| Stage | Tip |
| --- | --- |
| 04 Skin Detailer | Krea 2 skin is already good; try it **off** (group switch at the top) for a more natural look. |
| 05 Eye Detailer | Keep **on** — biggest quality gain (sharp iris, catchlight). |
| 06 Photo Finisher | `Everyday Capture` (default), `Clean Digital` (cleaner), `Low Light` (evening/night). |
| Seed | New random seed each run. Fix the seed to iterate on one image. |

Every stage has an ON/OFF switch in the **Fast Groups Bypasser** at the top of the canvas.

**Auto Prompter (optional, paid):** add a few reference photos, press **Generate Prompt**, then copy the result into the manual prompt. Uses the xAI API (a few cents per prompt) — set `XAI_API_KEY` in Environment Variables.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Model / LoRA not in the list | wait until the download finishes, then press **R** in ComfyUI |
| Out of memory at 4K | switch to 2K, turn off Skin Detailer, or pick a bigger GPU |
| `CUDA driver` error | deploy on a machine with CUDA 12.8+ (filter in the GPU list) |
| LoRA download failed | Civitai needs `CIVITAI_TOKEN`; check `/workspace/matrix-krea2/logs/lora.log` |

Don't forget to **Stop / Terminate** the pod when you are done — you pay while it runs.
