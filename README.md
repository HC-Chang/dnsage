# DNSage — ML 自動學習的 Pi-hole 廣告阻擋系統

以 Docker Compose 部署的全網路廣告阻擋系統，結合 **Pi-hole (DNS sinkhole)** 與 **Donut-Hole (ML 自動分類)**，利用本地 Ollama LLM 自動分析 DNS 查詢、建立阻擋規則，越用越準。

## 系統架構

```
使用者裝置 → DNS 查詢 → Pi-hole (DNS sinkhole)
                            │
                    比對 blocklist → 命中 → 回傳 0.0.0.0 (封鎖)
                            │ 未命中
                            └→ 上游 DNS → 真實 IP
                            │
                    (每 5 分鐘) Donut-Hole
                         ├─ 從 Pi-hole API 拉取新域名
                         ├─ llama3.2 分類 (廣告/追蹤/正常)
                         ├─ all-minilm 向量嵌入比對歷史決定
                         └─ Web UI 審核 → 匯出 blocklist → Pi-hole
```

## 服務一覽

| 容器 | 用途 | 連接埠 |
|---|---|---|
| `pihole` | DNS sinkhole + 廣告封鎖 | `:53` (DNS), `:80` (Web) |
| `donut-hole-postgres` | PostgreSQL + pgvector 向量資料庫 | `127.0.0.1:5432` |
| `donut-hole-backend` | FastAPI 分類引擎 + 排程器 | 內部 `:8343` |
| `donut-hole-frontend` | SvelteKit 審核 UI | `:5174` |
| `ollama` (既存) | LLM 服務 (llama3.2 + all-minilm) | `:11434` |

## 前置需求

- Docker + Docker Compose
- Ollama 服務 (已運作)，需載入以下模型：
  - `llama3.2` — 域名分類
  - `all-minilm:33m` — 向量嵌入 (相似度學習)

## 目錄結構

```
dnsage/
├── docker-compose.yml    # 主 Compose 定義
├── .env                  # 環境變數 (密碼、設定)
├── README.md
└── donut-hole/           # Donut-Hole 原始碼 (git clone)
    ├── backend/          # FastAPI 後端
    ├── frontend/         # SvelteKit 前端
    └── postgres/         # 資料庫初始化腳本
```

## 快速開始

```bash
# 1. 確認 Ollama 模型已就緒
docker exec ollama ollama list | grep -E "llama3.2|all-minilm"

# 2. 啟動全部服務
docker compose up -d

# 3. 檢查健康狀態
docker compose ps

# 4. 將路由器 DHCP DNS 指向本機 IP (e.g. 192.168.1.198)
```

首次啟動時 Pi-hole 會自動下載 StevenBlack 封鎖清單 (~84k 域名) 並執行 gravity 更新。

## 登入資訊

| 服務 | 網址 | 帳號 | 密碼 |
|---|---|---|---|
| Pi-hole Admin | `http://<host-ip>:80/admin/` | — | 見 `.env` `PIHOLE_PASSWORD` |
| Donut-Hole UI | `http://<host-ip>:5174/` | `admin` | 見 `.env` `ADMIN_PASSWORD` |

## ML 學習流程

### 自動化週期

```
[Pi-hole 累積 DNS 查詢]
        ↓ (每 5 分鐘)
[Donut-Hole 拉取日誌]
        ↓
[llama3.2 分類未處理域名]
        ↓ (分類結果)
[all-minilm 產生向量嵌入]
        ↓
[存入 PostgreSQL + pgvector]
        ↓
[Web UI 待審核清單]
        ↓ (使用者 Approve / Reject)
[匯出 hosts 格式 blocklist]
        ↓ (Pi-hole 執行 Update Gravity)
[規則生效，新域名自動被封鎖]
```

### 學習曲線

- **初期**：每個新域名都送 LLM 分類 (~1-2 秒/次)
- **中期**：向量相似度找到已分類域名 → 直接建議，不需 LLM
- **成熟期**：95% 以上域名瞬間比對完成，只需偶爾審核新域名

### 管理指令

```bash
# 查看即時日誌
docker compose logs -f

# 查看特定服務日誌
docker compose logs backend -f

# 手動重啟單一服務
docker compose restart backend

# 全部重啟
docker compose restart

# 停止並清除
docker compose down

# 重建後啟動 (更新代碼後)
docker compose build && docker compose up -d
```

## 設定檔說明

### docker-compose.yml

主要服務定義：
- **pihole**：上游 DNS 設為 Quad9 + Cloudflare (`9.9.9.9;1.1.1.1`)
- **backend**：透過 Ollama 外部網路 (`ollama_ollama-docker`) 連接 LLM
- **frontend**：反向代理到 backend，輸出至 `:5174`
- **pgadmin**：僅在 `--profile debug` 時啟動

### .env

| 變數 | 用途 |
|---|---|
| `PIHOLE_PASSWORD` | Pi-hole Web 密碼 |
| `POSTGRES_PASSWORD` | PostgreSQL 密碼 |
| `JWT_SECRET` | Donut-Hole JWT 簽章金鑰 |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Donut-Hole 登入帳密 |
| `CORS_ORIGINS` | 允許的前端來源 |
| `LLM_PROVIDER_CHAIN` | LLM 提供商順序 (`ollama`) |
| `LLM_MODELS` | 各提供商對應模型 (`{"ollama":"llama3.2"}`) |
| `EMBEDDING_MODEL` | 向量嵌入模型 (`all-minilm:33m`) |

## 常見問題

### DNS 查詢 `@<host-ip>` 超時？

本機無法透過外部 IP 存取 Docker 對應的 DNS 埠（hairpin NAT），但同一區域網路的其他裝置可以正常使用。從本機測試請用 `dig @127.0.0.1`。

### Donut-Hole 後端無法連線到 Pi-hole？

確認 `PIHOLE_URL` 設為 `http://pihole:80`（Docker 內部網路名稱），不要用 IP。

### Ollama 連線失敗？

確認 `ollama_ollama-docker` 外部網路存在：
```bash
docker network ls | grep ollama
```
若 Ollama 非使用 docker-compose，請修改 `docker-compose.yml` 中的 `OLLAMA_BASE_URL` 為實際 IP。

### 如何重置 Pi-hole 密碼？

```bash
docker exec pihole pihole setpassword <新密碼>
```
並同步更新 `.env` 中的 `PIHOLE_PASSWORD`。

## 授權

- Pi-hole: AGPL-3.0
- Donut-Hole: MIT
