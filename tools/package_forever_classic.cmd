@echo off
python "%~dp0package_forever_classic.py"
if errorlevel 1 (
    echo Packaging failed. Check the error above.
    pause
    exit /b 1
)
pause
