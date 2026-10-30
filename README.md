<div align="center">
<img src="Resources/AppIcon.svg" width="96" alt="Mac Music Widget">

# Mac Music Widget — Safari YouTube

**macOS 우측 알림 센터의 정식 WidgetKit 위젯.**

Safari YouTube의 **썸네일·제목·재생/일시정지·이전·다음**을 표시합니다.
영상은 Safari에서 재생하며 위젯 안에는 영상 플레이어를 넣지 않습니다.

원작: **[Ignacio Martin Vazquez](https://github.com/ignasave)** · [MIT 라이선스](LICENSE)

</div>

> 개발 중인 MVP입니다. 자동 테스트, 서명된 1.2.1 앱 설치와 Safari의 실제 YouTube Music → 호스트 전달을 확인했습니다.
> 일반 YouTube 영상, 알림 센터 화면과 실제 재생 버튼의 전체 동작 검증은 남아 있습니다.
> [검증 결과와 미확인 항목](docs/testing/safari-mvp.md)을 먼저 확인하세요.

## 범위

- **Safari 일반 YouTube 영상**: `https://www.youtube.com/watch?v=…`의 제목, 썸네일, 재생/일시정지 상태.
- **Safari YouTube Music**: `https://music.youtube.com/`에서 현재 곡의 제목·아트워크·상태를 같은 확장으로 읽습니다. 주소에 영상 ID가 없어도 동작하며, JavaScript from Apple Events 설정이 필요 없습니다.
- **재생 제어**: 열려 있는 해당 Safari 탭만 조작합니다. 이전/다음은 YouTube 플레이어의 버튼이 사용 가능할 때만 활성화됩니다. 이전 버튼이 없는 일반 영상에서는 이전 이동을 제공하지 않습니다.
- **기존 음악 지원 유지**: Spotify·Apple Music 어댑터를 유지했습니다. Safari 포함 빌드의 YouTube Music은 확장을 사용하고, 음악 전용 빌드와 다른 브라우저는 기존 AppleScript 경로를 사용합니다. 기존 음악 앱과의 실제 회귀 확인은 수동 검증 항목입니다.
- **Instagram 제외**: 게시물, 릴스, 임베드, 하위 도메인에 접근하거나 메타데이터를 수집하지 않습니다. YouTube 최상위 페이지에만 확장 권한을 요청합니다.
- 광고 재생 중, Shorts, 다른 사이트의 YouTube 임베드, 비공개 브라우징은 MVP 지원 범위 밖입니다.
- 다른 스트리밍 사이트는 사이트별 메타데이터·권한·DRM 검증 후 확장합니다. 범용 스트리밍 지원으로 간주하지 마세요.
- Small/Medium 크기를 지원합니다. 플로팅 창·노치 UI·화면 캡처는 없습니다.

## 설치: Safari 확장 포함 빌드

macOS 14+, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 필요합니다.
Safari 17+를 기준으로 작성했습니다. Safari 확장과 호스트의 App Group 공유에는 적절한 Apple 서명과 entitlement 설정이 필요합니다.

```bash
git clone https://github.com/jh3779/mac-music-widget.git
cd mac-music-widget
git switch feat/safari-youtube-notification-widget
brew install xcodegen
xcodegen generate --spec project-safari.yml
open MacMusicWidget.xcodeproj
```

### Xcode 설정

1. 프로젝트의 `BUNDLE_ID_PREFIX`를 자신이 사용할 고유한 reverse-DNS 식별자로 바꿉니다. 예: `com.yourname.macmusicwidget`.
2. 세 타깃 `MacMusicWidgetHost`, `MacMusicWidgetExtension`, `SafariWebExtension`에 **같은 개발 Team**을 지정합니다. Automatic Signing을 사용합니다.
3. 호스트와 Safari 확장의 **Signing & Capabilities → App Groups**에 같은 그룹을 추가합니다. macOS 개인 설치에는 `TEAMID.<고유이름>` 형식을 사용할 수 있습니다. `group.<고유이름>` 형식은 계정에 등록하고 해당 그룹을 포함한 프로비저닝 프로필을 준비합니다.
4. 프로젝트 Build Settings의 `APP_GROUP_IDENTIFIER`를 그 값으로 바꿉니다. 호스트와 Safari 확장의 `MediaAppGroup` Info.plist 값 및 entitlement가 모두 이 설정을 참조합니다. 기본 `group.com.jh3779.macmusicwidget`을 다른 계정에서 그대로 사용하지 마세요.
5. `MacMusicWidgetHost` 스킴으로 빌드하고 실행합니다. 호스트 안에 WidgetKit 및 Safari 확장이 함께 포함됩니다.
6. 재생성하면 Xcode에서 직접 수정한 설정이 사라질 수 있습니다. 지속할 설정은 로컬 `project-safari.yml`이나 아래 명령의 환경값에 반영하세요. 개인 Team/프로필 파일을 PR에 커밋할 필요는 없습니다.

이 작업의 로컬 설치는 같은 Apple Development 인증서와 `TEAMID.<group name>` 형식으로 서명했습니다. 서명 없이 App Group을 쓸 수 있다고 가정하지 마세요.
[Apple의 App Group 설정 문서](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)를 참고하세요.

설정이 준비됐다면 명령으로 빌드할 수도 있습니다. 다음 값은 예시이며 실제 값으로 교체해야 합니다.

```bash
DEVELOPMENT_TEAM=YOURTEAMID \
APP_GROUP_IDENTIFIER=group.com.yourname.macmusicwidget \
BUNDLE_ID_PREFIX=com.yourname.macmusicwidget \
./build.sh --safari
```

앱은 `build/Mac Music Widget.app`에 생성됩니다. Finder로 `/Applications`에 복사하고 실행하세요.
`./build.sh --safari --install`은 기존 `/Applications/Mac Music Widget.app`을 교체하므로 기존 설치를 보관하려면 먼저 다른 곳에 복사하세요.
1.2.1은 이 작업의 Mac에서 `/Applications/Mac Music Widget.app`에 설치하고 실행했습니다. 개인 개발 서명이며 공증된 일반 배포 릴리스가 아닙니다. 다른 Mac의 설치·실행을 보증하지 않습니다. 앱 리소스에도 원본 MIT LICENSE를 포함합니다.

### Safari 권한

1. Safari → **설정 → 확장 프로그램**에서 **Mac Music Widget — Safari YouTube**를 켭니다.
2. `www.youtube.com`과 `music.youtube.com` 접근을 명시적으로 허용합니다. Safari는 권한 목록에서 둘을 `youtube.com`으로 묶어 표시할 수 있습니다. 실제 확장의 접근 대상은 이 두 호스트뿐입니다. 확장이 보이지 않으면 앱을 실행한 뒤 메뉴 막대의 음표 → **Safari Extension Settings…**를 선택합니다.
3. 설치·업데이트 후에는 이미 열린 YouTube/YouTube Music 탭을 한 번 새로고침하고 직접 재생합니다. Safari가 업데이트 전 content script의 연결을 끊을 수 있습니다.
4. 확장 툴바 팝업에서 Native bridge 상태를 확인합니다. 정상 표시는 네이티브 연결 확인이며, 호스트 실행이나 위젯 표시까지 검증한 것은 아닙니다.
5. 이 Safari 확장을 사용하는 일반 영상 및 YouTube Music 경로는 **Allow JavaScript from Apple Events가 필요하지 않습니다**. 이 설정은 음악 전용 빌드의 기존 Safari AppleScript 경로에만 필요합니다.

이 작업의 설치본은 **Allow Unsigned Extensions를 켜지 않고** 활성화했습니다. 설정이 필요한지 먼저 서명을 확인하세요. Safari 확장과 웹사이트 접근은 사용자 동의가 필요합니다. 개인정보 보호 브라우징 접근은 요청하거나 활성화하지 않습니다.

### 알림 센터에 추가

메뉴 막대 오른쪽 **날짜·시간 클릭 → 알림 센터 맨 아래 ‘위젯 편집’ → Mac Music Widget → Small 또는 Medium 추가**.
호스트는 음표 아이콘이 있는 백그라운드 앱으로 계속 실행되어야 합니다.
소스 메뉴에서 **Safari YouTube**를 고르면 다른 음악 앱의 Automation 권한 없이 일반 YouTube 경로를 확인할 수 있습니다.
`Auto`는 재생 중인 Safari YouTube → Spotify → Apple Music → YouTube Music 순으로 선택합니다.
여러 YouTube 탭은 재생 중인 탭을 우선하고, 같은 상태에서는 마지막으로 영상/재생 상태가 바뀐 탭을 고릅니다. 단순 heartbeat는 선택을 빼앗지 않습니다.

macOS는 같은 WidgetKit 위젯을 바탕화면에도 추가할 수 있습니다. 이 프로젝트의 설치 및 검증 대상은 **우측 알림 센터**입니다.

## 기존 음악 전용 빌드

```bash
./build.sh
```

이 기본 구성(`project.yml`)은 원본처럼 ad-hoc 서명과 로컬 통신을 사용하며 **Safari 일반 영상 확장은 포함하지 않습니다**.
새 Safari 기능에는 위의 `--safari` 구성이 필요합니다.

- Apple Music·Spotify: 최초 Automation 요청을 허용합니다.
- YouTube Music: 소스와 브라우저를 선택하고 해당 브라우저의 **Allow JavaScript from Apple Events**를 켭니다.
- Safari가 설치돼 있으면 최초 브라우저 선택 기본값으로 사용합니다. 저장된 선택은 유지합니다.
- 원본 호스트와 이 포크를 동시에 실행하면 로컬 포트 `47893`이 충돌합니다. 하나만 실행하세요.

## 갱신 및 제어 한계

- 확장은 변경 이벤트와 약 2초 간격의 heartbeat로 메타데이터를 전달합니다. 호스트도 약 2초 간격으로 읽습니다. Safari가 탭을 절전·중지하면 길어질 수 있습니다.
- **이 간격이 화면 갱신 주기는 아닙니다.** 호스트는 일반 갱신 요청을 최소 30초 간격으로 묶지만, 실제 위젯 갱신은 macOS가 지연하거나 생략할 수 있습니다. 제목·썸네일·상태가 즉시 따라오는 실시간 플레이어로 보장하지 않습니다.
- 제어 직후 상태 변경에는 추가 갱신을 요청합니다. 버튼 명령은 다음 heartbeat에 전달되며, 8초가 지나면 폐기됩니다. 빠르게 여러 번 누르면 마지막 명령으로 합쳐질 수 있습니다. 성공 응답/재시도 보장은 없으며, 실제 상태 변화를 확인해야 합니다.
- 위젯에 보이던 문서·영상이 호스트의 현재 대상과 다르면 조작을 거절합니다. 갱신 전의 오래된 버튼이 다른 영상을 조작하지 않습니다.
- 호스트는 45초 동안 새 정보가 없으면 해당 데이터를 선택·제어 대상에서 제외합니다. 이 짧은 브라우저 유효 기간이 위젯의 제목·이미지를 지우지는 않습니다.
- 위젯은 마지막 관측 내용을 표시하며 즉시 갱신을 보장하지 않습니다. 5분 이상 갱신되지 않은 Safari 정보에는 **업데이트 대기**를 표시하고 재생 버튼을 비활성화합니다. **↻ 새로 고침**으로 최신 정보를 요청할 수 있습니다. 시스템이 렌더링을 늦추는 동안 마지막 내용이 남을 수 있습니다.
- 1.2.0에서 45초 뒤 `Safari update unavailable`만 남던 표시 오류를 1.2.1에서 수정했습니다. 이전 화면이 남으면 위젯을 다시 추가해 설치된 최신 버전을 선택하고, Safari 탭도 새로고침하세요.
- Safari의 자동재생 정책 때문에 `play()`가 거절될 수 있습니다. 이때 Safari에서 직접 재생한 후 다시 확인하세요.
- CDN에서 썸네일을 제공하지 않는 영상이나 네트워크 오류는 기본 이미지로 표시됩니다. 로그인·DRM·지역 제한을 우회하지 않습니다.

Apple은 일반적으로 자주 보는 위젯에 하루 40–70회의 갱신 예산을 설명하며, 정확한 간격은 사용 패턴과 시스템 조건에 따라 달라집니다.
[WidgetKit 갱신 문서](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

## 데이터 흐름과 개인정보

```text
허용된 Safari YouTube 탭
  → content script → background → Safari native extension
  → App Group: 프로필/탭별 최신 스냅샷
  → Host 앱: 소스 선택 및 갱신 요청
  → 127.0.0.1:47893 → WidgetKit Timeline → 알림 센터

위젯 버튼 → Host → App Group의 짧은 수명 명령
  → 다음 native 응답 → 정확한 문서/영상이 일치하는 Safari 탭
```

확장은 제목·채널/아티스트·미디어 식별자·재생 상태·버튼 가능 여부·무작위 문서 ID와 필요한 아트워크 주소만 공유합니다. 쿠키, 로그인 정보, 전체 방문 URL, 영상 바이트를 수집하지 않습니다.
일반 영상 썸네일은 검증된 영상 ID로 만든 `i.ytimg.com` HTTPS 주소를 사용합니다. YouTube Music은 곡 변경마다 생성한 임시 ID와 `googleusercontent.com`/`ytimg.com` 계열의 검증된 HTTPS 아트워크만 허용합니다. Instagram 수집 경로와 화면 캡처 코드는 없습니다.
로컬 App Group에는 각 탭의 최신 스냅샷만 저장합니다. 닫힘 이벤트로 제거하고, 새 데이터 수신 시 만료 스냅샷을 정리합니다. 강제 종료·권한 철회 후 수신이 완전히 끊기면 이전 파일이 디스크에 남을 수 있으나 만료 데이터는 표시 대상으로 선택하지 않습니다.
로컬 HTTP는 웹 Origin/Referer 요청, 잘못된 Host 및 GET 제어를 거절합니다. 같은 사용자 권한의 로컬 프로세스에 대한 인증 경계는 아니며, 원본의 loopback 구조를 유지합니다.

## 검증

```bash
swift test --enable-code-coverage
node --test Tests/JavaScript/*.test.cjs
xcodegen generate --spec project-safari.yml
xcodebuild -project MacMusicWidget.xcodeproj -scheme MacMusicWidgetHost \
  -configuration Debug -derivedDataPath .build/xcode-safari CODE_SIGNING_ALLOWED=NO build
```

마지막 명령은 **서명 없는 컴파일 검증**입니다. 실행 가능한 Safari 배포본을 보증하지 않습니다.
자동 테스트, 전체 수동 검증표, 현재 결과는 [검증 문서](docs/testing/safari-mvp.md)에 있습니다.
접근법 비교(시스템 Now Playing, 비공개 API, Safari 확장, AppleScript)와 원본 분석은 [아키텍처 문서](docs/architecture.md)를 참고하세요.

## 라이선스

[MIT](LICENSE) © 2026 [Ignacio Martin Vazquez](https://github.com/ignasave).
원본 LICENSE 전체와 저작권 고지를 유지합니다. [원본 저장소](https://github.com/ignasave/mac-music-widget)의 README도 [별도 보관](docs/upstream-README.md)했습니다.
