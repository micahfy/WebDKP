@echo off
setlocal
set PYTHONDONTWRITEBYTECODE=1
python "%~dp0package_standard.py" %*
if errorlevel 1 (
    echo Packaging failed. Check the error above.
    pause
    exit /b 1
)
pause
