@echo off
setlocal
cd /d "%~dp0"
for %%I in ("%~dp0.") do set "PROJECT=%%~fI"

set "GODOT=%PROJECT%\engine\Godot_v4.7-stable_win64_console.exe"
if exist "%GODOT%" goto godot_found
for %%G in (godot4.7 godot4 godot) do (
  where %%G >nul 2>&1
  if not errorlevel 1 (
    set "GODOT=%%G"
    goto godot_found
  )
)
echo Godot 4.7 was not found.
echo Install Godot and add it to PATH, or place the portable files in .\engine.
pause
exit /b 1

:godot_found

echo Starting Local Strike Godot in Forward+ quality mode...
echo Close the game window to return here.
echo.
"%GODOT%" --path "%PROJECT%" --rendering-method forward_plus --verbose %*
if errorlevel 1 (
  echo.
  echo Forward+ could not start. Retrying with OpenGL compatibility...
  "%GODOT%" --path "%PROJECT%" --rendering-method gl_compatibility --verbose %*
  if errorlevel 1 (
    echo.
    echo Godot exited with an error. The diagnostic output is shown above.
    pause
    exit /b 1
  )
)
endlocal
