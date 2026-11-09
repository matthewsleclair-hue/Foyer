#!/usr/bin/env python3
"""Makes android/app/build.gradle(.kts) sign release builds with android/key.properties.
Safe to run more than once. Without key.properties it falls back to the debug key."""
import os, re, sys

proj = sys.argv[1] if len(sys.argv) > 1 else '.'
app = os.path.join(proj, 'android', 'app')
kts = os.path.join(app, 'build.gradle.kts')
groovy = os.path.join(app, 'build.gradle')
path = kts if os.path.exists(kts) else groovy
if not os.path.exists(path):
    sys.exit('No android/app/build.gradle(.kts) found in ' + proj)
s = open(path).read()
if 'keystoreProperties' in s:
    print('Signing already set up in', os.path.basename(path)); sys.exit(0)

if path.endswith('.kts'):
    load = '''
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

'''
    signing = '''    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

'''
    s = 'import java.util.Properties\n' + s
    relsign = 'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
    s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', relsign, s)
else:
    load = '''
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

'''
    signing = '''    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }

'''
    relsign = 'signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug'
    s = re.sub(r'signingConfig\s+signingConfigs\.debug', relsign, s)

m = re.search(r'^android\s*\{', s, re.M)
if not m:
    sys.exit('Could not find the android { block')
s = s[:m.start()] + load.lstrip('\n') + s[m.start():]
m = re.search(r'^\s*buildTypes\s*\{', s, re.M)
if not m:
    sys.exit('Could not find buildTypes')
s = s[:m.start()] + signing + s[m.start():]
if 'keystorePropertiesFile.exists()) signingConfigs' not in s and 'keystorePropertiesFile.exists() ?' not in s:
    sys.exit('Could not find the release signingConfig line to replace; edit it by hand.')
open(path, 'w').write(s)
print('Release signing added to', os.path.basename(path))
