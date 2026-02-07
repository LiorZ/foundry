# ==============================================================================
# Foundry - Protein Design & Structure Prediction Framework
# Multi-stage Dockerfile with all model checkpoints pre-installed
# ==============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Build wheel
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

# Build the wheel (hatch-vcs needs git history for versioning)
RUN pip install --no-cache-dir hatchling "hatch-vcs==0.4" \
    && python -m hatchling build -t wheel

# ---------------------------------------------------------------------------
# Stage 2: Runtime image
# ---------------------------------------------------------------------------
FROM vastai/base-image:cuda-12.4.1-auto

ENV DEBIAN_FRONTEND=noninteractive

# Add deadsnakes PPA for Python 3.12 (Ubuntu 22.04 ships 3.10)
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3.12 \
        python3.12-venv \
        python3.12-dev \
        wget \
        git \
    && rm -rf /var/lib/apt/lists/*

# Make python3.12 the default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Upgrade pip
RUN python -m ensurepip --upgrade 2>/dev/null; \
    python -m pip install --no-cache-dir --upgrade pip setuptools wheel

# ---------------------------------------------------------------------------
# Install PyTorch with CUDA 12.4 support
# ---------------------------------------------------------------------------
RUN pip install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu124

# ---------------------------------------------------------------------------
# Install foundry from the built wheel (with all optional dependencies)
# ---------------------------------------------------------------------------
COPY --from=builder /build/dist/*.whl /tmp/
RUN WHEEL=$(ls /tmp/*.whl) && pip install --no-cache-dir "${WHEEL}[all]" \
    && rm -f /tmp/*.whl

# ---------------------------------------------------------------------------
# Download all model checkpoints
# ---------------------------------------------------------------------------
ENV FOUNDRY_CHECKPOINT_DIR=/root/.foundry/checkpoints
RUN mkdir -p /root/.foundry/checkpoints

# RFdiffusion3
RUN wget -q --show-progress -O /root/.foundry/checkpoints/rfd3_latest.ckpt \
    "https://files.ipd.uw.edu/pub/rfd3/rfd3_foundry_2025_12_01_remapped.ckpt"

# RosettaFold3 (latest)
RUN wget -q --show-progress -O /root/.foundry/checkpoints/rf3_foundry_01_24_latest_remapped.ckpt \
    "https://files.ipd.uw.edu/pub/rf3/rf3_foundry_01_24_latest_remapped.ckpt"

# ProteinMPNN
RUN wget -q --show-progress -O /root/.foundry/checkpoints/proteinmpnn_v_48_020.pt \
    "https://files.ipd.uw.edu/pub/ligandmpnn/proteinmpnn_v_48_020.pt"

# LigandMPNN
RUN wget -q --show-progress -O /root/.foundry/checkpoints/ligandmpnn_v_32_010_25.pt \
    "https://files.ipd.uw.edu/pub/ligandmpnn/ligandmpnn_v_32_010_25.pt"

# SolubleMPNN
RUN wget -q --show-progress -O /root/.foundry/checkpoints/solublempnn_v_48_020.pt \
    "https://files.ipd.uw.edu/pub/ligandmpnn/solublempnn_v_48_020.pt"

# Enhanced MPNN (local weights, fine-tuned from LigandMPNN)
COPY weights/enhanced_mpnn_step_80000.pt /root/.foundry/checkpoints/enhanced_mpnn_step_80000.pt

# ---------------------------------------------------------------------------
# Environment configuration
# ---------------------------------------------------------------------------
ENV FOUNDRY_CHECKPOINT_DIRS=/root/.foundry/checkpoints

WORKDIR /workspace

# Default entrypoint: drop into a shell
CMD ["bash"]
