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
exit /b 1

:godot_found
set "APPDATA=%TEMP%\LocalStrikeGodotTests"
if not exist "%APPDATA%" mkdir "%APPDATA%"

echo Running Local Strike gameplay tests...
"%GODOT%" --disable-crash-handler --headless --rendering-method gl_compatibility --path "%PROJECT%" --script res://test_runner.gd
if errorlevel 1 goto failed

echo Running Arsenal and new weapon tests...
"%GODOT%" --disable-crash-handler --headless --rendering-method gl_compatibility --path "%PROJECT%" --script res://arsenal_test.gd
if errorlevel 1 goto failed

echo Running pause menu and weapon holding tests...
"%GODOT%" --disable-crash-handler --headless --rendering-method gl_compatibility --path "%PROJECT%" --script res://menu_holding_test.gd
if errorlevel 1 goto failed

echo Running LAN socket tests...
"%GODOT%" --disable-crash-handler --headless --rendering-method gl_compatibility --path "%PROJECT%" --script res://network_socket_test.gd
if errorlevel 1 goto failed

echo Running LAN gameplay synchronization tests...
"%GODOT%" --disable-crash-handler --headless --rendering-method gl_compatibility --path "%PROJECT%" --script res://network_gameplay_test.gd
if errorlevel 1 goto failed

echo All Local Strike tests passed.
exit /b 0

:failed
echo Local Strike tests failed.
exit /b 1
