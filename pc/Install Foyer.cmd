@echo off
rem Double-click to install or update Foyer for PC.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
