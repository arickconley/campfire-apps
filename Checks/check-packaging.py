"""Check packaging argument handling without mounting images or downloading tools."""
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).resolve().parents[1] / 'Packaging/build-dmg.sh'
with tempfile.TemporaryDirectory(prefix='campfire packaging ') as directory:
    root = Path(directory)
    app = root / 'Campfire.app'
    (app / 'Contents').mkdir(parents=True)
    (app / 'Contents/Info.plist').touch()
    tools = root / 'tools'
    tools.mkdir()
    for name, body in {
        'uvx': 'printf "%s\\n" "$@" > "$CAPTURE"\nfor arg; do output="$arg"; done\ntouch "$output"',
        'hdiutil': '[ "$1" = verify ] && [ -f "$2" ]',
    }.items():
        tool = tools / name
        tool.write_text('#!/bin/bash\nset -eu\n' + body + '\n')
        tool.chmod(0o755)
    capture = root / 'arguments'
    env = dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}', CAPTURE=str(capture))
    output = root / 'output directory/Campfire.dmg'
    def run(*args):
        return subprocess.run([str(script), *map(str, args)], cwd=root, env=env,
                              capture_output=True, text=True)
    result = run(app, output)
    assert result.returncode == 0, result.stderr
    arguments = capture.read_text().splitlines()
    assert arguments == ['--from', 'dmgbuild==1.6.7', 'dmgbuild', '-s',
                         'Packaging/dmg-settings.py', '-D', f'app={app}', 'Campfire', str(output)]
    assert run(app, output).returncode != 0
    assert run(root / 'missing.app', root / 'missing.dmg').returncode != 0
    assert run().returncode != 0
print('Packaging checks passed.')
