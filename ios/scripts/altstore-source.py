"""Writes altstore.json (AltStore Classic source) for the IPA CI just built.
Usage: python3 altstore-source.py <ipa> <version> <build> <out.json>"""
import json, os, sys, datetime

ipa, version, build, out = sys.argv[1:5]
repo = os.environ.get("GITHUB_REPOSITORY", "theVentus/jubilant-octo-potato")
source = {
    "name": "FX",
    "identifier": "com.theventus.fx.source",
    "subtitle": "Offline currency converter",
    "sourceURL": f"https://github.com/{repo}/releases/download/latest/altstore.json",
    "apps": [{
        "name": "FX",
        "bundleIdentifier": "com.theventus.fx",
        "developerName": "theVentus",
        "subtitle": "Offline currency converter",
        "localizedDescription": "Liquid Glass currency converter with a built-in calculator. Works offline.",
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/ios/FX/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
        "tintColor": "#F7931A",
        "appPermissions": {"entitlements": [], "privacy": {}},
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localizedDescription": f"Build {build} from {os.environ.get('GITHUB_SHA', '')[:7]}",
            "downloadURL": f"https://github.com/{repo}/releases/download/latest/FX.ipa",
            "size": os.path.getsize(ipa),
            "minOSVersion": "26.0",
        }],
    }],
    "news": [],
}
json.dump(source, open(out, "w"), indent=2)
print(f"wrote {out}: FX {version} ({build})")
