package com.company.infra.config

import com.cloudbees.groovy.cps.NonCPS

class EnvironmentConfig implements Serializable {
    final String name
    final String agentLabel
    final boolean approvalRequired
    final boolean migrationApprovalRequired
    final String deployCommand
    final String verifyCommand
    final String smokeTestCommand
    final String rollbackCommand
    final String migrationCommand
    final List<Map> credentials
    final Map<String, String> variables

    EnvironmentConfig(String name, Map raw = [:], String defaultAgentLabel = '') {
        this.name = name
        this.agentLabel = text(raw.agentLabel ?: defaultAgentLabel)
        this.approvalRequired = bool(raw.approvalRequired, name == 'prod')
        this.migrationApprovalRequired = bool(raw.migrationApprovalRequired, false)
        this.deployCommand = text(raw.deployCommand)
        this.verifyCommand = text(raw.verifyCommand)
        this.smokeTestCommand = text(raw.smokeTestCommand)
        this.rollbackCommand = text(raw.rollbackCommand)
        this.migrationCommand = text(raw.migrationCommand)
        this.credentials = (raw.credentials ?: []).collect { Map credential -> new LinkedHashMap(credential) }
        this.variables = (raw.variables ?: [:]).collectEntries { key, value ->
            [(key.toString()): value == null ? '' : value.toString()]
        }
    }

    @NonCPS
    private static String text(Object value) {
        value == null ? '' : value.toString().trim()
    }

    @NonCPS
    private static boolean bool(Object value, boolean defaultValue) {
        value == null ? defaultValue : value as boolean
    }
}
