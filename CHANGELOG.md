# Changelog

All notable development notes are recorded here. For user documentation, see [README.md](README.md).

---

## 2026-07-13 — Mirror URL fixes (round 2)

### Root cause: UPDATE_ROOT ≠ DIST_SERVER

rustup uses two separate HTTP endpoints, which live at **different paths** on most mirrors:

| Env var | Purpose | Expected URL | 
|---|---|---|
| `RUSTUP_UPDATE_ROOT` | `+ /release-stable.toml` → rustup self-update | `https://mirror/rustup/release-stable.toml` |
| `RUSTUP_DIST_SERVER` | `+ /dist/channel-rust-*.toml` → toolchain metadata | `https://mirror/rustup/dist/channel-rust-*.toml` |

All four mirrors have `/rustup/` in both paths — but the code had them set to identical values, so `RUSTUP_UPDATE_ROOT` was pointing at the dist server root and returning 404.

### Verified working config

| Mirror | `rustup_dist_server` | `rustup_update_root` | `rustup check` |
|---|---|---|---|
| rsproxy | `https://rsproxy.cn` | `https://rsproxy.cn/rustup` | ✅ 1121ms |
| tuna | `https://mirrors.tuna.tsinghua.edu.cn/rustup` | `https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup` | ✅ 699ms |
| sjtu | `https://mirrors.sjtug.sjtu.edu.cn/rust-static` | `https://mirrors.sjtug.sjtu.edu.cn/rust-static/rustup` | ✅ 862ms |
| ustc | `https://mirrors.ustc.edu.cn/rustup` | `https://mirrors.ustc.edu.cn/rustup/rustup` | ✅ 25s (redirects to mirrors.zju.edu.cn) |

### Code change

Added comment explaining the two-URL architecture and fixed all four mirror entries in `$MIRRORS` table.

> Note: rsproxy.cn's channel manifest (`/dist/channel-rust-*.toml`) contains absolute `static.rust-lang.org` URLs for packages — so the mirror accelerates **metadata** only, not the actual `.tar.gz` downloads (those still come from `static.rust-lang.org`).

---

## 2026-07-13 — Mirror URL fixes

### Problem
All four built-in mirrors returned 404 when fetching `rustup-init.exe` (the bootstrap installer). Additionally, `rsproxy.cn`'s `rustup_update_root` was wrong (pointed to `/rustup` which doesn't exist).

### Root cause: mirrors don't host rustup-init.exe
- `rustup-init.exe` can only be downloaded from `https://static.rust-lang.org/rustup/dist/$arch/rustup-init.exe`
- Chinese mirrors only host **toolchain packages** (`.tar.gz`) and **channel metadata** (`.toml`), not the init binary
- `rustup-init.exe` also respects `RUSTUP_DIST_SERVER` env var — if set to a mirror, the init itself tries to download toolchains from the mirror (which doesn't have the init binary), causing silent failures

### Verified mirror status (2026-07-13)

| Mirror | Channel metadata | Toolchain packages | rustup-init.exe |
|---|---|---|---|
| official | ✅ `/dist/` | ✅ direct | ✅ |
| rsproxy | ✅ `/dist/` | ⚠️ mirrors `static.rust-lang.org` (manifest URLs) | ❌ |
| tuna | ✅ `/rustup/dist/` | ⚠️ mirrors `static.rust-lang.org` (manifest URLs) | ❌ |
| ustc | ✅ `/rustup/dist/` | ✅ 完整镜像（redirects to `mirrors.zju.edu.cn`） | ❌ |
| sjtu | ✅ `/rust-static/dist/` | ✅ 完整镜像 | ❌ |

### Fixes
1. **`Invoke-RvmInstall` (`_DoInstall`):** first-time `rustup-init` call no longer wrapped in `Invoke-WithRustupEnv`. Runs bare so `RUSTUP_DIST_SERVER` is unset — init always uses official source for initial toolchain.
2. **`Repair-Rustup` (Step 4):** same fix — `rustup-init` runs without mirror env vars.
3. **`$MIRRORS["rsproxy"]`:** `rustup_update_root` corrected from `"https://rsproxy.cn/rustup"` to `"https://rsproxy.cn"`.
4. **README mirrors table:** added verified/unverified status labels and a note that `rustup-init.exe` always comes from official source.

> Note: the existing toolchain install path (calling `rustup toolchain install` when rustup already exists) still uses `Invoke-WithRustupEnv` with the mirror — this is correct and desired for speed.

### Architecture

RVM wraps `rustup` with a centralized directory and restores `RUSTUP_HOME` / `CARGO_HOME` / `RUSTUP_DIST_SERVER` around every rustup invocation. It does **not** replace rustup — it only manages where rustup stores its data.

| Aspect | pvm-windows (Python) | rvm-windows (Rust) |
|---|---|---|
| Runtime | embeddable zip (full runtime) | N/A — Rust has no embeddable zip |
| Isolation | directory junctions | rustup manages toolchains centrally |
| Core mechanism | junctions + settings.json | RUSTUP_HOME/CARGO_HOME redirection |

### Commands

`install`, `use`, `list`, `current`, `uninstall`, `default`, `root`, `mirror (show|set)`, `version`, `help`

### Built-in mirrors

`official`, `rsproxy` (ByteDance), `tuna` (Tsinghua), `ustc` (USTC), `sjtu` (SJTU)

---

## 2026-07-10 — Fix: `rvm current` broken after first install

### Problem
`rvm current` reported "No active toolchain" and `rustc --version` failed immediately after installation.

### Root cause 1: `Get-CurrentToolchain` regex mismatch
- `rustup default` output: `stable-x86_64-pc-windows-msvc (default)`
- Original regex `'([^']+)'` looked for single-quoted text → no match → returned `$null`
- Fix: changed to `^([^\s]+)` to match the first non-whitespace token

### Root cause 2: `Invoke-RvmUse` did not persist env vars
- `RUSTUP_HOME` / `CARGO_HOME` were set only in-process; lost after script exited
- Fix: write to registry via `[Environment]::SetEnvironmentVariable(..., "User")`

### Root cause 3: `rvm.bat :refreshpath` had broken `for /f` syntax
- `for /f "tokens=2* delims="` disabled all delimiters → entire line as one token
- `%%B` was always empty → env vars never set in CMD session
- Fix: changed to `for /f "tokens=2*"` (uses default space/tab delimiters)

### Root cause 4: `rvm.bat` relied on fragile `reg query` pipeline
- `reg query HKCU\Environment /v RUSTUP_HOME | findstr REG_` could fail depending on call context
- Final fix: abandon registry entirely; batch file computes RVM root from `%~dp0..`
  ```batch
  for %%I in ("%~dp0..") do set "RVM_ROOT=%%~fI"
  set "RUSTUP_HOME=%RVM_ROOT%\rustup"
  set "CARGO_HOME=%RVM_ROOT%\cargo"
  set "PATH=%RVM_ROOT%\cargo\bin;%PATH%"
  ```

---

## 2026-07-10 — Improvements: doctor, repair, auto-fix

### `rvm uninstall` — stale default reference
After deleting a toolchain directory, RVM now checks `settings.toml` and warns if that toolchain was the default. The fix is to run `rvm use <toolchain>` to set a new default.

> Tried directly writing `default_toolchain = ""` to `settings.toml` — rustup rejected it (version field format mismatch). Prompting the user is the safer approach.

### `rvm use <toolchain>` — auto-install if missing
`Invoke-RvmUse` now calls `Resolve-ToolchainDir` at the start; if the toolchain isn't installed it automatically invokes `Invoke-RvmInstall` before switching.

### `rvm doctor` — health diagnostic
Checks RVM_HOME, RUSTUP_HOME, CARGO_HOME, settings.toml validity, rustup version, installed toolchains, current default, and mirror. Detects stale defaults pointing to deleted toolchains and corrupted `settings.toml` missing the `version` field.

### `rvm repair` — full auto-repair
1. Clear `tmp/`, `update-hashes/`, `settings.toml` via `Clear-RustupCache`
2. Remove `rustup.exe` and `rustup-init.exe` from `CARGO_HOME\bin`
3. Re-download `rustup-init.exe`
4. Re-initialize with `rustup-init -y --no-modify-path`

**Preserves all installed toolchains.**

### `rvm install` — transparent auto-repair
If rustup reports `metadata is out of date` / `TOML parse error` / `could not parse settings`, RVM automatically clears cache and retries once. If still failing, suggests `rvm repair`.

### `Get-CurrentToolchain` — graceful error handling
Added `^error[:]` guard so rustup's error messages (e.g. "error: metadata is out of date") don't get parsed as toolchain names.

### `Invoke-RvmUninstall` — removed `Ensure-RustupInitialized` guard
Direct directory deletion doesn't require rustup to be functional. Allows uninstall even when metadata is corrupted.

---

## File inventory

| File | Purpose |
|---|---|
| `rvm.ps1` | Main script (~680 lines, all logic) |
| `rvm.bat` | CMD launcher (computes paths from `%~dp0`, no env var dependency) |
| `install.ps1` | Installer (directory setup, PATH, env vars, registry) |
| `uninstall.ps1` | Clean removal |
| `settings.json` | RVM config (root path, mirror) |
| `CHANGELOG.md` | This file |
