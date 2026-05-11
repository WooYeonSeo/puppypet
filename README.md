# PuppyPet 🐶

macOS 메뉴바 위에서 함께 일하는 데스크탑 펫. 작업 중 휴식을 챙겨주고, 캘린더 일정과 Claude Code 작업 흐름까지 옆에서 알려줍니다.

## 기능

- **메뉴바 펫** — 알파 채널 영상으로 움직이는 강아지, 자유롭게 드래그 (메뉴바·Dock 위도 OK)
- **클릭 → 멍!** — 강아지를 누르면 랜덤 한 줄 멘트 말풍선
- **작업 리마인더** — 일정 시간 단위로 휴식·스트레칭 알림 말풍선
- **Google Calendar 연동** — 일정 10분 전 자동 말풍선, 토큰 만료 시 자동 해제 + 안내
- **Claude Code 워처** — `~/.claude/projects/**/*.jsonl`을 감시해
  - 진행 중일 때 💭 표시
  - 턴 끝나면 _"…클코 작업 끝났다멍"_ 말풍선 → 탭하면 마지막 응답 본문 팝오버

## 셋업

요구사항: macOS 14+, Xcode 15+

```bash
open puppy.xcodeproj
```

Xcode에서 빌드(`⌘R`)하면 메뉴바 우측에 강아지가 뜹니다.

### Google Calendar (선택)

연동하려면 강아지 **우클릭 → "Google 캘린더 연결"**.
ASWebAuthenticationSession + PKCE 플로우로 로그인하며, 토큰은 Keychain에 저장됩니다.

> 자체 OAuth 클라이언트를 쓰려면 `puppy/Services/GoogleAuth.swift`의 `clientID` / `urlScheme`을 본인 값으로 교체하고, Info.plist의 URL Scheme도 동일하게 등록하세요. 스코프는 `calendar.events.readonly`.

## 프로젝트 구조

```
puppy/
├── puppyApp.swift          # @main, AppDelegate, 서비스 와이어링
├── MenuBar/                # NSStatusItem 컨트롤러
├── Window/                 # PetPanel (NSPanel) + 컨트롤러
├── Views/                  # PetView, SpeechBubbleView, 영상/스프라이트 뷰
├── Services/
│   ├── WorkTimer.swift         # 작업 시간 추적
│   ├── ReminderEngine.swift    # 휴식 리마인더
│   ├── GoogleAuth.swift        # OAuth (PKCE)
│   ├── CalendarService.swift   # Google Calendar API
│   ├── CalendarReminder.swift  # 일정 10분 전 알림
│   └── TranscriptWatcher.swift # Claude Code jsonl 감시
├── Storage/                # Keychain·UserDefaults 헬퍼
└── Resources/              # 영상·스프라이트·메시지 풀
```
