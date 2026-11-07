"""External security/codesign fixture; never invokes macOS signing tools."""
import base64
import json
import os
from pathlib import Path
import stat
import sys

command = [Path(sys.argv[0]).name, *sys.argv[1:]]
record = {'command': command}
if command[:2] == ['security', 'import']:
    source = Path(command[2])
    record.update(data=base64.b64encode(source.read_bytes()).decode(),
                  mode=stat.S_IMODE(source.stat().st_mode))
with open(os.environ['SIGN_TEST_LOG'], 'a') as log:
    log.write(json.dumps(record) + '\n')
operation = command[1]
if command[0] == 'codesign':
    operation = 'verify' if '--verify' in command else 'sign'
elif operation == 'list-keychains':
    operation = 'read' if '-s' not in command else ('restore' if len(command) == 7 else 'register')
elif operation == 'import':
    operation = 'identity' if command[2].endswith('.p12') else 'intermediate'
if operation == os.environ.get('SIGN_TEST_FAILURE'):
    print('fixture-password private fixture diagnostic', file=sys.stderr)
    sys.exit(37)
if operation == 'read':
    print('"/Users/fixture/Library/Keychains/login keychain-db"\n"/Library/Keychains/System.keychain"')
if operation == 'find-identity':
    print('0 valid identities found' if os.environ.get('SIGN_TEST_INVALID') else os.environ['MACOS_SIGNING_IDENTITY'])
