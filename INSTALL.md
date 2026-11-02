# How to install

이 저장소(`nanhyang9/gridsnap`)의 소스로 GridSnap을 빌드해 Mac에 설치하고, 코드가 바뀐 뒤 다시 설치하는 방법입니다.

Homebrew나 원본 저장소(`konieczkow/gridsnap`) Releases에서 받는 앱은 원본 버전입니다. 이 저장소에서 추가한 기능(창 흔들기 레이아웃, 패널 색 설정 등)은 들어 있지 않으니, 이 문서대로 직접 빌드해야 합니다.

## 준비물 (처음 한 번)

- macOS 14 이상, Apple Silicon 또는 Intel
- **Xcode Command Line Tools** (macOS 26 SDK 포함 버전). `git`도 여기에 들어 있습니다.

터미널을 열고 확인합니다.

```bash
git --version
```

버전이 나오지 않으면 설치합니다.

```bash
xcode-select --install
```

Homebrew로 GridSnap을 설치한 적이 있다면 먼저 지웁니다. 그대로 두면 나중에 `brew upgrade`가 직접 빌드한 앱을 원본 버전으로 덮어씁니다.

```bash
brew uninstall --cask gridsnap
```

## 처음 설치

1. 저장소를 내려받을 위치로 이동합니다. 예시는 홈 폴더의 `Projects`입니다.

   ```bash
   mkdir -p ~/Projects && cd ~/Projects
   ```

2. 저장소를 복제하고 폴더로 들어갑니다. 저장소가 비공개라면 GitHub 로그인을 요구하며, 비밀번호 칸에는 계정 비밀번호 대신 Personal Access Token을 넣습니다(GitHub › Settings › Developer settings › Personal access tokens).

   ```bash
   git clone https://github.com/nanhyang9/gridsnap.git
   ```

   ```bash
   cd gridsnap
   ```

3. 빌드하고 `/Applications`에 설치합니다. 출력이 `installed /Applications/GridSnap.app`으로 끝나면 성공입니다.

   ```bash
   ./build.sh install
   ```

4. 실행합니다.

   ```bash
   open /Applications/GridSnap.app
   ```

5. **손쉬운 사용(Accessibility)** 권한을 줍니다. 요청 창이 뜨면 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 GridSnap을 켭니다. 메뉴 막대 아이콘의 **Grant Accessibility…** 항목으로도 그 화면을 열 수 있습니다. 권한을 켜면 1초쯤 뒤 저절로 동작을 시작하며, 다시 실행할 필요는 없습니다.

## 다시 설치 (코드가 바뀐 뒤)

`gridsnap` 폴더에서 차례로 실행합니다.

1. 실행 중인 GridSnap을 종료합니다. 메뉴 막대 아이콘 › **Quit GridSnap**을 눌러도 됩니다.

   ```bash
   pkill -x GridSnap
   ```

2. 최신 `master`를 받습니다.

   ```bash
   git checkout master
   ```

   ```bash
   git pull origin master
   ```

3. 빌드하고 설치합니다.

   ```bash
   ./build.sh install
   ```

4. 예전 권한 기록을 지웁니다. 아래 [권한을 매번 다시 줘야 하는 이유](#권한을-매번-다시-줘야-하는-이유)의 인증서를 만들어 두었다면 이 단계는 건너뜁니다.

   ```bash
   tccutil reset Accessibility com.zerodivisionerror.gridsnap
   ```

5. 실행하고, 권한 요청이 뜨면 손쉬운 사용 목록에서 GridSnap을 켭니다.

   ```bash
   open /Applications/GridSnap.app
   ```

## 권한을 매번 다시 줘야 하는 이유

macOS는 손쉬운 사용 권한을 앱의 **코드 서명**에 묶어 둡니다. 인증서 없이 빌드하면 매번 서명이 새로 만들어지므로, 시스템 설정에는 GridSnap이 켜져 있는 것처럼 보여도 새 빌드에는 권한이 없습니다. 그러면 그리드 단축키도, 창 흔들기도 동작하지 않습니다. 그래서 다시 설치할 때마다 4–5단계가 필요합니다.

자체 서명 인증서를 한 번 만들어 두면 빌드해도 서명이 유지되어 권한을 다시 줄 필요가 없습니다.

1. **키체인 접근**(Keychain Access)을 엽니다. Spotlight(⌘Space)에서 검색하면 됩니다.
2. 메뉴 막대에서 키체인 접근 › 인증서 지원 › 인증서 생성…(Keychain Access › Certificate Assistant › Create a Certificate)을 고릅니다.
3. 이름은 `GridSnap Dev`, 인증서 유형은 **코드 서명**(Code Signing)으로 하고 만듭니다.
4. 다음부터 `./build.sh`가 이 인증서를 알아서 찾아 씁니다. 빌드 출력의 `signed:` 뒤에 `GridSnap Dev`가 보이면 적용된 것입니다.

인증서를 만든 직후 첫 빌드는 서명이 바뀌므로, 그때 한 번만 4–5단계를 더 합니다.

## 문제가 생기면

**그리드 단축키(기본 ⌃⌥D)가 동작하지 않을 때**
메뉴 막대의 GridSnap 아이콘을 눌러 보세요. 맨 위에 **Grant Accessibility…**가 보이면 권한 문제입니다. 다시 설치 4–5단계를 하세요.

**메뉴 막대에 아이콘이 아예 없을 때**
앱이 실행되자마자 꺼졌을 수 있습니다. 터미널에서 직접 실행해 출력되는 메시지를 확인합니다.

```bash
/Applications/GridSnap.app/Contents/MacOS/GridSnap
```

**새로 빌드한 앱이 설치됐는지 모를 때**
`./build.sh install`의 마지막 줄이 `installed /Applications/GridSnap.app`인지 확인하세요. 빌드 중 오류가 나면 설치 단계까지 가지 않고, 예전 앱이 그대로 남습니다.

**창 흔들기 패널이 뜨지 않을 때**
1. 메뉴 막대 GridSnap 메뉴에서 **Shake Window for Layouts**에 체크 표시가 있는지 봅니다.
2. 그래도 안 되면 진단 로그를 켭니다.

   ```bash
   defaults write com.zerodivisionerror.gridsnap debugShake -bool true
   ```

3. GridSnap을 종료했다가 다시 엽니다.
4. 다른 터미널 창에서 로그를 띄워 둔 채로 창 제목 막대를 잡고 흔들어 봅니다. `shake:`로 시작하는 줄을 보면 어디서 막혔는지 알 수 있습니다. 멈출 때는 Ctrl+C를 누릅니다.

   ```bash
   log stream --predicate 'process == "GridSnap"'
   ```

5. 다 봤으면 진단 로그를 끄고 GridSnap을 다시 엽니다.

   ```bash
   defaults delete com.zerodivisionerror.gridsnap debugShake
   ```
