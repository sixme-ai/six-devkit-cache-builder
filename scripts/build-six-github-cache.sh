#!/usr/bin/env bash
# Public dependency-only seed for github-mcp. No checkout of private repositories.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_BASE="${RUNNER_TEMP:-$ROOT/.build}"
REPOSITORY="$TEMP_BASE/maven-repository"
WORKSPACE="$TEMP_BASE/seed-github-mcp"
DIST="$ROOT/dist"
mkdir -p "$REPOSITORY" "$WORKSPACE/src/main/java/dev/offline/cache" "$WORKSPACE/src/test/java/dev/offline/cache" "$DIST"
java -version 2>&1 | grep -Eq 'version "25([.+-]|")' || { echo 'JDK 25 required' >&2; exit 2; }
mvn -version | grep -Fq 'Apache Maven 3.9.16' || { echo 'Maven 3.9.16 required' >&2; exit 2; }
cp "$ROOT/pom-six-github.xml" "$WORKSPACE/pom.xml"
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
PROFILES="-Pci-coverage,offline-quality"
echo "Resolving github-mcp public dependencies and plugins..."
mvn_seed -U $PROFILES dependency:go-offline
mvn_seed $PROFILES dependency:resolve-plugins
mvn_seed $PROFILES clean verify
mvn_seed $PROFILES checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs
echo "Verifying github-mcp with Maven -o and the SAME repository..."
mvn_seed -o $PROFILES clean verify
mvn_seed -o $PROFILES checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs
test -s "$REPOSITORY/org/springframework/ai/spring-ai-mcp/2.0.1/spring-ai-mcp-2.0.1.jar" || { echo "Missing org/springframework/ai/spring-ai-mcp/2.0.1/spring-ai-mcp-2.0.1.jar" >&2; exit 3; }
test -s "$REPOSITORY/org/springframework/ai/mcp-spring-webmvc/2.0.1/mcp-spring-webmvc-2.0.1.jar" || { echo "Missing org/springframework/ai/mcp-spring-webmvc/2.0.1/mcp-spring-webmvc-2.0.1.jar" >&2; exit 3; }
test -s "$REPOSITORY/org/springframework/boot/spring-boot-starter-security/4.1.1/spring-boot-starter-security-4.1.1.jar" || { echo "Missing org/springframework/boot/spring-boot-starter-security/4.1.1/spring-boot-starter-security-4.1.1.jar" >&2; exit 3; }
test -s "$REPOSITORY/org/springframework/boot/spring-boot-starter-oauth2-resource-server/4.1.1/spring-boot-starter-oauth2-resource-server-4.1.1.jar" || { echo "Missing org/springframework/boot/spring-boot-starter-oauth2-resource-server/4.1.1/spring-boot-starter-oauth2-resource-server-4.1.1.jar" >&2; exit 3; }
test -s "$REPOSITORY/org/springframework/security/spring-security-oauth2-jose/7.1.1/spring-security-oauth2-jose-7.1.1.jar" || { echo "Missing org/springframework/security/spring-security-oauth2-jose/7.1.1/spring-security-oauth2-jose-7.1.1.jar" >&2; exit 3; }
find "$REPOSITORY" -name '*.lastUpdated' -type f -delete
BUNDLE="$DIST/six-github-maven-repository-offline.tar.gz"
tar -czf "$BUNDLE" -C "$TEMP_BASE" maven-repository
(cd "$DIST" && sha256sum "$(basename "$BUNDLE")" > "$(basename "$BUNDLE").sha256")
cat > "$DIST/manifest.txt" <<EOF
source=public_synthetic_dependency_coordinates_only
project=github-mcp
java_major=25
maven_version=3.9.16
offline_seed_verification=PASS
private_project_compilation=NOT_TESTED
external_integrations=NOT_TESTED
no_private_source_or_business_logic=TRUE
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
find "$VERIFY_DIR/maven-repository/org/apache/maven/plugins/maven-compiler-plugin" -type f -name 'maven-compiler-plugin-*.jar' -print -quit | grep -q .
(
  cd "$WORKSPACE"
  mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" $PROFILES clean verify
  mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" $PROFILES dependency:tree
  mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" $PROFILES checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs
)

echo "Created $BUNDLE"
