@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  게임이 업데이트되었거나, 한국어 패치를 새로 설치했거나, 이미지를 추가하고 싶을 때 실행하세요.
echo  데이터를 처음부터 다시 만듭니다.
echo.
if exist "site\data.js" del /q "site\data.js"
call "%~dp0start.bat"