# WorkBuddy AI Portable

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | **한국어**

[WorkBuddy AI](https://www.workbuddy.ai/) 데스크톱 버전(Electron)을 [PortableApps.com](https://portableapps.com/) 형식의
Windows 포터블 버전으로 패키징한 프로젝트입니다. 프로그램, 설정, 세션 데이터, 캐시가 모두 포터블 폴더 안에
저장되므로 다른 PC로 복사해도 그대로 사용할 수 있고 시스템 드라이브를 오염시키지 않습니다.

- 런처: [PortableApps.com Launcher 2.2.9](https://portableapps.com/apps/development/portableapps.com_launcher) (`vendor/`에 내장되어 있어 네트워크 다운로드 불필요)
- 지원 환경: Windows 10/11 x64
- 업스트림 버전: 공식 `v2/update` 엔드포인트에서 자동 감지

## 배포 파일

[Releases](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) 페이지에서 내려받거나,
로컬 빌드 후 `dist/` 폴더를 확인하세요:

| 파일 | 설명 |
| --- | --- |
| [`WorkBuddyAIPortable_<version>_English.paf.exe`](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) | PAF 설치 프로그램, 더블클릭하여 원하는 폴더에 설치 |
| [`WorkBuddyAIPortable_<version>_portable.zip`](https://github.com/jilefo/WorkBuddyAIPortable/releases/latest) | 순수 포터블 압축 파일, 압축 해제 후 바로 사용 |

버전은 업스트림 `genieVersion`의 앞 3개 세그먼트입니다. 예: 업스트림 `5.8.4.41366630` → `WorkBuddyAIPortable_584_*`.

## 사전 요구 사항

- **7-Zip**: NSIS 아카이브를 해제할 수 있는 정식 `7z.exe`가 필요합니다
  (`7za.exe` / `7zr.exe`는 NSIS 핸들러가 없는 축소판이라 `.paf.exe`와 업스트림 설치 파일을 열 수 없습니다)
- **PATH**: `7za.exe` 또는 `7z.exe`가 PATH에 있으면 자동 감지합니다. `PORTABLEAPPS_7Z_PATH`로 절대 경로를 지정할 수도 있습니다
- 버전 21.07 이상

## 로컬 빌드

```powershell
# 전체 빌드: 업스트림 확인 → 다운로드 → 압축 해제 → 컴파일 → 패키징
.\build.ps1

# 기존 App/WorkBuddyAI를 재사용하고 재컴파일·재패키징만 수행
.\build.ps1 -SkipDownload
```

스크립트는 다음 순서로 동작합니다:

1. `App\AppInfo\appinfo.ini`에서 `ID` / `Name` / `PackageVersion` 읽기
2. 사용 가능한 7-Zip 감지 (기본은 `7za` 우선, NSIS 해제 시 자동으로 정식 `7z.exe`로 전환)
3. `https://www.workbuddy.ai/v2/update` 조회 후 업스트림 설치 파일을 내려받아 `App\WorkBuddyAI`에 압축 해제
4. PAL 템플릿과 `makensis`로 런처 `WorkBuddyAIPortable.exe` 컴파일
5. 순수 zip 생성 후 PAF를 `dist/`로 복사

선택 환경 변수: `PORTABLEAPPS_7Z_PATH`, `PORTABLEAPPS_MAKENSIS`.

## CI (GitHub Actions)

워크플로: [`.github/workflows/build.yml`](.github/workflows/build.yml)

트리거:

| 트리거 | 설명 |
| --- | --- |
| `workflow_dispatch` | 수동 실행. `force_build=true`를 넘기면 버전 차이를 무시하고 강제 재빌드 |
| `schedule` | 매주 월요일 02:00 UTC에 업스트림 업데이트 확인 |
| `main` 브랜치 `push` | 푸시 후 업스트림 새 버전 확인 |

```bash
# 명령줄에서 수동 실행 (gh 설치 및 로그인 필요)
gh workflow run build.yml -f force_build=true
```

저장소 화면의 **Actions → Build & Release WorkBuddyAIPortable → Run workflow**에서
`force_build`를 켜고 실행해도 됩니다.

참고: 기본적으로 업스트림 버전이 로컬 `PackageVersion`보다 높을 때만 실제 빌드가 수행되며,
그렇지 않으면 이후 단계가 모두 `skipped` 됩니다. 동일한 빌드를 중복 생성하지 않기 위한 의도된 동작입니다.
강제로 검증하려면 `force_build=true`를 사용하세요.

## 포터블 동작 원리

설정은 [`App\AppInfo\Launcher\WorkBuddyAIPortable.ini`](App/AppInfo/Launcher/WorkBuddyAIPortable.ini)에 있습니다:

- **데이터 리디렉션**: `WORKBUDDY_CONFIG_DIR` / `WORKBUDDY_USER_DATA_DIR` / `CODEBUDDY_CONFIG_DIR`로
  설정과 Electron `userData`를 `Data\`로 지정
- **홈 디렉터리 리디렉션**: `USERPROFILE` / `HOME`을 `Data\home`으로 지정하여 앱 내부에서
  `os.homedir()`로 파생되는 모든 기본 경로를 포괄
- **자동 업데이트 차단**: `WORKBUDDY_UPDATE_URL=http://127.0.0.1:9`를 도달 불가능한 로컬 포트로 지정하여
  업데이트 소스 검증을 즉시 실패시킴
  (빈 문자열로 설정하면 효과가 없습니다. falsy로 판정되어 기본 서버로 폴백합니다)
- **레지스트리**: HKCU 사용자 수준 키만 기록(`workbuddy://`, `buddy-app://` 프로토콜 연결, 시작 시 자동 실행),
  종료 시 정리
- **임시 디렉터리**: `TEMP` / `TMP`를 `Data\temp`로 지정

## GPU 크래시 완화

일부 환경에서 GPU 프로세스가 크래시하고(`child-process-gone exitCode=-1`) 이로 인해 렌더러도 함께
크래시 → 창이 파괴됨 → `window-all-closed` → 앱이 스스로 종료됩니다. 외부에서는 "잠시 쓰다 보면 꺼진다"로 보입니다.

런처는 소프트웨어 렌더링을 미리 강제합니다:

```ini
CommandLineArguments=--disable-gpu --disable-gpu-compositing --disable-direct-composition
```

하드웨어 가속을 되돌리려면(그래픽 성능 우선) 해당 줄을 비우면 됩니다.
이는 완화책일 뿐이며 근본 원인은 앱 또는 그래픽 드라이버 계층에 있습니다.

## 디렉터리 구조

```
WorkBuddyAIPortable/
├── App/
│   └── AppInfo/
│       ├── appinfo.ini              # PAF 메타데이터 (ID / 버전 / 카테고리)
│       ├── Launcher/
│       │   ├── WorkBuddyAIPortable.ini   # PAL 실행 설정 (리디렉션, 실행 인수)
│       │   └── Custom.nsh                # 사용자 정의 NSIS 훅
│       └── appicon*.png / .ico
├── vendor/
│   └── PortableApps.comLauncher_2.2.9.paf.exe   # 내장 런처, CI는 외부 네트워크 불필요
├── .github/workflows/build.yml      # CI: 빌드 + 릴리스
├── build.ps1                        # 로컬 원커맨드 빌드
└── dist/                            # 빌드 산출물 (버전 관리 제외)
```

`App\WorkBuddyAI\`(업스트림 프로그램 본체)와 `Data\`(사용자 데이터)는 git에 포함되지 않으며
빌드 스크립트 또는 실행 시 생성됩니다.

## 면책 조항

이 프로젝트는 포터블화를 위한 재패키징만 수행하며 업스트림 프로그램 본체를 수정하지 않습니다.
WorkBuddy AI 공식과 아무런 제휴 관계가 없습니다. WorkBuddy AI의 저작권은 각 권리자에게 있으며,
사용 시 공식 라이선스 조건을 따라주세요.
