# Six DevKit — Public Maven Offline Cache Builder

Repositório público destinado **exclusivamente** à preparação de dependências Maven abertas para o DevKit offline. Não contém código-fonte, arquivos de configuração privados, credenciais ou históricos dos projetos Aquifer e Chess.

## Versões-alvo

- Java 25 e Maven 3.9.16
- Spring Boot 4.1.1, Spring AI 2.0.1 e Flyway 13.6.0 (sem atualizar Spring AI)
- JUnit Jupiter 6.1.2
- JaCoCo 0.8.15, Checkstyle (plugin 3.6.0/engine 14.3.0), PMD 3.28.0 e SpotBugs 4.10.5.0

## Geração do pacote

Abra **Actions → Build public Maven offline dependency bundle → Run workflow**. Após a execução, baixe o artefato **six-aquifer-maven-offline**. Ele inclui o tarball do repositório Maven, SHA-256 e um manifesto de versões.

O workflow executa testes sintéticos online e, depois, em modo Maven offline (-o). Ele **não testa o código privado do Aquifer nem integrações PostgreSQL**; essa validação será realizada no ambiente local ao recebermos o pacote.

## Segurança

- O workflow usa somente dependências públicas e permissão `contents: read`.
- Não transfira POMs privados, fontes, tokens, settings.xml ou URLs internas para cá.
- Artefatos de workflows em repositórios públicos podem ser acessíveis publicamente.
- Gatilho manual apenas, sem execução em PRs externos.
- O Chess poderá ser incorporado ao manifesto posteriormente, reutilizando a mesma árvore Maven onde versões e coordenadas coincidirem.

## Pacote isolado `six-github-maven-offline`

O workflow `Build six-github Maven offline dependency bundle` produz um ZIP independente para o DevKit offline, preservando o pacote Aquifer existente.

A base `pom-six-github.xml` é um manifesto **sintético público**: inclui as coordenadas de JUnit, Testcontainers PostgreSQL, JDBC e plugins de build observadas no POM da branch `agente/andreia` do Six Chess, além de Spring Boot, Spring AI, Flyway, JaCoCo e quality tools já presentes neste builder. Não publica POM privado, fontes ou segredos.

O workflow executa resolução online e testes Maven reais (incluindo verificação subsequente em modo offline); o sucesso não comprova testes funcionais nos repositórios privados, Docker ou PostgreSQL. O artefato tem validade de 7 dias e seu SHA-256 precisa ser validado antes de integrar o DevKit.
