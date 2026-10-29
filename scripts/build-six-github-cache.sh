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

cp "$ROOT/pom-six-github.xml" "$WORKSPACE/pom.xml"
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

# Validate the Chess-specific public coordinates are actually present, not just declared.
test -s "$REPOSITORY/org/testcontainers/testcontainers-postgresql/2.0.5/testcontainers-postgresql-2.0.5.jar" || {
  echo 'ERROR: Chess Testcontainers PostgreSQL dependency missing from offline cache.' >&2
  exit 3
}
test -s "$REPOSITORY/org/postgresql/postgresql/42.7.13/postgresql-42.7.13.jar" || {
  echo 'ERROR: Chess PostgreSQL JDBC dependency missing from offline cache.' >&2
  exit 3
}
# Exercise the actual Spring Boot-managed Maven plugin versions used by six-github.
# The Chess synthetic POM above explicitly pins Surefire/Failsafe 3.6.0,
# while Spring Boot 4.1.1 manages 3.5.6 when the private project leaves them unpinned.
COMPAT="$TEMP_BASE/six-github-compat"
mkdir -p "$COMPAT"
cp "$ROOT/pom-six-github-compat.xml" "$COMPAT/pom.xml"
cp -R "$WORKSPACE/src" "$COMPAT/src"
printf '\n== Six GitHub compatibility: Spring Boot-managed Surefire/Failsafe 3.5.6 online ==\n'
(cd "$COMPAT" && mvn_seed -U -Pci-coverage clean verify)
printf '\n== Six GitHub compatibility: Surefire/Failsafe 3.5.6 offline ==\n'
(cd "$COMPAT" && mvn_seed -o -Pci-coverage clean verify)
for plugin in maven-failsafe-plugin maven-surefire-plugin; do
  for version in 3.5.6 3.6.0; do
    test -s "$REPOSITORY/org/apache/maven/plugins/$plugin/$version/$plugin-$version.jar" || {
      echo "ERROR: missing $plugin:$version from offline bundle." >&2; exit 3;
    }
  done
done
find "$REPOSITORY" -name '*.lastUpdated' -type f -delete
BUNDLE="$DIST/six-github-maven-repository-offline.tar.gz"
tar -czf "$BUNDLE" -C "$TEMP_BASE" maven-repository
(cd "$DIST" && sha256sum "$(basename "$BUNDLE")" > "$(basename "$BUNDLE").sha256")
cat > "$DIST/manifest.txt" <<EOF
source=public_synthetic_chess_and_six_github_dependency_manifest
java_major=25
maven_version=3.9.16
chess_pom_source_ref=agente/andreia
chess_pom_blob_sha=0458a5b83eda3e4b66a08fcb93ba144f23aad556
chess_testcontainers=2.0.5
chess_postgresql_jdbc=42.7.13
chess_maven_compiler=3.15.0
chess_maven_enforcer=3.6.3
chess_maven_surefire_failsafe=3.6.0
spring_boot=4.1.1
spring_ai=2.0.1
junit_jupiter=6.1.2
coverage=jacoco_0.8.15
quality=checkstyle_3.6.0_pmd_3.28.0_spotbugs_4.10.5.0
offline_seed_verification=PASS
private_project_compilation=NOT_TESTED
postgresql_integration_tests=NOT_TESTED
EOF
printf '\nCreated %s\n' "$BUNDLE"
