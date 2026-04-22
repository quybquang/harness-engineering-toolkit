# Harness Engineering Toolkit — Hướng Dẫn Sử Dụng (Tiếng Việt)

> Bản dịch này tương ứng với tài liệu chính [`docs/USAGE.md`](USAGE.md).

## Mục lục

1. [Harness Engineering là gì?](#1-harness-engineering-là-gì)
2. [Yêu cầu](#2-yêu-cầu)
3. [Cài đặt](#3-cài-đặt)
4. [Bắt đầu nhanh](#4-bắt-đầu-nhanh)
5. [Khái niệm cốt lõi](#5-khái-niệm-cốt-lõi)
   - [Pipeline 5 bước](#pipeline-5-bước)
   - [Tier độ phức tạp](#tier-độ-phức-tạp)
   - [Hai Zone](#hai-zone)
   - [CLAUDE.md là bản đồ](#claudemd-là-bản-đồ)
6. [Tham chiếu lệnh](#6-tham-chiếu-lệnh)
   - [harness init](#harness-init)
   - [harness update](#harness-update)
   - [harness check](#harness-check)
   - [harness eject](#harness-eject)
7. [Tham chiếu cờ (flags)](#7-tham-chiếu-cờ-flags)
8. [Đầu ra được tạo](#8-đầu-ra-được-tạo)
9. [15 mẫu Harness](#9-15-mẫu-harness)
10. [Chấm điểm & phân loại Tier](#10-chấm-điểm--phân-loại-tier)
11. [Git & sử dụng nhóm](#11-git--sử-dụng-nhóm)
12. [Xử lý sự cố](#12-xử-lý-sự-cố)
13. [Câu hỏi thường gặp](#13-câu-hỏi-thường-gặp)

---

## 1. Harness Engineering là gì?

**Harness Engineering** là thực hành thiết kế lớp điều phối xung quanh một tác nhân AI — môi trường kiểm soát tác nhân nhìn thấy gì, có thể làm gì, và làm việc như thế nào.

```
Agent = bộ não
Harness = hệ thần kinh
```

Nếu không có harness, tác nhân chạy "trần trụi":
- Không biết dự án dùng `pnpm` thay vì `npm`
- Không biết lệnh nào nguy hiểm
- Không có trí nhớ giữa các phiên
- Cần re-briefing toàn bộ ngữ cảnh mỗi lần

Harness giải quyết bằng cách **mã hóa kiến thức vào môi trường**, thay vì dựa vào re-injection context-window mỗi phiên.

### Bốn trụ cột

| Trụ cột | Điều khiển gì | Ví dụ |
|---|---|---|
| **Context** | Tác nhân nhìn thấy gì | `CLAUDE.md`, `conventions.md`, `architecture.md` |
| **Permissions** | Tác nhân có thể làm gì | `risk-rules.md`, pre-command hooks |
| **Workflow** | Tác nhân làm việc như thế nào | `workflow.md`, session protocol |
| **Automation** | Hệ thống can thiệp ở đâu | Shell hooks (pre/post tool-use) |

### Nguyên tắc cốt lõi

```
LLM tạo nội dung → Shell script ghi file
```

LLM không bao giờ trực tiếp chạm vào filesystem. Script là người ghi duy nhất — deterministic, an toàn, có thể audit.

---

## 2. Yêu cầu

| Phụ thuộc | Cài đặt | Mục đích |
|---|---|---|
| `jq` | `brew install jq` / `apt install jq` | Xử lý JSON |
| `git` | có sẵn trên hầu hết hệ thống | Phát hiện contributor |
| `sh` (POSIX) | có sẵn | Tất cả script tương thích POSIX |
| Claude Code | [claude.ai/code](https://claude.ai/code) | Các bước cần LLM (generate, validate chất lượng) |

---

## 3. Cài đặt

```bash
# 1. Clone repository
git clone <repo-url> ~/tools/harness-engineering-toolkit
cd ~/tools/harness-engineering-toolkit

# 2. Chạy installer
./install.sh
```

Installer làm hai việc:
1. **Symlink CLI** vào `~/.local/bin/harness`
2. **Cài đặt slash commands** vào `~/.claude/commands/` (nếu Claude Code đã có)

### Thiết lập PATH

Nếu `~/.local/bin` chưa có trong PATH, thêm dòng này vào `~/.zshrc` hoặc `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Sau đó reload:

```bash
source ~/.zshrc
```

### Kiểm tra cài đặt

```bash
harness version
# → harness-toolkit v0.1.0
```

### Gỡ cài đặt

```bash
./uninstall.sh
```

---

## 4. Bắt đầu nhanh

```bash
# Vào một dự án bất kỳ
cd ~/my-project

# Xem trước nội dung sẽ tạo (an toàn — không ghi file)
harness init --dry-run

# Khởi tạo harness
harness init

# Kiểm tra sức khỏe
harness check

# Sau khi dự án thay đổi
harness update

# Tự quản lý toàn bộ (từ bỏ toolkit)
harness eject
```

### Trong Claude Code

Sau khi cài đặt, các slash command có sẵn trong mọi phiên Claude Code:

```
/harness-init      Khởi tạo với hỗ trợ LLM
/harness-update    Cập nhật với hỗ trợ LLM
/harness-check     Kiểm tra sức khỏe harness
/harness-eject     Từ bỏ quản lý toolkit
```

---

## 5. Khái niệm cốt lõi

### Pipeline 5 bước

Mỗi `harness init` chạy pipeline 5 bước:

```
[1] Discover → [2] Classify → [3] Generate → [4] Write → [5] Validate
  (script)       (script)       (LLM)         (script)    (script+LLM)
```

| Bước | Người thực thi | Đầu vào | Đầu ra |
|---|---|---|---|
| **Discover** | Shell script | Quét filesystem + Q&A tùy chọn | `project-context.json` |
| **Classify** | Shell (scoring) | `project-context.json` | Tier + pattern list → `config.json` |
| **Generate** | LLM (Claude) | Context + prompt templates | `conventions.md`, `risk-rules.md`, hooks, v.v. |
| **Write** | Shell script | Nội dung đã tạo | File trong `.claude/harness/` + `CLAUDE.md` |
| **Validate** | Shell + LLM | Trạng thái harness hiện tại | Pass / warn / fail |

### Tier độ phức tạp

Bước classify gán **tier** dựa trên tín hiệu phát hiện được (chấm điểm):

| Tier | Điểm | Kích hoạt | Số pattern | Nội dung tạo ra |
|---|---|---|---|---|
| `minimal` | 0–2 | Mọi dự án | 4 | CLAUDE.md + conventions + risk-rules + hooks |
| `standard` | 3–5 | Docker, CI/CD, database | 8 | + workflow + Zone B state |
| `full` | 6–12 | AI agents, MCP, multi-service | 12 | + architecture + evaluator quality loop |
| `enterprise` | 13+ | Nhóm lớn (5+), monorepo | 15 | + dream consolidation + fork-join templates |

**Tín hiệu chấm điểm:**

| Tín hiệu | Điểm |
|---|---|
| Containerized (Docker) | +2 |
| CI/CD phát hiện | +2 |
| Database phát hiện | +1 |
| AI agents | +3 |
| MCP integration | +2 |
| AI SDK dependency | +1 |
| Monorepo (Turbo/Lerna/Nx) | +3 |
| Multi-service (>2) | +2 |
| Nhóm 2–5 | +2 |
| Nhóm 5+ | +4 |
| Codebase lớn (>500 files) | +1 |

Ghi đè tier thủ công:

```bash
harness init --tier=full
```

### Hai Zone

Thư mục `.claude/harness/` được tạo ra có hai zone với quyền sở hữu khác nhau:

```
.claude/harness/
├── rules/          ← Zone A: Toolkit quản lý. Ghi đè khi update.
├── hooks/          ← Zone A: Toolkit quản lý. Ghi đè khi update.
├── config.json     ← Zone A: Toolkit quản lý.
├── state/          ← Zone B: Agent quản lý. Tạo một lần, KHÔNG bao giờ ghi đè.
│   ├── progress.md
│   ├── learnings.md
│   └── plans/
└── backup/         ← Auto-backups (giữ 5 bản cuối)
```

**Zone A** — Toolkit quản lý. Cập nhật mỗi `harness update`. Không sửa thủ công (sẽ bị ghi đè).

**Zone B** — Tác nhân AI quản lý. Toolkit tạo từ template lần đầu init và không bao giờ chạm lại. Tác nhân đọc và ghi `progress.md`, `learnings.md`, và các file plan xuyên suốt phiên.

### CLAUDE.md là bản đồ

`CLAUDE.md` là **bản đồ** (~20 dòng), không phải manual. Nó vừa với L1 context và trỏ đến các file chi tiết.

```markdown
<!-- HARNESS:START v2 — Auto-generated by harness-toolkit v0.1.0. Do not edit. -->

# Harness · my-project · standard tier

TypeScript · Next.js 15 · pnpm · Vitest · Vercel

## Rules
- Read `.claude/harness/rules/conventions.md` before writing code
- Read `.claude/harness/rules/risk-rules.md` before running commands
- Follow session protocol in `.claude/harness/rules/workflow.md`

## State
- `.claude/harness/state/progress.md` — read at start, update at end
- `.claude/harness/state/plans/` — active work plans

## Critical
- Use `pnpm`, never `npm` or `yarn`
- Run `pnpm check` before committing

<!-- HARNESS:END v2 -->
```

Nội dung **bên ngoài** các marker là do người dùng sở hữu và không bao giờ bị chạm.

---

## 6. Tham chiếu lệnh

### harness init

Pipeline đầy đủ cho dự án mới: `discover → classify → generate → write → validate`

```bash
harness init [flags]
```

**Hành vi:**
- Thoát lỗi nếu đã được khởi tạo (dùng `--force` để ghi đè)
- Hỏi 2–3 câu chỉ khi tín hiệu mơ hồ
- Dùng `--skip-questions` để bỏ qua tất cả prompt

---

### harness update

Khám phá lại dự án, phát hiện thay đổi, và tái tạo chọn lọc nội dung cũ.

```bash
harness update [flags]
```

**Hành vi:**
- Thoát lỗi nếu chưa khởi tạo
- So sánh trạng thái hiện tại với context hash đã lưu
- Chỉ tái tạo phần đã thay đổi (trừ khi `--force`)
- **Không bao giờ ghi đè file Zone B** (`state/`)
- Tạo backup trước mọi thao tác ghi

**Khi nào chạy:**
- Sau khi thêm dependency hoặc service mới
- Sau khi đổi package manager, framework, hoặc deployment target
- Sau khi nhóm lớn hơn vượt ngưỡng tier

---

### harness check

Xác thực harness hiện tại mà không sửa đổi gì. An toàn chạy bất cứ lúc nào.

```bash
harness check [--fix] [--verbose]
```

**Bốn cấp độ validation:**

| Cấp độ | Tier | Kiểm tra |
|---|---|---|
| Structure | All | File tồn tại, marker hợp lệ, hooks executable, settings.json đã đăng ký |
| Consistency | All | Context hash, thời gian sửa đổi file so với thời gian discovery |
| Freshness | Standard+ | Tuổi `progress.md`, plan mồ côi (in-progress >14 ngày) |
| Quality | Full+ | LLM đánh giá file rules về tính cụ thể, khả thi, ngắn gọn |

**Mã thoát:**
- `0` — mọi thứ ổn (hoặc chỉ warning)
- `1` — phát hiện lỗi

**Auto-fix** (`--fix`) sửa:
- Hook script không executable (`chmod +x`)
- File Zone B thiếu (tạo lại từ template)

---

### harness eject

Xóa quản lý toolkit. Giao quyền sở hữu toàn bộ cho người dùng.

```bash
harness eject [--dry-run]
```

**Eject làm gì:**
- Xóa marker `<!-- HARNESS:START v2 -->` / `<!-- HARNESS:END v2 -->` khỏi `CLAUDE.md` (nội dung giữ lại)
- Xóa hook `[harness]` khỏi `.claude/settings.json`
- Xóa metadata toolkit: `config.json`, `project-context.json`, `backup/`

**Eject giữ lại gì:**
- Toàn bộ nội dung `CLAUDE.md`
- `.claude/harness/rules/` — file rule của bạn
- `.claude/harness/hooks/` — hook script của bạn
- `.claude/harness/state/` — file trạng thái agent của bạn

Sau khi eject, bạn sở hữu toàn bộ file. Sửa thoải mái. Để khởi tạo lại: `harness init --force`.

---

## 7. Tham chiếu cờ (flags)

| Cờ | Lệnh | Mô tả |
|---|---|---|
| `--dry-run` | tất cả | Xem trước thay đổi, không ghi file |
| `--force` | init, update | Bỏ qua kiểm tra conflict, tái tạo toàn bộ |
| `--verbose` | tất cả | Log chi tiết |
| `--fix` | check | Tự sửa vấn đề có thể giải quyết |
| `--json` | tất cả | Output dạng machine-readable |
| `--skip-questions` | init, update | Dùng mặc định cho câu hỏi discovery |
| `--tier=<tier>` | init | Ghi đè tier: `minimal` / `standard` / `full` / `enterprise` |

---

## 8. Đầu ra được tạo

Sau `harness init`, cấu trúc sau được tạo trong dự án:

```
project-root/
├── CLAUDE.md                           ← Bản đồ (~20 dòng, v2 markers)
├── .harnessignore                      ← Pattern loại trừ quét
└── .claude/
    ├── settings.json                   ← Đăng ký hook
    └── harness/
        ├── project-context.json        ← Kết quả discovery
        ├── config.json                 ← Tier, patterns, version hashes
        ├── rules/                      ← Zone A
        │   ├── conventions.md          ← Quy ước coding dự án
        │   ├── risk-rules.md           ← Quy tắc phân loại rủi ro lệnh
        │   ├── workflow.md             ← Session protocol (standard+)
        │   └── architecture.md         ← Quyết định kiến trúc (full+)
        ├── hooks/                      ← Zone A
        │   ├── pre-command.sh          ← Phân loại rủi ro (auto-parsed từ risk-rules.md)
        │   └── post-edit.sh            ← Auto-formatter (nếu phát hiện formatter)
        ├── state/                      ← Zone B
        │   ├── progress.md             ← Liên tục phiên
        │   ├── learnings.md            ← Gotcha đã phát hiện
        │   └── plans/
        │       ├── _template-feature.md
        │       └── _template-bugfix.md
        └── backup/                     ← 5 bản backup tự động cuối
```

### Nên commit gì

```gitignore
# .gitignore — thêm những dòng này:
.claude/harness/backup/

# Commit mọi thứ còn lại:
# CLAUDE.md
# .claude/harness/rules/
# .claude/harness/hooks/
# .claude/harness/config.json
# .claude/harness/state/   (tùy chọn — tùy team preference)
```

---

## 9. 15 mẫu Harness

Các pattern tích lũy — mỗi tier bao gồm toàn bộ pattern từ tier thấp hơn.

### Nhóm 1: Bộ nhớ & Ngữ cảnh

| # | Pattern | Tier | Vấn đề giải quyết |
|---|---|---|---|
| 1 | **Persistent Instruction File** | Minimal | Agent quên conventions mỗi phiên |
| 2 | **Scoped Context Assembly** | Standard | Xung đột rule giữa các module |
| 3 | **Tiered Memory** (L1/L2/L3) | Full | Context window tràn |
| 4 | **Dream Consolidation** | Enterprise | Bộ nhớ phình to theo thời gian |
| 5 | **Progressive Context Compaction** | Full | Cuộc hội thoại dài mất context |
| 6 | **Living State** | Standard | Không liên tục giữa các phiên |

### Nhóm 2: Workflow & Điều phối

| # | Pattern | Tier | Vấn đề giải quyết |
|---|---|---|---|
| 7 | **Explore-Plan-Act Loop** | Standard | Agent sửa trước khi hiểu |
| 8 | **Context-Isolated Subagents** | Full | Ô nhiễm context giữa các agent |
| 9 | **Fork-Join Parallelism** | Enterprise | Bottleneck thực thi tuần tự |
| 10 | **Session Protocol** | Standard | Phiên không có cấu trúc bị drift |

### Nhóm 3: Công cụ & Quyền hạn

| # | Pattern | Tier | Vấn đề giải quyết |
|---|---|---|---|
| 11 | **Progressive Tool Expansion** | Enterprise | Quá nhiều công cụ làm mô hình bối rối |
| 12 | **Command Risk Classification** | Minimal | Lệnh phá hoại không được kiểm soát |
| 13 | **Single-Purpose Tool Design** | Minimal | Shell chung quá rộng để validate |

### Nhóm 4: Tự động hóa

| # | Pattern | Tier | Vấn đề giải quyết |
|---|---|---|---|
| 14 | **Deterministic Lifecycle Hooks** | Minimal | Agent quên các bước thủ tục |
| 15 | **Generator-Evaluator Loop** | Full | Nội dung tạo ra quá chung chung hoặc dài dòng |

---

## 10. Chấm điểm & phân loại Tier

Bước classify dùng hệ thống **chấm điểm** — không cần LLM cho trường hợp cơ bản.

```
điểm 0-2   → minimal
điểm 3-5   → standard
điểm 6-12  → full
điểm 13+   → enterprise
```

Nếu phát hiện tín hiệu xung đột (ví dụ: thư mục agents nhưng không có AI SDK), toolkit log warning và tiếp tục với rule-based classification. Chạy trong Claude Code cho phép LLM-assisted conflict resolution.

**Ghi đè khi điểm sai:**

```bash
# Dự án có agents nhưng chỉ được standard:
harness init --tier=full
```

---

## 11. Git & sử dụng nhóm

### `.gitignore` khuyến nghị

```gitignore
.claude/harness/backup/
```

### Mỗi thành viên nhóm cần gì

- Toolkit cài đặt local (`./install.sh`)
- `jq` đã cài
- Claude Code (cho các bước LLM)

### Thiết lập lần đầu trên dự án đã có harness

```bash
# Dự án đã có .claude/harness/ được check in
harness check      # validate những gì có
harness update     # tái tạo nếu cũ
```

### Chia sẻ harness trong nhóm

Commit `rules/`, `hooks/`, `config.json`, và `CLAUDE.md`. Tùy chọn commit `state/` (hữu ích cho shared context; bỏ qua nếu team thích trạng thái agent cá nhân).

---

## 12. Xử lý sự cố

### `harness: command not found`

```bash
# Kiểm tra symlink
ls -la ~/.local/bin/harness

# Kiểm tra PATH
echo $PATH | tr ':' '\n' | grep local

# Fix: thêm vào ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
source ~/.zshrc
```

### `jq is required but not installed`

```bash
# macOS
brew install jq

# Ubuntu/Debian
apt install jq

# Alpine
apk add jq
```

### `Harness already initialized`

```bash
# Tùy chọn 1: Cập nhật harness hiện tại
harness update

# Tùy chọn 2: Khởi tạo lại toàn bộ (giữ Zone B)
harness init --force
```

### `Harness not initialized`

```bash
harness init
```

### Hook không executable

```bash
harness check --fix
```

### CLAUDE.md marker bị hỏng

```bash
# Eject để xóa marker, sau đó khởi tạo lại
harness eject
harness init --force
```

### Generation failed (LLM error)

Đảm bảo bạn đang chạy trong phiên Claude Code (không phải bare shell) cho bước generate. Hoặc chạy `harness init --tier=minimal` — minimal tier không dùng LLM.

---

## 13. Câu hỏi thường gặp

**Q: Toolkit có hoạt động không có Claude Code không?**  
A: Các bước discover, classify, write, và structure-validate hoạt động không cần Claude Code. Chỉ bước generate (tạo nội dung) và quality validate cần LLM access.

**Q: Tôi có thể sửa file rule thủ công không?**  
A: File Zone A (`rules/`, `hooks/`) sẽ bị ghi đè khi `harness update`. Sửa chúng sau khi chạy `harness eject`, hoặc dùng `harness update --force` để trigger regeneration với context hiện tại.

**Q: CLAUDE.md hiện tại của tôi sẽ thế nào?**  
A: Toolkit chỉ sửa nội dung giữa marker `<!-- HARNESS:START v2 -->` và `<!-- HARNESS:END v2 -->`. Mọi thứ bên ngoài không bị chạm.

**Q: `.harnessignore` là gì?**  
A: Tương tự `.gitignore` — pattern liệt kê đây được loại trừ khỏi quét filesystem trong quá trình discovery. Hữu ích cho thư mục generated lớn. Mặc định loại trừ: `node_modules`, `.git`, `dist`, `build`, `.next`, `__pycache__`, `vendor`, `target`.

**Q: Tôi có thể dùng với tác nhân AI không phải Claude không?**  
A: Toolkit tạo file Markdown tiêu chuẩn. Mọi tác nhân đọc `CLAUDE.md` (hoặc tương đương) đều có thể dùng output. Hook script là shell script — chúng hoạt động với mọi tool hỗ trợ pre-command hooks.

**Q: Làm sao thêm pattern tùy chỉnh?**  
A: Sau khi eject, bạn sở hữu toàn bộ file. Thêm section tùy chỉnh vào `conventions.md`, mở rộng `risk-rules.md`, hoặc tạo file bổ sung. Tham chiếu chúng trong `CLAUDE.md`.
