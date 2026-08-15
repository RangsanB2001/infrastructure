import com.company.infra.config.PipelineConfig
import com.company.infra.core.ApplicationPipeline

/**
 * Public entry point for consumer Jenkinsfiles.
 *
 * Usage:
 *   @Library('infra-ops-pipeline@v0.1.0') _
 *   infraPipeline(applicationName: 'my-service', ...)
 */
def call(Map rawConfig = [:]) {
    PipelineConfig config = new PipelineConfig(rawConfig)
    config.validate()

    new ApplicationPipeline(this, config).run()
}
