"""SQL integration; only a disposable database supplied explicitly by the runner."""
import os
import unittest
from datetime import date
from unittest.mock import patch
from sqlalchemy import create_engine, text
from app.modules.inventarios.demand import report


@unittest.skipUnless(os.environ.get('DEMAND_TEST_DSN'), 'Requires disposable demand database')
class DemandPostgresTests(unittest.TestCase):
    def test_paid_receipts_shared_consumption_local_and_lima_boundaries(self):
        engine = create_engine(os.environ['DEMAND_TEST_DSN'])
        try:
            with engine.connect() as conn, conn.begin():
                self.assertEqual(conn.execute(text('select current_database()')).scalar(), 'demand_test')
                conn.exec_driver_sql('''
                CREATE TEMP TABLE salon_cobro(id_local int, creado_en timestamptz, comprobante jsonb, id_movimiento int);
                CREATE TEMP TABLE presentacion_venta(id_presentacion_venta int, id_item_carta int);
                CREATE TEMP TABLE item_carta(id_item_carta int, id_categoria_carta int);
                CREATE TEMP TABLE categoria_carta(id_categoria_carta int,nombre text);
                CREATE TEMP TABLE movimiento_inventario(id_movimiento_inventario int,id_local int);
                CREATE TEMP TABLE movimiento_inventario_detalle(id_movimiento_inventario int,id_producto int,cantidad numeric);
                CREATE TEMP TABLE inventario_evento(id_local int,id_producto int,cantidad numeric,registrado_en timestamptz);
                CREATE TEMP TABLE producto(id_producto int,codigo text,nombre text,unidad text,id_categoria int,activo bool);
                CREATE TEMP TABLE categoria_producto(id_categoria int,nombre text);
                CREATE TEMP TABLE inventario_stock_teorico(id_local int,id_producto int,stock_actual numeric);
                INSERT INTO producto VALUES(1,'Q1','Queso','kg',1,true),(2,'B1','IPA','L',1,true);
                INSERT INTO categoria_producto VALUES(1,'Productos');
                INSERT INTO inventario_stock_teorico VALUES(1,1,12),(2,1,999),(1,2,5);
                INSERT INTO presentacion_venta VALUES(10,10),(11,11);
                INSERT INTO item_carta VALUES(10,1),(11,1);
                INSERT INTO categoria_carta VALUES(1,'Comida');
                INSERT INTO movimiento_inventario VALUES(1,1),(2,1),(3,2),(4,1);
                INSERT INTO movimiento_inventario_detalle VALUES(1,1,2),(2,1,4),(3,1,999),(4,1,100);
                INSERT INTO salon_cobro VALUES
                  (1,'2026-10-02 04:00:00+00','{"lineas":[{"id_presentacion":10,"nombre":"Hamburguesa","cantidad":2,"precio":10}]}',1),
                  (1,'2026-10-03 04:00:00+00','{"lineas":[{"id_presentacion":11,"nombre":"Papas","cantidad":1,"precio":8}]}',2),
                  (2,'2026-10-02 04:00:00+00','{"lineas":[{"id_presentacion":10,"nombre":"Otra tienda","cantidad":999,"precio":10}]}',3),
                  (1,'2026-10-03 05:00:00+00','{"lineas":[{"id_presentacion":10,"nombre":"Fuera del periodo","cantidad":100,"precio":10}]}',4);
                INSERT INTO inventario_evento VALUES(1,1,20,'2026-10-02 04:00:00+00'),(1,1,-100,'2026-10-02 04:00:00+00'),(2,1,999,'2026-10-02 04:00:00+00');
                ''')
                def rows(sql, params):
                    return [dict(r) for r in conn.execute(text(sql), params).mappings()]
                with patch('app.modules.inventarios.operativo.filas', side_effect=rows):
                    result = report(1, date(2026,10,1), date(2026,10,2))
                self.assertEqual(sum(r['cantidad'] for r in result['articulos']), 3)
                cheese = result['productos'][0]
                self.assertEqual(cheese['consumo_ventas'], 6)
                self.assertEqual(cheese['consumo_diario'], 3)
                self.assertEqual(cheese['cobertura_dias'], 4)
                self.assertEqual(cheese['entradas'], 20)
                self.assertEqual(result['productos'][1]['prioridad'], 'SIN_CONSUMO_REGISTRADO')
                conn.exec_driver_sql('''INSERT INTO salon_cobro VALUES
                  (1,'2026-10-03 04:30:00+00','{"lineas":[{"id_presentacion":10,"nombre":"Hamburguesa renombrada","cantidad":2,"precio":12}]}',NULL),
                  (1,'2026-10-03 04:40:00+00','{"lineas":[{"id_presentacion":null,"id_promocion":20,"nombre":"Combo","cantidad":1,"precio":30,"selecciones_promocion":[{"id_presentacion":10,"nombre":"Hamburguesa renombrada"}]}]}',NULL),
                  (1,'2026-10-03 04:50:00+00','{"lineas":[{"id_presentacion":null,"id_promocion":21,"nombre":"Otro combo","cantidad":1,"precio":40}]}',NULL);''')
                with patch('app.modules.inventarios.operativo.filas', side_effect=rows):
                    expanded = report(1, date(2026,10,1), date(2026,10,2))
                burgers = [r for r in expanded['articulos'] if r['id_presentacion']==10]
                self.assertEqual(len(burgers), 1)
                self.assertEqual(burgers[0]['nombre'], 'Hamburguesa renombrada')
                self.assertEqual(burgers[0]['cantidad'], 5)
                self.assertEqual(burgers[0]['cantidad_en_promociones'], 1)
                self.assertEqual(burgers[0]['total'], 44)
                self.assertEqual({r['id_promocion'] for r in expanded['articulos'] if r['id_promocion']}, {20,21})
        finally:
            engine.dispose()
