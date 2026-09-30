-- AlterTable
ALTER TABLE `abonos_cobrar` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `categorias` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `clientes` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `compra_detalle` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `compras` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `cuentas_cobrar` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `cuentas_pagar` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `lotes` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `movimientos` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `pagos_pagar` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `productos` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `proveedores` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `venta_detalle` ADD COLUMN `usuario_id` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `ventas` ADD COLUMN `usuario_id` VARCHAR(191) NULL;
