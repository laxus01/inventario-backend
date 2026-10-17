import { PrismaClient, Prisma } from '@prisma/client';
import { prisma } from './prisma';

/**
 * Sincronización por cursor de cambios (changelog).
 *
 * - Push: el cliente envía las filas modificadas localmente; el servidor las
 *   aplica con last-write-wins (updated_at) y registra cada escritura en la
 *   tabla `cambios` con un número de secuencia (seq) monotónico, dentro de la
 *   misma transacción.
 * - Pull: el cliente envía su `last_seq` y recibe las filas afectadas por los
 *   cambios con seq mayor, en lotes paginados. El cursor lo asigna el
 *   servidor, así que ninguna diferencia de reloj puede hacer perder cambios.
 * - Compatibilidad: un cliente antiguo que envíe `last_sync` (fecha) en vez de
 *   `last_seq` sigue siendo atendido con el mecanismo delta por timestamp.
 */

const TABLAS = [
  'usuarios',
  'bases',
  'categorias',
  'proveedores',
  'clientes',
  'productos',
  'presentaciones',
  'lotes',
  'movimientos',
  'compras',
  'compra_detalle',
  'ventas',
  'venta_pagos',
  'venta_detalle',
  'cuentas_cobrar',
  'abonos_cobrar',
  'cuentas_pagar',
  'pagos_pagar',
] as const;

export type NombreTabla = (typeof TABLAS)[number];

export type SyncPayload = {
  /** Cursor del cliente: última secuencia de `cambios` ya aplicada localmente. */
  last_seq?: number | null;
  /** Mecanismo antiguo (clientes previos al cursor): fecha ISO de última sync. */
  last_sync?: string | null;
  /** Ignorado: MySQL es la fuente de verdad y nunca se vacía por un cliente. */
  reset?: boolean;
  changes?: Partial<Record<NombreTabla, Record<string, unknown>[]>>;
  /** Filas que fallaron en un pull anterior (FK faltante) y se reintentan. */
  reintentar?: Partial<Record<NombreTabla, string[]>>;
};

interface DelegadoGenerico {
  findUnique(args: { where: { id: string } }): Promise<Record<string, unknown> | null>;
  create(args: { data: Record<string, unknown> }): Promise<unknown>;
  update(args: { where: { id: string }; data: Record<string, unknown> }): Promise<unknown>;
  findMany(args: Record<string, unknown>): Promise<Record<string, unknown>[]>;
}

type ClientePrisma = PrismaClient | Prisma.TransactionClient;

function delegadosDe(cliente: ClientePrisma): Record<NombreTabla, DelegadoGenerico> {
  return {
    categorias: cliente.categoria,
    bases: cliente.baseCaja,
    proveedores: cliente.proveedor,
    clientes: cliente.cliente,
    productos: cliente.producto,
    presentaciones: cliente.presentacion,
    lotes: cliente.lote,
    movimientos: cliente.movimiento,
    compras: cliente.compra,
    compra_detalle: cliente.compraDetalle,
    ventas: cliente.venta,
    venta_pagos: cliente.ventaPago,
    venta_detalle: cliente.ventaDetalle,
    cuentas_cobrar: cliente.cuentaCobrar,
    abonos_cobrar: cliente.abonoCobrar,
    cuentas_pagar: cliente.cuentaPagar,
    pagos_pagar: cliente.pagoPagar,
    usuarios: cliente.usuario,
  } as unknown as Record<NombreTabla, DelegadoGenerico>;
}

/**
 * Campos que deben ser enteros (cantidades y valores de venta). Si la app
 * envía un decimal (p. ej. por un cálculo de ganancia), se redondea aquí.
 */
const CAMPOS_ENTEROS: Partial<Record<NombreTabla, string[]>> = {
  bases: ['base_efectivo', 'base_cuenta'],
  productos: ['stock', 'stock_minimo', 'precio_venta'],
  presentaciones: ['factor'],
  lotes: ['cantidad_inicial', 'cantidad_restante'],
  movimientos: ['cantidad'],
  compra_detalle: ['cantidad'],
  venta_detalle: ['cantidad', 'precio_unitario', 'presentacion_factor'],
  ventas: ['total', 'ganancia'],
  venta_pagos: ['monto'],
  cuentas_cobrar: ['total'],
  abonos_cobrar: ['valor'],
};

/**
 * Campos que acepta cada modelo de Prisma. El cliente puede enviar columnas
 * que aún no existen en el servidor; se descartan para que una fila
 * desconocida no rompa toda la sincronización.
 */
const CAMPOS_PERMITIDOS: Record<NombreTabla, string[]> = {
  usuarios: ['usuario', 'nombre', 'clave_hash', 'rol', 'activo', 'created_at', 'updated_at'],
  bases: ['fecha', 'base_efectivo', 'base_cuenta', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  categorias: ['nombre', 'descripcion', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  proveedores: ['nombre', 'contacto', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  clientes: ['nombre', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  productos: [
    'codigo', 'nombre', 'descripcion', 'categoria_id', 'unidad', 'precio_compra',
    'precio_venta', 'stock', 'stock_minimo', 'activo', 'usuario_id', 'deleted_at',
    'created_at', 'updated_at',
  ],
  presentaciones: ['producto_id', 'nombre', 'factor', 'precio_venta', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  lotes: ['producto_id', 'cantidad_inicial', 'cantidad_restante', 'costo_unitario', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  movimientos: ['producto_id', 'tipo', 'cantidad', 'motivo', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  compras: ['proveedor_id', 'total', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  compra_detalle: ['compra_id', 'producto_id', 'cantidad', 'costo_unitario', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  ventas: ['total', 'ganancia', 'metodo_pago', 'nota', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  venta_pagos: ['venta_id', 'metodo', 'monto', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  venta_detalle: ['venta_id', 'producto_id', 'lote_id', 'cantidad', 'precio_unitario', 'costo_unitario', 'presentacion_nombre', 'presentacion_factor', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  cuentas_cobrar: ['venta_id', 'cliente_id', 'concepto', 'total', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  abonos_cobrar: ['cuenta_id', 'valor', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  cuentas_pagar: ['compra_id', 'proveedor_id', 'concepto', 'total', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
  pagos_pagar: ['cuenta_id', 'valor', 'usuario_id', 'deleted_at', 'created_at', 'updated_at'],
};

/**
 * Campos con restricción UNIQUE en el servidor. Cuando un create falla con
 * P2002 se busca la fila existente por uno de estos campos para aplicar
 * last-write-wins en vez de tumbar la sincronización.
 */
const CAMPOS_UNICOS: Partial<Record<NombreTabla, string[]>> = {
  usuarios: ['usuario'],
};

/** Tolerancia ante relojes de clientes adelantados (5 minutos). */
const MARGEN_RELOJ_MS = 5 * 60 * 1000;

/** Tamaño máximo del lote de cambios devuelto en cada pull. */
const LOTE_PULL = 1000;

function normalizarFila(tabla: NombreTabla, fila: Record<string, unknown>): Record<string, unknown> {
  const permitidos = new Set(CAMPOS_PERMITIDOS[tabla]);
  const salida: Record<string, unknown> = {};
  for (const [campo, valor] of Object.entries(fila)) {
    if (permitidos.has(campo)) salida[campo] = valor;
  }
  // El cliente SQLite envía activo como 0/1; Prisma espera boolean
  if ((tabla === 'productos' || tabla === 'usuarios') && 'activo' in salida) {
    salida.activo = Boolean(salida.activo);
  }
  for (const campo of CAMPOS_ENTEROS[tabla] ?? []) {
    if (campo in salida) {
      salida[campo] = Math.round(Number(salida[campo] ?? 0));
    }
  }
  return salida;
}

/** Fecha de referencia para el LWW, con tope ante relojes adelantados. */
function fechaEntrante(data: Record<string, unknown>): number {
  const ms = new Date(String(data.updated_at ?? 0)).getTime();
  if (Number.isNaN(ms)) return 0;
  return Math.min(ms, Date.now() + MARGEN_RELOJ_MS);
}

/**
 * Aplica los cambios entrantes con last-write-wins y registra cada escritura
 * en el changelog `cambios`, todo dentro de la transacción recibida:
 * - Si la fila no existe, se crea.
 * - Si existe y la versión entrante es más reciente (updated_at), se sobrescribe.
 * - Si el servidor tiene una versión más nueva, se ignora la entrante.
 */
async function aplicarTabla(
  tx: ClientePrisma,
  tabla: NombreTabla,
  filas: Record<string, unknown>[],
): Promise<{ aplicados: number; fallidos: string[] }> {
  const delegado = delegadosDe(tx)[tabla];
  let aplicados = 0;
  const fallidos: string[] = [];

  for (const fila of filas) {
    if (!fila || typeof fila.id !== 'string') continue;
    const id = fila.id;
    const data = normalizarFila(tabla, fila);
    try {
      const existente = await delegado.findUnique({ where: { id } });

      if (!existente) {
        // El id (uuid del cliente) viaja aparte porque normalizarFila lo descarta
        await delegado.create({ data: { id, ...data } });
        await tx.cambio.create({ data: { tabla, fila_id: id } });
        aplicados++;
        continue;
      }

      const entrante = fechaEntrante(data);
      const actual = new Date(String(existente.updated_at ?? 0)).getTime();
      if (entrante > actual) {
        const { id: _id, ...cambios } = data;
        await delegado.update({ where: { id }, data: cambios });
        await tx.cambio.create({ data: { tabla, fila_id: id } });
        aplicados++;
      } else {
        console.log(`[sync] ${tabla}: fila ${id} ignorada (el servidor tiene versión más nueva)`);
      }
    } catch (error) {
      const err = errorPrisma(error);
      console.error(
        `[sync] ERROR aplicando fila en ${tabla} (${id})`,
        `\n  codigo Prisma: ${err.code ?? 'desconocido'}`,
        `\n  meta: ${JSON.stringify(err.meta ?? null)}`,
        `\n  datos de la fila: ${JSON.stringify(data)}`,
        `\n  fila original: ${JSON.stringify(fila)}`,
      );
      if (err.code === 'P2002') {
        // Colisión de campo único (p. ej. usuarios.usuario cuando el mismo
        // usuario se sembró en dos dispositivos con uuid distinto): se busca
        // la fila existente por el campo en conflicto y se aplica
        // last-write-wins sobre ella en vez de tumbar la sincronización.
        const campo = (CAMPOS_UNICOS[tabla] ?? []).find((c) => data[c] != null);
        if (campo) {
          const rivales = await delegado.findMany({ where: { [campo]: data[campo] } });
          const rival = rivales[0];
          if (rival) {
            const entrante = fechaEntrante(data);
            const actual = new Date(String(rival.updated_at ?? 0)).getTime();
            if (entrante > actual) {
              await delegado.update({ where: { id: String(rival.id) }, data });
              await tx.cambio.create({ data: { tabla, fila_id: String(rival.id) } });
              aplicados++;
            }
            continue;
          }
        }
      }
      if (err.code === 'P2003') {
        // FK faltante (p. ej. un proveedor que aún no se sincronizó): se omite
        // la fila para no tumbar la sync; el cliente la reintentará.
        console.warn(`[sync] ${tabla}: fila ${id} OMITIDA por referencia faltante (el cliente la reintentará)`);
        fallidos.push(id);
        continue;
      }
      fallidos.push(id);
    }
  }
  return { aplicados, fallidos };
}

function errorPrisma(error: unknown): { code?: string; meta?: unknown; message?: string } {
  return error as { code?: string; meta?: unknown; message?: string };
}

/** Filas que un cliente pide reintentar (fallaron antes por FK faltante). */

/** Filas que un cliente pide reintentar (fallaron antes por FK faltante). */
async function filasReintentar(
  cliente: ClientePrisma,
  reintentar: SyncPayload['reintentar'],
): Promise<Record<string, Record<string, unknown>[]>> {
  const salida: Record<string, Record<string, unknown>[]> = {};
  if (!reintentar) return salida;
  const delegados = delegadosDe(cliente);
  for (const tabla of TABLAS) {
    const ids = reintentar[tabla];
    if (!Array.isArray(ids) || ids.length === 0) continue;
    const filas: Record<string, unknown>[] = [];
    for (const id of ids) {
      if (typeof id !== 'string') continue;
      const fila = await delegados[tabla].findUnique({ where: { id } });
      if (fila) filas.push(fila);
    }
    if (filas.length > 0) salida[tabla] = filas;
  }
  return salida;
}

/**
 * Lote de cambios desde un cursor `seq`. Devuelve las filas agrupadas por
 * tabla, el nuevo cursor y si quedan más cambios pendientes.
 */
async function loteDesde(
  cliente: ClientePrisma,
  desdeSeq: number,
): Promise<{ changes: Record<string, Record<string, unknown>[]>; last_seq: number; hasMore: boolean }> {
  const delegados = delegadosDe(cliente);
  const entradas = await cliente.cambio.findMany({
    where: { seq: { gt: desdeSeq } },
    orderBy: { seq: 'asc' },
    take: LOTE_PULL,
  });

  const idsPorTabla = new Map<NombreTabla, Set<string>>();
  for (const entrada of entradas) {
    const tabla = entrada.tabla as NombreTabla;
    if (!TABLAS.includes(tabla as NombreTabla)) continue;
    (idsPorTabla.get(tabla) ?? idsPorTabla.set(tabla, new Set()).get(tabla)!).add(entrada.fila_id);
  }

  const changes: Record<string, Record<string, unknown>[]> = {};
  for (const [tabla, ids] of idsPorTabla) {
    const filas = await delegados[tabla].findMany({
      where: { id: { in: [...ids] } },
      orderBy: { updated_at: 'asc' },
    });
    changes[tabla] = filas;
  }

  const lastSeq = entradas.length > 0 ? entradas[entradas.length - 1].seq : desdeSeq;
  const restantes = entradas.length === LOTE_PULL
    ? await cliente.cambio.count({ where: { seq: { gt: lastSeq } } })
    : 0;
  return { changes, last_seq: lastSeq, hasMore: restantes > 0 };
}

/** Primera sincronización de un cliente (sin cursor): volcado completo. */
async function volcadoCompleto(
  cliente: ClientePrisma,
): Promise<{ changes: Record<string, Record<string, unknown>[]>; last_seq: number }> {
  const delegados = delegadosDe(cliente);
  const changes: Record<string, Record<string, unknown>[]> = {};
  for (const tabla of TABLAS) {
    const filas = await delegados[tabla].findMany({ orderBy: { updated_at: 'asc' } });
    if (filas.length > 0) {
      changes[tabla] = filas;
    }
  }
  const ultimo = await cliente.cambio.findFirst({ orderBy: { seq: 'desc' } });
  return { changes, last_seq: ultimo?.seq ?? 0 };
}

export async function sincronizar(payload: SyncPayload) {
  const modoCursor = 'last_seq' in payload;
  const cambios = payload.changes ?? {};

  const resumenEntrada = Object.entries(cambios)
    .map(([tabla, filas]) => `${tabla}:${Array.isArray(filas) ? filas.length : 0}`)
    .join(', ');
  console.log(
    `[sync] Petición recibida | last_seq=${payload.last_seq ?? 'null'} | last_sync=${modoCursor ? '(cursor)' : payload.last_sync ?? 'null'} | entrante: ${resumenEntrada || 'nada'}`,
  );

  // Aplicación del push en una transacción: o se aplica todo el lote de la
  // tabla (con su changelog), o nada. Una fila con error se omite y queda
  // marcada como fallida para que el cliente la reintente.
  const aplicados: Record<string, number> = {};
  const fallidos: Record<string, string[]> = {};
  await prisma.$transaction(async (tx) => {
    const delegados = delegadosDe(tx);
    for (const tabla of TABLAS) {
      const filas = cambios[tabla];
      if (!Array.isArray(filas) || filas.length === 0) continue;
      const resultado = await aplicarTabla(tx, tabla, filas);
      aplicados[tabla] = resultado.aplicados;
      if (resultado.fallidos.length > 0) fallidos[tabla] = resultado.fallidos;
      console.log(`[sync] ${tabla}: ${resultado.aplicados} fila(s) aplicada(s) de ${filas.length}`);
    }
  });

  // Pull: lotes por cursor (clientes nuevos) o delta por fecha (compatibilidad).
  if (modoCursor) {
    const desdeSeq = Number(payload.last_seq ?? 0);
    if (!Number.isFinite(desdeSeq) || desdeSeq < 0) {
      throw new Error(`last_seq inválido: ${payload.last_seq}`);
    }
    const reintentadas = await filasReintentar(prisma, payload.reintentar);
    const respuesta: Record<string, Record<string, unknown>[]> = { ...reintentadas };
    let lastSeq: number;
    let hasMore: boolean;

    if (payload.last_seq == null) {
      // Primera sync de un cliente nuevo: volcado completo (el changelog solo
      // cubre escrituras desde su creación; los datos previos van por fecha).
      const completo = await volcadoCompleto(prisma);
      for (const [tabla, filas] of Object.entries(completo.changes)) {
        (respuesta[tabla] ??= []).push(...filas);
      }
      lastSeq = completo.last_seq;
      hasMore = false;
    } else {
      const lote = await loteDesde(prisma, desdeSeq);
      for (const [tabla, filas] of Object.entries(lote.changes)) {
        (respuesta[tabla] ??= []).push(...filas);
      }
      lastSeq = lote.last_seq;
      hasMore = lote.hasMore;
    }
    const filtrada = Object.fromEntries(
      Object.entries(respuesta).filter(([, filas]) => filas.length > 0),
    );
    return finalizar(filtrada, lastSeq, hasMore, aplicados, fallidos);
  }

  // Compatibilidad con clientes antiguos: delta por fecha.
  const lastSync = payload.reset || !payload.last_sync
    ? new Date(0)
    : new Date(payload.last_sync);
  const delegados = delegadosDe(prisma);
  const respuesta: Record<string, unknown> = {};
  for (const tabla of TABLAS) {
    const filas = await delegados[tabla].findMany({
      where: { updated_at: { gt: lastSync } },
      orderBy: { updated_at: 'asc' },
    });
    if (filas.length > 0) respuesta[tabla] = filas;
  }
  const lastSeq = (await prisma.cambio.findFirst({ orderBy: { seq: 'desc' } }))?.seq ?? 0;
  return finalizar(respuesta, lastSeq, false, aplicados, fallidos);
}

function finalizar(
  respuesta: Record<string, unknown>,
  lastSeq: number,
  hasMore: boolean,
  aplicados: Record<string, number>,
  fallidos: Record<string, string[]>,
) {
  const resumenSalida = Object.keys(respuesta)
    .map((t) => `${t}: ${(respuesta[t] as unknown[]).length}`)
    .join(', ');
  console.log(`[sync] Respondiendo con: ${resumenSalida || 'nada'} | last_seq=${lastSeq} | hasMore=${hasMore}`);

  return {
    server_time: new Date().toISOString(),
    last_seq: lastSeq,
    hasMore,
    aplicados,
    fallidos,
    changes: respuesta,
  };
}
