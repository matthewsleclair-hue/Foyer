#!/usr/bin/env python3
"""Adds the Android libraries Foyer's native code uses to android/app/build.gradle(.kts), once.
  - ZXing core: draws QR codes on the TV (e.g. "scan to type on your phone").
Usage: python3 tools/patch_deps.py <project-path>   (update.sh and release.sh run it for you)"""
import os
import sys

proj = sys.argv[1] if len(sys.argv) > 1 else '.'
app = os.path.join(proj, 'android', 'app')
kts = os.path.join(app, 'build.gradle.kts')
groovy = os.path.join(app, 'build.gradle')
path = kts if os.path.exists(kts) else groovy
if not os.path.exists(path):
    sys.exit('No android/app/build.gradle(.kts) found in ' + proj)
s = open(path).read()
if 'com.google.zxing:core' in s:
    sys.exit(0)
if path.endswith('.kts'):
    s = s.rstrip() + '\n\ndependencies {\n    implementation("com.google.zxing:core:3.5.3")\n}\n'
else:
    s = s.rstrip() + "\n\ndependencies {\n    implementation 'com.google.zxing:core:3.5.3'\n}\n"
open(path, 'w').write(s)
print('Added ZXing (QR codes) to', os.path.basename(path))
