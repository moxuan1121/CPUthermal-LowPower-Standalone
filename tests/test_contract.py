from pathlib import Path
import plistlib
import struct

root = Path(__file__).resolve().parents[1]
sample = plistlib.loads((root / "preferences.example.plist").read_bytes())
assert sample["enabled"] is True
assert sample["whitelistEnabled"] is False
assert set(sample) == {"enabled", "whitelistEnabled", "lowPowerStrength", "lowPowerApps"}
assert plistlib.loads(plistlib.dumps(sample)) == sample
for name in ("CTLowPower.plist", "CTLowPowerForeground.plist"):
    assert "Filter" in plistlib.loads((root / name).read_bytes())

code = (root / "LowPower.xm").read_text(encoding="utf-8")
assert "MIN(target, CTCapMW())" in code
assert "MAX(level, 2)" in code
assert "%hook CommonProduct" in code
assert "%hook ApplePPMCPU" in code
assert "CTApplyKnownLevel(ppm)" in code
assert "CTApplyKnownLevel(result);" in code
assert "CTApplyKnownLevel(self);" in code
assert "level >= 0 && level < 2" in code
assert "MIN(ceiling, CTCapPercent())" in code
assert "CTRefreshMode" in code
assert "return !selected || CTContainsHash(whitelist, CTForegroundHash());" in code
assert '"com.apple.springboard.hasBlankedScreen"' not in code
assert "shouldApplyFullCPUProtection" not in code
assert "setPackageLowPowerTarget" not in code
assert "setPowerSaveActive" not in code
assert "jbroot(@\"/var/mobile/Library/Preferences/" in code
makefile = (root / "Makefile").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/package.yml").read_text(encoding="utf-8")
control = (root / "control").read_text(encoding="utf-8")
assert "THEOS_PACKAGE_SCHEME = roothide" in makefile
assert "roothide/theos.git" in workflow
assert "THEOS_PACKAGE_SCHEME=roothide" in workflow
assert "Architecture: iphoneos-arm64e" in control
assert "THEOS_PACKAGE_SCHEME=rootless" not in workflow
assert "preferenceloader" in control
assert "rootless-compat" not in control
assert "killall -q thermalmonitord" in (root / "layout/DEBIAN/postinst").read_text(encoding="utf-8")

settings = root / "Settings"
info = plistlib.loads((settings / "Info.plist").read_bytes())
entry = plistlib.loads((root / "layout/Library/PreferenceLoader/Preferences/CTLowPowerSettings.plist").read_bytes())["entry"]
items = plistlib.loads((settings / "Root.plist").read_bytes())["items"]
assert info["NSPrincipalClass"] == entry["detail"] == "CTLowPowerRootListController"
assert entry["bundle"] == info["CFBundleExecutable"] == "CTLowPowerSettings"
assert entry["icon"] == "icon.png"
entitlements = plistlib.loads((settings / "Settings.entitlements").read_bytes())
assert entitlements["platform-application"] is True
assert {item.get("key") for item in items if "key" in item} == {"enabled", "whitelistEnabled", "lowPowerStrength"}
assert next(item for item in items if item.get("key") == "whitelistEnabled")["cell"] == "PSSwitchCell"
assert {item.get("detail") for item in items if "detail" in item} == {"CTLowPowerAppListController"}
for filename, size in (("icon.png", 29), ("icon@2x.png", 58), ("icon@3x.png", 87)):
    data = (settings / filename).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", data[16:24]) == (size, size)
    assert data[25] == 6  # RGBA: rounded corners have transparency.
for filename in ("CTLowPowerRootListController.m", "CTLowPowerAppListController.m"):
    assert '@"' not in (settings / filename).read_text(encoding="utf-8")
assert '@"' not in (settings / "CTSettingsPrefs.h").read_text(encoding="utf-8")

h = 1469598103934665603
for byte in b"com.example.game":
    h = ((h ^ byte) * 1099511628211) & ((1 << 64) - 1)
assert h == 0xBEF3442DC20DC844
print("standalone low-power static contract: OK")
