-- Agrega borrado lógico (deleted_at) a las tablas de detalle, abonos y pagos
-- para que la sincronización propague las eliminaciones de ventas, compras,
-- cuentas y abonos realizadas en la app.
ALTER TABLE `compra_detalle` ADD COLUMN `deleted_at` DATETIME(3) NULL;
ALTER TABLE `venta_detalle` ADD COLUMN `deleted_at` DATETIME(3) NULL;
ALTER TABLE `abonos_cobrar` ADD COLUMN `deleted_at` DATETIME(3) NULL;
ALTER TABLE `pagos_pagar` ADD COLUMN `deleted_at` DATETIME(3) NULL;
