# DevDock — Implementation Plan

> Menu bar app cá nhân, chỉ chạy trên máy mình. Làm **từng module một**, mỗi module chạy được và dùng được trước khi sang module tiếp theo.

## Quyết định đã chốt

| Vấn đề | Quyết định |
|---|---|
| Đối tượng | Bắt đầu cho cá nhân; từ 2026-10-12 chia sẻ được cho người khác (cài từ source bằng `./install.sh`) |
| Phân phối | Build từ source (`./install.sh` → `~/Applications`), không notarize, không App Store, không auto-update |
| Sandbox | Tắt (cần `kill`, đọc `~/.claude`, `~/.codex`, gọi CLI) |
| Dashboard riêng | Không, chỉ popup menu bar |
| Quản lý `.env` / API keys | Bỏ |
| Sync nhiều máy | Không |
| Target | **macOS 15+** (Liquid Glass chỉ bật trên macOS 26), build bằng Xcode 26 / Swift 6.2, SwiftUI + AppKit, `@Observable` |
| Project file | **XcodeGen** (`project.yml`), không commit `.xcodeproj` → structure gọn, không conflict pbxproj |
| Vị trí hiển thị | Icon trên **menu bar** (thanh trên cùng màn hình), bấm vào xổ panel xuống ngay dưới icon |

## UI & Design

### Vibe mục tiêu (tham chiếu CodexBar)
- Panel **kính mờ trong suốt**: màu wallpaper xuyên qua, ám tím/xanh nhạt như menu hệ thống macOS 26
- Góc bo lớn (~16pt), viền sáng mảnh, shadow mềm
- Chữ **SF Pro** hệ thống: title đậm, text phụ màu `secondary` xám
- Tab provider/module: icon + label nhỏ, tab active là **pill màu accent xanh** chữ trắng, dưới mỗi tab có mini progress bar
- Progress bar mảnh (~6pt), track xám mờ, fill theo màu thương hiệu (Claude cam đất `#C46A4A`, Codex xanh ngọc, …)
- Divider mảnh chia section, khoảng trắng thoáng
- Cuối panel là các dòng kiểu menu: `Settings…`, `Quit`, highlight khi hover giống menu item thật

### Cách làm kính mờ
- `NSPanel` borderless, non-activating, đặt ngay dưới `NSStatusItem` (thay cho `NSPopover`: không có mũi tên, giống menu thật, vẫn tương tác được với search field và nút)
- Nền dùng **Liquid Glass** của macOS 26 (`.glassEffect()` / `GlassEffectContainer`), fallback `NSVisualEffectView(material: .menu, state: .active)` nếu glass nhìn không ổn
- Đóng panel khi click ra ngoài / nhấn Esc

### Thư viện UI
Hệ SwiftUI **không có thư viện component kiểu shadcn** đủ tốt cho macOS. Thêm thư viện component bên ngoài sẽ phá vibe native, nên chọn cách:
- **Tự dựng design system nhỏ** trong `DesignSystem/` (tokens + ~8 component), dựa hoàn toàn trên SwiftUI native + Liquid Glass. Đây là chỗ quyết định độ đẹp.
- Dùng thư viện cho **phần hạ tầng** (chất lượng cao, phổ biến, của sindresorhus):

| Package | Dùng cho |
|---|---|
| [`Defaults`](https://github.com/sindresorhus/Defaults) | Lưu settings type-safe, observe thay đổi |
| [`LaunchAtLogin-Modern`](https://github.com/sindresorhus/LaunchAtLogin-Modern) | Toggle khởi động cùng máy |
| [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) | Phím tắt toàn cục mở panel (vd ⌥⌘D) |
| [`Settings`](https://github.com/sindresorhus/Settings) *(M4)* | Cửa sổ Settings kiểu native |

- Icon: **SF Symbols** cho module; logo provider (Claude, Codex) dùng SVG/PDF đơn sắc trong Asset Catalog.

### Component trong `DesignSystem/`
| Component | Mô tả |
|---|---|
| `Tokens` | Màu (accent, brand provider, success/warn/danger), spacing (4/8/12/16), radius, font scale |
| `GlassPanel` | Container nền kính, bo góc, viền, shadow |
| `TabPill` | Tab icon + label + mini progress, trạng thái active/hover |
| `UsageBar` | Progress bar mảnh, màu theo ngưỡng/brand, animate khi đổi giá trị |
| `SectionHeader` | Title + subtitle + accessory bên phải ("Updated just now · Max") |
| `MenuRow` | Dòng giống menu item: icon, label, hover highlight, chevron tùy chọn |
| `ListRow` | Dòng dữ liệu (port, process) với trailing actions hiện khi hover |
| `StatusBadge` | Badge nhỏ: nguồn dữ liệu, trạng thái, conflict |
| `SearchField` | Ô search gọn, nền glass |
| `EmptyState` / `ErrorState` | Trạng thái rỗng/lỗi thống nhất |

Mọi view trong `Features/` **chỉ** dùng component và token từ `DesignSystem/`, không hard-code màu/spacing → giao diện đồng nhất, đổi vibe chỉ cần sửa một chỗ.

## Kiến trúc thư mục

```
devdock/
├── project.yml                 # XcodeGen
├── PLAN.md
└── DevDock/
    ├── App/
    │   ├── DevDockApp.swift        # @main, AppDelegate adaptor
    │   ├── StatusItemController.swift  # icon menu bar, click → toggle panel
    │   ├── PanelController.swift   # NSPanel kính mờ, định vị, đóng khi click ngoài
    │   └── RootView.swift          # Header tabs + nội dung module + footer menu
    ├── DesignSystem/
    │   ├── Tokens.swift
    │   └── Components/             # GlassPanel, TabPill, UsageBar, MenuRow, ...
    ├── Core/
    │   ├── Shell/ShellRunner.swift # async Process, login-shell PATH
    │   ├── Refresh/RefreshScheduler.swift
    │   ├── Settings/AppSettings.swift  # Defaults keys
    │   ├── Module/AppModule.swift  # danh sách module cho header
    │   └── Formatting/          # RelativeTime ("Resets in 3h 53m")
    ├── Features/
    │   ├── Ports/       { Models, Services, Views }
    │   ├── AIUsage/     { UsageProvider.swift, Providers/ClaudeCode, Providers/Codex, Views }
    │   └── Settings/    { Views }
    └── Resources/       # Assets.xcassets (logo provider, app icon), Info.plist
```

Nguyên tắc:
- Mỗi feature là một folder độc lập, chia `Models / Services / Views`. Feature chỉ phụ thuộc `Core/` và `DesignSystem/`, **không import lẫn nhau**.
- Header đọc module từ `AppModule` → thêm module mới chỉ cần đăng ký, không sửa module cũ.
- Service là `actor`/class thuần, không dính SwiftUI → dễ test.

---

## Phase 1 — MVP

### M0 · Foundation (khung app)
**Mục tiêu:** Có icon trên menu bar, bấm vào xổ panel kính mờ với header 3 tab và footer menu. Dữ liệu là mock, nhưng **nhìn đã đúng vibe**.

- `brew install xcodegen`, tạo `project.yml`, thêm SPM packages (`Defaults`, `LaunchAtLogin-Modern`, `KeyboardShortcuts`)
- `LSUIElement = YES` (không hiện Dock icon), tắt App Sandbox
- `StatusItemController` + `PanelController` (NSPanel kính mờ, xem mục UI & Design)
- `DesignSystem/`: Tokens + `GlassPanel`, `TabPill`, `UsageBar`, `SectionHeader`, `MenuRow`
- `RootView`: header tab Ports / AI / Settings, nội dung mock, footer `Settings…` / `Quit`
- Phím tắt toàn cục mở/đóng panel
- `ShellRunner`: chạy command async, có timeout, lấy `PATH` từ login shell (`zsh -lc 'echo $PATH'`) rồi cache lại
- `RefreshScheduler`: refresh theo interval, refresh ngay khi mở panel, dừng khi panel đóng (tiết kiệm CPU)
- Dark/Light mode theo hệ thống

**Done khi:** App chạy; panel xổ ngay dưới icon, nền kính thấy wallpaper xuyên qua giống ảnh tham chiếu; chuyển tab mượt; click ra ngoài hoặc Esc thì đóng. **Dừng lại để bạn duyệt giao diện** trước khi sang M1.

### M1 · Local Ports
**Mục tiêu:** Thay hẳn được `lsof -i :3000` + `kill`.

- Quét TCP LISTEN ports bằng `libproc` (`proc_listallpids` → `proc_pidfdinfo` socket). Fallback dùng `lsof -nP -iTCP -sTCP:LISTEN` nếu cần
- Mỗi dòng: port, PID, process name, command line rút gọn
- `ProjectResolver`: lấy cwd của process (`PROC_PIDVNODEPATHINFO`), đi ngược lên tìm `package.json` / `.git` / `go.mod` / `Cargo.toml` / `pyproject.toml` → tên project và path
- Git branch của project (đọc thẳng `.git/HEAD`, không cần gọi git)
- Actions: mở `http://localhost:PORT`, copy URL/port/PID, mở folder trong Finder/VS Code, **Kill (có confirm)**
- Chỉ cho kill process thuộc user hiện tại; process của system/root thì ẩn nút kill
- Search theo port/process/project
- Context tabs: All / By Project
- Đánh dấu conflict (nhiều process cùng port, khác interface)

**Done khi:** Chạy 2–3 dev server, nhìn popup là biết port nào của project nào, kill được trong 2 click.

**Đã làm (2026-10-12):**
- Quét bằng `lsof` + `ps` (~50ms, chỉ chạy khi panel mở), chưa cần `libproc`
- Phân nhóm Projects / Services (Homebrew) / Apps & system (ẩn mặc định, có nút Show)
- Monorepo: tên repo + package con (`my-app › apps/web`), branch, framework (Next.js, Vite, Uvicorn …)
- Badge `LAN` khi port mở ra mạng nội bộ
- Bấm vào dòng → màn chi tiết: URL, project, folder, branch, process/PID, thời gian chạy, RAM/CPU, địa chỉ bind, command (bấm để copy); nút Open / VS Code / Terminal / Finder; Stop (SIGTERM) và Force (SIGKILL) có xác nhận ngay trong panel
- Chưa làm: đánh dấu conflict nhiều process cùng port; chọn IDE/Terminal ưa dùng (M4)

### M2 · AI Usage — Core + Claude Code (nhiều account)
**Mục tiêu:** Nhìn một chỗ là biết cả 3 account Claude Code còn bao nhiêu quota, không cần chạy `/usage` trong từng account.

**Hiện trạng trên máy (đã khảo sát 2026-10-12):** mỗi account là một `CLAUDE_CONFIG_DIR` riêng, gọi qua alias trong `~/.zshrc`.

| Account | Config dir | Xác thực | Credential |
|---|---|---|---|
| personal | `~/.claude-personal` | OAuth subscription | Keychain `Claude Code-credentials-<hash>` |
| side | `~/.claude-side` | OAuth subscription | Keychain `Claude Code-credentials-<hash>` |
| work | `~/.claude-work` | Gateway công ty (`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` trong `settings.json`) | Không dùng Keychain |
| *(mặc định)* | `~/.claude` | OAuth, **cùng email với personal** | Keychain `Claude Code-credentials` |

Hậu tố Keychain = 8 ký tự hex đầu của `sha256(đường dẫn config dir)`. Riêng `~/.claude` không có hậu tố.

- **Model:** `AIAccount { id (config dir), provider, name, auth: .subscription | .gateway(host) }`; `UsageSnapshot` gắn với account, không gắn với provider
- **`ClaudeAccountDiscovery`:** quét `~/.claude*/` có `settings.json` hoặc `.claude.json`, bỏ `~/.claude-mem` (không phải account)
  - Tên account lấy từ hậu tố thư mục (`.claude-personal` → `personal`)
  - Đọc `oauthAccount.emailAddress` trong `.claude.json` để **gộp account trùng email** (`~/.claude` trùng `personal` thì chỉ hiện một)
  - Có `env.ANTHROPIC_BASE_URL` trong `settings.json` thì xếp vào loại `.gateway`
- **Account subscription:** đọc token OAuth từ Keychain theo đúng tên mục, gọi endpoint usage (session/weekly %, reset time)
  - Token lấy qua `security find-generic-password -s <service> -w`. Lần đầu macOS sẽ hỏi quyền cho từng mục, bấm *Always Allow* là xong
  - **Không bao giờ** ghi token ra log hay lưu lại; chỉ giữ trong bộ nhớ
  - Token hết hạn hoặc endpoint lỗi → báo "Cần mở `claude-<name>` để đăng nhập lại", không tự refresh token (tránh làm hỏng phiên của Claude Code)
- **Account gateway (work):** không có quota → đếm token từ log local `~/.claude-work/projects/**/*.jsonl` (Hôm nay / 7 ngày), badge `Local logs`, ghi chú "Via <host> · no quota limit"
  - Nếu khảo sát ra gateway có API usage riêng thì thêm sau, không chặn M2
- **Fetch độc lập:** mỗi account chạy riêng (`TaskGroup`); account này lỗi không ảnh hưởng account khác
- **UI** (đã có mock ở M0): hàng pill theo account (`personal` / `side` / `work` / `Codex`) với mini bar theo mức dùng cao nhất; account gateway không có bar
  - Chi tiết: tiêu đề `Claude · personal`, plan, session/weekly, countdown reset, "Updated X ago", badge nguồn
- Lỗi/không có dữ liệu → trạng thái rõ ràng, không bịa số

**Done khi:** Số % của personal và side khớp với `/usage` khi chạy `claude-personal` / `claude-side`; work hiện số token hợp lý; tắt mạng hoặc hỏng một account thì các account còn lại vẫn hiển thị đúng.

> Bước đầu của M2: spike endpoint usage với token của một account (personal), xác nhận format response, rồi mới code đầy đủ.

### M3 · AI Usage — Codex
- Codex provider: đọc rate limit từ session log trong `~/.codex/sessions/` (hoặc nguồn tốt hơn nếu khảo sát ra)
- Codex là một `AIAccount` nữa trong cùng hàng pill (hiện tại có 1 account; nếu sau này có nhiều thì dùng lại cơ chế của Claude, theo `CODEX_HOME`)
- Icon menu bar đổi màu khi có provider vượt ngưỡng (vd ≥ 80%)

**Done khi:** Codex hiển thị đúng cạnh 3 account Claude; account nào lỗi cũng không ảnh hưởng account khác.

### M4 · Settings cơ bản
- Refresh interval (Ports / AI riêng)
- Launch at login (`SMAppService.mainApp`)
- Danh sách account AI: đổi tên hiển thị, ẩn/hiện, sắp xếp thứ tự, thêm config dir thủ công nếu không nằm dưới `~/.claude*`
- IDE ưa dùng (VS Code / Cursor / …), Terminal ưa dùng (Terminal / iTerm / Ghostty / …)
- Ngưỡng cảnh báo quota

**Done khi:** Đổi setting có hiệu lực ngay, giữ nguyên sau khi restart app.

---

## Phase 2 — làm sau, mỗi mục là một module riêng

| Module | Nội dung chính |
|---|---|
| M5 · Projects | Auto-detect project từ thư mục gốc cấu hình sẵn, pinned/recent, mở VS Code/Terminal, chạy npm/pnpm script |
| M6 · Git | Branch, số file thay đổi, mở GitHub repo/PR (gắn vào Project) |
| M7 · Docker & Services | `docker ps`, start/stop/restart, logs; `brew services` |
| M8 · Workspace | Nhóm nhiều project, start/stop FE+BE cùng lúc |
| M9 · Notifications | Thông báo khi quota gần hết, khi port bị chiếm |

## Phase 3 — chỉ làm nếu thật sự cần
Resource monitor, orphan process detection, quick actions (flush DNS, clear cache), thêm provider Cursor/Gemini/Copilot.

---

## Cách làm từng module
1. Khảo sát/spike trước nếu có rủi ro kỹ thuật (đặc biệt M2, M3)
2. Code model + service, test bằng unit test hoặc chạy thử
3. Làm UI
4. Dùng thật vài ngày, sửa xong mới sang module tiếp theo

## Tiến độ
- [x] M0 Foundation (chờ duyệt UI)
- [x] M1 Local Ports (chờ duyệt: danh sách theo project + màn chi tiết)
- [x] M2 AI Usage — Claude Code (3 account) — chờ duyệt
  - personal: số thật từ API (Session/Weekly, reset, gói, tỷ lệ Claude Code/Cowork/Chats trong tuần)
  - side: token hết hạn → nhắc chạy `claude-side`; có cache lần đọc tốt gần nhất (`~/Library/Application Support/DevDock/usage-cache.json`)
  - work: đếm token từ log local (lọc trùng theo message id)
  - Gọi API tối đa 1 lần/phút/account; `~/.claude` trùng email với personal nên được gộp
- [x] M3 AI Usage — Codex — chờ duyệt
  - Nguồn chính: API live `chatgpt.com/backend-api/wham/usage` với token trong `~/.codex/auth.json` (không tự refresh)
  - Dự phòng: event `rate_limits` mới nhất (limit_id `codex`) trong `~/.codex/sessions/**/*.jsonl`; window đã qua giờ reset thì tính 0%
  - Chỉ có 1 account Codex (`~/.codex`); `~/.codex_cursor` là file, không phải account
  - Menu bar: logo + mỗi account một chữ cái và 2 thanh mảnh (Session/Weekly), đơn sắc, chỉ thanh vượt ngưỡng mới cam/đỏ; hoặc kiểu số % / chỉ icon; chọn account hiển thị trong Settings; rê chuột xem chi tiết
- [x] Launch at login (`SMAppService`): `make install` chép app vào `~/Applications`, lần chạy đầu tự bật; tắt trong Settings
- [x] Dự đoán tốc độ dùng: lưu mẫu usage 8 ngày (`usage-history.json`), tính tốc độ 2h (Session) / 24h (Weekly) → "runs out ~12:40, 20m before reset" hoặc "~85% by reset"
- [x] Unit test (Swift Testing, `make test`): pace, nhãn menu bar
- [x] Logo: khay dock + 3 cột (vẽ bằng vector trong `BrandMark`), dùng cho cả menu bar và app icon (`DevDock --render-icon <dir>` để sinh lại PNG)
- [x] Thông báo quota (kéo M9 lên sớm): báo 1 lần khi vượt ngưỡng / chạm 100% mỗi chu kỳ; hẹn giờ báo "đã reset" đúng lúc reset
  - Usage AI cập nhật ngầm cả khi panel đóng, theo setting "Update AI usage every" (không thêm request)
  - Settings: ngưỡng cảnh báo 70/80/90%, bật/tắt thông báo
- [ ] M4 Settings
