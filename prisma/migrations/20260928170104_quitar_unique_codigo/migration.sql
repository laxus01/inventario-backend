-- DropIndex
DROP INDEX `productos_codigo_key` ON `productos`;

-- CreateIndex
CREATE INDEX `productos_codigo_idx` ON `productos`(`codigo`);
