@echo off
REM ============================================================
REM  Instala la API de inventario como servicio de Windows
REM  Ejecutar como ADMINISTRADOR (clic derecho > Ejecutar como admin)
REM ============================================================
setlocal

set RUTA_BACKEND=%~dp0
set NOMBRE_SERVICIO=InventarioAPI
set NSSM=%RUTA_BACKEND%nssm.exe

REM --- Descargar NSSM si no existe ---
if not exist "%NSSM%" (
  echo Descargando NSSM...
  powershell -Command "Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile '%RUTA_BACKEND%nssm.zip'"
  powershell -Command "Expand-Archive -Path '%RUTA_BACKEND%nssm.zip' -DestinationPath '%RUTA_BACKEND%nssm-temp' -Force"
  copy /y "%RUTA_BACKEND%nssm-temp\nssm-2.24\win64\nssm.exe" "%NSSM%" >nul
  rmdir /s /q "%RUTA_BACKEND%nssm-temp"
  del "%RUTA_BACKEND%nssm.zip"
)

REM --- Verificar que el proyecto esta compilado ---
if not exist "%RUTA_BACKEND%dist\server.js" (
  echo ERROR: Compila primero el proyecto con: npm run build
  pause
  exit /b 1
)

REM --- Crear carpeta de logs ---
if not exist "%RUTA_BACKEND%logs" mkdir "%RUTA_BACKEND%logs"

REM --- Instalar el servicio ---
%NSSM% install %NOMBRE_SERVICIO% "C:\Program Files\nodejs\node.exe" "%RUTA_BACKEND%dist\server.js"
%NSSM% set %NOMBRE_SERVICIO% AppDirectory "%RUTA_BACKEND%"
%NSSM% set %NOMBRE_SERVICIO% AppStdout "%RUTA_BACKEND%logs\api-out.log"
%NSSM% set %NOMBRE_SERVICIO% AppStderr "%RUTA_BACKEND%logs\api-err.log"
%NSSM% set %NOMBRE_SERVICIO% AppRotateFiles 1
%NSSM% set %NOMBRE_SERVICIO% AppRotateOnline 1
%NSSM% set %NOMBRE_SERVICIO% AppRotateBytes 5242880
%NSSM% set %NOMBRE_SERVICIO% Start SERVICE_AUTO_START
%NSSM% set %NOMBRE_SERVICIO% Description "API de sincronizacion de inventario (Node.js + MySQL)"

REM --- Arrancar el servicio ---
%NSSM% start %NOMBRE_SERVICIO%

echo.
echo ============================================================
echo  Servicio %NOMBRE_SERVICIO% instalado y arrancado.
echo  Arrancara automaticamente al encender el equipo.
echo  Logs: %RUTA_BACKEND%logs\
echo ============================================================
pause
