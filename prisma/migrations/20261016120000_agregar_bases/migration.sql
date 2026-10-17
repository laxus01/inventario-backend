-- Base de caja entregada para operar el día (vueltos): en efectivo y en cuenta.
CREATE TABLE `bases` (
    `id` VARCHAR(191) NOT NULL,
    `fecha` VARCHAR(191) NOT NULL,
    `base_efectivo` INTEGER NOT NULL DEFAULT 0,
    `base_cuenta` INTEGER NOT NULL DEFAULT 0,
    `usuario_id` VARCHAR(191) NULL,
    `deleted_at` DATETIME(3) NULL,
    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updated_at` DATETIME(3) NOT NULL,

    INDEX `bases_fecha_idx`(`fecha`),

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
