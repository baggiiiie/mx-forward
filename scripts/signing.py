#!/usr/bin/env python3
"""Keep the same certificate identity across local app rebuilds."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import NamedTuple


class SigningError(Exception):
    pass


class Identity(NamedTuple):
    fingerprint: str
    name: str


def run(*arguments):
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise SigningError(result.stdout.strip() or f"{arguments[0]} failed")
    return result.stdout


def available_identities():
    output = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning")
    return [Identity(match[0].upper(), match[1]) for match in re.findall(
        r'^\s*\d+\)\s+([0-9a-fA-F]{40})\s+"(.+)"\s*$', output, re.MULTILINE)]


def select_identity(identities, explicit=None, saved=None):
    choice = explicit or saved
    if choice == "-":
        raise SigningError("Ad-hoc signing breaks permission continuity. Select a code-signing certificate instead.")
    if choice:
        matches = [item for item in identities
                   if item.fingerprint == choice.upper() or item.name == choice]
        if len(matches) == 1:
            return matches[0]
        raise SigningError(f"Signing identity {choice!r} is missing, expired, or ambiguous. "
                           "Set MX_FORWARD_SIGN_IDENTITY to a valid certificate's SHA-1 fingerprint.")
    if len(identities) == 1:
        return identities[0]
    raise SigningError("Select a code-signing certificate with MX_FORWARD_SIGN_IDENTITY. "
                       "Use 'security find-identity -v -p codesigning' to list choices. "
                       "If none exist, create a Code Signing certificate in Keychain Access or Xcode.")


def resolve_identity(explicit=None):
    path = Path.home() / ".config/mx-forward/signing-identity"
    saved = path.read_text().strip() if path.exists() else None
    identity = select_identity(available_identities(), explicit or os.environ.get("MX_FORWARD_SIGN_IDENTITY"), saved)
    if saved != identity.fingerprint:
        if saved:
            print("Signing certificate changed; macOS may need one new permission grant.", file=sys.stderr)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        # Replace atomically so an interrupted build can't leave a partial fingerprint.
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as file:
            temporary = Path(file.name)
            file.write(identity.fingerprint + "\n")
        try:
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return identity


def requirement(identifier, fingerprint):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", identifier):
        raise SigningError("Invalid bundle identifier")
    if not re.fullmatch(r"[0-9A-Fa-f]{40}", fingerprint):
        raise SigningError("Invalid certificate fingerprint")
    return f'identifier "{identifier}" and certificate leaf = H"{fingerprint.upper()}"'


def designated_requirement(app):
    output = run("/usr/bin/codesign", "-d", "-r-", str(app))
    for line in output.splitlines():
        if "designated => " in line:
            return line.split("designated => ", 1)[1].strip()
    raise SigningError(f"No signing requirement found for {app}")


def check(app, identifier):
    run("/usr/bin/codesign", "--verify", "--strict", str(app))
    rule = designated_requirement(app)
    match = re.fullmatch(r'identifier "([A-Za-z0-9.-]+)" and certificate leaf = H"([0-9A-Fa-f]{40})"', rule)
    if not match or match[1] != identifier:
        raise SigningError(f"{app} isn't signed with MX Forward's stable certificate requirement. "
                           "Rebuild it with scripts/build-app.sh before installing.")
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + rule, str(app))
    return match[2].upper()


def sign(app, identifier, identity):
    rule = requirement(identifier, identity.fingerprint)
    output = run("/usr/bin/codesign", "--force", "--sign", identity.fingerprint,
                 "--timestamp=none", "--identifier", identifier,
                 "--requirements", "=designated => " + rule, str(app))
    if output.strip():
        print(output.strip(), file=sys.stderr)
    if check(app, identifier) != identity.fingerprint:
        raise SigningError("The app was signed by an unexpected certificate")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("identity", help="select and remember a valid signing certificate")
    for command in ("sign", "check"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("app", type=Path)
        subparser.add_argument("identifier")
        if command == "sign":
            subparser.add_argument("--identity")
    arguments = parser.parse_args()
    try:
        if arguments.command == "identity":
            identity = resolve_identity()
            print(f"Using {identity.name}", file=sys.stderr)
            print(identity.fingerprint)
        elif arguments.command == "sign":
            sign(arguments.app, arguments.identifier, resolve_identity(arguments.identity))
        else:
            print(check(arguments.app, arguments.identifier))
    except (SigningError, OSError) as error:
        parser.exit(1, f"Signing error: {error}\n")


if __name__ == "__main__":
    main()
