package com.company.infra.core

import com.company.infra.config.EnvironmentConfig
import com.company.infra.config.PipelineConfig
import com.company.infra.runtime.CommandRunner

class ApplicationPipeline implements Serializable {
    private final def steps
    private final PipelineConfig config
    private final CommandRunner runner

    ApplicationPipeline(steps, PipelineConfig config) {
        this.steps = steps
        this.config = config
        this.runner = new CommandRunner(steps)
    }

    void run() {
        configureJob()

        String targetEnvironment = (steps.params.TARGET_ENV ?: config.defaultEnvironment).toString()
        boolean dryRun = steps.params.DRY_RUN == null ? true : steps.params.DRY_RUN as boolean
        EnvironmentConfig environment = config.resolveEnvironment(targetEnvironment)

        steps.currentBuild.description = "${config.applicationName} -> ${targetEnvironment}${dryRun ? ' (dry-run)' : ''}"

        steps.stage('Validate Request') {
            config.safeSummary(targetEnvironment, dryRun).each { key, value ->
                steps.echo("${key}: ${value}")
            }
        }

        steps.timeout(time: config.pipelineTimeoutMinutes, unit: 'MINUTES') {
            buildAndPackage(dryRun, targetEnvironment)
            requestApprovals(environment, dryRun)
            deployAndVerify(environment, dryRun)
        }
    }

    private void configureJob() {
        List jobProperties = [
            steps.parameters([
                steps.choice(
                    name: 'TARGET_ENV',
                    choices: config.environmentNames().join('\n'),
                    description: 'Allow-listed deployment environment'
                ),
                steps.booleanParam(
                    name: 'DRY_RUN',
                    defaultValue: true,
                    description: 'Validate and print the deployment plan without mutating the target'
                )
            ]),
            steps.buildDiscarder(steps.logRotator(numToKeepStr: config.buildsToKeep.toString())),
            steps.disableConcurrentBuilds()
        ]

        if (config.cron) {
            jobProperties << steps.pipelineTriggers([steps.cron(config.cron)])
        }

        steps.properties(jobProperties)
    }

    private void buildAndPackage(boolean dryRun, String targetEnvironment) {
        steps.node(config.buildAgent) {
            try {
                steps.stage('Checkout') {
                    steps.checkout(steps.scm)
                }

                Map<String, String> context = runtimeVariables(dryRun, targetEnvironment)

                steps.stage('Build') {
                    runner.run('Restore', config.commands.restore, context)
                    runner.run('Build', config.commands.build, context)
                }

                steps.stage('Test') {
                    runner.run('Test', config.commands.test, context)
                }

                if (config.testResults) {
                    steps.junit(testResults: config.testResults, allowEmptyResults: false)
                }

                steps.stage('Package') {
                    runner.run('Package', config.commands.package, context)
                    steps.stash(
                        name: config.stashName,
                        includes: config.artifactIncludes,
                        useDefaultExcludes: false
                    )
                    steps.archiveArtifacts(
                        artifacts: config.archiveArtifacts,
                        fingerprint: true,
                        allowEmptyArchive: false
                    )
                }
            } finally {
                steps.deleteDir()
            }
        }
    }

    private void requestApprovals(EnvironmentConfig environment, boolean dryRun) {
        if (dryRun) {
            steps.echo('DRY_RUN=true: approval gates are skipped because no target mutation is allowed.')
            return
        }

        if (environment.approvalRequired) {
            steps.stage("Approval: ${environment.name}") {
                steps.timeout(time: config.approvalTimeoutMinutes, unit: 'MINUTES') {
                    steps.input(
                        message: "Deploy ${config.applicationName} to ${environment.name}?",
                        ok: 'Deploy'
                    )
                }
            }
        }

        if (environment.migrationCommand && environment.migrationApprovalRequired) {
            steps.stage("Migration Approval: ${environment.name}") {
                steps.timeout(time: config.approvalTimeoutMinutes, unit: 'MINUTES') {
                    steps.input(
                        message: "Run database migration for ${config.applicationName} in ${environment.name}?",
                        ok: 'Run migration'
                    )
                }
            }
        }
    }

    private void deployAndVerify(EnvironmentConfig environment, boolean dryRun) {
        steps.node(environment.agentLabel) {
            boolean mutationStarted = false
            Throwable originalFailure = null
            Map<String, String> context = runtimeVariables(dryRun, environment.name)
            context.putAll(environment.variables)

            try {
                steps.deleteDir()
                steps.unstash(config.stashName)

                if (environment.migrationCommand) {
                    steps.stage("Migrate: ${environment.name}") {
                        if (!dryRun) {
                            mutationStarted = true
                        }
                        runner.run('Migration', environment.migrationCommand, context, environment.credentials)
                    }
                }

                steps.stage("Deploy: ${environment.name}") {
                    if (!dryRun) {
                        mutationStarted = true
                    }
                    steps.timeout(time: config.stageTimeoutMinutes, unit: 'MINUTES') {
                        runner.run('Deploy', environment.deployCommand, context, environment.credentials)
                    }
                }

                steps.stage("Verify: ${environment.name}") {
                    runner.run('Verify', environment.verifyCommand, context, environment.credentials)
                    runner.run('Smoke test', environment.smokeTestCommand, context, environment.credentials)
                }
            } catch (Throwable failure) {
                originalFailure = failure
                steps.currentBuild.result = 'FAILURE'

                if (mutationStarted && config.rollbackOnFailure && environment.rollbackCommand) {
                    context.DRY_RUN = 'false'
                    attemptRollback(environment, context)
                }
            } finally {
                steps.archiveArtifacts(
                    artifacts: config.evidenceIncludes,
                    fingerprint: true,
                    allowEmptyArchive: true
                )
                steps.deleteDir()
            }

            if (originalFailure != null) {
                throw originalFailure
            }
        }
    }

    private void attemptRollback(EnvironmentConfig environment, Map<String, String> context) {
        steps.stage("Automatic Rollback: ${environment.name}") {
            try {
                runner.run('Rollback', environment.rollbackCommand, context, environment.credentials)
            } catch (Throwable rollbackFailure) {
                steps.echo("Rollback also failed: ${rollbackFailure.message}")
            }
        }
    }

    private Map<String, String> runtimeVariables(boolean dryRun, String targetEnvironment) {
        [
            APPLICATION_NAME: config.applicationName,
            TARGET_ENV     : targetEnvironment,
            DRY_RUN        : dryRun.toString(),
            BUILD_NUMBER   : steps.env.BUILD_NUMBER ?: '',
            BUILD_TAG      : steps.env.BUILD_TAG ?: '',
            GIT_COMMIT     : steps.env.GIT_COMMIT ?: ''
        ]
    }
}
