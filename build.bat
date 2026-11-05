@echo off
setlocal
REM Usage: build.bat [pull [branch]] [run [editor]]
REM   pull          get the latest version of the current branch from GitHub first
REM   pull branch   switch to that branch and get its latest version
REM   run           start the game in VICE after building
REM   run editor    start CITYEDIT in VICE instead
REM Examples: build.bat run / build.bat pull run / build.bat run editor

if /I not "%~1"=="pull" goto pull_done
shift
where git >nul 2>nul
if errorlevel 1 (
    echo git not found. Install Git for Windows or put git.exe on PATH.
    exit /b 1
)
git fetch origin
if errorlevel 1 exit /b 1
set "PULL_BRANCH="
if not "%~1"=="" if /I not "%~1"=="run" set "PULL_BRANCH=%~1"
if defined PULL_BRANCH shift
REM git may replace this file, so update and restart the script on one line.
if defined PULL_BRANCH (git checkout "%PULL_BRANCH%" && git pull --ff-only && "%~f0" %1 %2) else (git pull --ff-only && "%~f0" %1 %2)
echo Could not update from GitHub. Commit or stash your local changes first.
exit /b 1
:pull_done
REM Set KICKASS_JAR to the full path of KickAss.jar if it is not in this folder.
if not defined KICKASS_JAR if exist "..\KickAss.jar" set "KICKASS_JAR=..\KickAss.jar"
if not defined KICKASS_JAR set "KICKASS_JAR=KickAss.jar"
if not exist "%KICKASS_JAR%" (
    echo KickAss.jar not found. Set KICKASS_JAR to its full path.
    exit /b 1
)

if not exist build mkdir build
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
if not defined JAVA_EXE set "JAVA_EXE=java"
REM -odir is relative to the source file, so ..\build is this folder's build.
"%JAVA_EXE%" -jar "%KICKASS_JAR%" "src\worldcities.asm" -odir ..\build -symbolfile
if errorlevel 1 exit /b 1
"%JAVA_EXE%" -jar "%KICKASS_JAR%" "src\cityedit.asm" -odir ..\build
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "prepare_data.ps1"
if errorlevel 1 exit /b 1

if not defined C1541_EXE set "C1541_EXE=c1541"
where "%C1541_EXE%" >nul 2>nul
if errorlevel 1 (
    echo c1541.exe not found. Set C1541_EXE to its full path.
    exit /b 1
)

REM The disk is made fresh each time from data\cities.csv and assets\worldmap.png.
REM Disk filenames must be lowercase: c1541 stores uppercase ASCII as shifted
REM PETSCII, which the programs' LOAD calls ("CITIES", "WORLDMAP") never match.
if exist "build\worldcities.d64" del "build\worldcities.d64"
"%C1541_EXE%" -format "worldcities,64" d64 "build\worldcities.d64" -write "build\worldcities.prg" worldcities -write "build\cityedit.prg" cityedit -write "build\cities.prg" cities -write "build\worldmap.prg" worldmap
if errorlevel 1 exit /b 1
REM The title picture is optional: without assets\title.png the game shows a text title.
if exist "assets\title.png" (
    "%C1541_EXE%" "build\worldcities.d64" -write "build\titlescr.prg" titlescr -write "build\titlebmp.prg" titlebmp
    if errorlevel 1 exit /b 1
)

echo Built build\worldcities.prg and build\worldcities.d64
if /I not "%~1"=="run" goto :eof
if /I "%~2"=="editor" (
    x64sc -8 "build\worldcities.d64" -autostart "build\cityedit.prg"
) else (
    x64sc -8 "build\worldcities.d64" -autostart "build\worldcities.prg"
)
