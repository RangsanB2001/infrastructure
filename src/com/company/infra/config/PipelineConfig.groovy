package com.company.infra.config

class PipelineConfig implements Serializable {
    private static final Set<String> RESERVED_VARIABLES = [
        'APPLICATION_NAME',
        'TARGET_ENV',
        'DRY_RUN',
        'BUILD_NUMBER',
        'BUILD_TAG',
        'GIT_COMMIT'
    ] as Set

    final String applicationName
    final String buildAgent
    final String deployAgent
    final String defaultEnvironment
    final Map<String, String> commands
    final Map<String, Map> environmentDefinitions
    final String artifactIncludes
    final String archiveArtifacts
    final String evidenceIncludes
    final String testResults
    final String stashName
    final int approvalTimeoutMinutes
    final int stageTimeoutMinutes
    final int pipelineTimeoutMinutes
    final int buildsToKeep
    final boolean rollbackOnFailure
    final String cron

    PipelineConfig(Map raw = [:]) {
        applicationName = text(raw.applicationName)
        buildAgent = text(raw.buildAgent ?: 'linux')
        deployAgent = text(raw.deployAgent ?: buildAgent)
        defaultEnvironment = text(raw.defaultEnvironment ?: 'dev')
        commands = normalizeStringMap(raw.commands ?: [:])
        environmentDefinitions = (raw.environments ?: [:]).collectEntries { key, value ->
            [(key.toString()): new LinkedHashMap((Map) value)]
        }
        artifactIncludes = text(raw.artifactIncludes ?: 'out/**/*')
        archiveArtifacts = text(raw.archiveArtifacts ?: artifactIncludes)
        evidenceIncludes = text(raw.evidenceIncludes ?: 'evidence/**/*')
        testResults = text(raw.testResults)
        stashName = text(raw.stashName ?: 'application-package')
        approvalTimeoutMinutes = positiveInt(raw.approvalTimeoutMinutes, 15)
        stageTimeoutMinutes = positiveInt(raw.stageTimeoutMinutes, 30)
        pipelineTimeoutMinutes = positiveInt(raw.pipelineTimeoutMinutes, 60)
        buildsToKeep = positiveInt(raw.buildsToKeep, 30)
        rollbackOnFailure = raw.rollbackOnFailure == null ? true : raw.rollbackOnFailure as boolean
        cron = text(raw.cron)
    }

    List<String> environmentNames() {
        environmentDefinitions.keySet().toList()
    }

    EnvironmentConfig resolveEnvironment(String name) {
        Map raw = environmentDefinitions[name]
        if (raw == null) {
            throw new IllegalArgumentException(
                "TARGET_ENV '${name}' is not allowed. Expected one of: ${environmentNames().join(', ')}"
            )
        }

        new EnvironmentConfig(name, raw, deployAgent)
    }

    void validate() {
        List<String> errors = []

        requireText(errors, 'applicationName', applicationName)
        requireText(errors, 'buildAgent', buildAgent)
        requireText(errors, 'deployAgent', deployAgent)

        ['build', 'test', 'package'].each { String commandName ->
            requireText(errors, "commands.${commandName}", commands[commandName])
        }

        if (environmentDefinitions.isEmpty()) {
            errors << 'environments must contain at least one named environment'
        }

        if (!environmentDefinitions.containsKey(defaultEnvironment)) {
            errors << "defaultEnvironment '${defaultEnvironment}' must exist in environments"
        }

        environmentDefinitions.each { String name, Map raw ->
            EnvironmentConfig environment = new EnvironmentConfig(name, raw, deployAgent)
            requireText(errors, "environments.${name}.agentLabel", environment.agentLabel)
            requireText(errors, "environments.${name}.deployCommand", environment.deployCommand)
            requireText(errors, "environments.${name}.verifyCommand", environment.verifyCommand)

            if (rollbackOnFailure) {
                requireText(errors, "environments.${name}.rollbackCommand", environment.rollbackCommand)
            }

            if (environment.migrationApprovalRequired && !environment.migrationCommand) {
                errors << "environments.${name}.migrationApprovalRequired needs migrationCommand"
            }

            environment.credentials.eachWithIndex { Map credential, int index ->
                validateCredential(errors, name, credential, index)
            }

            environment.variables.keySet().each { String variable ->
                if (!(variable ==~ /[A-Z][A-Z0-9_]*/)) {
                    errors << "environments.${name}.variables key '${variable}' must be uppercase shell variable syntax"
                }
                if (variable in RESERVED_VARIABLES) {
                    errors << "environments.${name}.variables cannot override reserved variable '${variable}'"
                }
            }
        }

        if (errors) {
            throw new IllegalArgumentException(
                "Invalid infraPipeline configuration:\n - ${errors.join('\n - ')}"
            )
        }
    }

    Map<String, String> safeSummary(String targetEnvironment, boolean dryRun) {
        [
            application : applicationName,
            environment : targetEnvironment,
            dryRun      : dryRun.toString(),
            artifact    : artifactIncludes
        ]
    }

    private static void validateCredential(List<String> errors, String environmentName, Map credential, int index) {
        String prefix = "environments.${environmentName}.credentials[${index}]"
        String type = text(credential.type ?: 'string')
        String id = text(credential.id)
        String variable = text(credential.variable)

        if (!(type in ['string', 'usernamePassword', 'file'])) {
            errors << "${prefix}.type '${type}' is unsupported"
        }
        requireText(errors, "${prefix}.id", id)

        if (type in ['string', 'file']) {
            requireText(errors, "${prefix}.variable", variable)
        }
        if (type == 'usernamePassword') {
            requireText(errors, "${prefix}.usernameVariable", text(credential.usernameVariable))
            requireText(errors, "${prefix}.passwordVariable", text(credential.passwordVariable))
        }
    }

    private static Map<String, String> normalizeStringMap(Map raw) {
        raw.collectEntries { key, value -> [(key.toString()): text(value)] }
    }

    private static int positiveInt(Object value, int defaultValue) {
        int parsed = value == null ? defaultValue : value as int
        parsed > 0 ? parsed : defaultValue
    }

    private static void requireText(List<String> errors, String field, String value) {
        if (!value?.trim()) {
            errors << "${field} is required"
        }
    }

    private static String text(Object value) {
        value == null ? '' : value.toString().trim()
    }
}
