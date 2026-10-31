@echo off
rem TypePHP preflight for Windows — answer "can this machine build?" before blaming PHP code.
rem Usage: preflight.bat [project-dir]
setlocal EnableDelayedExpansion
set FAIL=0

set PROJ=%~1
if "%PROJ%"=="" set PROJ=.

echo == shell ==
echo platform             windows

echo.
echo == C/C++ toolchain ==
where cl >nul 2>&1
if errorlevel 1 (
  echo cl on PATH           FAIL
  set /a FAIL+=1
) else (
  echo cl on PATH           ok
)
rem The subtle one: cl.exe on PATH is NOT enough; INCLUDE must point at the MSVC headers.
echo %INCLUDE% | findstr /i "msvc" >nul 2>&1
if errorlevel 1 (
  echo INCLUDE              FAIL  ^(run vcvars64.bat^)
  set /a FAIL+=1
) else (
  echo INCLUDE              ok
)

echo.
echo == TypePHP toolchain ==
if exist "%PHP_HOME%\tpc.exe" (
  echo tpc in PHP_HOME       ok
) else (
  where tpc >nul 2>&1
  if errorlevel 1 (
    echo tpc                  FAIL  ^(set PHP_HOME^)
    set /a FAIL+=1
  ) else (
    echo tpc on PATH          ok
  )
)
if defined PHP_HOME  (echo PHP_HOME             ok) else (echo PHP_HOME             warn ^(unset^))
if defined PHPX_HOME (echo PHPX_HOME            ok) else (echo PHPX_HOME            warn ^(unset^))

echo.
echo == project ==
if exist "%PROJ%\project.yml" (
  echo project.yml          ok
) else (
  echo project.yml          warn  ^(file/dir build only^)
)

echo.
if "%FAIL%"=="0" (
  echo READY - no blocking problem found.
  exit /b 0
)
echo %FAIL% blocking problem^(s^). Fix those before debugging PHP code; they fail every build.
echo Hint: run inside a Developer Command Prompt, or call "...\VC\Auxiliary\Build\vcvars64.bat".
exit /b 1
