from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
sample = plistlib.loads((root / "preferences.example.plist").read_bytes())
assert sample["enabled"] is True
assert sample["powerMode"] == "lowPower"
assert set(sample) == {"enabled", "powerMode", "lowPowerStrength", "fullPowerApps", "lowPowerApps"}
assert plistlib.loads(plistlib.dumps(sample)) == sample
for name in ("CTLowPower.plist", "CTLowPowerForeground.plist"):
    assert "Filter" in plistlib.loads((root / name).read_bytes())

code = (root / "LowPower.xm").read_text(encoding="utf-8")
assert "MIN(target, CTCapMW())" in code
assert "MIN(ceiling, CTCapPercent())" in code
assert "CTRefreshMode" in code
assert "shouldApplyFullCPUProtection" not in code
assert "setPackageLowPowerTarget" not in code
assert "setPowerSaveActive" not in code

h = 1469598103934665603
for byte in b"com.example.game":
    h = ((h ^ byte) * 1099511628211) & ((1 << 64) - 1)
assert h == 0xBEF3442DC20DC844
print("standalone low-power static contract: OK")
