@echo off
REM ============================================================
REM  Actualiza la API en el PC del cliente (ejecutar como ADMIN)
REM  Debe correr desde la carpeta del backend del cliente
REM ============================================================
cd /d "%~dp0"

echo Aplicando migraciones a la base de datos...
call npx prisma migrate deploy
if errorlevel 1 (
  echo ERROR: fallo la migracion. No se reinicia el servicio.
  pause
  exit /b 1
)

echo Reiniciando servicio InventarioAPI...
nssm restart InventarioAPI

echo.
echo Actualizacion completada.
pause
