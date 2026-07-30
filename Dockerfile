# syntax=docker/dockerfile:1

# X-AnyLabeling-Server 非官方 CPU 镜像
# 上游: https://github.com/CVHub520/X-AnyLabeling-Server
#
# 两个构建目标:
#   base — 仅核心依赖，体积小，只能跑 API 类模型 (GLM / OpenAI 兼容)
#   all  — 额外装 ultralytics / transformers / sam3 与 CPU 版 PyTorch

ARG PYTHON_VERSION=3.12
ARG UV_VERSION=0.12.0

# COPY --from= 不支持变量展开，所以先把带版本的 uv 镜像固定成一个命名 stage
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uvbin

# ---------------------------------------------------------------- 上游源码
FROM python:${PYTHON_VERSION}-slim AS source

ARG UPSTREAM_REPO=CVHub520/X-AnyLabeling-Server
ARG UPSTREAM_REF=main

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 不加 "|| git clone <默认分支>" 兜底: ref 不存在就让构建失败，
# 否则会把 main 的内容打上版本号标签推出去
RUN git clone --depth 1 --branch "${UPSTREAM_REF}" \
      "https://github.com/${UPSTREAM_REPO}.git" . \
  && git rev-parse HEAD > UPSTREAM_SHA \
  && rm -rf .git

# ---------------------------------------------------------------- base
FROM python:${PYTHON_VERSION}-slim AS base

ARG UPSTREAM_REF=main
ARG BUILD_DATE

COPY --from=uvbin /uv /usr/local/bin/uv

LABEL org.opencontainers.image.title="X-AnyLabeling-Server" \
      org.opencontainers.image.description="X-AnyLabeling-Server (CPU, core deps only)" \
      org.opencontainers.image.source="https://github.com/CVHub520/X-AnyLabeling-Server" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${UPSTREAM_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    UV_SYSTEM_PYTHON=1 \
    UV_NO_CACHE=1 \
    UV_LINK_MODE=copy

# curl 给 HEALTHCHECK 用; libgomp1 是 numpy / onnxruntime 等原生库的运行时依赖
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl libgomp1 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=source /src /app

# 用 editable 安装: app/core/config.py 按 <repo_root>/configs/server.yaml
# 解析默认配置，源码留在 /app 才能让 /app/configs 成为可挂载覆盖的位置
RUN uv pip install -e . \
  && mkdir -p /app/weights /app/logs

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/health || exit 1

CMD ["x-anylabeling-server", "--host", "0.0.0.0", "--port", "8000"]

# ---------------------------------------------------------------- all
FROM base AS all

# ultralytics 依赖非 headless 的 opencv-python，需要这些系统库
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       libgl1 libglib2.0-0 libsm6 libxext6 \
  && rm -rf /var/lib/apt/lists/*

# 先从 PyTorch CPU 索引装 torch，否则下一步会从 PyPI 拉约 2.5GB 的 CUDA 版。
# uv 默认 first-index 策略: torch/torchvision 命中 pytorch 索引，
# 其余传递依赖回落到 PyPI
RUN uv pip install torch torchvision \
      --index-url https://download.pytorch.org/whl/cpu \
      --extra-index-url https://pypi.org/simple

# [all] 里 sam3 要求 torch>=2.7.0，上一步装的 CPU 版已满足，不会被覆盖重装
RUN uv pip install -e ".[all]"

LABEL org.opencontainers.image.description="X-AnyLabeling-Server (CPU, all extras)"
