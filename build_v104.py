import os
import subprocess
import shutil
import sys

flutter = r"D:\flutter\bin\flutter.bat"
base = r"d:\notenra"
rel_dir = os.path.join(base, "release_builds")
os.makedirs(rel_dir, exist_ok=True)

# DEMO_ACCOUNTS=false is REQUIRED for any build that reaches real users: without
# it the encrypted DB is seeded with built-in demo logins and fake patient rows
# (see lib/app_config.dart). Never ship a store build without this flag.
DEMO_OFF = "--dart-define=DEMO_ACCOUNTS=false"

print("=== Building Release APK v1.0.4 ===")
p_apk = subprocess.run([flutter, "build", "apk", "--release", "--no-tree-shake-icons", DEMO_OFF], cwd=base)
if p_apk.returncode != 0:
    print(f"Error building APK (code {p_apk.returncode})")
    sys.exit(1)

apk_src = os.path.join(base, "build", "app", "outputs", "flutter-apk", "app-release.apk")
target_apk = os.path.join(rel_dir, "notenra-v1.0.4-release.apk")
shutil.copyfile(apk_src, target_apk)
print(f"[SUCCESS] Created {target_apk} ({os.path.getsize(target_apk)} bytes)")

print("\n=== Building Release App Bundle (AAB) v1.0.4 ===")
p_aab = subprocess.run([flutter, "build", "appbundle", "--release", "--no-tree-shake-icons", DEMO_OFF], cwd=base)
if p_aab.returncode != 0:
    print(f"Error building AppBundle (code {p_aab.returncode})")
    sys.exit(1)

aab_src = os.path.join(base, "build", "app", "outputs", "bundle", "release", "app-release.aab")
target_aab = os.path.join(rel_dir, "notenra-v1.0.4-playstore.aab")
shutil.copyfile(aab_src, target_aab)
print(f"[SUCCESS] Created {target_aab} ({os.path.getsize(target_aab)} bytes)")

print("\nAll files in release_builds:")
for f in os.listdir(rel_dir):
    p = os.path.join(rel_dir, f)
    print(f"  • {f} ({os.path.getsize(p):,} bytes)")
