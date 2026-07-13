@echo off
echo ====================================================
echo      COMPILING PYTHON BACKEND TO NATIVE EXE
echo ====================================================
echo.
echo Installing Nuitka compiler dependency...
python -m pip install nuitka zstandard
echo.
echo Starting compilation using Nuitka (this may take a few minutes)...
python -m nuitka --standalone --onefile --show-progress main.py
echo.
echo Compilation completed! main.exe is now ready in this directory.
pause
