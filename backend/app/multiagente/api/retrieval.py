"""Local lexical retrieval. Only immutable document chunks enter the bounded cache."""
from collections import Counter
from functools import lru_cache
from hashlib import sha256
import math
import re
import unicodedata

CHUNK_SIZE = 1600
OVERLAP = 160
STOPWORDS = frozenset('a al de del el en es la las los o para por que se un una y cuando como'.split())


def terms(text):
    normalized = ''.join(c for c in unicodedata.normalize('NFKD', text.casefold())
                         if not unicodedata.combining(c))
    return [word for word in re.findall(r'\w+', normalized) if word not in STOPWORDS]


@lru_cache(maxsize=64)
def document_chunks(content):
    """Bound cache memory as well as entry count; callers provide document text only."""
    content = content[:200000]
    digest = sha256(content.encode('utf-8')).hexdigest()
    return tuple((index + 1, digest, content[start:start + CHUNK_SIZE])
                 for index, start in enumerate(range(0, len(content), CHUNK_SIZE - OVERLAP)))


def select(documents, query, limit, provenance=None):
    """Return provenance-labelled chunks; never memoize a query or its results."""
    candidates = []
    for document in documents:
        for number, digest, text in document_chunks(document.get('contenido', '')[:200000]):
            candidates.append((document, number, digest, text, Counter(terms(text))))
    query_terms = set(terms(query[:12000]))
    frequencies = Counter(term for item in candidates for term in set(item[4]) if term in query_terms)
    def score(item):
        counts = item[4]
        return sum((1 + math.log(counts[term])) * math.log(1 + len(candidates) / frequencies[term])
                   for term in query_terms if counts[term]) / (1 + len(item[3]) / CHUNK_SIZE)
    ranked = sorted(candidates, key=score, reverse=True)
    if query_terms:
        ranked = [item for item in ranked if score(item) > 0]
        if not ranked:
            return '[Sin coincidencias relevantes en los documentos activos para esta consulta.]'
    parts = []
    remaining = max(0, limit)
    partial = False
    for document, number, digest, text, _ in ranked:
        # Escape source metadata so filenames cannot create false provenance lines.
        name = str(document.get('nombre', '')).replace('\n', ' ').replace('\r', ' ')
        source_id = str(document.get('id', '')).replace('\n', ' ').replace('\r', ' ')
        header = f'Archivo: {name} | id:{source_id} | sha256:{digest} | fragmento:{number}\n'
        if remaining <= len(header):
            break
        excerpt = text[:remaining - len(header)]
        partial = partial or len(excerpt) < len(text)
        parts.append(header + excerpt)
        if provenance is not None:
            provenance.append({'id': str(document.get('id', '')), 'sha256': digest,
                               'fragmento': number})
        remaining -= len(header) + len(excerpt) + 2
        if remaining <= 0:
            break
    if partial or len(parts) < len(ranked):
        parts.append('[Referencia truncada: selección parcial de fragmentos; no afirmar lectura completa.]')
    return '\n\n'.join(parts)
