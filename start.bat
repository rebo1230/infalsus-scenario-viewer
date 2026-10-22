@echo off
chcp 65001 >nul
cd /d "%~dp0"
if exist "site\data.js" goto open
echo.
echo  처음 실행입니다. 설치된 게임에서 데이터를 만듭니다.
echo.
set IMG=
choice /c YN /n /m " 이미지(곡 자켓, 연출 이미지, CG)도 불러올까요? 5~10분 정도 더 걸립니다. [Y/N] "
if errorlevel 2 (set IMG=) else (set IMG=-Images)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %IMG%
if not errorlevel 1 goto open
echo.
echo  게임 설치 폴더를 자동으로 찾지 못했을 수 있습니다.
echo  Steam에서 In Falsus 우클릭 - 관리 - 로컬 파일 보기 로 연 폴더의 주소를 복사해 붙여넣고 Enter를 누르세요.
set /p GAMEDIR= 설치 폴더: 
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Game "%GAMEDIR%" %IMG%
if errorlevel 1 (
  echo.
  echo  데이터를 만들지 못했습니다. 위 메시지를 확인해 주세요.
  pause
  exit /b 1
)
:open
start "" "%~dp0site\index.html"