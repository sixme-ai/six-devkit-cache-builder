#!/usr/bin/env bash
# Public dependency-only seed for chess. No checkout of private repositories.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_BASE="${RUNNER_TEMP:-$ROOT/.build}"
REPOSITORY="$TEMP_BASE/maven-repository"
WORKSPACE="$TEMP_BASE/seed-chess"
DIST="$ROOT/dist"
mkdir -p "$REPOSITORY" "$WORKSPACE/src/main/java/dev/offline/cache" "$WORKSPACE/src/test/java/dev/offline/cache" "$DIST"
java -version 2>&1 | grep -Eq 'version "25([.+-]|")' || { echo 'JDK 25 required' >&2; exit 2; }
mvn -version | grep -Fq 'Apache Maven 3.9.16' || { echo 'Maven 3.9.16 required' >&2; exit 2; }
cp "$ROOT/pom-six-chess.xml" "$WORKSPACE/pom.xml"
cat > "$WORKSPACE/src/main/java/dev/offline/cache/Seed.java" <<'JAVA'
package dev.offline.cache;
public final class Seed {
  private Seed() { }
  public static int twice(int value) { return value * 2; }
}
JAVA
cat > "$WORKSPACE/src/test/java/dev/offline/cache/OfflineCacheTest.java" <<'JAVA'
package dev.offline.cache;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
class OfflineCacheTest {
  @Test void checksJUnit() { assertEquals(4, Seed.twice(2)); }
}
JAVA
cat > "$WORKSPACE/src/test/java/dev/offline/cache/OfflineCacheIT.java" <<'JAVA'
package dev.offline.cache;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
class OfflineCacheIT {
  @Test void checksFailsafe() { assertEquals(6, Seed.twice(3)); }
}
JAVA
cd "$WORKSPACE"
mvn_seed() { mvn -B -ntp "-Dmaven.repo.local=$REPOSITORY" "$@"; }
PROFILES=""
echo "Resolving chess public dependencies and plugins..."
mvn_seed -U $PROFILES dependency:go-offline
mvn_seed $PROFILES dependency:resolve-plugins
mvn_seed $PROFILES clean verify
# No unrelated build quality plugins seeded for Chess.
echo "Verifying chess with Maven -o and the SAME repository..."
mvn_seed -o $PROFILES clean verify

test -s "$REPOSITORY/org/testcontainers/testcontainers-postgresql/2.0.5/testcontainers-postgresql-2.0.5.jar" || { echo "Missing org/testcontainers/testcontainers-postgresql/2.0.5/testcontainers-postgresql-2.0.5.jar" >&2; exit 3; }
test -s "$REPOSITORY/org/postgresql/postgresql/42.7.13/postgresql-42.7.13.jar" || { echo "Missing org/postgresql/postgresql/42.7.13/postgresql-42.7.13.jar" >&2; exit 3; }
find "$REPOSITORY" -name '*.lastUpdated' -type f -delete
BUNDLE="$DIST/six-chess-maven-repository-offline.tar.gz"
tar -czf "$BUNDLE" -C "$TEMP_BASE" maven-repository
(cd "$DIST" && sha256sum "$(basename "$BUNDLE")" > "$(basename "$BUNDLE").sha256")
cat > "$DIST/manifest.txt" <<EOF
source=public_synthetic_dependency_coordinates_only
project=chess
java_major=25
maven_version=3.9.16
offline_seed_verification=PASS
private_project_compilation=NOT_TESTED
external_integrations=NOT_TESTED
no_private_source_or_business_logic=TRUE
EOF
echo "Created $BUNDLE"
