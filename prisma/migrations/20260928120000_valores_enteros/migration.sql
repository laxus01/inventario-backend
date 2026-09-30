-- Cantidades → enteros
ALTER TABLE `lotes` MODIFY `cantidad_inicial` INTEGER NOT NULL, MODIFY `cantidad_restante` INTEGER NOT NULL;
ALTER TABLE `movimientos` MODIFY `cantidad` INTEGER NOT NULL;
ALTER TABLE `compra_detalle` MODIFY `cantidad` INTEGER NOT NULL;
ALTER TABLE `venta_detalle` MODIFY `cantidad` INTEGER NOT NULL, MODIFY `precio_unitario` INTEGER NOT NULL;
ALTER TABLE `productos` MODIFY `stock` INTEGER NOT NULL DEFAULT 0, MODIFY `stock_minimo` INTEGER NOT NULL DEFAULT 0;

-- Valores de venta → enteros
ALTER TABLE `ventas` MODIFY `total` INTEGER NOT NULL DEFAULT 0, MODIFY `ganancia` INTEGER NOT NULL DEFAULT 0;
ALTER TABLE `productos` MODIFY `precio_venta` INTEGER NOT NULL DEFAULT 0;
ALTER TABLE `cuentas_cobrar` MODIFY `total` INTEGER NOT NULL;
ALTER TABLE `abonos_cobrar` MODIFY `valor` INTEGER NOT NULL;
