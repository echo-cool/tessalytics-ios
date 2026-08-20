#!/usr/bin/env python3
"""Minimal App Store Connect API client for Tessalytics.

The ASC API needs an ES256 JWT signed with the .p8 private key. PyJWT isn't
installed here, so the token is assembled by hand with `cryptography` — the only
fiddly part is that ASC requires the raw r||s signature form, not the DER
sequence that `sign()` returns.

Usage:
  ./scripts/asc.py show                    # app info, versions, recent builds
  ./scripts/asc.py builds                  # build processing state
  ./scripts/asc.py get apps/<id>/builds    # any raw GET
  ./scripts/asc.py create-version          # create the version.txt record
  ./scripts/asc.py prepare-version         # rename the editable record and attach the build
  ./scripts/asc.py push-locale en-US       # name/subtitle/URLs/description/whatsNew
  ./scripts/asc.py push-review-notes       # App Review notes (demo-mode text)
  ./scripts/asc.py push-beta-notes         # TestFlight "What to Test" for the build

`submit-for-review` does submit. It refuses while another submission is open, so
withdraw first — App Store Connect keeps one editable version per app.

Environment:
  ASC_ISSUER_ID   required (Users and Access > Integrations > Issuer ID)
  ASC_KEY_ID      defaults to 6XCPQNJPCG
  ASC_KEY_PATH    defaults to ~/.appstoreconnect/private_keys/AuthKey_<id>.p8
  ASC_VERSION_ID  the appStoreVersion to push version copy to; defaults to the
                  version matching metadata/version.txt, else the editable one
  ASC_METADATA    colon-separated metadata directories, searched in order, so a
                  release kit can carry only the copy that changed:
                  ASC_METADATA=release/tessalytics-1.2.1/metadata:app-store/metadata
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

BASE = "https://api.appstoreconnect.apple.com/v1"

APP_ID = "6803221525"

REPO = pathlib.Path(__file__).resolve().parent.parent
# Searched in order, first hit wins. One directory is the normal case; two let a
# release push what it changed and inherit the rest from the release before it.
METADATA_DIRS = [
    REPO / path
    for path in os.environ.get(
        "ASC_METADATA", "release/tessalytics-1.2.1/metadata"
    ).split(":")
]

# Which file feeds which field, split by the two resources ASC keeps them in.
# App Info localizations are per-app (the listing's identity); App Store Version
# localizations are per-version (what changes between releases).
APP_INFO_FIELDS = {
    "name": "name.txt",
    "subtitle": "subtitle.txt",
    "privacyPolicyUrl": "privacy_policy_url.txt",
}
VERSION_FIELDS = {
    "description": "description.txt",
    # Absent on a first release — App Store Connect shows no What's New field
    # until there is a previous version to be new against — and skipped
    # silently, because a missing file contributes no attribute.
    "whatsNew": "whats_new.txt",
    "keywords": "keywords.txt",
    "promotionalText": "promotional_text.txt",
    "supportUrl": "support_url.txt",
    "marketingUrl": "marketing_url.txt",
}

EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token() -> str:
    issuer = os.environ.get("ASC_ISSUER_ID")
    if not issuer:
        sys.exit(
            "ASC_ISSUER_ID is not set.\n"
            "App Store Connect > Users and Access > Integrations > Issuer ID"
        )
    key_id = os.environ.get("ASC_KEY_ID", "6XCPQNJPCG")
    key_path = pathlib.Path(
        os.environ.get(
            "ASC_KEY_PATH",
            pathlib.Path.home() / f".appstoreconnect/private_keys/AuthKey_{key_id}.p8",
        )
    )
    if not key_path.exists():
        sys.exit(f"private key not found: {key_path}")

    key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer,
        "iat": now,
        # ASC rejects anything over 20 minutes.
        "exp": now + 15 * 60,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        _b64(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64(json.dumps(payload, separators=(",", ":")).encode())
    ).encode()

    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return signing_input.decode() + "." + _b64(raw)


def request(method: str, path: str, body: dict | None = None, tolerate: bool = False) -> dict:
    url = path if path.startswith("http") else f"{BASE}/{path.lstrip('/')}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        if tolerate:
            raise ASCError(error.code, detail) from error
        sys.exit(f"{method} {url} -> {error.code}\n{detail}")


class ASCError(Exception):
    """An HTTP error the caller has said it can handle."""

    def __init__(self, status: int, detail: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail

    @property
    def locked_attributes(self) -> set[str]:
        """The attribute names the service refused to edit, if that is why."""
        try:
            errors = json.loads(self.detail).get("errors", [])
        except json.JSONDecodeError:
            return set()
        names = set()
        for error in errors:
            if error.get("code") != "STATE_ERROR":
                continue
            match = re.search(r"Attribute '([^']+)' cannot be edited", error.get("detail", ""))
            if match:
                names.add(match.group(1))
        return names


def read(locale: str, filename: str) -> str | None:
    """The locale's own file, falling back to the shared files, then to the kit
    behind this one.

    Directory-major on purpose: a newer kit's copy has to beat an older kit's,
    and only then does the shared (English) file stand in.
    """
    for directory in METADATA_DIRS:
        for candidate in (directory / locale / filename, directory / filename):
            if candidate.exists():
                return candidate.read_text().strip()
    return None


def app_info_id() -> str:
    """The editable App Info record, which is where per-app copy lives.

    A live app keeps two: the published one and the editable one. Picking the
    published record means every PATCH is rejected as read-only.
    """
    infos = request("GET", f"apps/{APP_ID}/appInfos?limit=200")["data"]
    for item in infos:
        if item["attributes"].get("appStoreState") in EDITABLE_STATES:
            return item["id"]
    if not infos:
        sys.exit("no appInfos on this app")
    return infos[0]["id"]


def version_id() -> str:
    """ASC_VERSION_ID, else the record matching metadata/version.txt, else the
    one App Store Connect currently lets you edit."""
    if override := os.environ.get("ASC_VERSION_ID"):
        return override
    wanted = read("en-US", "version.txt")
    versions = request("GET", f"apps/{APP_ID}/appStoreVersions?limit=200")["data"]
    if wanted:
        for item in versions:
            if item["attributes"]["versionString"] == wanted:
                return item["id"]
    for item in versions:
        if item["attributes"].get("appStoreState") in EDITABLE_STATES:
            print(
                f"   note: no {wanted!r} version record; using the editable "
                f"{item['attributes']['versionString']}",
                file=sys.stderr,
            )
            return item["id"]
    sys.exit(
        f"no version record for {wanted!r} and none editable — run create-version"
    )


def build_id(version: str | None = None) -> tuple[str, str]:
    """(id, version) of the build matching build.txt, else the newest."""
    wanted = version or read("en-US", "build.txt")
    builds_data = request(
        "GET", f"builds?filter[app]={APP_ID}&limit=200&sort=-uploadedDate"
    )["data"]
    if not builds_data:
        sys.exit("no builds on this app yet")
    if wanted:
        for item in builds_data:
            if item["attributes"]["version"] == wanted:
                return item["id"], wanted
        sys.exit(
            f"build {wanted} not found — it may still be registering; "
            "processing can take up to twenty minutes"
        )
    return builds_data[0]["id"], builds_data[0]["attributes"]["version"]


def find_localization(collection: str, parent_id: str, locale: str) -> str | None:
    path = {
        "appInfo": f"appInfos/{parent_id}/appInfoLocalizations",
        "version": f"appStoreVersions/{parent_id}/appStoreVersionLocalizations",
    }[collection]
    for item in request("GET", f"{path}?limit=200").get("data", []):
        if item["attributes"]["locale"] == locale:
            return item["id"]
    return None


def push_locale(locale: str) -> None:
    print(f"== {locale}")

    # App Info localization: name, subtitle, privacy policy URL.
    attributes = {
        field: read(locale, filename)
        for field, filename in APP_INFO_FIELDS.items()
        if read(locale, filename)
    }
    if attributes:
        info_id = app_info_id()
        existing = find_localization("appInfo", info_id, locale)
        if existing:
            request("PATCH", f"appInfoLocalizations/{existing}", {
                "data": {"type": "appInfoLocalizations", "id": existing,
                         "attributes": attributes}
            })
            print(f"   updated appInfoLocalization {existing}")
        else:
            created = request("POST", "appInfoLocalizations", {
                "data": {
                    "type": "appInfoLocalizations",
                    "attributes": {**attributes, "locale": locale},
                    "relationships": {
                        "appInfo": {"data": {"type": "appInfos", "id": info_id}}
                    },
                }
            })
            print(f"   created appInfoLocalization {created['data']['id']}")
        for field in attributes:
            print(f"     {field}")

    # App Store Version localization: description, keywords, promo, URLs, whatsNew.
    attributes = {
        field: read(locale, filename)
        for field, filename in VERSION_FIELDS.items()
        if read(locale, filename)
    }
    if not attributes:
        return
    vid = version_id()
    existing = find_localization("version", vid, locale)
    if existing:
        # `whatsNew` is locked until an app has a released version, so a first
        # release cannot set it. Dropping the field it names beats abandoning the
        # description, keywords and URLs that were about to be written with it.
        for _ in range(len(attributes)):
            try:
                request("PATCH", f"appStoreVersionLocalizations/{existing}", {
                    "data": {"type": "appStoreVersionLocalizations", "id": existing,
                             "attributes": attributes}
                }, tolerate=True)
                break
            except ASCError as error:
                locked = error.locked_attributes & attributes.keys()
                if not locked:
                    sys.exit(f"PATCH appStoreVersionLocalizations/{existing} -> {error.status}\n{error.detail}")
                for field in locked:
                    del attributes[field]
                    print(f"     {field}: locked by App Store Connect, skipped")
                if not attributes:
                    return
        print(f"   updated appStoreVersionLocalization {existing}")
    else:
        created = request("POST", "appStoreVersionLocalizations", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {**attributes, "locale": locale},
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": vid}
                    }
                },
            }
        })
        print(f"   created appStoreVersionLocalization {created['data']['id']}")
    for field in attributes:
        print(f"     {field}")


def push_review_notes() -> None:
    """The App Review notes — the demo-mode instructions for the reviewer."""
    notes = read("en-US", "review_notes.txt")
    if not notes:
        sys.exit("no review_notes.txt in the metadata directories")
    vid = version_id()
    existing = request(
        "GET", f"appStoreVersions/{vid}/appStoreReviewDetail"
    ).get("data")
    if existing:
        request("PATCH", f"appStoreReviewDetails/{existing['id']}", {
            "data": {"type": "appStoreReviewDetails", "id": existing["id"],
                     "attributes": {"notes": notes}}
        })
        print(f"updated appStoreReviewDetail {existing['id']} ({len(notes)} chars)")
    else:
        created = request("POST", "appStoreReviewDetails", {
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": {"notes": notes},
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": vid}
                    }
                },
            }
        })
        print(f"created appStoreReviewDetail {created['data']['id']} "
              f"({len(notes)} chars)")


def push_beta_notes(locale: str = "en-US") -> None:
    """TestFlight's "What to Test" for the uploaded build."""
    notes = read(locale, "testflight_whats_new.txt")
    if not notes:
        sys.exit("no testflight_whats_new.txt in the metadata directories")
    bid, version = build_id()
    existing = None
    for item in request(
        "GET", f"builds/{bid}/betaBuildLocalizations?limit=200"
    ).get("data", []):
        if item["attributes"]["locale"] == locale:
            existing = item["id"]
            break
    if existing:
        request("PATCH", f"betaBuildLocalizations/{existing}", {
            "data": {"type": "betaBuildLocalizations", "id": existing,
                     "attributes": {"whatsNew": notes}}
        })
        print(f"updated betaBuildLocalization {existing} for build {version}")
    else:
        created = request("POST", "betaBuildLocalizations", {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": locale, "whatsNew": notes},
                "relationships": {
                    "build": {"data": {"type": "builds", "id": bid}}
                },
            }
        })
        print(f"created betaBuildLocalization {created['data']['id']} "
              f"for build {version}")


def create_version() -> None:
    wanted = read("en-US", "version.txt")
    if not wanted:
        sys.exit("no version.txt in the metadata directories")
    for item in request("GET", f"apps/{APP_ID}/appStoreVersions?limit=200")["data"]:
        if item["attributes"]["versionString"] == wanted:
            print(f"version {wanted} already exists: {item['id']} "
                  f"({item['attributes'].get('appStoreState')})")
            return
    created = request("POST", "appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "versionString": wanted,
                "platform": "IOS",
                "releaseType": "AFTER_APPROVAL",
            },
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    })
    print(f"created appStoreVersion {wanted}: {created['data']['id']}")


def prepare_version() -> None:
    """Points the editable version record at version.txt and attaches build.txt.

    App Store Connect keeps one editable version per app, so a new release
    normally renames the existing record rather than adding one. Attaching the
    build is a separate relationship write; a version with no build cannot be
    submitted.
    """
    wanted = read("en-US", "version.txt")
    if not wanted:
        sys.exit("no version.txt in the metadata directories")

    editable = None
    for item in request("GET", f"apps/{APP_ID}/appStoreVersions?limit=200")["data"]:
        state = item["attributes"].get("appStoreState")
        if item["attributes"]["versionString"] == wanted:
            editable = item
            break
        if state in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}:
            editable = editable or item
    if not editable:
        sys.exit("no editable version to reuse; run create-version")

    version = editable["id"]
    if editable["attributes"]["versionString"] != wanted:
        request("PATCH", f"appStoreVersions/{version}", {
            "data": {
                "type": "appStoreVersions",
                "id": version,
                "attributes": {"versionString": wanted, "releaseType": "AFTER_APPROVAL"},
            }
        })
        print(f"renamed {editable['attributes']['versionString']} -> {wanted}")

    build, build_version = build_id()
    request("PATCH", f"appStoreVersions/{version}/relationships/build", {
        "data": {"type": "builds", "id": build}
    })
    print(f"version {wanted} ({version}) now uses build {build_version}")


def builds() -> None:
    data = request(
        "GET", f"builds?filter[app]={APP_ID}&limit=20&sort=-uploadedDate"
    )["data"]
    print(f"{'build':<16} {'state':<12} {'expired':<8} uploaded")
    for item in data:
        a = item["attributes"]
        print(f"{a['version']:<16} {a.get('processingState',''):<12} "
              f"{str(a.get('expired','')):<8} {a.get('uploadedDate','')}")


def show() -> None:
    info_id = app_info_id()
    print(f"App {APP_ID}  editable appInfo {info_id}")
    info = request("GET", f"appInfos/{info_id}/appInfoLocalizations?limit=200")
    print("App Info localizations:")
    for item in info["data"]:
        a = item["attributes"]
        print(f"  {a['locale']:<8} {a.get('name')!r} / {a.get('subtitle')!r}")
    print("Versions:")
    for item in request("GET", f"apps/{APP_ID}/appStoreVersions?limit=200")["data"]:
        a = item["attributes"]
        print(f"  {a['versionString']:<8} {a.get('appStoreState'):<24} {item['id']}")
    print()
    builds()



# --- Screenshots -----------------------------------------------------------
#
# Assets are a three-step dance: reserve a slot and get signed upload
# operations, PUT the bytes at each of them, then commit with the file's MD5 so
# the service can verify what landed. There is no single-request form.

SCREENSHOT_DISPLAY_TYPES = {
    "iphone-6.9": "APP_IPHONE_67",
    "ipad-12.9": "APP_IPAD_PRO_3GEN_129",
}


def _upload(operations: list[dict], payload: bytes) -> None:
    for operation in operations:
        chunk = payload[operation["offset"] : operation["offset"] + operation["length"]]
        req = urllib.request.Request(operation["url"], data=chunk, method=operation["method"])
        for header in operation.get("requestHeaders", []):
            req.add_header(header["name"], header["value"])
        try:
            with urllib.request.urlopen(req) as response:
                response.read()
        except urllib.error.HTTPError as error:
            sys.exit(f"upload chunk -> {error.code}\n{error.read().decode()}")


def _screenshot_set(localization_id: str, display_type: str) -> str:
    existing = request("GET", f"appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
    for item in existing.get("data", []):
        if item["attributes"].get("screenshotDisplayType") == display_type:
            return item["id"]
    created = request(
        "POST",
        "appScreenshotSets",
        {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                    }
                },
            }
        },
    )
    return created["data"]["id"]


def push_screenshots(kind: str, directory: str, locale: str = "en-US") -> None:
    """Replaces one display type's screenshots with the files in a directory.

    Replaces rather than appends: a set that accumulates every run ends up
    showing three generations of the same screen in the wrong order.
    """
    display_type = SCREENSHOT_DISPLAY_TYPES.get(kind)
    if not display_type:
        sys.exit(f"unknown screenshot kind '{kind}'; expected one of {', '.join(SCREENSHOT_DISPLAY_TYPES)}")

    files = sorted(pathlib.Path(directory).glob("*.png"))
    if not files:
        sys.exit(f"no .png files in {directory}")

    localization_id = find_localization("version", version_id(), locale)
    if not localization_id:
        sys.exit(f"no {locale} localization on the editable version")
    set_id = _screenshot_set(localization_id, display_type)

    for existing in request("GET", f"appScreenshotSets/{set_id}/appScreenshots").get("data", []):
        request("DELETE", f"appScreenshots/{existing['id']}")
        print(f"  removed {existing['attributes'].get('fileName')}")

    for position, path in enumerate(files):
        payload = path.read_bytes()
        reserved = request(
            "POST",
            "appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileSize": len(payload), "fileName": path.name},
                    "relationships": {
                        "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                    },
                }
            },
        )
        screenshot_id = reserved["data"]["id"]
        _upload(reserved["data"]["attributes"]["uploadOperations"], payload)
        request(
            "PATCH",
            f"appScreenshots/{screenshot_id}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": screenshot_id,
                    "attributes": {
                        "uploaded": True,
                        "sourceFileChecksum": hashlib.md5(payload).hexdigest(),
                    },
                }
            },
        )
        print(f"  uploaded {path.name} ({len(payload) // 1024} KB) at position {position}")

    print(f"{display_type}: {len(files)} screenshot(s) for {locale}")


# --- Review submission -----------------------------------------------------


def review_submissions() -> list[dict]:
    response = request(
        "GET",
        f"apps/{APP_ID}/reviewSubmissions?filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW",
    )
    return response.get("data", [])


def withdraw_review() -> None:
    """Cancels any open submission so the version becomes editable again.

    App Store Connect keeps one editable version per app, so a submission that is
    still queued blocks store copy for everything behind it.
    """
    open_submissions = review_submissions()
    if not open_submissions:
        print("no open review submission")
        return
    for submission in open_submissions:
        state = submission["attributes"].get("state")
        request(
            "PATCH",
            f"reviewSubmissions/{submission['id']}",
            {"data": {"type": "reviewSubmissions", "id": submission["id"], "attributes": {"canceled": True}}},
        )
        print(f"withdrew submission {submission['id']} (was {state})")


def submit_for_review() -> None:
    """Creates a submission for the editable version and submits it."""
    version = version_id()
    if review_submissions():
        sys.exit("an open review submission already exists; run withdraw-review first")

    submission = request(
        "POST",
        "reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        },
    )
    submission_id = submission["data"]["id"]
    request(
        "POST",
        "reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version}},
                },
            }
        },
    )
    request(
        "PATCH",
        f"reviewSubmissions/{submission_id}",
        {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )
    print(f"submitted {submission_id} for review")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = sys.argv[1]
    if command == "get":
        print(json.dumps(request("GET", sys.argv[2]), indent=2, ensure_ascii=False))
    elif command == "push-locale":
        for locale in sys.argv[2:] or ["en-US"]:
            push_locale(locale)
    elif command == "push-review-notes":
        push_review_notes()
    elif command == "push-beta-notes":
        push_beta_notes(*sys.argv[2:3])
    elif command == "create-version":
        create_version()
    elif command == "prepare-version":
        prepare_version()
    elif command == "builds":
        builds()
    elif command == "show":
        show()
    elif command == "push-screenshots":
        if len(sys.argv) < 4:
            sys.exit("usage: asc.py push-screenshots <iphone-6.9|ipad-12.9> <directory> [locale]")
        push_screenshots(sys.argv[2], sys.argv[3], *sys.argv[4:5])
    elif command == "review-status":
        open_submissions = review_submissions()
        for submission in open_submissions:
            print(submission["id"], submission["attributes"].get("state"))
        if not open_submissions:
            print("no open review submission")
    elif command == "withdraw-review":
        withdraw_review()
    elif command == "submit-for-review":
        submit_for_review()
    else:
        sys.exit(f"unknown command: {command}")


if __name__ == "__main__":
    main()
