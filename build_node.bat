@echo off
echo ====================================================
echo      COMPILING NODE.JS WHATSAPP SERVICE TO EXE
echo ====================================================
echo.
echo Installing Javascript Obfuscator and PKG compiler globally...
call npm install -g javascript-obfuscator pkg
echo.
echo Scrambling and obfuscating JavaScript source code...
cd wa_service
call javascript-obfuscator index.js --output index.obfuscated.js --compact false --self-defending false --string-array true --string-array-encoding none --ignore-imports true
echo.
echo Compiling obfuscated script to native EXE...
call pkg index.obfuscated.js --targets node18-win-x64 --output wa_service.exe
echo.
echo Cleanup temporary files...
del index.obfuscated.js
echo.
echo Done! wa_service.exe is created inside wa_service/ directory.
cd ..
pause
