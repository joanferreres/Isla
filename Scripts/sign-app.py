#!/usr/bin/env python3
"""Reuse Isla's local certificate so macOS permissions survive rebuilds.

The private key lives in a dedicated local keychain, never in the repository
or distributable. No Apple membership or system trust override is required.
On another Mac without that identity, packaging keeps the ad hoc fallback.
"""
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1])
base = Path.home() / 'Library/Application Support/Isla/Signing'
keychain = base / 'isla-signing.keychain-db'
certificate = base / 'certificate.pem'
password = base / 'keychain-password'
helper = app / 'Contents/Resources/MediaRemoteAdapter/libIslaMediaRemoteAdapter.dylib'
widget = app / 'Contents/PlugIns/IslaWidget.appex'
widget_entitlements = Path(__file__).resolve().parent.parent / 'Resources/Widget.entitlements'
if all(p.exists() for p in (keychain, certificate, password)):
    result = subprocess.run(['security', 'unlock-keychain', '-p', password.read_text(), str(keychain)], capture_output=True)
    if result.returncode:
        raise SystemExit('Cannot unlock Isla signing identity; refusing to change its identity.')
    fingerprint = subprocess.check_output(['openssl', 'x509', '-in', str(certificate), '-noout', '-fingerprint', '-sha1'], text=True).strip().split('=')[1].replace(':', '')
    args = ['codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain)]
    subprocess.run(args + [str(helper)], check=True)
    if widget.exists():
        subprocess.run(args + ['--entitlements', str(widget_entitlements), str(widget)], check=True)
    requirement = f'-r=designated => identifier "local.personal.isla" and certificate leaf = H"{fingerprint}"'
    subprocess.run(args + [requirement, str(app)], check=True)
    print('Signed with persistent personal Isla identity.')
else:
    print('Personal identity absent: ad hoc signature; permissions may need renewing after updates.')
    args = ['codesign', '--force', '--sign', '-']
    subprocess.run(args + [str(helper)], check=True)
    if widget.exists():
        subprocess.run(args + ['--entitlements', str(widget_entitlements), str(widget)], check=True)
    subprocess.run(args + [str(app)], check=True)
