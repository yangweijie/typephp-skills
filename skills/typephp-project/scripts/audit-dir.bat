@echo off
rem TypePHP compatibility audit for PHP code you did not write.
rem
rem   audit-dir.bat <dir-or-file>... [--mode lib^|bin] [--max-exclusions N]
rem   audit-dir.bat <project-dir-with-project.yml>
rem
rem Why this exists: the obvious approach (point check_code at each file) is wrong for
rem library code, because check_code always runs bin mode, and bin mode demands a global
rem main(). Every library file gets rejected and it reads like a compatibility verdict.
rem This script runs tpc directly, in lib mode by default, and compiles whole directories
rem so inheritance and traits resolve.
rem
rem A directory containing project.yml is compiled through the manifest (whole-app mode)
rem instead of scanning subdirectories: an app's php-src may hold only .stub.php files,
rem and its sources may include cpp-src.
rem
rem --max-exclusions enumerates further offenders by removing one at a time, but marks
rem the results CONTAMINATED: excluding a file causes cascade failures elsewhere.

setlocal EnableDelayedExpansion
set MODE=lib
set MAX_EXCL=0
set N=0

:parse
if "%~1"=="" goto parsed
set "ARG=%~1"
if /i "!ARG!"=="-h" goto usage
if /i "!ARG!"=="--help" goto usage
if /i "!ARG!"=="--mode" (
    set "MODE=%~2"
    shift & shift & goto parse
)
if /i "!ARG!"=="--max-exclusions" (
    set "MAX_EXCL=%~2"
    shift & shift & goto parse
)
if /i "!ARG:~0,7!"=="--mode=" (
    set "MODE=!ARG:~7!"
    shift & goto parse
)
if /i "!ARG:~0,17!"=="--max-exclusions=" (
    set "MAX_EXCL=!ARG:~17!"
    shift & goto parse
)
set /a N+=1
set "TARGET_!N!=!ARG!"
shift
goto parse

:parsed
if "%N%"=="0" goto usage

rem Prefer the release package: the repo-root build has been observed to fail with
rem 0xC0000139 on Windows.
set "TPC="
if exist "%PHP_HOME%\tpc.exe" set "TPC=%PHP_HOME%\tpc.exe"
if not defined TPC (
    where tpc >nul 2>&1 && set "TPC=tpc"
)
if not defined TPC (
    echo tpc not found; set PHP_HOME or put tpc on PATH
    exit /b 2
)

set "WORK=%TEMP%\typephp-audit-%RANDOM%%RANDOM%"
mkdir "%WORK%" 2>nul
echo tpc:    %TPC%
echo mode:   %MODE%
echo.

for /L %%i in (1,1,%N%) do call :audit "!TARGET_%%i!"

rmdir /s /q "%WORK%" 2>nul

echo Reading the result
echo   PASS  whole-directory compile succeeded: no known incompatibility.
echo   FAIL  compile stopped at the first problem. Real for a directory; a single file
echo         may still be a false positive -- see below.
echo   N/A   nothing compilable was collected ^(wrong dir, or .stub.php only^).
echo.
echo Do not trust per-file FAILs saying "Trait X not found" or "inherits from a
echo non-existent class": those resolve when the directory is compiled together.
echo Measured on psr/log: 2/8 files fail per-file, 0/8 fail as a directory.
exit /b 0

:usage
echo usage: audit-dir.bat ^<dir-or-file^>... [--mode lib^|bin] [--max-exclusions N]
echo        audit-dir.bat ^<project-dir-with-project.yml^>   (whole-app mode)
exit /b 2

rem ================================================================ :audit
:audit
set "TGT=%~1"
if not exist "%TGT%" (
    echo SKIP  %TGT%  ^(does not exist^)
    goto :eof
)

set FILES=0
for /f "delims=" %%f in ('dir /s /b "%TGT%\*.php" 2^>nul') do set /a FILES+=1

rem ---- whole-app mode ----------------------------------------------------
if exist "%TGT%\project.yml" (
    "%TPC%" --dry "%TGT%\project.yml" --no-progress --build-dir "%WORK%\bd-app" > "%WORK%\o.txt" 2>&1
    findstr /b /c:"Fatal error" "%WORK%\o.txt" >nul
    if not errorlevel 1 (
        echo FAIL  %TGT%\project.yml  ^(whole app, %FILES% files^)
        set "FIRST="
        for /f "delims=" %%l in ('findstr /b /c:"Fatal error" "%WORK%\o.txt"') do (
            if not defined FIRST (
                set "FIRST=%%l"
                echo       !FIRST!
            )
        )
        goto :eof
    )
    findstr /b /c:"No valid source file found" "%WORK%\o.txt" >nul
    if not errorlevel 1 (
        echo N/A   %TGT%\project.yml  ^(no compilable source^)
        goto :eof
    )
    echo PASS  %TGT%\project.yml  ^(whole app, %FILES% files^)
    goto :eof
)

rem ---- stub-only directory -----------------------------------------------
set STUBS=0
for /f "delims=" %%f in ('dir /s /b "%TGT%\*.stub.php" 2^>nul') do set /a STUBS+=1
set /a REAL=%FILES%-%STUBS% 2>nul
if %REAL% LEQ 0 (
    echo N/A   %TGT%  ^(%FILES% file^(s^), all .stub.php -- nothing to compile^)
    goto :eof
)

rem ---- plain directory / single file -------------------------------------
"%TPC%" --dry --mode=%MODE% "%TGT%" --no-progress --build-dir "%WORK%\bd-a" > "%WORK%\o2.txt" 2>&1
findstr /b /c:"No valid source file found" "%WORK%\o2.txt" >nul
if not errorlevel 1 (
    echo N/A   %TGT%  ^(no compilable source^)
    goto :eof
)
findstr /b /c:"Fatal error" "%WORK%\o2.txt" >nul
if errorlevel 1 (
    echo PASS  %TGT%  ^(%FILES% files^)
    goto :eof
)

echo FAIL  %TGT%  ^(%FILES% files^)
set "FIRST="
for /f "delims=" %%l in ('findstr /b /c:"Fatal error" "%WORK%\o2.txt"') do (
    if not defined FIRST (
        set "FIRST=%%l"
        echo       !FIRST!
    )
)

if %MAX_EXCL% LEQ 0 goto :eof
if not exist "%TGT%\" goto :eof

echo       enumerating more via exclusion ^(results are CONTAMINATED^)...
if exist "%WORK%\w" rmdir /s /q "%WORK%\w"
xcopy /e /i /q /y "%TGT%" "%WORK%\w" >nul 2>&1

set IDX=0
:exclLoop
set /a IDX+=1
if %IDX% GTR %MAX_EXCL% goto :exclDone
"%TPC%" --dry --mode=%MODE% "%WORK%\w" --no-progress --build-dir "%WORK%\bd-b" > "%WORK%\o3.txt" 2>&1
findstr /b /c:"Fatal error" "%WORK%\o3.txt" >nul
if errorlevel 1 (
    echo       [!IDX!] no more errors
    goto :exclDone
)

rem Message shape: "Fatal error: <text> in <abs path>:<line>".
rem Take the text after the LAST " in ", cut the prefix up to the copy dir marker "\w\",
rem then drop the trailing ":<digits>". Do it all with string ops: splitting on ":"
rem would also eat a drive letter.
set "LINE="
for /f "delims=" %%l in ('findstr /b /c:"Fatal error" "%WORK%\o3.txt"') do (
    if not defined LINE set "LINE=%%l"
)
set "P=!LINE:* in =!"
set "P=!P:\w\=#!"
for /f "tokens=1,* delims=#" %%a in ("!P!") do set "P=%%b"
set "TAIL=!P!"
rem strip one trailing ":<digits>"
for /f "delims=" %%a in ("!TAIL!") do (
    set "T=%%~a"
)
set "STEM=!T!"
set "DIGS="
:popDigit
if "!STEM!"=="" goto :haveTail
set "LAST=!STEM:~-1!"
if "!LAST!"=="0" goto :gotDigit
if "!LAST!"=="1" goto :gotDigit
if "!LAST!"=="2" goto :gotDigit
if "!LAST!"=="3" goto :gotDigit
if "!LAST!"=="4" goto :gotDigit
if "!LAST!"=="5" goto :gotDigit
if "!LAST!"=="6" goto :gotDigit
if "!LAST!"=="7" goto :gotDigit
if "!LAST!"=="8" goto :gotDigit
if "!LAST!"=="9" goto :gotDigit
goto :haveTail
:gotDigit
set "DIGS=!LAST!!DIGS!"
set "STEM=!STEM:~0,-1!"
goto :popDigit
:haveTail
rem STEM now has the digits removed; it still ends with ":" before the line number.
set "TAIL=!STEM!"
if "!TAIL:~-1!"==":" set "TAIL=!TAIL:~0,-1!"
set "TAIL=!TAIL:/=\!"
if "!TAIL!"=="" (
    echo       [!IDX!] cannot parse path; stopping
    goto :exclDone
)
if not exist "%WORK%\w\!TAIL!" (
    echo       [!IDX!] !TAIL! already gone ^(cascade^); stopping
    goto :exclDone
)
echo       [!IDX!] exclude !TAIL!
del /q "%WORK%\w\!TAIL!" >nul 2>&1
goto :exclLoop

:exclDone
echo       ^^ each exclusion can cause cascades; confirm each file individually
goto :eof
