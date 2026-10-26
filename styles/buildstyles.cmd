@echo off
rem Builds GDEMThemes.res, the FMX styles GDEM's themes use, which the GDEM
rem programs link in on every platform.
rem
rem 1. Copies any of the four .style files missing from this folder out of
rem    RAD Studio's Redist\styles\Fmx; files already here are left alone, so
rem    a style can be replaced by hand.
rem 2. Compiles GDEMThemes.rc into GDEMThemes.res with RAD Studio's brcc32,
rem    from this folder, so the file names in the .rc resolve here.
rem
rem Run by each project's pre-build event, for every platform and
rem configuration, before anything is compiled:
rem   call "$(PROJECTDIR)\..\styles\buildstyles.cmd" "$(BDS)"
rem Any failure stops the build with an error saying what went wrong.

rem Paths are expanded with !...! inside brackets, as RAD Studio's usual
rem folder, Program Files (x86), would otherwise end a bracketed block.
setlocal EnableDelayedExpansion
set "BDSDIR=%~1"
set "SRC=%BDSDIR%\Redist\styles\Fmx"
set "BRCC=%BDSDIR%\bin\brcc32.exe"
set FAILED=0

pushd "%~dp0"

for %%S in (Dark AquaGraphite RubyGraphite GoldenGraphite) do (
  if not exist "%%S.style" (
    if exist "%SRC%\%%S.style" (
      copy /Y "%SRC%\%%S.style" "%%S.style" >nul
      echo Copied %%S.style from !SRC!
    ) else (
      echo buildstyles.cmd : error : %%S.style not found in this folder or in !SRC!
      set FAILED=1
    )
  )
)
if %FAILED% neq 0 goto done

if not exist "%BRCC%" (
  echo buildstyles.cmd : error : brcc32.exe not found at !BRCC!
  set FAILED=1
  goto done
)

"!BRCC!" -fo GDEMThemes.res GDEMThemes.rc
if errorlevel 1 (
  echo buildstyles.cmd : error : brcc32 could not compile GDEMThemes.rc
  set FAILED=1
)

:done
popd
exit /b %FAILED%
