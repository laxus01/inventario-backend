# Inventario Backend

API de sincronizacion del inventario, desarrollada con Node.js, Express,
TypeScript y Prisma. Utiliza una base de datos MySQL.

## Inicio rapido

Si las dependencias y el archivo `.env` ya estan preparados, abre PowerShell:

```powershell
cd "D:\Mis proyectos\Inventario Movil\inventario-backend"
npm run dev
```

Deja la terminal abierta mientras utilizas el backend. Para detenerlo, presiona
`Ctrl+C`.

El puerto predeterminado es **3000**. Comprueba que la API y la conexion a MySQL
funcionan abriendo:

http://localhost:3000/health

Respuesta esperada:

```json
{"ok":true,"db":"up"}
```

## Preparacion en otro equipo

Requisitos: Node.js con npm y acceso a una instancia de MySQL con la base de
datos y las tablas del proyecto ya preparadas.

1. Abre una terminal en la carpeta `inventario-backend`.
2. Instala las dependencias con `npm ci`.
3. Crea un archivo `.env` en esa carpeta usando el ejemplo siguiente.
4. Genera el cliente de Prisma con `npm run prisma:generate`.
5. Inicia el backend con `npm run dev`.

Ejemplo de `.env` (reemplaza los valores de ejemplo por los de tu entorno):

```dotenv
DATABASE_URL="mysql://USUARIO:CONTRASENA@localhost:3306/NOMBRE_BASE"
PORT=3000
# Opcional: proteger la sincronizacion con un token.
# SYNC_TOKEN="TU_TOKEN"
```

- MySQL debe estar encendido y accesible desde el equipo del backend.
- Si la contrasena contiene caracteres especiales, codificalos para usarlos en
  una URL.
- No publiques el archivo `.env` ni sus credenciales.
- Si configuras `SYNC_TOKEN`, el cliente debe enviar ese mismo valor en la
  cabecera `x-sync-token` de las peticiones a `/api/sync`.

Estos pasos no crean ni migran las tablas. El script `prisma:migrate` modifica
la estructura de la base de datos: no es necesario para arrancar si la base ya
esta preparada y no debe ejecutarse como parte del inicio habitual.

## Ejecutar la version compilada

Desde la carpeta del backend:

```powershell
npm run build
npm start
```

`npm run build` compila TypeScript en `dist/`. `npm start` ejecuta
`dist/server.js`; vuelve a compilar si modificas el codigo fuente.

`npm run dev` ejecuta directamente `src/server.ts`, pero no tiene reinicio
automatico: detenlo y vuelve a iniciarlo despues de cambiar el codigo.

## Direcciones utiles

| Direccion | Uso |
| --- | --- |
| `GET http://localhost:3000/health` | Verifica la conexion a MySQL mediante una consulta de lectura. |
| `POST http://localhost:3000/api/sync` | Sincroniza datos; puede escribir en la base de datos. No usar como prueba de conectividad. |
| `http://localhost:3000` | Sirve la aplicacion web si la carpeta `web/` contiene su build, incluido `index.html`. |

El servidor escucha en `0.0.0.0`, por lo que tambien puede recibir conexiones
desde otros equipos. Para acceder desde un celular de la misma red, usa
`http://IP_DEL_EQUIPO:3000`, no `localhost`, y comprueba los permisos del firewall.
No expongas el puerto a Internet sin proteccion adicional.

## Problemas frecuentes

- **`db: "down"` en `/health`:** revisa que MySQL este encendido y verifica
  `DATABASE_URL`, las credenciales y el acceso a la base.
- **`EADDRINUSE`:** el puerto ya esta ocupado. Deten la otra instancia o cambia
  `PORT` en `.env` y reinicia el backend.
- **Cliente de Prisma no generado:** ejecuta `npm run prisma:generate`.
- **Cambios que no aparecen con `npm start`:** ejecuta de nuevo
  `npm run build` y reinicia el proceso.
- **Error 401 al sincronizar:** comprueba que `x-sync-token` coincida con
  `SYNC_TOKEN`, si esta configurado.
