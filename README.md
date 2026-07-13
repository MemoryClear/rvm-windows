# RVM - Rust Version Manager for Windows

**Centralized Rust toolchain management** for Windows. Manage multiple Rust versions with zero configuration overhead, built-in China mirrors, and automatic metadata repair.

Inspired by pvm-windows (Python Version Manager) and rbenv.

---

## Architecture

RVM wraps `rustup` with a **centralized directory** and saves/restores environment variables (`RUSTUP_HOME`, `CARGO_HOME`, `RUSTUP_DIST_SERVER`) around every invocation.

```
~/.rvm/                      # Default installation (or D:\rvm etc.)
  bin/
    rvm.ps1                  # Main script (PowerShell)
    rvm.bat                  # Launcher (batch, detects pwsh/powershell)
    rustup-init.exe          # Downloaded on first install
    uninstall.ps1            # Uninstaller
  rustup/                    # RUSTUP_HOME — toolchains, etc.
    settings.toml            # Rustup config (version, default toolchain)
    toolchains/              # Installed Rust toolchains
      stable-x86_64-pc-windows-msvc/
      1.75.0-x86_64-pc-windows-msvc/
    tmp/                     # Stale/metadata cache (auto-cleared if needed)
  cargo/                     # CARGO_HOME — cargo registry, bins, crates
    bin/                     # rustup.exe, rustc.exe, cargo.exe live here
    registry/
  settings.json              # RVM config (root path, mirror, etc.)
```

Key benefits:
- ✅ All toolchains and crates under one directory
- ✅ No conflict with system-wide Rust installations
- ✅ Easy to move or remove
- ✅ Built-in mirror support (rsproxy, TUNA, USTC, SJTU)

---

## Quick Start

```powershell
# 1. Install
powershell -ExecutionPolicy Bypass -File install.ps1 -InstallDir D:\rvm

# 2. Restart your terminal

# 3. (China users) Set a mirror first
rvm mirror set rsproxy       # ByteDance CDN — recommended
# rvm mirror set tuna        # Tsinghua TUNA — also very fast

# 4. Install Rust
rvm install stable

# 5. Switch to it
rvm use stable

# 6. Check
rvm current
```

---

## Commands

| Command | Description |
|---|---|
| **Install & Switch** | |
| `rvm install stable` | Install the latest stable Rust |
| `rvm install 1.75.0` | Install a specific version |
| `rvm use stable` | Switch to stable (auto-installs if missing) |
| `rvm use 1.78.0` | Switch to a specific version (auto-installs if missing) |
| **Information** | |
| `rvm list` | List installed toolchains |
| `rvm list available` | Fetch and show available versions |
| `rvm current` | Show active toolchain + rustc version |
| `rvm default` | Show current default toolchain |
| `rvm version` | Show RVM version |
| **Manage** | |
| `rvm uninstall 1.75.0` | Remove a toolchain |
| `rvm root` | Show installation directory |
| `rvm root D:\dev\rvm` | Move RVM (migrates all data) |
| **Mirrors** | |
| `rvm mirror show` | Show current mirror config |
| `rvm mirror set rsproxy` | Set ByteDance/rsproxy mirror |
| `rvm mirror set tuna` | Set Tsinghua TUNA mirror |
| `rvm mirror set official` | Reset to official sources |
| **Troubleshooting** | |
| `rvm doctor` | Diagnose rustup health |
| `rvm repair` | Full auto-repair of corrupted metadata |
| `rvm help` | Show help |

---

## Mirrors

Built-in mirrors for users in China (avoids slow downloads and connection issues).

> **Note:** `rustup-init.exe` (the bootstrap installer) is always downloaded from the official source because mirrors do not host it. All other traffic — channel metadata and toolchain packages — goes through the selected mirror.

| Mirror | Provider | RUSTUP_DIST_SERVER | RUSTUP_UPDATE_ROOT | Check speed | Packages |
|---|---|---|---|---|---|
| `rsproxy` | ByteDance | `https://rsproxy.cn` | `https://rsproxy.cn/rustup` | ~1s ✅ | ✅ ByteDance CDN |
| `tuna` | Tsinghua | `https://mirrors.tuna.tsinghua.edu.cn/rustup` | `https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup` | ~0.7s ✅ | ✅ 清华源直连 |
| `sjtu` | SJTU | `https://mirrors.sjtug.sjtu.edu.cn/rust-static` | `https://mirrors.sjtug.sjtu.edu.cn/rust-static/rustup` | ~0.9s ✅ | ⚠️ 回源 official |
| `ustc` | USTC | `https://mirrors.ustc.edu.cn/rustup` | `https://mirrors.ustc.edu.cn/rustup/rustup` | ~43s ⚠️ | ✅ 浙大镜像 (`zju.edu.cn`) |
| `official` | Rust official | — (default) | — (default) | — | ✅ 官方直连 |

Mirror configuration affects:
- **`RUSTUP_DIST_SERVER`** — where rustup downloads toolchains and metadata
- **`cargo registry`** — where `cargo install` and `cargo build` fetch crates from

The mirror setting is persisted in `settings.json` and takes effect immediately.

---

## Troubleshooting

### `rustup's metadata is out of date`

This happens when switching between mirrors (e.g., from rsproxy back to official) because rustup caches metadata from the previous mirror.

**Fix:** Run `rvm repair` — it clears stale cache, re-downloads rustup-init, and re-initializes rustup without touching installed toolchains.

```cmd
rvm doctor    # Check health first
rvm repair    # Auto-fix metadata corruption
```

### `rvm use` or `rvm install` hangs

If a rustup command seems to hang (especially `rustup toolchain remove` on Windows):

1. Press Ctrl+C to abort
2. Run `rvm uninstall <toolchain>` — RVM deletes the toolchain directory directly instead of calling `rustup toolchain remove`

### Cannot find `rustc` or `cargo` after switching

After `rvm use <toolchain>`, the current CMD/PowerShell session should have the correct PATH. If not:

```cmd
rvm use stable    # Re-run to refresh PATH
```

Or **restart your terminal**.

---

## Installation

### Fresh install

```powershell
# Clone or download this repo
git clone https://github.com/yourname/rvm-windows.git
cd rvm-windows

# Default install (to ~/.rvm)
powershell -ExecutionPolicy Bypass -File install.ps1

# Custom location
powershell -ExecutionPolicy Bypass -File install.ps1 -InstallDir D:\rvm
```

The installer:
1. Creates directory structure
2. Copies scripts to `<InstallDir>\bin\`
3. Creates `rvm.bat` launcher (uses `%~dp0` — no env var dependency)
4. Adds `<InstallDir>\bin\` to user PATH
5. Sets `RVM_HOME` environment variable
6. Initializes `settings.json`

### Requirements

- Windows 7+
- PowerShell 5.0+ (ships with modern Windows) or PowerShell Core
- Internet connection (for downloading rustup-init and toolchains)

### Uninstall

```powershell
# Uninstall toolchains first
rvm uninstall stable
rvm uninstall 1.78.0

# Run the uninstaller
powershell -ExecutionPolicy Bypass -File "%RVM_HOME%\bin\uninstall.ps1"
```

Then manually:
- Remove `%RVM_HOME%` directory
- Remove `RVM_HOME` user environment variable
- Remove `<InstallDir>\bin` from user PATH

---

## Architecture Comparison

| Aspect | pvm-windows (Python) | rvm-windows (Rust) |
|---|---|---|
| Runtime | Python embeddable zip (ships full runtime) | N/A — Rust has no embeddable zip |
| Dependency | Python.org zip + directory junctions | rustup-init.exe + rustup multi-instance |
| Version isolation | Junctions per version | rustup manages toolchains centrally |
| Mirror support | Direct URL override in settings | RUSTUP_DIST_SERVER + cargo config.toml |
| Metadata corruption | N/A (no external state) | Auto-repair via `rvm repair` |
| Key innovation | Zero-download Python CLI | Lightweight mirror + centralized wrap |

---

## Files

| File | Purpose |
|---|---|
| `rvm.ps1` | Main PowerShell script (~500 lines, all logic) |
| `rvm.bat` | CMD launcher (finds rvm.ps1 via `%~dp0`) |
| `install.ps1` | Installer (directory setup, PATH, env vars) |
| `uninstall.ps1` | Clean removal |
| `settings.json` | RVM configuration (root path, mirror) |

## License

MIT
