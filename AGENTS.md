# AGENTS.md

Guide for coding agents working on this repository. Gõ Nhanh is a Vietnamese input method (Telex and VNI). A platform-independent Rust engine decides what to type; each platform app captures keys and injects the result.

This checkout is a fork used as the base for a custom keyboard:

| Remote | Repo | Use |
|---|---|---|
| `origin` | `thienanblog/gonhanh.org` | Our fork. Push branches and open PRs here. |
| `upstream` | `khaphanspace/gonhanh.org` | Original project. Read only. Do not open PRs or push here unless asked. |

`gh` defaults to `upstream` (read-only), so always pass `--repo thienanblog/gonhanh.org` to `gh pr ...`.

Some files in `docs/` are stale: they mention a `CLAUDE.md` and macOS files that no longer exist, and give old line counts. Trust the code over the docs.

## Layout

```
core/                     Rust engine (no runtime dependencies)
  src/lib.rs              C FFI: ime_init, ime_key, ime_key_ext, ime_key_with_char, ime_method,
                          ime_enabled, ime_modern, ime_free_tone, ime_english_auto_restore,
                          ime_auto_capitalize, ime_allow_foreign_consonants, ime_skip_w_shortcut,
                          ime_bracket_shortcut, ime_esc_restore, ime_clear, ime_clear_all,
                          ime_get_buffer, ime_restore_word, ime_*_shortcut(s), ime_free
  src/engine/mod.rs       Engine state machine (~8.7k lines): marks, tones, revert, auto-restore
  src/engine/{buffer,syllable,validation,transform,shortcut}.rs
  src/input/{telex,vni}.rs  Key-to-modifier mappings per input method
  src/data/               Key codes, vowel table, dictionaries, telex_doubles (generated, 10k lines)
  src/updater/            Version comparison used by the macOS updater
  src/utils.rs            Shared helpers + test_utils (type_word, telex(), vni(), ...)
  tests/                  Integration tests, one file per feature/issue; tests/data holds 22k VN / 100k EN word lists
platforms/macos/          SwiftUI menu-bar app (Xcode project GoNhanh.xcodeproj, bundle org.gonhanh.GoNhanh, macOS 13+)
platforms/windows/        WPF/.NET app (Core/KeyboardHook.cs, Core/TextSender.cs, Core/RustBridge.cs)
platforms/linux/          Fcitx5 addon in C++ (src/Engine.cpp, src/RustBridge.cpp, tests/)
scripts/build/            core.sh (universal static lib), macos.sh, windows.sh
scripts/test/             dict.sh (dictionary pass rates), typing/auto-restore Swift harnesses
scripts/release/          DMG, release notes, contributors
```

## How a keystroke flows

1. The platform hook gets a key down. On macOS this is a CGEventTap in `RustBridge.swift` `keyboardCallback`.
2. The hook calls `ime_key_ext(key, caps, ctrl, shift)`. The engine returns a `Result` with `action` (0 None, 1 Send, 2 Restore), `backspace`, `count`, `chars[256]` (UTF-32) and `flags` (bit 0 = key consumed).
3. On Send, the platform deletes `backspace` characters and types `chars` (`TextInjector`). The original key is swallowed; break keys may be re-posted after the replacement.
4. Word boundaries (space, punctuation, navigation, clicks, Cmd shortcuts) clear the engine buffer.

The engine is a pure function of key codes plus settings. If output is wrong for a given key sequence, reproduce it in `core/tests`. If the engine output is right but the screen is wrong, the bug is in the platform injection layer.

## macOS app (platforms/macos)

| File | Role |
|---|---|
| `RustBridge.swift` | FFI bindings, `KeyboardHookManager` (event tap, watchdog, secure input), `TextInjector` (all synthetic events), `detectMethod()` (per-app injection method + delays), debug `Log` |
| `MainSettingsView.swift` | `AppState` (all settings, persisted in UserDefaults) and the main settings UI |
| `AdvancedSettingsView.swift`, `PerAppConfigModels.swift` | Per-app profiles: injection override and delay presets |
| `AppMetadata.swift` | `AppMetadata`, `SettingsKey` (UserDefaults keys `gonhanh.*`), `InputMode` (0 Telex, 1 VNI) |
| `MenuBar.swift`, `OnboardingView.swift` | Status item, onboarding / Accessibility permission flow |
| `SpecialPanelAppDetector.swift`, `InputSourceManager.swift` | Spotlight/Raycast panels; auto-disable for non-Latin input sources |
| `UpdateChecker.swift`, `UpdateManager.swift` | Hourly background update check against **upstream** releases (`khaphanspace/gonhanh.org`, URL in `UpdateChecker.githubAPIURL`). A newer upstream version is downloaded silently and offered as a restart-to-update in the menu. Accepting it installs the upstream app over a locally built fork app and drops every fork-only change. Repoint or disable this before shipping fork builds. |

Injection rules worth knowing before touching `TextInjector`:

- Methods: `fast` (default), `slow` (terminals/Electron), `charByChar` (Safari content), `emptyCharPrefix` (browser address bars), `selection` (combo boxes, search fields), `axDirect` (Spotlight, via the AX API), `syncProxy` (games), `passthrough` (iPhone Mirroring, remote desktop clients).
- Synthetic events carry `kEventMarker` in `eventSourceUserData`, so the tap ignores its own events.
- Tap level: HID by default; session level when "Chế độ remote desktop" (`gonhanh.sessionTapMode`) is on or the Accessibility Keyboard is visible (the watchdog switches automatically). In session mode every synthetic event must go through `tapPostEvent(proxy)` (`TextInjector.sessionProxy`). Posting to `.cgSessionEventTap` lets a real keystroke typed mid-injection slip between the backspaces and the text ("cái nút" → "c áinút"). Any new posting path must go through `postKey` / `postText` / `postPair` with the proxy.
- The injection runs synchronously inside the tap callback. Keep it short: macOS disables taps whose callbacks overrun (the watchdog re-enables them).

Debug log: `touch /tmp/gonhanh_debug.log` enables logging and `make watch` tails it; delete the file to turn logging off.

## Commands

Rust (run from the repo root):

```bash
cd core && cargo test                 # all tests (CI runs this)
cd core && cargo fmt --check && cargo clippy -- -D warnings
make test-dict                        # dictionary pass rates (VN 100%, EN 97% thresholds)
make test-22k                         # heavy ignored tests
make test-100k                        # English 100k
```

Write engine tests with `gonhanh_core::utils::{telex, vni, telex_auto_restore, type_word}`: `telex(&[("vieejt", "việt")])`. In `type_word` input, `<` is Backspace and `\x1b` is Esc. Settings that matter for repros: `set_method(1)` for VNI, `set_modern_tone`, `set_english_auto_restore`, `set_free_tone`, `set_auto_capitalize`.

macOS:

```bash
make build      # format + core.sh + macos.sh + windows.sh, then opens the app
make install    # build, copy to /Applications, open
make lint       # clippy + swiftformat --lint (CI fails on swiftformat issues)
```

Known local pitfalls on this machine:

- `scripts/build/core.sh` builds a universal lib and needs `rustup target add x86_64-apple-darwin`. Without it, for an arm64-only local build:
  ```bash
  cd core && cargo build --release --target aarch64-apple-darwin
  cp target/aarch64-apple-darwin/release/libgonhanh_core.a ../platforms/macos/
  cd ../platforms/macos && xcodebuild -scheme GoNhanh -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/build/DerivedData" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
  ```
- `libgonhanh_core.a` must exist in `platforms/macos/` (gitignored) for both the app build and `xcodebuild test`.
- `macos.sh` kills any running `GoNhanh` and ends with a `sudo sqlite3` write to the TCC database. That step fails in non-interactive shells; do not work around it. After a rebuild with a new signature, the user re-grants Accessibility in System Settings.
- `swiftformat` is not installed locally (`brew install swiftformat`). CI lints Swift with it.
- Swift tests: `cd platforms/macos && xcodebuild test -scheme GoNhanh -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=-`.
- No automated test covers macOS injection timing. Verify those changes by typing fast in a real app, in both HID and session tap modes.

## CI and releases

- `.github/workflows/ci.yml` runs on push and PRs to `main`: Rust fmt/clippy/test (Ubuntu), swiftformat lint + release build (macOS), Fcitx5 build + tests (Ubuntu).
- `release.yml` runs on `v*` tags. `make release*` commits, tags and pushes to `origin`, and its links point at upstream. Do not run release targets unless asked.
- `update-contributors.yml` regularly pushes "docs: update contributors [skip ci]" commits to `main`.

## Conventions

- Conventional Commits (`feat:`, `fix(macos):`, `fix(core):`, `test:`, `docs:`). Reference issues as `(#123)`.
- Rust: `cargo fmt`, no clippy warnings, add a test in `core/tests` for every engine behavior change (name issue-specific files `issue_<n>_*.rs` or add to `bug_reports_test.rs`).
- Swift: swiftformat clean. Explain non-obvious event-tap or injection behavior in comments, including the issue number.
- UI strings are Vietnamese; code, comments and docs are English.
- Keep the engine free of platform code and runtime dependencies. The release profile optimizes for size (`opt-level = "z"`, LTO, `panic = "abort"`).
