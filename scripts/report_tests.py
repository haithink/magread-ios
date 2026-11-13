"""Expose simulator failures through public Actions annotations and summary."""
from pathlib import Path
import json
import os

messages = []
result = Path('build/test-result.json')
if result.exists():
    def visit(value):
        if isinstance(value, dict):
            message = value.get('message', {}).get('_value')
            if message:
                name = value.get('testCaseName', {}).get('_value', '')
                messages.append(f'{name}: {message}' if name else message)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(json.loads(result.read_text()))
log = Path('build/test-output.log')
if log.exists():
    for line in log.read_text(errors='replace').splitlines():
        if any(marker in line for marker in ('error:', 'failed', 'crashed', 'Timed out', 'TEST FAILED')):
            messages.append(line.strip())
messages = list(dict.fromkeys(messages))[:35]
for message in messages:
    escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print('::warning::' + escaped)
if os.environ.get('GITHUB_STEP_SUMMARY'):
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
        output.write('### Simulator test diagnostics\n\n')
        output.write('\n\n'.join(messages) if messages else 'No test failures reported.')
