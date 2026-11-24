"""Split ciphertext only; authenticate the reassembled archive before decrypting."""
from pathlib import Path
import re


def dividir(data, name, maximum=32*1024*1024):
    if maximum <= 0:raise ValueError('Tamaño de parte inválido.')
    if len(data) <= maximum:return [(name,data)]
    return [(name+f'.part{index//maximum+1:03}',data[index:index+maximum]) for index in range(0,len(data),maximum)]


def leer(path):
    path=Path(path)
    match=re.fullmatch(r'(.+\.enc)\.part(\d{3})',path.name)
    if not match:return path.read_bytes()
    if match[2]!='001':raise ValueError('Selecciona la primera parte (.part001).')
    parts=sorted(file for file in path.parent.glob(match[1]+'.part*') if re.fullmatch(re.escape(match[1])+r'\.part\d{3}',file.name))
    if [int(file.name[-3:]) for file in parts]!=list(range(1,len(parts)+1)):
        raise ValueError('Faltan partes del respaldo.')
    return b''.join(file.read_bytes() for file in parts)
