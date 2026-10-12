# DevDock

> Made by [**npmh0310**](https://github.com/npmh0310)

A small macOS menu bar app for developers. One click shows:

- **Local ports**: every dev server and database listening on your Mac, which project it belongs to (repo, package, branch, framework), and a two-click stop.
- **AI usage**: session and weekly quota for each Claude Code account and Codex, when it resets, and where it is heading at your current pace. It notifies you when a quota runs low or comes back.

The menu bar shows a small ring per AI account (inner ring: session, outer ring: weekly). It turns orange past your warning threshold and red when the quota is used up.

## Requirements

- macOS 15 or newer
- Xcode 26 or newer (the full app from the App Store, not only the Command Line Tools); it needs macOS 15.6+
- [Homebrew](https://brew.sh), used to install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have it

## Install

```sh
git clone https://github.com/npmh0310/devdock.git
cd devdock
./install.sh
```

The script checks the requirements, builds DevDock from source and installs it to `~/Applications/DevDock.app`. It starts at login from then on (turn that off in **Settings**).

The first launch asks for permission to send notifications; allow it for quota alerts.

**Update:** `git pull && make install`
**Uninstall:** `make uninstall`

## Using it

| | |
|---|---|
| Open the panel | Click the menu bar item, or press **⌃⌥D** (change it in Settings) |
| Port details | Click a row: URL, project folder, branch, process, memory, command line |
| Stop a server | Hover a row, click ⏹, then **Stop?** |
| Refresh now | ↻ in the panel header |
| Menu bar style | Settings › *Menu bar shows*: usage rings, percent, or icon only |

Can't see the menu bar item? On a MacBook with a notch, a full menu bar hides items behind it. Hold ⌘ and drag other icons away, or use ⌃⌥D.

## AI accounts

DevDock finds accounts on its own:

- **Claude Code**: every config directory `~/.claude` and `~/.claude-*`. To run several accounts side by side, give each its own directory:

  ```sh
  # ~/.zshrc
  alias claude-work='CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude'
  alias claude-personal='CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude'
  ```

  Run each alias once and log in. DevDock picks up the aliases, so its "login expired, run `claude-work`" hints use your own commands.
- **Claude Code through an API gateway** (`ANTHROPIC_BASE_URL` in that directory's `settings.json`): there is no quota, so DevDock counts tokens from the local session logs instead.
- **Codex**: `~/.codex`, logged in with ChatGPT.

Choose which accounts appear in the menu bar under Settings.

## Privacy

DevDock runs entirely on your Mac. It has no server, no analytics and no account.

- To read quota it uses the login that Claude Code and Codex already saved: the Claude token from the Keychain (through `/usr/bin/security`, as Claude Code does) and the Codex token from `~/.codex/auth.json`. Tokens are only held in memory for the request to `api.anthropic.com` / `chatgpt.com`, the same endpoints the tools' own `/usage` screens use. They are never written to disk or logged.
- It never refreshes those tokens itself, so it can't log Claude Code or Codex out. If a login has expired, run the tool once and DevDock picks the new token up.
- The last readings and a week of usage history (for the pace estimate) are kept in `~/Library/Application Support/DevDock`.

The usage endpoints are not official public APIs and may change; when they fail, DevDock says so instead of showing made-up numbers, and Codex falls back to its session logs.

## Development

```sh
make build   # Debug build
make run     # build and launch the Debug app
make test    # unit tests (Swift Testing)
make install # Release build into ~/Applications
```

The Xcode project is generated from `project.yml` by XcodeGen; open it with `make gen && open DevDock.xcodeproj`.

```
DevDock/
├── App/            status item, dropdown panel, app state, menu bar rendering
├── DesignSystem/   tokens, brand mark, shared components (no feature logic)
├── Core/           shell runner, refresh scheduler, settings, system helpers
└── Features/
    ├── Ports/      lsof/ps scanner, project resolver, list and detail views
    ├── AIUsage/    account discovery, usage clients, pace, alerts, views
    └── Settings/
```

Features depend only on `Core` and `DesignSystem`, never on each other. See [PLAN.md](PLAN.md) for the roadmap.

## Author

DevDock is built and maintained by [**npmh0310**](https://github.com/npmh0310). Issues and ideas are welcome.
