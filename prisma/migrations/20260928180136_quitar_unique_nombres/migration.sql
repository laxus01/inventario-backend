-- DropIndex
DROP INDEX `categorias_nombre_key` ON `categorias`;

-- DropIndex
DROP INDEX `clientes_nombre_key` ON `clientes`;

-- DropIndex
DROP INDEX `proveedores_nombre_key` ON `proveedores`;

-- CreateIndex
CREATE INDEX `categorias_nombre_idx` ON `categorias`(`nombre`);

-- CreateIndex
CREATE INDEX `clientes_nombre_idx` ON `clientes`(`nombre`);

-- CreateIndex
CREATE INDEX `proveedores_nombre_idx` ON `proveedores`(`nombre`);
