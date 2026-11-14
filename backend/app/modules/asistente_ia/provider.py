"""OpenAI transport. Secrets and provider error bodies never leave this module."""
import json
import os
import logging
import socket
import ssl
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from uuid import uuid4

logger = logging.getLogger(__name__)


class AssistantError(ValueError):
    def __init__(self, message, status=400, retryable=False):
        super().__init__(message)
        self.status = status
        self.retryable = retryable


def configured():
    return bool(os.getenv('OPENAI_API_KEY', '').strip())


def _open_connection(req, timeout):
    """Recover brief transport failures within the original request budget."""
    deadline = time.monotonic() + timeout
    for attempt in range(3):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError()
        try:
            return urlopen(req, timeout=remaining)
        except HTTPError:
            # Provider responses (including auth/quota errors) are not a
            # connection failure and must retain their existing handling.
            raise
        except (URLError, OSError) as error:
            reason = error.reason if isinstance(error, URLError) else error
            permanent = isinstance(reason, ssl.SSLCertVerificationError) or (
                isinstance(reason, socket.gaierror) and reason.errno in (socket.EAI_NONAME, 11001))
            delay = .25 * (2 ** attempt)
            retry = attempt < 2 and not permanent and deadline - time.monotonic() > delay
            # Never log error text: it can contain URLs, credentials or data.
            logger.warning('OpenAI connection failure attempt=%s category=%s errno=%s retry=%s',
                           attempt + 1, type(reason).__name__, getattr(reason, 'errno', None), retry)
            if not retry:
                raise
            time.sleep(delay)


def call(path, body, content_type='application/json', timeout=60):
    key = os.getenv('OPENAI_API_KEY', '').strip()
    if not key:
        raise AssistantError('Falta configurar OPENAI_API_KEY en el backend y reiniciarlo.', 503)
    req = Request('https://api.openai.com/v1/' + path, data=body, headers={
        'Authorization': 'Bearer ' + key, 'Content-Type': content_type})
    try:
        with _open_connection(req, timeout=timeout) as response:
            return json.load(response)
    except HTTPError as error:
        messages = {401: 'La clave de OpenAI no es válida. Revisa la configuración del backend.',
                    429: 'OpenAI alcanzó el límite de solicitudes o saldo. Revisa Billing y vuelve a intentar.',
                    403: 'Tu proyecto de OpenAI no tiene acceso al modelo configurado.',
                    404: 'El modelo configurado no está disponible para tu proyecto de OpenAI.'}
        raise AssistantError(messages.get(error.code, 'OpenAI no pudo procesar la solicitud. Intenta nuevamente.'),
                             502, retryable=error.code in (500, 502, 503, 504)) from None
    except TimeoutError:
        raise AssistantError('OpenAI superó el tiempo de espera.', 504, retryable=True) from None
    except URLError as error:
        if isinstance(error.reason, TimeoutError):
            raise AssistantError('OpenAI superó el tiempo de espera.', 504, retryable=True) from None
        raise AssistantError('No se pudo conectar con OpenAI.', 502, retryable=True) from None
    except OSError:
        raise AssistantError('Se interrumpió la conexión con OpenAI.', 502, retryable=True) from None
    except ValueError:
        raise AssistantError('OpenAI devolvió una respuesta no válida.', 502) from None


def respond(messages, tools, max_output_tokens=3500):
    data = call('responses', json.dumps({
        'model': os.getenv('OPENAI_MODEL', 'gpt-6-luna'), 'store': False,
        'input': messages, 'tools': tools, 'parallel_tool_calls': False,
        'max_output_tokens': max_output_tokens,
    }, ensure_ascii=False).encode('utf-8'))
    if data.get('status') != 'completed':
        raise AssistantError('La respuesta quedó incompleta. Divide tu instrucción en pasos más pequeños.', 502)
    return data.get('output', [])


def transcribe(content, mime):
    extensions = {'audio/webm': 'webm', 'audio/mp4': 'mp4', 'audio/ogg': 'ogg',
                  'audio/wav': 'wav', 'audio/mpeg': 'mp3'}
    mime = mime.split(';')[0]
    if mime not in extensions or not content or len(content) > 15 * 1024 * 1024:
        raise AssistantError('Envía audio WebM, MP4, OGG, WAV o MP3 de hasta 15 MB.')
    boundary = 'barbarito-' + uuid4().hex
    body = b''
    for name, value in [('model', os.getenv('OPENAI_TRANSCRIPTION_MODEL', 'gpt-4o-mini-transcribe')), ('language', 'es'), ('response_format', 'json')]:
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode()
    body += (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="dictado.{extensions[mime]}"\r\nContent-Type: {mime}\r\n\r\n').encode()
    body += content + f'\r\n--{boundary}--\r\n'.encode()
    result = call('audio/transcriptions', body, 'multipart/form-data; boundary=' + boundary)
    if not isinstance(result, dict) or not isinstance(result.get('text'), str):
        raise AssistantError('El servicio de transcripción no devolvió texto válido. Intenta nuevamente.', 502)
    transcript = result['text'].strip()
    if not transcript:
        raise AssistantError('No se reconoció voz en la grabación. Reproduce el audio y comprueba el micrófono seleccionado antes de volver a dictar.', 422)
    return transcript
