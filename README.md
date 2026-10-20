# WorkBuddy AI Portable

**English** | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

Packages the [WorkBuddy AI](https://www.workbuddy.ai/) desktop app (Electron) into a
[PortableApps.com](https://portableapps.com/) style Windows portable edition: the program, settings,
session data and caches all stay inside the portable folder, so you can copy it to another machine
and keep working without polluting the system drive.

- Launcher: [PortableApps.com Launcher 2.2.9](https://portableapps.com/apps/development/portableapps.com_launcher) (bundled in `vendor/`, no network access needed)
- Platform: Windows 10/11 x64
- Upstream version: detected automatically from the official `v2/update` endpoint

## Artifacts

Grab them from the [Releases](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) page, or build
locally and look in `dist/`:

| File | Description |
| --- | --- |
| [`WorkBuddyAIPortable_<version>_English.paf.exe`](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) | PAF installer, double-click to install into any folder |
| [`WorkBuddyAIPortable_<version>_portable.zip`](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) | Plain portable archive, extract and run |

The version is the first three segments of the upstream `genieVersion`, e.g. upstream `5.8.4.41366630`
→ `WorkBuddyAIPortable_584_*`.

## Prerequisites

- **7-Zip**: you need the full `7z.exe` that can unpack NSIS archives (`7za.exe` / `7zr.exe` are the
  reduced builds without the NSIS handler, so they cannot open `.paf.exe` or the upstream installer)
- **PATH**: just have `7za.exe` or `7z.exe` on PATH — the script auto-detects it; you can also point
  `PORTABLEAPPS_7Z_PATH` at an absolute path
- Version 21.07 or newer

## Local build

```powershell
# Full build: probe upstream -> download -> unpack -> compile -> package
.\build.ps1

# Reuse the existing App/WorkBuddyAI and only recompile + repackage
.\build.ps1 -SkipDownload
```

The script performs these steps:

1. Read `App\AppInfo\appinfo.ini` for `ID` / `Name` / `PackageVersion`
2. Detect a usable 7-Zip (prefers `7za`; automatically switches to the full `7z.exe` for NSIS archives)
3. Query `https://www.workbuddy.ai/v2/update`, download and unpack the upstream installer into `App\WorkBuddyAI`
4. Compile the launcher `WorkBuddyAIPortable.exe` with the PAL template + `makensis`
5. Build the plain zip and copy the PAF into `dist/`

Optional environment variables: `PORTABLEAPPS_7Z_PATH`, `PORTABLEAPPS_MAKENSIS`.

## CI (GitHub Actions)

Workflow: [`.github/workflows/build.yml`](.github/workflows/build.yml)

Triggers:

| Trigger | Description |
| --- | --- |
| `workflow_dispatch` | Manual run; pass `force_build=true` to rebuild even if versions match |
| `schedule` | Every Monday 02:00 UTC, check for upstream updates |
| `push` to `main` | Check for a new upstream version after each push |

```bash
# Trigger from the command line (requires gh, logged in)
gh workflow run build.yml -f force_build=true
```

Or use the repository UI: **Actions → Build & Release WorkBuddyAIPortable → Run workflow**,
enable `force_build`, then run.

Note: by default a build only happens when the upstream version is newer than the local
`PackageVersion`; otherwise all following steps are `skipped`. That is intentional, to avoid
repackaging identical builds. Use `force_build=true` to force a verification build.

## How portability works

Configuration lives in [`App\AppInfo\Launcher\WorkBuddyAIPortable.ini`](App/AppInfo/Launcher/WorkBuddyAIPortable.ini):

- **Data redirection**: `WORKBUDDY_CONFIG_DIR` / `WORKBUDDY_USER_DATA_DIR` / `CODEBUDDY_CONFIG_DIR`
  point the config and Electron `userData` at `Data\`
- **Home redirection**: `USERPROFILE` / `HOME` point at `Data\home`, covering every default path
  derived from `os.homedir()` inside the app
- **Auto-update blocked**: `WORKBUDDY_UPDATE_URL=http://127.0.0.1:9` points at an unreachable local
  port so the update-source check fails immediately
  (note: setting it to an empty string does not work — it is treated as falsy and falls back to the
  default server)
- **Registry**: only HKCU user-level keys (`workbuddy://`, `buddy-app://` protocol handlers,
  run-at-startup), removed on exit
- **Temp directory**: `TEMP` / `TMP` point at `Data\temp`

## GPU crash mitigation

On some machines the GPU process crashes (`child-process-gone exitCode=-1`), which takes the renderer
down with it → the window is destroyed → `window-all-closed` → the app exits on its own. From the
outside this looks like "it crashes after running for a while".

The launcher forces software rendering up front:

```ini
CommandLineArguments=--disable-gpu --disable-gpu-compositing --disable-direct-composition
```

To restore hardware acceleration (better graphics performance), just clear that line.
Note this is only a mitigation — the root cause is in the app or the graphics driver.

## Repository layout

```
WorkBuddyAIPortable/
├── App/
│   └── AppInfo/
│       ├── appinfo.ini              # PAF metadata (ID / version / category)
│       ├── Launcher/
│       │   ├── WorkBuddyAIPortable.ini   # PAL runtime config (redirection, launch args)
│       │   └── Custom.nsh                # custom NSIS hooks
│       └── appicon*.png / .ico
├── vendor/
│   └── PortableApps.comLauncher_2.2.9.paf.exe   # bundled launcher, CI no longer needs the internet
├── .github/workflows/build.yml      # CI: build + release
├── build.ps1                        # one-command local build
└── dist/                            # build output (not tracked)
```

`App\WorkBuddyAI\` (the upstream program) and `Data\` (user data) are not tracked by git; they are
produced by the build script or at runtime.

## Disclaimer

This project only repackages the app for portability; it does not modify the upstream program and is
not affiliated with WorkBuddy AI. All rights to WorkBuddy AI belong to their respective owners — use
it under the official license terms.
