START TRANSACTION;

-- 1) Lote de la compra: costo real ($2.000/un) y cantidad real (1.000 un.)
UPDATE lotes
SET costo_unitario = 2000,
    cantidad_inicial = 1000,
    cantidad_restante = 916,
    updated_at = NOW(3)
WHERE id = '73943cf9-b199-415d-9776-107bc1615ad6';

-- 2) Stock del producto Costeñita: 999.916 -> 916
UPDATE productos
SET stock = 916,
    precio_compra = 2000,
    updated_at = NOW(3)
WHERE id = '97be49f4-d676-4be9-8c73-bc377d43aa95';

-- 3) Detalle de la compra: 1.000 un. a $2.000 (total sigue siendo $2.000.000)
UPDATE compra_detalle
SET cantidad = 1000,
    costo_unitario = 2000,
    updated_at = NOW(3)
WHERE id = '21989f22-24aa-4b31-adc7-2e521af19962'
  AND producto_id = '97be49f4-d676-4be9-8c73-bc377d43aa95';

-- 4) Movimiento de entrada de la compra: 1.000.000 -> 1.000
UPDATE movimientos
SET cantidad = 1000,
    updated_at = NOW(3)
WHERE id = '7c3225b6-3deb-474e-a7fa-9d5c88c1756e'
  AND motivo = 'Compra #1';

-- 5) Detalles de venta: congelar el costo real ($2.000)
UPDATE venta_detalle
SET costo_unitario = 2000,
    updated_at = NOW(3)
WHERE id IN (
  '0a752d7a-0a3e-4108-9d3c-2af6cab39dcb',
  '56be4d48-4ff0-4fd5-b6d9-42a133f975a5',
  '58bd80e3-f991-487c-9256-0062f96dccb8',
  '9367fb70-fce0-4adc-a655-0f3290d8e6c2'
);

-- 6) Ganancia de las 4 ventas: total - (unidades x $2.000)
UPDATE ventas SET ganancia = 12000, updated_at = NOW(3)
WHERE id = 'f512861e-ae09-4b0e-9e1d-8d61714230ba';

UPDATE ventas SET ganancia = 4000, updated_at = NOW(3)
WHERE id = '6dc30616-74aa-4cd8-9948-f84b1f65920f';

UPDATE ventas SET ganancia = 14000, updated_at = NOW(3)
WHERE id = '9372c8f1-a583-4953-b0df-30a26c8ef513';

UPDATE ventas SET ganancia = 12000, updated_at = NOW(3)
WHERE id = '06e408ab-b84e-403e-b51c-2e81e0b5bf4c';

-- 7) Changelog para que el movil baje las filas corregidas
INSERT INTO cambios (tabla, fila_id) VALUES
  ('lotes',         '73943cf9-b199-415d-9776-107bc1615ad6'),
  ('productos',     '97be49f4-d676-4be9-8c73-bc377d43aa95'),
  ('compra_detalle','21989f22-24aa-4b31-adc7-2e521af19962'),
  ('movimientos',   '7c3225b6-3deb-474e-a7fa-9d5c88c1756e'),
  ('venta_detalle', '0a752d7a-0a3e-4108-9d3c-2af6cab39dcb'),
  ('venta_detalle', '56be4d48-4ff0-4fd5-b6d9-42a133f975a5'),
  ('venta_detalle', '58bd80e3-f991-487c-9256-0062f96dccb8'),
  ('venta_detalle', '9367fb70-fce0-4adc-a655-0f3290d8e6c2'),
  ('ventas',        'f512861e-ae09-4b0e-9e1d-8d61714230ba'),
  ('ventas',        '6dc30616-74aa-4cd8-9948-f84b1f65920f'),
  ('ventas',        '9372c8f1-a583-4953-b0df-30a26c8ef513'),
  ('ventas',        '06e408ab-b84e-403e-b51c-2e81e0b5bf4c');

COMMIT;
