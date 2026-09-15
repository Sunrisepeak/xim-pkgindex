#!/usr/bin/env bash
# Runs the installed kotlinc ($KOTLINC) on a program written here: it compiles
# with the stdlib included, and the compiled jar runs through the package's own
# `kotlin` launcher with its arguments. Every criterion prints one READING line;
# the script exits non-zero on the first criterion that does not hold.
set -uo pipefail
: "${KOTLINC:?KOTLINC must name the installed program}"

W="$RUNNER_TEMP/kotlin"
rm -rf "$W"; mkdir -p "$W"
cd "$W" || exit 1

reading() { printf 'READING %s: %s\n' "$1" "$2"; }
fail() { echo "::error::$*"; exit 1; }
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

bindir="$(dirname "$KOTLINC")"
home="$(dirname "$bindir")"

# 1. The version the recipe pins, through the launcher the store holds.
out=$("$KOTLINC" -version 2>&1); rc=$?
reading "kotlinc -version" "exit=$rc $out"
[ "$rc" -eq 0 ] && contains "$out" "2.4.20" || fail "kotlinc -version printed '$out' with exit $rc"

# 2. The stdlib a consumer links against is where the layout says.
[ -f "$home/kotlinc/lib/kotlin-stdlib.jar" ] || fail "$home/kotlinc/lib/kotlin-stdlib.jar is absent"
reading "stdlib" "$home/kotlinc/lib/kotlin-stdlib.jar"

# 3. A program compiles against a Java class, and runs with its arguments.
mkdir -p src/org/xim
cat > src/org/xim/Greeter.java <<'J'
package org.xim;
public final class Greeter {
    public static String greet(String who) { return "hello " + who; }
}
J
cat > src/Main.kt <<'K'
import org.xim.Greeter
fun main(args: Array<String>) {
    println("KOTLIN-MARKER " + Greeter.greet(args.joinToString(",")))
}
K
out=$("$KOTLINC" src/Main.kt src/org/xim/Greeter.java -d kt-classes 2>&1); rc=$?
reading "kotlinc Main.kt + Greeter.java (mixed sources)" "exit=$rc"
[ "$rc" -eq 0 ] || { echo "$out"; fail "the mixed Kotlin/Java compile failed"; }
[ -f kt-classes/MainKt.class ] || fail "kotlinc wrote no MainKt.class"

java_bin="$(grep -m1 '^JAVA_HOME=' "$KOTLINC" | sed 's/^JAVA_HOME="\(.*\)"$/\1/')/bin"
mkdir -p java-classes
"$java_bin/javac" -cp kt-classes -d java-classes src/org/xim/Greeter.java || fail "javac failed on the Java half"

out=$("$KOTLINC" src/Main.kt -include-runtime -cp java-classes -d hello.jar 2>&1); rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; fail "kotlinc -include-runtime failed"; }
out=$("$bindir/kotlin" -cp "hello.jar:java-classes" MainKt a b 2>&1); rc=$?
reading "kotlin MainKt a b" "exit=$rc $out"
[ "$rc" -eq 0 ] && [ "$out" = "KOTLIN-MARKER hello a,b" ] || fail "the program printed '$out' with exit $rc"

# 4. The shim resolves to the same launcher.
out=$(kotlinc -version 2>&1); rc=$?
reading "shim kotlinc -version" "exit=$rc $out ($(command -v kotlinc))"
[ "$rc" -eq 0 ] && contains "$out" "2.4.20" || fail "the shim printed '$out' with exit $rc"
