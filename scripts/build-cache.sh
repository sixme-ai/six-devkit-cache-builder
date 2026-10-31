#!/usr/bin/env bash
# Prepare public Maven dependencies without any private source checkout.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_BASE="${RUNNER_TEMP:-$ROOT/.build}"
REPOSITORY="$TEMP_BASE/maven-repository"
WORKSPACE="$TEMP_BASE/maven-offline-seed"
DIST="$ROOT/dist"
mkdir -p "$REPOSITORY" "$WORKSPACE" "$DIST"

if ! java -version 2>&1 | grep -Eq 'version "25([.+-]|\")'; then
  echo 'ERROR: JDK 25 is required.' >&2
  exit 2
fi
if ! mvn -version | grep -Fq 'Apache Maven 3.9.16'; then
  echo 'ERROR: Maven 3.9.16 is required.' >&2
  exit 2
fi

cp "$ROOT/pom.xml" "$WORKSPACE/pom.xml"
mkdir -p "$WORKSPACE/src/main/java/dev/offline/cache" \
         "$WORKSPACE/src/test/java/dev/offline/cache"
cat > "$WORKSPACE/src/main/java/dev/offline/cache/Seed.java" <<'JAVA'
package dev.offline.cache;

public final class Seed {
    private Seed() { }

    public static int twice(int value) {
        return value * 2;
    }
}
JAVA
cat > "$WORKSPACE/src/test/java/dev/offline/cache/OfflineCacheTest.java" <<'JAVA'
package dev.offline.cache;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;

class OfflineCacheTest {
    @Test
    void testJUnitProvider() {
        assertEquals(4, Seed.twice(2));
    }
}
JAVA
cat > "$WORKSPACE/src/test/java/dev/offline/cache/OfflineCacheIT.java" <<'JAVA'
package dev.offline.cache;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OfflineCacheIT {
    @Test
    void testFailsafeProvider() {
        assertTrue(Seed.twice(3) == 6);
    }
}
JAVA

cd "$WORKSPACE"
mvn_seed() { mvn -B -ntp "-Dmaven.repo.local=$REPOSITORY" "$@"; }
P='offline-quality,postgresql-migration-verification'

printf '\n== Downloading Maven dependency and plugin graph ==\n'
mvn_seed -U -P"$P" dependency:go-offline
mvn_seed -P"$P" dependency:resolve-plugins

printf '\n== Exercising compiler, JUnit, Surefire, Failsafe, JaCoCo ==\n'
mvn_seed -P"$P" clean verify

printf '\n== Exercising Checkstyle, PMD, CPD and SpotBugs ==\n'
mvn_seed -P"$P" checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs

printf '\n== Exercising Flyway Maven plugin without database connectivity ==\n'
mvn_seed org.apache.maven.plugins:maven-help-plugin:3.5.1:describe -Dplugin=org.flywaydb:flyway-maven-plugin:13.6.0 -Dgoal=migrate -Ddetail=false

printf '\n== Verifying the same operations in Maven offline mode ==\n'
mvn_seed -o -P"$P" clean verify
mvn_seed -o -P"$P" checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs
mvn_seed -o org.apache.maven.plugins:maven-help-plugin:3.5.1:describe -Dplugin=org.flywaydb:flyway-maven-plugin:13.6.0 -Dgoal=migrate -Ddetail=false

find "$REPOSITORY" -name '*.lastUpdated' -type f -delete
BUNDLE="$DIST/six-aquifer-maven-repository-offline.tar.gz"
tar -czf "$BUNDLE" -C "$TEMP_BASE" maven-repository
(cd "$DIST" && sha256sum "$(basename "$BUNDLE")" > "$(basename "$BUNDLE").sha256")
cat > "$DIST/manifest.txt" <<EOF
source=public_synthetic_pom_no_private_code
java_major=25
maven_version=3.9.16
spring_boot=4.1.1
spring_ai=2.0.1
junit_jupiter=6.1.2
coverage=jacoco_0.8.15
quality=checkstyle_3.6.0_pmd_3.28.0_spotbugs_4.10.5.0
offline_seed_verification=PASS
private_project_compilation=NOT_TESTED
postgresql_integration_tests=NOT_TESTED
EOF

# VERIFY_EXTRACTED_MAVEN_CACHE: no other project's cache, ~/.m2 or build workspace is trusted.
# Extract the ACTUAL outgoing archive and re-run all synthetic project gates
# against the exclusively extracted repository. A missing transitive/plugin
# dependency must fail the build before artifact publication.
VERIFY_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/maven-offline-verify-XXXXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
(cd "$DIST" && sha256sum -c "$(basename "$BUNDLE").sha256")
tar -xzf "$BUNDLE" -C "$VERIFY_DIR"
test -d "$VERIFY_DIR/maven-repository"
test -s "$VERIFY_DIR/maven-repository/org/apache/maven/plugins/maven-compiler-plugin/"*"/maven-compiler-plugin-"*".jar"
(
  cd "$WORKSPACE"
  mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" -P"$P" clean verify
  mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" -P"$P" dependency:tree
  mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" -P"$P" checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs
)

printf '\nCreated %s\n' "$BUNDLE"
