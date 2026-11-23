#!/usr/bin/env bash
# Public dependencies only. Six Security source and CI Common plugin are never fetched.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
REPOSITORY="$BASE/maven-repository"
SEED="$BASE/seed"
DIST="$ROOT/dist"
mkdir -p "$REPOSITORY" "$SEED/src/main/java/dev/offline/cache" "$SEED/src/test/java/dev/offline/cache" "$DIST"
java -version 2>&1 | grep -Eq 'version "25([.+-]|")' || { echo "Java 25 required" >&2; exit 2; }
mvn -version | grep -Fq 'Apache Maven 3.10.2' || { echo "Maven 3.10.2 required" >&2; exit 2; }
cp "$ROOT/pom-six-security.xml" "$SEED/pom.xml"
cat > "$SEED/src/main/java/dev/offline/cache/SecurityApiProbe.java" <<'JAVA'
package dev.offline.cache;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
public final class SecurityApiProbe {
  private SecurityApiProbe() { }
  public static String supportedTypes() {
    return ClientRegistration.class.getSimpleName() + ":" + ZipArchiveEntry.class.getSimpleName();
  }
}
JAVA
cat > "$SEED/src/test/java/dev/offline/cache/SecurityApiProbeTest.java" <<'JAVA'
package dev.offline.cache;
import io.modelcontextprotocol.server.transport.HttpServletStreamableServerTransportProvider;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
class SecurityApiProbeTest {
  @Test void resolvesOAuthClientAndSafeZipLibraries() {
    assertEquals("ClientRegistration:ZipArchiveEntry", SecurityApiProbe.supportedTypes());
    assertNotNull(HttpServletStreamableServerTransportProvider.builder()
        .sessionSweepInterval(Duration.ofSeconds(3)));
  }
}
JAVA
cat > "$SEED/src/test/java/dev/offline/cache/SecurityApiProbeIT.java" <<'JAVA'
package dev.offline.cache;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
class SecurityApiProbeIT {
  @Test void resolvesClientRegistrationInIntegrationPhase() {
    assertEquals("ClientRegistration:ZipArchiveEntry", SecurityApiProbe.supportedTypes());
  }
}
JAVA
cd "$SEED"
mvn_seed() { mvn -B -ntp "-Dmaven.repo.local=$REPOSITORY" "$@"; }
mvn_seed -U org.apache.maven.plugins:maven-dependency-plugin:3.9.0:go-offline
mvn_seed org.apache.maven.plugins:maven-dependency-plugin:3.9.0:resolve-plugins
mvn_seed clean verify
test -s "$SEED/target/surefire-reports/TEST-dev.offline.cache.SecurityApiProbeTest.xml"
test -s "$SEED/target/failsafe-reports/TEST-dev.offline.cache.SecurityApiProbeIT.xml"
for spec in   org/springframework/boot/spring-boot-starter-oauth2-client/4.1.1/spring-boot-starter-oauth2-client-4.1.1.jar \
  io/modelcontextprotocol/sdk/mcp/2.1.0/mcp-2.1.0.jar \
  org/apache/maven/plugins/maven-surefire-plugin/3.6.1/maven-surefire-plugin-3.6.1.jar \
  org/apache/maven/plugins/maven-failsafe-plugin/3.6.1/maven-failsafe-plugin-3.6.1.jar; do
  test -s "$REPOSITORY/$spec" || { echo "Missing public coordinate: $spec" >&2; exit 3; }
done
find "$REPOSITORY" -name '*.lastUpdated' -type f -delete
tar -czf "$DIST/six-security-maven-repository-offline.tar.gz" -C "$BASE" maven-repository
(cd "$DIST" && sha256sum six-security-maven-repository-offline.tar.gz > six-security-maven-repository-offline.tar.gz.sha256)
mkdir -p "$BASE/fresh"
(cd "$DIST" && sha256sum -c six-security-maven-repository-offline.tar.gz.sha256)
tar -xzf "$DIST/six-security-maven-repository-offline.tar.gz" -C "$BASE/fresh"
mvn -B -ntp -o "-Dmaven.repo.local=$BASE/fresh/maven-repository" clean verify
test -s "$SEED/target/surefire-reports/TEST-dev.offline.cache.SecurityApiProbeTest.xml"
test -s "$SEED/target/failsafe-reports/TEST-dev.offline.cache.SecurityApiProbeIT.xml"
cp "$RUNNER_TEMP/apache-maven-3.10.2-bin.tar.gz" "$DIST/"
cp "$RUNNER_TEMP/apache-maven-3.10.2-bin.tar.gz.sha512" "$DIST/"
(cd "$DIST" && expected=$(awk '{print $1}' apache-maven-3.10.2-bin.tar.gz.sha512) && printf '%s  %s\n' "$expected" apache-maven-3.10.2-bin.tar.gz | sha512sum -c -)
cat > "$DIST/manifest.txt" <<'MANIFEST'
source=public_synthetic_dependency_coordinates_only
project=six-security
java_major=25
maven_version=3.10.2
maven_surefire_version=3.6.1
maven_failsafe_version=3.6.1
mcp_sdk_version=2.1.0
offline_extracted_bundle_verification=PASS
private_ci_common_plugin=NOT_INCLUDED
private_security_project_build=NOT_TESTED
external_integrations=NOT_TESTED
MANIFEST
echo "Public Six Security Maven cache verified"
