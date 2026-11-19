"""Decrypt a backup locally; never publish the key or the decrypted dump."""
import argparse
from pathlib import Path
from cryptography.fernet import Fernet

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('respaldo',type=Path)
parser.add_argument('--clave',type=Path,required=True)
parser.add_argument('--salida',type=Path,required=True)
args=parser.parse_args()
# Verify authentication before writing; refuse to overwrite an existing file.
plain=Fernet(args.clave.read_bytes().strip()).decrypt(args.respaldo.read_bytes())
with args.salida.open('xb') as output: output.write(plain)
print('Respaldo descifrado. Restaurar en una base nueva con pg_restore.')
