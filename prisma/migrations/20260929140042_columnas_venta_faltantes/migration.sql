-- AlterTable
ALTER TABLE `venta_detalle` ADD COLUMN `presentacion_factor` INTEGER NULL,
    ADD COLUMN `presentacion_nombre` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `ventas` ADD COLUMN `nota` VARCHAR(191) NULL;
