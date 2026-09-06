#!/usr/bin/env python3
"""Set harness environment on BitMatchTests in an Xcode-generated xctestrun."""
import plistlib
import sys
from pathlib import Path


def configure(path, assignments):
    with path.open('rb') as stream:
        document = plistlib.load(stream)
    targets = []
    if 'TestConfigurations' in document:
        for configuration in document['TestConfigurations']:
            for target in configuration.get('TestTargets', []):
                if target.get('BlueprintName') == 'BitMatchTests':
                    targets.append(target)
    elif isinstance(document.get('BitMatchTests'), dict):
        targets.append(document['BitMatchTests'])
    if not targets:
        raise ValueError('No BitMatchTests target found in generated xctestrun')
    environment = dict(item.split('=', 1) for item in assignments)
    for target in targets:
        values = target.setdefault('EnvironmentVariables', {})
        for key in ('BITMATCH_RUN_SOAK', 'BITMATCH_SOAK_SEED', 'BITMATCH_SOAK_ITERATIONS',
                    'BITMATCH_SOAK_RESULT', 'BITMATCH_FAULT_VOLUME'):
            values.pop(key, None)
        values.update(environment)
    with path.open('wb') as stream:
        plistlib.dump(document, stream)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit('Usage: configure_harness_environment.py FILE KEY=VALUE [...]')
    configure(Path(sys.argv[1]), sys.argv[2:])
