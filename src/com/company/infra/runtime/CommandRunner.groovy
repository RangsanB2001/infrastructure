package com.company.infra.runtime

class CommandRunner implements Serializable {
    private final def steps

    CommandRunner(steps) {
        this.steps = steps
    }

    void run(String label, String command, Map<String, String> variables = [:], List<Map> credentials = []) {
        if (!command?.trim()) {
            return
        }

        List<String> environment = variables.collect { key, value -> "${key}=${value}" }
        Closure execute = {
            steps.withEnv(environment) {
                if (steps.isUnix()) {
                    steps.sh(label: label, script: command)
                } else {
                    steps.bat(label: label, script: command)
                }
            }
        }

        List bindings = credentialBindings(credentials)
        if (bindings) {
            steps.withCredentials(bindings) {
                execute()
            }
        } else {
            execute()
        }
    }

    private List credentialBindings(List<Map> credentials) {
        credentials.collect { Map credential ->
            String type = (credential.type ?: 'string').toString()
            switch (type) {
                case 'string':
                    return steps.string(
                        credentialsId: credential.id.toString(),
                        variable: credential.variable.toString()
                    )
                case 'file':
                    return steps.file(
                        credentialsId: credential.id.toString(),
                        variable: credential.variable.toString()
                    )
                case 'usernamePassword':
                    return steps.usernamePassword(
                        credentialsId: credential.id.toString(),
                        usernameVariable: credential.usernameVariable.toString(),
                        passwordVariable: credential.passwordVariable.toString()
                    )
                default:
                    throw new IllegalArgumentException("Unsupported credential type '${type}'")
            }
        }
    }
}
