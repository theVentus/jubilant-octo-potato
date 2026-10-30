"""Prints the UDID of the best available iOS 26 iPhone simulator (prefers iPhone 17 Pro Max)."""
import json, subprocess, sys

d = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
c = sorted((rt, x["name"], x["udid"]) for rt, xs in d.items() if "iOS-26" in rt for x in xs if x["name"].startswith("iPhone"))
if not c:
    sys.exit("no iOS 26 iPhone simulator; runtimes: " + ", ".join(d))
pick = [x for x in c if x[1] == "iPhone 17 Pro Max"] or [x for x in c if "Pro Max" in x[1]] or c
print(pick[-1][2])
print(pick[-1][0], pick[-1][1], file=sys.stderr)
