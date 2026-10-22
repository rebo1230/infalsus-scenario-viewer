# In Falsus 시나리오 뷰어 (비공식 팬 도구)

> **In Falsus의 대사·이름·이미지 등 모든 저작권은 lowiro에 있습니다.**
> 이 도구는 lowiro와 관계없는 비공식 팬 도구입니다.

lowiro의 게임 *In Falsus* 스토리를 타임라인·화자·챕터별로 읽는 개인용 뷰어입니다.
여러 언어를 나란히 보고, 검색하고, 나만의 노트·주석·용어집을 남길 수 있습니다.

- 뷰어 버전: 2026-10-22
- 확인한 게임 버전: In Falsus v1.0.7 (한국어 패치 설치/미설치 모두)
- 뷰어 화면(메뉴·버튼·안내문)은 **한국어로만** 되어 있습니다. 대사는 한국어·일본어·영어·번체·간체 중에서 골라 볼 수 있습니다.
- 자세한 작동 방식은 [`HOW_IT_WORKS.md`](HOW_IT_WORKS.md)에 있습니다.

## 다운로드

**[⬇ 릴리스에서 zip 받기](../../releases)**

## 사용법 (Windows)

1. Steam으로 *In Falsus*를 설치해 둡니다.
2. 이 폴더를 원하는 곳에 압축 풀기 합니다. (예: `D:\infalsus-viewer`)
   경로가 너무 길거나 깊은 곳은 피해 주세요.
3. **`start.bat`을 더블클릭**합니다.
   - 처음 한 번은 설치된 게임에서 데이터를 만듭니다 (1~3분).
   - 이미지(곡 자켓, 연출 이미지, CG)도 불러올지 물어봅니다. **Y**를 누르면 몇 분 더 걸립니다 (PC에 따라 5~10분).
   - 끝나면 브라우저가 자동으로 열립니다. 다음부터는 바로 열립니다.
4. 게임이 업데이트되었거나 한국어 패치를 새로 설치했으면 **`rebuild.bat`**을 실행하세요.

게임 폴더를 자동으로 못 찾으면 창에서 설치 폴더를 물어봅니다.
Steam에서 In Falsus 우클릭 → 관리 → 로컬 파일 보기로 열린 폴더 주소를 붙여넣으면 됩니다.

### 한국어

- 한국어 팬 패치가 **게임에 설치되어 있으면** 한국어를 게임에서 바로 가져옵니다.
- 패치가 설치되어 있지 않으면 한국어 칸은 비고 일본어·영어·중국어만 나옵니다. 패치를 설치한 뒤 `rebuild.bat`을 실행하면 한국어가 들어갑니다.
  팬 번역 저장소를 따로 받아 두었다면 `build.ps1 -Repo "저장소 폴더"`로 지정할 수도 있습니다.
- 한국어 패치가 설치된 게임은 영어 칸 일부(챕터 이름, RMI 분포 이름, 인카운터 이름)가 패치로 덮여 있어 영어로는 표시되지 않습니다. 대사는 영어도 정상입니다.

### 이미지

이미지(곡 자켓, 연출 이미지, CG)는 **선택**입니다. 처음 실행할 때 Y를 고르면 게임 안의 압축 텍스처를 풀어서 함께 보여 줍니다.
N을 골라도 대사·회차·연출 위치는 모두 나오고, 나중에 `rebuild.bat`에서 Y를 고르면 추가할 수 있습니다.
명령으로 직접 만들 때는 `build.ps1 -Images`입니다.
한국어 패치가 설치된 게임에서는 연출 이미지의 영어판 일부가 패치로 한국어 그림으로 바뀌어 있습니다.

## 이 폴더에 들어 있는 것 / 없는 것

| 들어 있음 | 들어 있지 않음 |
|---|---|
| 뷰어 (`site/index.html`, `memo.js`, `memo.css`) | 게임 대사·문구 (대본, 이름, 챕터 제목, UI 문구) |
| 데이터 만들기 (`build.ps1`, `unityread.cs`) | 게임 이미지·CG·곡 자켓·로고 |
| 실행 파일 (`start.bat`, `rebuild.bat`), 로컬 서버 (`serve.ps1`, 선택) | 음악·효과음·영상 |

화면에 나오는 모든 내용은 **사용자가 자기 컴퓨터에서**, **자기가 가진 게임 파일**로 만든 것입니다.
게임 폴더는 읽기만 하고 아무것도 바꾸지 않습니다.

## 만들어지는 파일 — 공유 금지

아래는 게임 내용을 담은 파일이라 **다른 사람과 공유하거나 올리지 마세요.**

- `site\data.js` (대사·이름 등), `site\jackets\`, `site\textimg\`, `site\cg\`
- `out\` (게임에서 꺼낸 데이터, 대본)

## 문제 해결

- **브라우저가 열렸는데 화면이 비어 있음**: `start.bat`을 다시 실행하거나, PowerShell에서
  `serve.ps1`을 실행한 뒤 `http://localhost:8765/`로 열어 보세요.
- **메모가 사라짐**: 메모·주석은 브라우저에만 저장됩니다. 노트 패널의 내보내기로 백업해 두세요.

## 기술 메모

- `build.ps1`은 게임 폴더의 Addressables 번들(UnityFS, LZ4)과 `resources.assets`를 `unityread.cs`로 직접 읽습니다.
  대본 파일(`StreamingAssets\sam\*`)은 간단한 XOR로 인코딩되어 있어 읽을 때 풀어 사용하며, 결과는 `out\_scripts`에만 저장됩니다.
- 메모·주석·용어 기능은 브라우저 `localStorage`에만 저장되고 어디로도 전송되지 않습니다.

---

## English summary

**All rights to In Falsus, including its text, names and images, belong to lowiro. Unofficial fan tool, not affiliated with lowiro.**

Download: [Releases](../../releases)

A personal reader for the *In Falsus* story (timeline / speaker / arc views, several languages side by side,
private notes and annotations). **The viewer's interface is in Korean only**; the story text itself can be shown in
Korean, Japanese, English, Traditional and Simplified Chinese. Unzip, then double-click `start.bat` ("start"): it finds the Steam install, reads the
game's own data files (read-only) and opens the viewer in your browser. Run `rebuild.bat` after a game update. Korean text is taken from the Korean fan patch when it is installed in the game (or from a local copy of the translation via `build.ps1 -Repo`); nothing is downloaded.

This folder contains **code only**: no game text, images, music, logos or video. The generated files
(`site\data.js`, `site\jackets`, `site\textimg`, `site\cg`, `out\`) contain game content and must not be shared.
Images (song jackets, story text images, CGs) are optional: answer Y on first run, or use `build.ps1 -Images`; this decodes the game's BC7 textures and takes several minutes.
Technical note: the story script files are XOR-encoded in the game; `build.ps1` decodes them locally (into `out\_scripts`).
