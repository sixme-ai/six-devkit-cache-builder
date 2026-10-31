# Six DevKit — public Maven offline dependency builder

Public build-only repository. The Maven workflows contain **public coordinates, versions and synthetic JUnit tests**; the separate Pocket ID workflow bundles its **public upstream open-source binary**. No private project checkout, application source, business rules, credentials, internal API schemas or project secrets.

## Independent GitHub Actions

| Project | Workflow (Actions → Run workflow) | Public manifest | Build script | Artifact |
| --- | --- | --- | --- | --- |
| Aquifer | `Build Aquifer Maven offline dependency bundle` | `pom.xml` | `scripts/build-cache.sh` | `six-aquifer-maven-offline` |
| GitHub MCP | `Build GitHub MCP Maven offline dependency bundle` | `pom-six-github.xml` | `scripts/build-six-github-cache.sh` | `six-github-maven-offline` |
| Chess | `Build Chess Maven offline dependency bundle` | `pom-six-chess.xml` | `scripts/build-six-chess-cache.sh` | `six-chess-maven-offline` |

**Self-sufficiency invariant:** every project's seed must include **its full own dependency and plugin graph, even if the same artifacts appear in the other bundles**. Repeated dependencies are deliberately shipped again in each ZIP; no cross-bundle deduplication or installation order is allowed. The build extracts the finished tarball into a fresh repository and re-executes Maven `-o` from that extracted repository. The baseline is the project's actual POM, not the dependencies of another project. A public synthetic seed verifies only its declared coordinates; private-project build tests remain a separate requirement.

Each workflow is **independent** and has its own `workflow_dispatch`, push-path filters, concurrency group, synthetic seed, Maven repository archive, SHA-256, manifest and artifact name. Updating one project's POM/script triggers **only its Action**. Updating the Aquifer workflow itself affects Aquifer only.

### Versions and scope

- Toolchain: Java 25; Maven 3.9.16.
- Aquifer: its existing public synthetic Spring Boot 4.1.1 / Spring AI 2.0.1 / Flyway 13.6.0 seed, left unchanged.
- GitHub MCP: Spring Boot 4.1.1, Spring AI 2.0.1, Spring MVC/Tomcat, Spring AI MCP SDK + explicit servlet library, Spring Security, OAuth2 Resource Server and JOSE/JWT; JUnit 6.1.2, JaCoCo 0.8.15, Checkstyle, PMD, SpotBugs. **No automatic `spring-ai-starter-mcp-server-webmvc` transport**. No Chess/PostgreSQL seed dependencies.
- Chess: all public dependencies from supported Chess POMs (sprint-3 and sprint-4): JUnit 6.1.2, Testcontainers PostgreSQL 2.0.5, PostgreSQL JDBC 42.7.13, Jackson Annotations 2.22 (test), compiler, resources 3.5.0, enforcer, Surefire/Failsafe. Artifacts repeated in other projects are still bundled independently here. **No Spring AI / OAuth / Aquifer dependencies** unless required by a Chess POM.

## Build and download

Select the **project-specific workflow** in the Actions tab, click **Run workflow** on `main`, then download **that workflow run's artifact**. A push modifying that project's manifest/script also starts its Action. Artifacts are retained for 7 days.

Each artifact ZIP contains a `maven-repository` tarball, its `.sha256`, and `manifest.txt`. Verify the SHA-256 before integrating into a local DevKit. No workflow checks out any private project or uploads secrets.

A green workflow proves only **public dependency resolution and synthetic online/offline smoke tests**. It does **not** prove that the real application builds, that OAuth authenticates, or that external provider/DB tests passed. Those must be run in the relevant private project and QA environment.

### Backward compatibility

`pom-six-github-compat.xml` is an archived synthetic compatibility seed, **not used by any current workflow**. Keep it for historical comparison; do not use it to generate new GitHub MCP bundles.

## Optional offline Pocket ID for agent terminals

The independent `Build Pocket ID portable offline runtime` Action downloads the **official Linux amd64 v2.19.1 binary** (pinned SHA-256), includes BSD-2-Clause license, a `localhost` launcher and OIDC/JWKS validation script, and publishes a public direct-download ZIP. No Docker, database server, toolchain or internet is needed **after this ZIP is transferred into the terminal**. The runner verifies real startup and localhost discovery/JWKS. Secrets and SQLite state are generated only in each local agent environment; never copy them into the public ZIP. Use an authorized transfer such as Google Drive to import the ZIP into an air-gapped agent terminal. Browser passkeys require a same-host browser on localhost or HTTPS; headless agents can provision a local confidential client and test real scoped JWT issuance plus invalid-secret denial via `./agent-m2m.sh provision` and `./agent-m2m.sh verify`. M2M is not Code+PKCE for a human user. This is an optional isolated test IdP, **not** the real remote QA stage.
