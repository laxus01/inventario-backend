-- Tabla de presentaciones de venta (p. ej. "Cava" = caja de 30 unidades).
CREATE TABLE `presentaciones` (
    `id` VARCHAR(191) NOT NULL,
    `producto_id` VARCHAR(191) NOT NULL,
    `nombre` VARCHAR(191) NOT NULL,
    `factor` INTEGER NOT NULL,
    `precio_venta` DECIMAL(12,2) NULL,
    `usuario_id` VARCHAR(191) NULL,
    `deleted_at` DATETIME(3) NULL,
    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updated_at` DATETIME(3) NOT NULL,

    INDEX `presentaciones_producto_id_idx`(`producto_id`),

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- La llave foránea va sobre la tabla hija (presentaciones).
ALTER TABLE `presentaciones` ADD CONSTRAINT `presentaciones_producto_id_fkey` FOREIGN KEY (`producto_id`) REFERENCES `productos`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
