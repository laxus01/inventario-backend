-- Changelog de sincronizacion: cursor incremental (seq) para el pull delta.
CREATE TABLE `cambios` (
    `seq` INTEGER NOT NULL AUTO_INCREMENT,
    `tabla` VARCHAR(191) NOT NULL,
    `fila_id` VARCHAR(191) NOT NULL,
    `fecha` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `cambios_seq_idx`(`seq`),

    PRIMARY KEY (`seq`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
