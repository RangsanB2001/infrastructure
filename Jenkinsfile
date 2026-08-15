pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        skipDefaultCheckout(true)
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate Template') {
            steps {
                script {
                    if (isUnix()) {
                        sh 'pwsh -NoLogo -NoProfile -File ./tests/template-tests.ps1'
                    } else {
                        powershell './tests/template-tests.ps1'
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'tests/reports/**/*', allowEmptyArchive: true
            deleteDir()
        }
    }
}
