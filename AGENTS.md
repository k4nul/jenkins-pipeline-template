schema_version: "1.0"
project:
  id: "jenkins-pipeline-template"
  type: "devops.template.jenkins"
  status: "active"
scope:
  owns:
    - "jenkins/*.Jenkinsfile"
    - "jenkins/JOB_BLUEPRINT*.md"
    - "scripts/show-jenkins-job-plan.ps1"
    - "scripts/export-jenkins-job-dsl.ps1"
    - "scripts/validate-service-pipelines.ps1"
    - "config/service-pipelines.psd1"
    - "k8s/jenkins-controller/"
  consumes:
    k8s_template:
      path: "../k8s-platform-template"
      usage:
        - "bundle validation command examples"
        - "environment preset compatibility"
    docker_template:
      path: "../docker-build-template"
      usage:
        - "image build and push stages"
    cloud_template:
      path: "../cloud-infra-template"
      usage:
        - "terraform plan and apply stages"
instructions:
  template_rules:
    keep_company_specific_values_out: true
    require_parameterized_repo_url: true
    require_credentials_id_as_parameter: true
    avoid_hardcoded_branch_names: true
  pipeline_contract:
    stages:
      - "checkout"
      - "tool-preflight"
      - "validate"
      - "build"
      - "archive"
      - "promote"
    gates:
      destructive_actions: "manual approval or explicit parameter"
      production_apply: "manual approval"
  validation:
    required:
      - command: "pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json"
        when: "job plan logic changes"
      - command: "pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy"
        when: "Job DSL generation changes"
automation:
  enabled: true
  entrypoints:
    job_plan: "scripts/show-jenkins-job-plan.ps1"
    job_dsl: "scripts/export-jenkins-job-dsl.ps1"
    service_pipeline_plan: "scripts/show-service-pipeline-plan.ps1"
