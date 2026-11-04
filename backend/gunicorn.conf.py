import os

bind = '0.0.0.0:' + os.getenv('PORT', '8080')
# Workspace limits and rate limits are per-process. Keep one worker/replica.
workers = 1
threads = 4
timeout = 180
graceful_timeout = 30
accesslog = '-'
errorlog = '-'
