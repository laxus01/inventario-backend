import 'dotenv/config';
import path from 'path';
import fs from 'fs';
import express from 'express';
import cors from 'cors';
import { prisma } from './prisma';
import { sincronizar, SyncPayload } from './sync';

const app = express();
app.use(cors());
app.use(express.json({ limit: '25mb' }));

// App web (carpeta `web/`, copia del build de Ionic): se sirve desde el mismo
// puerto que la API para que el cliente la abra en el navegador sin otro server.
const WEB_DIR = path.join(__dirname, '..', 'web');
if (fs.existsSync(WEB_DIR)) {
  app.use(express.static(WEB_DIR));
  // Fallback SPA: cualquier ruta que no sea de la API devuelve index.html
  app.get(/^(?!\/(api|health)).*/, (_req, res) => {
    res.sendFile(path.join(WEB_DIR, 'index.html'));
  });
}

app.get('/health', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true, db: 'up' });
  } catch {
    res.status(500).json({ ok: false, db: 'down' });
  }
});

const PORT = Number(process.env.PORT ?? 3000);
const TOKEN_SYNC = process.env.SYNC_TOKEN ?? '';

app.post('/api/sync', (req, res, next) => {
  if (TOKEN_SYNC) {
    const token = req.header('x-sync-token');
    if (token !== TOKEN_SYNC) {
      res.status(401).json({ error: 'Token de sincronización inválido' });
      return;
    }
  }
  next();
});

app.post('/api/sync', async (req, res) => {
  try {
    const resultado = await sincronizar(req.body as SyncPayload);
    res.json(resultado);
  } catch (error) {
    const err = error as { code?: string; meta?: unknown; message?: string };
    console.error(
      '[api] Error en /api/sync:',
      `\n  codigo Prisma: ${err.code ?? 'desconocido'}`,
      `\n  meta: ${JSON.stringify(err.meta ?? null)}`,
      `\n  mensaje: ${err.message?.split('\n')[0] ?? 'sin mensaje'}`,
    );
    res.status(500).json({
      error: 'Error de sincronización',
      codigo: err.code ?? 'desconocido',
      meta: err.meta ?? null,
      detalle: err.message?.split('\n').slice(-4).join(' ').trim() ?? 'sin detalle',
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`API de inventario escuchando en http://0.0.0.0:${PORT}`);
});
