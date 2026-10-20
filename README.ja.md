# WorkBuddy AI Portable

[English](README.md) | [简体中文](README.zh-CN.md) | **日本語** | [한국어](README.ko.md)

[WorkBuddy AI](https://www.workbuddy.ai/) デスクトップ版（Electron）を [PortableApps.com](https://portableapps.com/) 形式の
Windows ポータブル版にまとめたものです。プログラム、設定、セッションデータ、キャッシュはすべてポータブルフォルダ内に
保存されるため、別の PC にコピーしてもそのまま使い続けられ、システムドライブを汚しません。

- ランチャー：[PortableApps.com Launcher 2.2.9](https://portableapps.com/apps/development/portableapps.com_launcher)（`vendor/` に同梱済み、ネット接続不要）
- 対応環境：Windows 10/11 x64
- 上流バージョン：公式 `v2/update` エンドポイントから自動検出

## 配布物

[Releases](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) ページからダウンロードするか、
ローカルビルド後は `dist/` を確認してください：

| ファイル | 説明 |
| --- | --- |
| [`WorkBuddyAIPortable_<version>_English.paf.exe`](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) | PAF インストーラー。ダブルクリックで任意のフォルダにインストール |
| [`WorkBuddyAIPortable_<version>_portable.zip`](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) | 純粋なポータブルアーカイブ。解凍するだけで使用可能 |

バージョンは上流の `genieVersion` の先頭 3 セグメントです（例：上流 `5.8.4.41366630` → `WorkBuddyAIPortable_584_*`）。

## 前提条件

- **7-Zip**：NSIS アーカイブを展開できるフル版 `7z.exe` が必要です
  （`7za.exe` / `7zr.exe` は NSIS ハンドラを含まない軽量版のため、`.paf.exe` や上流インストーラーを開けません）
- **PATH**：`7za.exe` または `7z.exe` が PATH にあれば自動検出します。`PORTABLEAPPS_7Z_PATH` で絶対パス指定も可能
- バージョン 21.07 以降

## ローカルビルド

```powershell
# フルビルド：上流検出 → ダウンロード → 展開 → コンパイル → パッケージ
.\build.ps1

# 既存の App/WorkBuddyAI を再利用し、再コンパイルと再パッケージのみ実行
.\build.ps1 -SkipDownload
```

スクリプトは次の順に処理します：

1. `App\AppInfo\appinfo.ini` から `ID` / `Name` / `PackageVersion` を読み取る
2. 使用可能な 7-Zip を検出（メインは `7za` を優先、NSIS 展開時は自動的にフル版 `7z.exe` に切り替え）
3. `https://www.workbuddy.ai/v2/update` を取得し、上流インストーラーをダウンロードして `App\WorkBuddyAI` に展開
4. PAL テンプレートと `makensis` でランチャー `WorkBuddyAIPortable.exe` をコンパイル
5. 純粋な zip を作成し、PAF を `dist/` にコピー

任意の環境変数：`PORTABLEAPPS_7Z_PATH`、`PORTABLEAPPS_MAKENSIS`。

## CI（GitHub Actions）

ワークフロー：[`.github/workflows/build.yml`](.github/workflows/build.yml)

トリガー：

| トリガー | 説明 |
| --- | --- |
| `workflow_dispatch` | 手動実行。`force_build=true` を渡すとバージョン差を無視して強制再ビルド |
| `schedule` | 毎週月曜 02:00 UTC に上流の更新を確認 |
| `main` への `push` | プッシュ後に上流の新バージョンを確認 |

```bash
# コマンドラインから手動実行（gh をインストールしログイン済みであること）
gh workflow run build.yml -f force_build=true
```

リポジトリ画面の **Actions → Build & Release WorkBuddyAIPortable → Run workflow** で
`force_build` を有効にして実行することもできます。

注意：デフォルトでは上流バージョンがローカルの `PackageVersion` より新しい場合のみ実際にビルドされ、
それ以外は後続ステップがすべて `skipped` になります。これは同一ビルドの重複作成を避けるための仕様です。
強制的に検証したい場合は `force_build=true` を使用してください。

## ポータブル化の仕組み

設定は [`App\AppInfo\Launcher\WorkBuddyAIPortable.ini`](App/AppInfo/Launcher/WorkBuddyAIPortable.ini) にあります：

- **データのリダイレクト**：`WORKBUDDY_CONFIG_DIR` / `WORKBUDDY_USER_DATA_DIR` / `CODEBUDDY_CONFIG_DIR` で
  設定と Electron の `userData` を `Data\` に向ける
- **ホームのリダイレクト**：`USERPROFILE` / `HOME` を `Data\home` に向け、アプリ内で `os.homedir()` から
  派生するすべての既定パスをカバーする
- **自動更新のブロック**：`WORKBUDDY_UPDATE_URL=http://127.0.0.1:9` を到達不能なローカルポートに向け、
  更新元の検証を即座に失敗させる
  （空文字列では効きません。falsy と判定されて既定サーバーにフォールバックします）
- **レジストリ**：HKCU のユーザーレベルのキーのみ書き込み（`workbuddy://`、`buddy-app://` のプロトコル関連付け、
  スタートアップ登録）。終了時に削除
- **一時ディレクトリ**：`TEMP` / `TMP` を `Data\temp` に向ける

## GPU クラッシュの緩和

一部の環境では GPU プロセスがクラッシュし（`child-process-gone exitCode=-1`）、それに伴って
レンダラーもクラッシュ → ウィンドウが破棄 → `window-all-closed` → アプリが自ら終了します。
外から見ると「しばらく動くと落ちる」という症状になります。

ランチャーはあらかじめソフトウェアレンダリングを強制しています：

```ini
CommandLineArguments=--disable-gpu --disable-gpu-compositing --disable-direct-composition
```

ハードウェアアクセラレーションを戻したい場合（描画性能優先）は、この行を空にしてください。
あくまで緩和策であり、根本原因はアプリまたはグラフィックスドライバ側にあります。

## ディレクトリ構成

```
WorkBuddyAIPortable/
├── App/
│   └── AppInfo/
│       ├── appinfo.ini              # PAF メタ情報（ID / バージョン / カテゴリ）
│       ├── Launcher/
│       │   ├── WorkBuddyAIPortable.ini   # PAL 実行設定（リダイレクト、起動引数）
│       │   └── Custom.nsh                # カスタム NSIS フック
│       └── appicon*.png / .ico
├── vendor/
│   └── PortableApps.comLauncher_2.2.9.paf.exe   # 同梱ランチャー、CI は外部ネット不要
├── .github/workflows/build.yml      # CI：ビルド + リリース
├── build.ps1                        # ローカルワンコマンドビルド
└── dist/                            # ビルド成果物（バージョン管理対象外）
```

`App\WorkBuddyAI\`（上流プログラム本体）と `Data\`（ユーザーデータ）は git 管理外で、
ビルドスクリプトまたは実行時に生成されます。

## 免責事項

本プロジェクトはポータブル化のための再パッケージのみを行い、上流プログラム本体は改変しません。
WorkBuddy AI 公式とは一切関係ありません。WorkBuddy AI の著作権は各権利者に帰属し、
ご利用は公式ライセンス条件に従ってください。
