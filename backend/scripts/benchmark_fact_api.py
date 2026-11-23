"""Measure the LOCAL demo bridge, never SUNAT or real sales.

Creates N explicitly labelled test documents in fact_api_demo only.
No payments, stock or purchase orders are changed. Outputs aggregate timings,
without tokens, customer documents or PDF contents.
"""
import argparse
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path
import statistics
import sys
from time import perf_counter
from uuid import uuid4

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.modules.facturacion.transport import call, validate_url
import os


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples',type=int,default=5)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if not 1<=args.samples<=20:parser.error('Usa entre 1 y 20 muestras.')
    url=validate_url(os.environ['FACT_API_URL'])
    from urllib.parse import urlsplit
    if urlsplit(url).hostname not in ('localhost','127.0.0.1','::1'):
        parser.error('Esta prueba crea documentos y solo se permite en localhost DEMO.')
    health=call('health')
    if health.get('modo')!='DEMO':
        raise RuntimeError('Se requiere un servicio DEMO confirmado.')
    measured={name:[] for name in ('registro','registro_repetido','pdf_a4_primero','pdf_a4_guardado','pdf_ticket_primero','pdf_ticket_guardado','total_registro_y_dos_pdf')}
    today=datetime.now(timezone(timedelta(hours=-5))).date().isoformat()
    for index in range(args.samples):
        key=str(uuid4())
        payload={'version':1,'origen':'VENTA','referencia':'BENCH-'+key[:8],'id_local':1,
            'empresa':{'nombre':'BARBARIAN','ruc':'00000000000'},'tipo':'03' if index%2==0 else '01',
            'serie':'TB01' if index%2==0 else 'TF01','fecha':today,'moneda':'PEN',
            'tercero':{'nombre':'PRUEBA DE RENDIMIENTO','documento':'','tipo':'1'},
            'lineas':[{'codigo':'BENCH','nombre':'Artículo de prueba, sin cobro real','cantidad':'1','unidad':'C62',
                'subtotal':'13.14','igv':'2.36','total':'15.50','tasa_igv':'18','afectacion':'GRAVADO'}],
            'subtotal':'13.14','igv':'2.36','total':'15.50'}
        timings={}
        def timed(name,*a,**kw):
            start=perf_counter();result=call(*a,**kw)
            timings[name]=round((perf_counter()-start)*1000,2)
            measured[name].append(timings[name]);return result
        result=timed('registro','documents',payload,key)
        assert result['total']=='15.50'
        assert timed('registro_repetido','documents',payload,key)['numero']==result['numero']
        for fmt,tag in [('A4','a4'),('80mm','ticket')]:
            path=f'documents/{key}/pdf?format={fmt}'
            first=timed(f'pdf_{tag}_primero',path,binary=True)
            assert first==timed(f'pdf_{tag}_guardado',path,binary=True)
        measured['total_registro_y_dos_pdf'].append(round(sum(timings[k] for k in ('registro','pdf_a4_primero','pdf_ticket_primero')),2))
        print(f'Muestra {index+1}/{args.samples}: completada',flush=True)
    def summarize(values):
        ordered=sorted(values)
        # Nearest-rank p95; small N is exploratory, not a capacity/SLA test.
        import math
        return {'n':len(values),'media_ms':round(statistics.mean(values),2),
            'mediana_ms':round(statistics.median(values),2),'p95_ms':ordered[math.ceil(.95*len(values))-1],
            'min_ms':min(values),'max_ms':max(values)}
    report={'fecha_lima':datetime.now(timezone(timedelta(hours=-5))).isoformat(),'modo':'DEMO_LOCAL',
        'alcance':'HTTP secuencial, documento de una línea; sin espera en cola ni SUNAT',
        'mediciones':{name:summarize(values) for name,values in measured.items()}}
    encoded=json.dumps(report,ensure_ascii=False,indent=2)
    if args.output:args.output.write_text(encoded+'\n',encoding='utf-8')
    print(encoded)


if __name__=='__main__':main()
