#!/usr/bin/env bash
# Independent public-only Maven dependency seed for CI Common.
# Never checkout, read, or package a private repository.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
REPOSITORY="$BASE/maven-repository"
WORKSPACE="$BASE/seed"
DIST="$ROOT/dist"
mkdir -p "$REPOSITORY" "$WORKSPACE/src/main/java/dev/offline/cache" \
  "$WORKSPACE/src/test/java/dev/offline/cache" "$DIST"

java -version 2>&1 | grep -Eq 'version "25([.+-]|")' || {
  echo 'Java 25 required' >&2
  exit 2
}
mvn -version | grep -Fq 'Apache Maven 3.10.2' || {
  echo 'Maven 3.10.2 required' >&2
  exit 2
}

cp "$ROOT/pom-six-ci-common.xml" "$WORKSPACE/pom.xml"
cat > "$WORKSPACE/src/main/java/dev/offline/cache/PublicApiProbe.java" <<'JAVA'
package dev.offline.cache;
import org.apache.maven.project.MavenProject;
import org.apache.maven.plugin.Mojo;
public final class PublicApiProbe {
  private PublicApiProbe() { }
  public static String coreName() { return MavenProject.class.getSimpleName(); }
  public static String pluginName() { return Mojo.class.getSimpleName(); }
}
JAVA
cat > "$WORKSPACE/src/test/java/dev/offline/cache/PublicApiProbeTest.java" <<'JAVA'
package dev.offline.cache;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
class PublicApiProbeTest {
  @Test void loadsPublicMavenApis() {
    assertEquals("MavenProject", PublicApiProbe.coreName());
    assertEquals("Mojo", PublicApiProbe.pluginName());
  }
}
JAVA

cd "$WORKSPACE"
mvn_seed() { mvn -B -ntp "-Dmaven.repo.local=$REPOSITORY" "$@"; }
echo 'Resolve the complete public Maven 3.10.2/plugin graph'
mvn_seed -U org.apache.maven.plugins:maven-dependency-plugin:3.9.0:go-offline
mvn_seed org.apache.maven.plugins:maven-dependency-plugin:3.9.0:resolve-plugins
# The private CI Common source still declares Maven API 3.9.16.
# Ship those public coordinates beside the 3.10.2 compiler/runtime graph.
for dependency in org.apache.maven:maven-plugin-api:3.9.16 org.apache.maven:maven-core:3.9.16; do
  mvn_seed org.apache.maven.plugins:maven-dependency-plugin:3.9.0:get "-Dartifact=$dependency"
done
mvn_seed clean verify
# Retain exact plugin graphs required by older Security/CI Common consumers.
mvn_seed org.apache.maven.plugins:maven-surefire-plugin:3.5.6:test
mvn_seed org.apache.maven.plugins:maven-surefire-plugin:3.6.0:test
mvn_seed -o clean verify
mvn_seed -o org.apache.maven.plugins:maven-dependency-plugin:3.9.0:tree

for artifact in maven-plugin-api maven-core; do
  test -s "$REPOSITORY/org/apache/maven/$artifact/3.10.2/$artifact-3.10.2.jar" || {
    echo "Missing org.apache.maven:$artifact:3.10.2" >&2
    exit 3
  }
done
test -s "$REPOSITORY/org/apache/maven/maven/3.10.2/maven-3.10.2.pom" || {
  echo 'Missing org.apache.maven:maven:3.10.2 parent POM' >&2
  exit 3
}
while read -r artifact version; do
  test -s "$REPOSITORY/org/apache/maven/plugins/$artifact/$version/$artifact-$version.jar" || {
    echo "Missing Maven plugin $artifact:$version" >&2
    exit 3
  }
done <<'PLUGINS'
maven-compiler-plugin 3.15.0
maven-resources-plugin 3.5.0
maven-jar-plugin 3.5.1
maven-surefire-plugin 3.6.1
maven-install-plugin 3.1.4
maven-clean-plugin 3.5.0
maven-dependency-plugin 3.9.0
PLUGINS

for version in 3.5.6 3.6.0 3.6.1; do
  jar="$REPOSITORY/org/apache/maven/plugins/maven-surefire-plugin/$version/maven-surefire-plugin-$version.jar"
  test -s "$jar" || exit 3
done
for artifact in maven-plugin-api maven-core; do
  test -s "$REPOSITORY/org/apache/maven/$artifact/3.9.16/$artifact-3.9.16.jar" || exit 3
done
find "$REPOSITORY" -type f -name '*.lastUpdated' -delete
BUNDLE="$DIST/six-ci-common-maven-repository-offline.tar.gz"
tar -czf "$BUNDLE" -C "$BASE" maven-repository
(cd "$DIST" && sha256sum "$(basename "$BUNDLE")" > "$(basename "$BUNDLE").sha256")

# Verify only the bytes that will be published, in a fresh isolated cache.
VERIFY_DIR="$BASE/verify-extracted"
mkdir -p "$VERIFY_DIR"
(cd "$DIST" && sha256sum -c "$(basename "$BUNDLE").sha256")
tar -xzf "$BUNDLE" -C "$VERIFY_DIR"
test -d "$VERIFY_DIR/maven-repository"
mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" clean verify
mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" \
  org.apache.maven.plugins:maven-surefire-plugin:3.5.6:test
mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" \
  org.apache.maven.plugins:maven-surefire-plugin:3.6.0:test
mvn -B -ntp -o "-Dmaven.repo.local=$VERIFY_DIR/maven-repository" \
  org.apache.maven.plugins:maven-dependency-plugin:3.9.0:tree

cp "$RUNNER_TEMP/apache-maven-3.10.2-bin.tar.gz" "$DIST/"
cp "$RUNNER_TEMP/apache-maven-3.10.2-bin.tar.gz.sha512" "$DIST/"
(cd "$DIST" && expected=$(awk '{print $1}' apache-maven-3.10.2-bin.tar.gz.sha512) && printf '%s  %s\n' "$expected" apache-maven-3.10.2-bin.tar.gz | sha512sum -c -)
cat > "$DIST/manifest.txt" <<'MANIFEST'
source=public_synthetic_dependency_coordinates_only
project=ci-common
java_major=25
maven_version=3.10.2
maven_core_version=3.10.2
maven_plugin_api_version=3.10.2
surefire_version=3.6.1
surefire_compat_versions=3.5.6,3.6.0,3.6.1
synthetic_junit_execution=PASS
offline_extracted_bundle_verification=PASS
private_repository_checkout=FALSE
private_project_compilation=NOT_TESTED
external_integrations=NOT_TESTED
MANIFEST
echo "Verified public-only offline Maven cache: $BUNDLE"
