"""Sign two different builds without running either app or touching TCC."""

import importlib.util
from pathlib import Path
import plistlib
import re
import shutil
import tempfile

spec = importlib.util.spec_from_file_location("signing", Path(__file__).resolve().parents[1] / "scripts/signing.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


def build_app(directory, version, identifier, identity):
    app = directory / "MX Signing Check.app"
    helper = app / "Contents/Library/LoginItems/MX Signing Check Agent.app"
    for bundle, name, bundle_id in [(app, "Check", identifier), (helper, "Agent", identifier + ".agent")]:
        executable = bundle / "Contents/MacOS" / name
        executable.parent.mkdir(parents=True)
        source = directory / (name + ".c")
        source.write_text(f"int main(void) {{ return {version}; }}\n")
        signing.run("/usr/bin/clang", str(source), "-o", str(executable))
        with (bundle / "Contents/Info.plist").open("wb") as file:
            plistlib.dump(dict(CFBundleIdentifier=bundle_id, CFBundleExecutable=name,
                               CFBundlePackageType="APPL", CFBundleVersion=str(version)), file)
    signing.sign(helper, identifier + ".agent", identity)
    signing.sign(app, identifier, identity)
    signing.run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    return app, helper


def code_hash(app):
    output = signing.run("/usr/bin/codesign", "-d", "--verbose=4", str(app))
    return re.search(r"^CDHash=(.+)$", output, re.MULTILINE)[1]


def main():
    identity = signing.resolve_identity()
    identifier = "local.baggie.mxforward.signing-check"
    with tempfile.TemporaryDirectory(prefix="mx-signing-check.") as directory:
        root = Path(directory)
        first = build_app(root / "first", 1, identifier, identity)
        second = build_app(root / "second", 2, identifier, identity)
        for old, new in zip(first, second):
            old_rule = signing.designated_requirement(old)
            assert code_hash(old) != code_hash(new), "Test binaries unexpectedly have the same hash"
            assert old_rule == signing.designated_requirement(new), "Rebuilding changed the signing identity"
            signing.run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + old_rule, str(new))
        unsigned = root / "Ad Hoc.app"
        shutil.copytree(second[1], unsigned)
        signing.run("/usr/bin/codesign", "--force", "--sign", "-", str(unsigned))
        try:
            signing.check(unsigned, identifier + ".agent")
        except signing.SigningError:
            pass
        else:
            raise AssertionError("An ad-hoc app passed the installer check")
    print("PASS: changed UI/agent binaries keep the same certificate requirement; ad-hoc builds are rejected")


if __name__ == "__main__":
    main()
