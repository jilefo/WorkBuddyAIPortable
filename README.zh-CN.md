# WorkBuddy AI Portable

[English](README.md) | **简体中文** | [日本語](README.ja.md) | [한국어](README.ko.md)

把 [WorkBuddy AI](https://www.workbuddy.ai/) 桌面版（Electron）封装成 [PortableApps.com](https://portableapps.com/) 格式的 Windows 便携版：
程序、配置、会话数据、缓存全部落在便携目录内，换机拷贝即可继续用，不污染系统盘。

- 启动器：[PortableApps.com Launcher 2.2.9](https://portableapps.com/apps/development/portableapps.com_launcher)（仓库内 `vendor/` 已内置，无需联网下载）
- 平台：Windows 10/11 x64
- 上游版本：跟随官方 `v2/update` 接口自动探测

## 产物

从 [Releases](https://github.com/jilefo/WorkBuddyAIPortable/releases) 页面直接下载，或本地构建后查看 `dist/`：

| 文件 | 说明 |
| --- | --- |
| `WorkBuddyAIPortable_<version>_English.paf.exe` | PAF 安装器，双击可安装到任意目录 |
| `WorkBuddyAIPortable_<version>_portable.zip` | 纯便携压缩包，解压即用 |

版本号取上游 `genieVersion` 的前三段，例如上游 `5.8.4.41366630` → `WorkBuddyAIPortable_584_*`。

## 前置条件

- **7-Zip**：需要能解 NSIS 归档的完整版 `7z.exe`（`7za.exe` / `7zr.exe` 是精简版，不含 NSIS handler，解不了 `.paf.exe` 和上游安装包）
- **PATH**：`7za.exe` 或 `7z.exe` 在 PATH 中即可，脚本会自动探测；也可用 `PORTABLEAPPS_7Z_PATH` 指定绝对路径
- 版本要求 21.07 及以上

## 本地构建

```powershell
# 完整构建：探测上游 → 下载 → 解包 → 编译 → 打包
.\build.ps1

# 复用已存在的 App/WorkBuddyAI，只重新编译和打包
.\build.ps1 -SkipDownload
```

脚本会依次完成：

1. 读取 `App\AppInfo\appinfo.ini`，取 `ID` / `Name` / `PackageVersion`
2. 探测可用的 7-Zip（主工具优先 `7za`；NSIS 解包自动切到完整版 `7z.exe`）
3. 拉取 `https://www.workbuddy.ai/v2/update`，下载并解包上游安装包到 `App\WorkBuddyAI`
4. 用 PAL 模板 + `makensis` 编译出启动器 `WorkBuddyAIPortable.exe`
5. 打纯 zip 包，并复制 PAF 到 `dist/`

可选环境变量：`PORTABLEAPPS_7Z_PATH`、`PORTABLEAPPS_MAKENSIS`。

## CI（GitHub Actions）

工作流：[`.github/workflows/build.yml`](.github/workflows/build.yml)

触发方式：

| 触发 | 说明 |
| --- | --- |
| `workflow_dispatch` | 手动触发，可传 `force_build=true` 忽略版本差异强制重建 |
| `schedule` | 每周一 02:00 UTC 自动检查上游更新 |
| `push` 到 `main` | 推送后检查上游是否有新版本 |

```bash
# 命令行手动触发（需已安装 gh 并登录）
gh workflow run build.yml -f force_build=true
```

也可以在仓库页面 **Actions → Build & Release WorkBuddyAIPortable → Run workflow**，
勾选 `force_build` 后运行。

注意：默认情况下只有上游版本高于本地 `PackageVersion` 才会真正构建，
否则后续步骤全部 `skipped` —— 这是有意设计，避免重复打包。想强制验证请用 `force_build=true`。

## 便携化原理

配置见 [`App\AppInfo\Launcher\WorkBuddyAIPortable.ini`](App/AppInfo/Launcher/WorkBuddyAIPortable.ini)：

- **数据重定向**：通过 `WORKBUDDY_CONFIG_DIR` / `WORKBUDDY_USER_DATA_DIR` / `CODEBUDDY_CONFIG_DIR` 把配置与 Electron `userData` 指向 `Data\`
- **主目录重定向**：`USERPROFILE` / `HOME` 指向 `Data\home`，兜住应用内所有由 `os.homedir()` 派生的默认路径
- **阻断自动更新**：`WORKBUDDY_UPDATE_URL=http://127.0.0.1:9` 指向本机不可达端口，使更新源校验立即失败
  （注意设为空字符串无效，会被判为 falsy 而回退到默认服务器）
- **注册表**：仅写 HKCU 用户级键（`workbuddy://`、`buddy-app://` 协议关联、开机自启），退出时清理
- **临时目录**：`TEMP` / `TMP` 指向 `Data\temp`

## GPU 崩溃缓解

实测部分机器上 GPU 进程会崩溃（`child-process-gone exitCode=-1`），连带 renderer 崩溃 →
窗口被销毁 → `window-all-closed` → 应用自行退出，表现为「跑一会儿就闪退」。

启动器已前置软件渲染参数：

```ini
CommandLineArguments=--disable-gpu --disable-gpu-compositing --disable-direct-composition
```

如需恢复硬件加速（图形性能优先），把该行清空即可。
注意这只是缓解，根因在应用或显卡驱动层。

## 目录结构

```
WorkBuddyAIPortable/
├── App/
│   └── AppInfo/
│       ├── appinfo.ini              # PAF 元信息（ID / 版本 / 分类）
│       ├── Launcher/
│       │   ├── WorkBuddyAIPortable.ini   # PAL 运行配置（重定向、启动参数）
│       │   └── Custom.nsh                # 自定义 NSIS 钩子
│       └── appicon*.png / .ico
├── vendor/
│   └── PortableApps.comLauncher_2.2.9.paf.exe   # 内置启动器，CI 不再依赖外网
├── .github/workflows/build.yml      # CI：构建 + Release
├── build.ps1                        # 本地一键构建
└── dist/                            # 构建产物（不纳入版本控制）
```

`App\WorkBuddyAI\`（上游程序本体）与 `Data\`（用户数据）都不进 git，由构建脚本或运行时生成。

## 免责声明

本项目仅做便携化封装，不修改上游程序本体，与 WorkBuddy AI 官方无从属关系。
WorkBuddy AI 的版权归其各自权利人所有，使用请遵守官方许可协议。
