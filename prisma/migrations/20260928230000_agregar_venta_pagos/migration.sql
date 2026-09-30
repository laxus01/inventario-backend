-- CreateTable
CREATE TABLE `venta_pagos` (
    `id` VARCHAR(191) NOT NULL,
    `venta_id` VARCHAR(191) NOT NULL,
    `metodo` VARCHAR(191) NOT NULL,
    `monto` INTEGER NOT NULL DEFAULT 0,
    `usuario_id` VARCHAR(191) NULL,
    `deleted_at` DATETIME(3) NULL,
    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updated_at` DATETIME(3) NOT NULL,

    INDEX `venta_pagos_venta_id_idx`(`venta_id`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `venta_pagos` ADD CONSTRAINT `venta_pagos_venta_id_fkey` FOREIGN KEY (`venta_id`) REFERENCES `ventas`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
