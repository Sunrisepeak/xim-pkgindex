#!/usr/bin/env bash
# Runs the installed cs ($CS): a Maven Central jar, then a Google Maven AAR graph
# with its transitive dependencies, each into a cache named here, with the JSON
# report a build tool reads. Every criterion prints one READING line; the script
# exits non-zero on the first criterion that does not hold.
set -uo pipefail
: "${CS:?CS must name the installed program}"

W="$RUNNER_TEMP/coursier"
rm -rf "$W"; mkdir -p "$W"
cd "$W" || exit 1

reading() { printf 'READING %s: %s\n' "$1" "$2"; }
fail() { echo "::error::$*"; exit 1; }

# 1. The version the recipe pins.
out=$("$CS" version 2>&1); rc=$?
reading "cs version" "exit=$rc $out"
[ "$rc" -eq 0 ] && [ "$out" = "2.1.24" ] || fail "cs version printed '$out' with exit $rc"

# 2. One jar from Maven Central, into an explicit cache.
out=$("$CS" fetch --cache "$W/cache" -r https://repo1.maven.org/maven2 org.jetbrains:annotations:24.1.0 2>&1); rc=$?
reading "cs fetch annotations" "exit=$rc $out"
[ "$rc" -eq 0 ] || fail "fetching org.jetbrains:annotations failed"
[ -f "$W/cache/https/repo1.maven.org/maven2/org/jetbrains/annotations/24.1.0/annotations-24.1.0.jar" ] \
    || fail "the jar is not at the cache path the layout implies"

# 3. An AAR graph from Google Maven: the requested module and its transitive
#    dependencies, AAR packaging included, with a JSON report.
out=$("$CS" fetch --cache "$W/cache" -r https://maven.google.com -r https://repo1.maven.org/maven2 \
        -A aar,jar --json-output-file "$W/graph.json" androidx.startup:startup-runtime:1.1.1 2>&1); rc=$?
reading "cs fetch startup-runtime" "exit=$rc"
[ "$rc" -eq 0 ] || { echo "$out"; fail "fetching androidx.startup:startup-runtime failed"; }
python3 - "$W/graph.json" <<'PY' || fail "the JSON report does not describe the graph"
import json, os, sys
deps = json.load(open(sys.argv[1]))["dependencies"]
coords = {d["coord"].replace(":aar:", ":"): d["file"] for d in deps}
print("READING graph:", sorted(coords))
for want, ext in (("androidx.startup:startup-runtime:1.1.1", ".aar"),
                  ("androidx.tracing:tracing:1.0.0", ".aar"),
                  ("androidx.annotation:annotation:1.1.0", ".jar")):
    f = coords.get(want)
    assert f and f.endswith(ext) and os.path.isfile(f), (want, f)
PY
