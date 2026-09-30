# MATRIX Krea 2 V1.1.0 — RunPod Pod template
#
# Reprodukuje presne overené prostredie z release 1.1.0:
#   ComfyUI 0.33.3 (4da9e2db…) · frontend 1.49.6 · PyTorch 2.8.0+cu128 · Python 3.12
#   MATRIX-LAB-Nodes 0.4.0 (27c48f36…) · rgthree-comfy (2c5342a8…)
# (PyTorch wheel si nesie vlastné CUDA/cuDNN knižnice, preto stačí base image.)
# Modely (~22.3 GB) sa sťahujú pri prvom štarte na /workspace (network volume) a overia SHA-256.

FROM nvidia/cuda:12.8.1-base-ubuntu24.04

ARG COMFYUI_COMMIT=4da9e2dbead52fc1e68beae33fe3d7ad63b63241
ARG MATRIX_NODES_COMMIT=27c48f36b0ad871b301d9cb848c0f4484c2850f5
ARG RGTHREE_COMMIT=2c5342a8cb0eaecaabf61435a5f37dd594c510ba
ARG WORKFLOW_COMMIT=658a5151bc4336e3b51470753b879c4f6ad743b0
ARG TORCH_INDEX=https://download.pytorch.org/whl/cu128

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_NO_CACHE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    COMFYUI_DIR=/opt/ComfyUI \
    YOLO_OFFLINE=True \
    HF_HUB_DISABLE_TELEMETRY=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev \
        git curl wget ca-certificates aria2 rsync nano less htop tmux unzip \
        openssh-server \
        libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 ffmpeg \
        build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# uv = rýchla inštalácia balíkov
COPY --from=ghcr.io/astral-sh/uv:0.8 /uv /usr/local/bin/uv
RUN uv venv --python /usr/bin/python3.12 /opt/venv

# 1) PyTorch — presne overená verzia (Blackwell/RTX 5090 potrebuje cu128)
RUN uv pip install --index-url ${TORCH_INDEX} \
        torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 \
    && printf 'torch==2.8.0\ntorchvision==0.23.0\ntorchaudio==2.8.0\n' > /opt/torch-constraints.txt

# 2) ComfyUI core pripnutý na v0.33.3
RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} \
    && git -C ${COMFYUI_DIR} checkout ${COMFYUI_COMMIT} \
    && uv pip install -c /opt/torch-constraints.txt -r ${COMFYUI_DIR}/requirements.txt

# 3) Custom nodes — pripnuté commity
RUN cd ${COMFYUI_DIR}/custom_nodes \
    && git clone https://github.com/JsonMatrixLab/MATRIX-LAB-Nodes.git MATRIX-LAB-Nodes \
    && git -C MATRIX-LAB-Nodes checkout ${MATRIX_NODES_COMMIT} \
    && test "$(git -C MATRIX-LAB-Nodes rev-parse HEAD)" = "${MATRIX_NODES_COMMIT}" \
    && git clone https://github.com/rgthree/rgthree-comfy.git rgthree-comfy \
    && git -C rgthree-comfy checkout ${RGTHREE_COMMIT} \
    && test "$(git -C rgthree-comfy rev-parse HEAD)" = "${RGTHREE_COMMIT}" \
    && uv pip install -c /opt/torch-constraints.txt \
        -r MATRIX-LAB-Nodes/requirements.txt \
        onnxruntime==1.29.0 ultralytics==8.4.142 segment-anything==1.0 \
    && python -c "import json;m=json.load(open('MATRIX-LAB-Nodes/MANIFEST.json'));print('MATRIX manifest OK')"

# 4) Workflow (UI + API) z release v1.1.0
RUN git clone https://github.com/JsonMatrixLab/MATRIX-Krea2-Workflow.git /opt/MATRIX-Krea2-Workflow \
    && git -C /opt/MATRIX-Krea2-Workflow checkout ${WORKFLOW_COMMIT} \
    && mkdir -p /opt/defaults/workflows \
    && cp /opt/MATRIX-Krea2-Workflow/MATRIX-Krea2-V1.json /opt/defaults/workflows/ \
    && cp /opt/MATRIX-Krea2-Workflow/API/MATRIX-Krea2-V1.api.json /opt/defaults/ \
    && rm -rf /opt/MATRIX-Krea2-Workflow/.git

# 5) Jupyter (sťahovanie výstupov / správa súborov)
RUN uv pip install "jupyterlab==4.4.*"

COPY models.txt /opt/models.txt
COPY comfy.settings.json /opt/defaults/comfy.settings.json
COPY scripts/ /opt/scripts/
RUN sed -i 's/\r$//' /opt/scripts/*.sh /opt/models.txt && chmod +x /opt/scripts/*.sh

# Rýchly sanity check (build beží bez GPU, preto iba import bez načítania modelu)
RUN cd ${COMFYUI_DIR} && python -c "import torch, folder_paths, onnxruntime, ultralytics, segment_anything; print('torch', torch.__version__)"

WORKDIR /workspace
EXPOSE 8188 8888 22

CMD ["/opt/scripts/start.sh"]
