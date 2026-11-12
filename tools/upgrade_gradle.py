#!/usr/bin/env python3
"""Moves the Flutter project's Android build to Gradle 9 / Android Gradle Plugin 9 / Kotlin 2.3,
following Flutter's "Migrate to AGP 9 / built-in Kotlin" guides. Keeps a .bak of every file it changes.
Usage: python3 tools/upgrade_gradle.py [project-path]      (default ~/Downloads/leclair_home)
Then:  cd <project> && flutter clean, and build as usual."""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

GRADLE, AGP, KOTLIN = "9.3.1", "9.0.1", "2.3.20"

proj = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Downloads" / "leclair_home")
android = proj / "android"
if not android.is_dir():
    sys.exit(f"No android/ folder in {proj}")
changed = []

flutter_ok = False
flutter_ver = None
try:
    v = json.loads(subprocess.run(["flutter", "--version", "--machine"], capture_output=True, text=True).stdout)
    major, minor = (int(x) for x in v["frameworkVersion"].split(".")[:2])
    flutter_ver = (major, minor)
    flutter_ok = flutter_ver >= (3, 47)
    print(f"Flutter {v['frameworkVersion']}")
except Exception:
    print("Couldn't read the Flutter version; assuming it's older than 3.47")


if flutter_ver is not None and flutter_ver < (3, 44):
    sys.exit("Your Flutter is older than 3.44, which can't build with Android Gradle Plugin 9. "
             "Run 'flutter upgrade' first, then this again. Nothing was changed.")



def edit(path: Path, fn):
    if not path.exists():
        return False
    old = path.read_text()
    new = fn(old)
    if new != old:
        bak = path.with_name(path.name + ".bak")
        if not bak.exists():
            shutil.copy2(path, bak)
        path.write_text(new)
        changed.append(str(path.relative_to(proj)))
    return True


def first(*names):
    for n in names:
        p = android / n
        if p.exists():
            return p
    return android / names[0]


# 1. Gradle itself
edit(android / "gradle" / "wrapper" / "gradle-wrapper.properties",
     lambda s: re.sub(r"gradle-[0-9.]+-(all|bin)\.zip", f"gradle-{GRADLE}-all.zip", s))


# 2. AGP and Kotlin versions (plugins block, Kotlin or Groovy syntax; or the old buildscript form)
def versions(s):
    s = re.sub(r'(id\s*\(?\s*["\']com\.android\.application["\']\s*\)?\s*version\s*)["\'][^"\']+["\']',
               rf'\1"{AGP}"', s)
    s = re.sub(r'(id\s*\(?\s*["\']org\.jetbrains\.kotlin\.android["\']\s*\)?\s*version\s*)["\'][^"\']+["\']',
               rf'\1"{KOTLIN}"', s)
    s = re.sub(r"(com\.android\.tools\.build:gradle:)[0-9.]+", rf"\g<1>{AGP}", s)
    s = re.sub(r"(ext\.kotlin_version\s*=\s*)['\"][^'\"]+['\"]", rf"\1'{KOTLIN}'", s)
    return s


edit(first("settings.gradle.kts", "settings.gradle"), versions)
edit(first("build.gradle.kts", "build.gradle"), versions)


# 3. app/build.gradle(.kts): AGP 9 has Kotlin built in, so the kotlin-android plugin goes,
#    and kotlinOptions { jvmTarget } becomes kotlin { compilerOptions { jvmTarget } }.
def app(s):
    jvm = "17"
    m = re.search(r"kotlinOptions\s*\{[^{}]*?jvmTarget[^\n]*?(\d+)", s)
    if m:
        jvm = m.group(1)
    s = re.sub(r'^[ \t]*id\s*\(?\s*["\'](kotlin-android|org\.jetbrains\.kotlin\.android)["\']\s*\)?[^\n]*\n', "", s, flags=re.M)
    s = re.sub(r"^[ \t]*apply plugin:\s*['\"]kotlin-android['\"][^\n]*\n", "", s, flags=re.M)
    s = re.sub(r"\n[ \t]*kotlinOptions\s*\{[^{}]*\}[ \t]*\n", "\n", s)
    if "compilerOptions" not in s:
        s = s.rstrip() + (
            "\n\nkotlin {\n    compilerOptions {\n"
            f"        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_{jvm}\n"
            "    }\n}\n")
    return s


edit(first("app/build.gradle.kts", "app/build.gradle"), app)

# 4. gradle.properties: old AGP DSL for now (Flutter still needs it); built-in Kotlin when Flutter supports it
def props(s):
    def put(s, key, val):
        if re.search(rf"^{re.escape(key)}\s*=", s, flags=re.M):
            return re.sub(rf"^{re.escape(key)}\s*=.*$", f"{key}={val}", s, flags=re.M)
        return s.rstrip() + f"\n{key}={val}\n"
    s = put(s, "android.newDsl", "false")
    s = put(s, "android.builtInKotlin", "true" if flutter_ok else "false")
    return s


edit(android / "gradle.properties", props)

print("Changed: " + (", ".join(changed) if changed else "nothing (already up to date)"))
print(f"Now: Gradle {GRADLE}, Android Gradle Plugin {AGP}, Kotlin {KOTLIN}, built-in Kotlin "
      + ("on" if flutter_ok else "off (needs Flutter 3.47+; run 'flutter upgrade' then this again)"))
print("Backups end in .bak. Next:  cd '%s' && flutter clean   then build as usual." % proj)
