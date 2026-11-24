"""Decrypt a backup locally; never publish the key or the decrypted dump."""
import argparse
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.local/backup-tools'))
from cryptography.fernet import Fernet
from partes import leer

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('respaldo',type=Path)
parser.add_argument('--clave',type=Path,required=True)
parser.add_argument('--salida',type=Path,required=True)
args=parser.parse_args()
# Verify authentication before writing; refuse to overwrite an existing file.
plain=Fernet(args.clave.read_bytes().strip()).decrypt(leer(args.respaldo))
with args.salida.open('xb') as output: output.write(plain)
print('Respaldo descifrado. Restaurar en una base nueva con pg_restore.')
