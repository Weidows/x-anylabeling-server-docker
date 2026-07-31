# x-anylabeling-server-docker

[X-AnyLabeling-Server](https://github.com/CVHub520/X-AnyLabeling-Server) 的非官方
Docker 镜像。上游没有提供官方镜像，这个仓库按周检查上游 release，有新版本就自动构建并推送。

> **这是纯推理 API 服务，不带 Web 界面。** 浏览器打开 `http://localhost:8000/`
> 会看到 404，这是正常的。界面在
> [X-AnyLabeling 桌面端](https://github.com/CVHub520/X-AnyLabeling)，由它连这个服务。
> 详见 [下面这节](#这是-api-服务没有-web-界面)。

- **构建配置与 Issue**: https://github.com/Weidows/x-anylabeling-server-docker
- **上游项目**: https://github.com/CVHub520/X-AnyLabeling-Server
- Docker Hub: [`weidows/x-anylabeling-server-docker`](https://hub.docker.com/r/weidows/x-anylabeling-server-docker)
- GHCR: `ghcr.io/weidows/x-anylabeling-server-docker`

两个 registry 推送同一批标签，Docker Hub 限流时可以直接换 GHCR。

## 镜像标签

| 标签 | 变体 | 拉取大小 | 磁盘占用 | 说明 |
| --- | --- | --- | --- | --- |
| `latest` `cpu` `<ver>` `<ver>-cpu` | CPU 全功能 | 0.70 GiB | 2.23 GiB | 含 `[all]` extras 与 CPU 版 PyTorch |
| `base` `slim` `<ver>-base` | CPU 精简 | 0.16 GiB | 0.45 GiB | 只装核心依赖，**只能跑 API 类模型** |
| `cuda` `gpu` `<ver>-cuda` `<ver>-cuda12.6` | CUDA 12.6 | 5.78 GiB | 10.36 GiB | 含 `[all]` extras 与 `cu126` 版 PyTorch |

体积是 v0.0.11 的实测值，每次构建都会把当次数字写进 Actions 的 job summary。

`<ver>` 是上游 release tag，例如 `v0.0.11`。带版本号的标签不会被覆盖，
`latest` / `base` / `cuda` 这类滚动标签会随新版本移动。

目前只构建 `linux/amd64`。

## 快速开始

```bash
docker run -d --name x-anylabeling-server \
  -p 8000:8000 \
  -v "$PWD/weights:/app/weights" \
  weidows/x-anylabeling-server-docker:latest

curl http://localhost:8000/health
curl http://localhost:8000/v1/models
```

GPU 版（需要宿主机装好 NVIDIA 驱动和 `nvidia-container-toolkit`）：

```bash
docker run -d --name x-anylabeling-server \
  --gpus all -p 8000:8000 \
  -v "$PWD/weights:/app/weights" \
  weidows/x-anylabeling-server-docker:cuda
```

或者用 compose（CPU，仅够快速试跑）：

```bash
docker compose up -d
```

## 这是 API 服务，没有 Web 界面

根路径 `/` 没有注册任何路由，也没有挂载静态文件，所以 `http://localhost:8000/`
返回 404 —— 服务是好的。全部路由如下：

| 路由 | 方法 | 说明 |
| --- | --- | --- |
| `/health` | GET | 健康检查，返回已加载模型数 |
| `/v1/models` | GET | 列出已加载的模型 |
| `/v1/models/{model_id}/info` | GET | 单个模型的元信息 |
| `/v1/predict` | POST | 图片推理 |
| `/v1/video/init` | POST | 视频会话初始化 |
| `/v1/video/prompt` | POST | 加提示（点/框/文本）|
| `/v1/video/propagate` | POST | 逐帧传播 |
| `/v1/video/propagate/stream` | POST | 传播（流式）|
| `/v1/video/status/{task_id}` | GET | 任务状态 |
| `/v1/video/cancel/{task_id}` | POST | 取消任务 |
| `/v1/video/cleanup/{session_id}` | POST | 清理会话 |

用浏览器唯一能看的是 FastAPI 自带的接口文档（上游没关掉）：

- `http://localhost:8000/docs` — Swagger UI，可以直接点着调接口
- `http://localhost:8000/redoc` — ReDoc
- `http://localhost:8000/openapi.json` — OpenAPI schema

### 让 X-AnyLabeling 桌面端连上来

1. 装[X-AnyLabeling 客户端](https://github.com/CVHub520/X-AnyLabeling)
2. 改 `~/.xanylabelingrc`：

   ```yaml
   server_url: http://127.0.0.1:8000   # 服务不在本机就改成对应地址
   ```

3. 客户端里按 `Ctrl+A` 打开 AI 自动标注，模型下拉框里选
   **CVHub** → **Remote-Server**，就能看到这个服务上已加载的模型

注意客户端读的是**已加载**的模型，所以 `models.yaml` 里没启用、或者启用了但权重
缺失加载失败的，下拉框里都不会出现。`/health` 返回的 `models_loaded` 和
`/v1/models` 可以用来对账。

## GPU 部署

`deploy/cuda/` 是一套可以直接用的完整配置：

```bash
cd deploy/cuda
cp .env.example .env      # 填端口、API key
docker compose up -d
curl http://localhost:8000/health
```

前置条件是宿主机装好 NVIDIA 驱动和 `nvidia-container-toolkit`，先验一下：

```bash
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu22.04 nvidia-smi
```

里面处理了几个 `docker run` 一把梭会踩的点：

- **模型默认跑在 CPU 上**。`device` 是每个模型各自配的，上游
  `configs/auto_labeling/yolo11n.yaml` 写死了 `device: "cpu"` —— 光用 CUDA 镜像
  不改配置，推理还是在 CPU。`deploy/cuda/auto_labeling/yolo11n.yaml` 是改成
  `cuda:0` 的覆盖示例（SAM 系列上游默认就是 `cuda:0`，不用改）。
- **配置只能单文件挂**。上游把 `config_dir` 硬编码成 `/app/configs`，整目录挂载会
  盖掉 `auto_labeling/` 下那 21 个模型定义。「启用哪些模型」的清单则通过
  `XANYLABELING_MODELS_CONFIG` 挪到了容器外，不占用那个目录。
- **缓存持久化**。`HF_HOME` / `TORCH_HOME` / `YOLO_CONFIG_DIR` 都指到 `/app/weights`，
  `working_dir` 也设成了 `/app/weights`（相对 `model_path` 的落点）。不设这些的话，
  Qwen3-VL 这类几个 GB 的模型每次重建容器都要重下。
- **`shm_size: 2gb`**。PyTorch dataloader 走共享内存，容器默认 64MB 不够。
- **`start_period: 10m`**。冷启动要下权重，健康检查给短了会被反复重启。

按需启用模型改 `deploy/cuda/models.yaml`，里面把 21 个模型按「权重怎么来」分组
注释好了。改完 `docker compose restart` 生效。

## 配置

镜像里上游源码放在 `/app`，配置文件是 `/app/configs/server.yaml` 和
`/app/configs/models.yaml`（上游默认路径，未做改动）。

改配置用单文件挂载，**不要整目录挂载** `/app/configs`，否则会盖掉
`configs/auto_labeling/` 里几十个模型定义：

```bash
docker run -d -p 8000:8000 \
  -v "$PWD/models.yaml:/app/configs/models.yaml:ro" \
  -v "$PWD/weights:/app/weights" \
  weidows/x-anylabeling-server-docker:latest
```

相关环境变量（都来自上游）：

| 变量 | 用途 |
| --- | --- |
| `ZHIPU_API_KEY` | GLM 等智谱 API 模型 |
| `XANYLABELING_API_KEY` | `server.yaml` 里开启 `security.api_key_enabled` 后的访问令牌 |
| `XANYLABELING_SERVER_CONFIG` | 覆盖 `server.yaml` 路径 |
| `XANYLABELING_MODELS_CONFIG` | 覆盖 `models.yaml` 路径 |

**模型权重不打进镜像。** 上游 `configs/auto_labeling/*.yaml` 里的 `model_path`
是相对路径（例如 `yolo11n.pt`），首次加载时按各自框架的规则下载或查找。挂载
`/app/weights` 只是给你一个持久化位置，具体路径要在模型配置里指定。

## 与上游的唯一差异

`base` 变体额外装了一个 `packaging`。上游 `app/utils/update_checker.py` 会
`import packaging`，但 `pyproject.toml` 的核心依赖里没声明它 —— `[all]` extras
是靠 transformers 的传递依赖顺带装上的，所以只装核心依赖时服务会直接
`ModuleNotFoundError: No module named 'packaging'` 起不来。

除此之外镜像内容与上游 release 完全一致，配置文件也没有改动。

## 已知注意点

- **`base` 变体的启动告警**：上游默认 `models.yaml` 启用了 `yolo11n`，而 `base`
  没装 ultralytics，启动日志里会出现一条加载失败。上游代码对这种情况是
  catch + log，服务本身照常起来，`/health` 正常（实测 3s 就绪）。想去掉告警就
  挂载一个自己的 `models.yaml`。
- **`all` / `cuda` 会自动下载 yolo11n 权重**：上游默认启用 `yolo11n`，
  ultralytics 首次加载时会去 GitHub 拉 `yolo11n.pt`。挂载 `/app/weights` 或改
  `models.yaml` 可以避免每次重建容器都重新下载。
- **AGPL-3.0**：镜像内的软件是 AGPL-3.0 的。如果你把它作为网络服务对外提供，
  AGPL 的条款适用于你。本仓库自身的打包文件是 MIT，见 [LICENSE](LICENSE)。
- 本仓库与上游作者无关，问题请先确认是镜像打包问题再提。

## 自动化机制

### 每周检查

`.github/workflows/watch-upstream.yml` 每周一 03:17 UTC（北京时间 11:17）运行：

1. 取上游最新 release 的 tag
2. 逐个变体探测目标标签在 Docker Hub / GHCR 上是否已存在
3. 只构建缺失的变体，然后把结果写进 `version.json` 并提交

判断依据是"镜像标签存不存在"而不是"版本号变没变"，所以上次构建失败的变体、
或者后来才配上 Docker Hub 凭据的情况，下一周都会自动补齐。

也可以在 Actions 页面手动跑 **Watch upstream releases**，勾 `force` 可以强制重建。

### 手动构建指定版本

Actions → **Build and push images** → Run workflow：

- `version`：上游 tag 或分支，留空则取最新 release
- `variants`：`base,all,cuda` 中选，逗号分隔
- `move_tags`：是否让 `latest` / `base` / `cuda` 指向这次构建。构建测试分支时
  记得取消勾选

### 定时任务会被 GitHub 自动停用

仓库连续 60 天没有活动，GitHub 会自动禁用 schedule 触发器（会给你发邮件）。
所以 watch 工作流每次运行都会提交一次 `version.json`（记录 `checked_at`）来保持活动。

## 鉴权配置

GHCR 用内置 `GITHUB_TOKEN`，不需要配置。Docker Hub 需要两个 secret：

1. 去 [Docker Hub → Account Settings → Personal access tokens](https://app.docker.com/settings/personal-access-tokens)
   新建一个 token：
   - 只推镜像 → **Read & Write** 就够
   - 还要自动同步仓库描述 → 必须 **Read, Write, Delete**（Docker Hub 改描述的
     接口不接受只有 read/write 的 token，会 401）
2. 在本仓库设置：

```bash
gh secret set DOCKERHUB_USERNAME --body "weidows" -R Weidows/x-anylabeling-server-docker
gh secret set DOCKERHUB_TOKEN -R Weidows/x-anylabeling-server-docker   # 粘贴 token 后回车
```

或者网页操作：Settings → Secrets and variables → Actions → New repository secret。

`DOCKERHUB_USERNAME` 必须是 Docker Hub 的账号名，而且要和工作流里
`DOCKERHUB_IMAGE` 的命名空间一致（`weidows/...`）。如果你的 Docker Hub 用户名
不是 `weidows`，三个工作流里的 `DOCKERHUB_IMAGE` 都要改。

**没配 secret 也能用**：工作流会检测凭据，缺失时打一条 warning 然后只推 GHCR，
不会失败。等你配好之后，下一次定时检查会自动把缺的 Docker Hub 标签补上。

### Docker Hub 页面上的描述

Docker Hub 不会从 GitHub 自动同步描述（那是旧的 Automated Builds，现在属于付费
功能），所以默认拉过去的镜像页面是空的。`sync-dockerhub-description.yml` 会在
README 变更时把它推上去：

- **overview** ← 本文件，相对链接会自动补成指向本仓库的绝对链接
- **short description** ← 本仓库在 GitHub 上的 description 字段（上限 100 字节）

两点前提：token 要有 delete 权限（见上），而且 **Docker Hub 上的仓库必须已经
存在** —— 描述接口是 PATCH，仓库不存在会 404。所以顺序是先推一次镜像（或手动
建好仓库），再同步描述。

不想给 token 加 delete 权限的话，直接在 Docker Hub 仓库设置里手动粘贴一次也行，
反正这段内容很少变。

## 构建实现

| 文件 | 作用 |
| --- | --- |
| `Dockerfile` | `base` 和 `all` 两个 target，共用一个 `source` 阶段拉上游代码 |
| `Dockerfile.cuda` | `nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04` + uv 托管的 Python 3.12 |

几个实现上的取舍：

- **`git clone --branch <ref>` 不做兜底**。ref 不存在就让构建失败，否则会把默认
  分支的代码打上版本号标签推出去。
- **torch 用 `uv pip install --torch-backend=cpu|cu126`**，不要改回手写
  `--index-url <pytorch> --extra-index-url <pypi>`：uv 里 `--extra-index-url`
  的优先级**高于** `--index-url`（和 pip 的直觉相反），torch 会从 PyPI 解析成
  自带 CUDA 库的版本。实测那种写法会往 CPU 镜像里塞进整套 CUDA 13 库，
  也让 CUDA 镜像装成 CUDA 13 而不是标签宣称的 cu126。
- **CUDA 版用 uv 托管的独立 CPython 3.12**（venv 在 `/opt/venv`）。Ubuntu 22.04
  自带 3.10，而 sam3 要求 3.12+，这样就不用引入 deadsnakes PPA。
- **editable 安装**。上游按 `<repo_root>/configs/server.yaml` 解析默认配置，源码
  留在 `/app` 才能让 `/app/configs` 成为可挂载覆盖的位置。
- **每个变体推送后都会真起一遍容器等 `/health`**。「构建成功」证明不了服务能跑 ——
  `base` 就曾经构建通过但启动即崩（上游漏了 `packaging`），是这一步抓到的。
- 构建 `all` / `cuda` 前会清理 runner 磁盘，默认空闲盘装不下这两个镜像。
- GitHub Actions 缓存配额是每仓库 10GB，所以只有 `base` 用 `type=gha`；
  `all` / `cuda` 不进缓存，否则会把 `base` 的挤掉甚至让 cache export 失败。

本地构建：

```bash
docker build -f Dockerfile --target base --build-arg UPSTREAM_REF=v0.0.11 -t xals:base .
docker build -f Dockerfile --target all  --build-arg UPSTREAM_REF=v0.0.11 -t xals:all  .
docker build -f Dockerfile.cuda --build-arg UPSTREAM_REF=v0.0.11 -t xals:cuda .
```
