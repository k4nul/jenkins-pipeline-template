# Jenkins 잡 청사진

[English](JOB_BLUEPRINT.md) | 한국어

권장하는 범용 폴더 레이아웃은 다음과 같습니다.

```text
platform/
  dev/
    repository-validation
    bundle-delivery
    bundle-promotion
  staging/
    repository-validation
    bundle-delivery
    bundle-promotion
  prod/
    repository-validation
    bundle-delivery
    bundle-promotion
```

## 이 레이아웃을 권장하는 이유

- 애플리케이션 예제가 바뀌어도 저장소 단위 잡 구조는 안정적으로 유지됩니다.
- delivery 와 promotion 단계가 명확하게 분리됩니다.
- 환경 프리셋이 Jenkins 폴더 구조에 자연스럽게 대응됩니다.
- 위 폴더 이름은 예시일 뿐입니다. `sandbox`, `qa`, `production` 같은 이름을 써도 같은 구조를 그대로 적용할 수 있습니다.

## 시드 기본값

- `job-seed.Jenkinsfile` 에서 `SEED_ENVIRONMENT_PRESETS` 를 비워두면 현재 `config/environments` 에 있는 모든 프리셋에 대해 잡이 생성됩니다.
- 환경 프리셋 없이 `SEED_SELECTION_NAME` 만 제공하면 공개용 기본값을 사용하는 커스텀 selection 하나를 생성합니다.
- `job-seed.Jenkinsfile` 에서 `SEED_REPO_URL` 과 `SEED_BRANCH_SPEC` 기본값은 비어 있습니다.
- `SEED_REPO_URL` 과 `SEED_BRANCH_SPEC` 를 제공하지 않으면 생성된 DSL 은 공개용 SCM placeholder 를 사용합니다.
- Jenkins 에서 생성된 DSL 을 적용한다면, 먼저 `SEED_REPO_URL`, `SEED_BRANCH_SPEC`, 필요 시 `SEED_SCM_CREDENTIALS_ID` 를 설정해 SCM 기반 잡이 의도한 저장소를 바라보게 하세요.
- `SEED_DOCKER_REGISTRY` 처럼 구체적인 registry metadata 를 제공하면 환경별 정보로 취급하세요. 구체적인 SCM, registry, credentials metadata 가 있으면 seed job 은 생성된 Job DSL artifact 보관을 건너뜁니다.
- `SEED_JOB_ROOT` 와 `SEED_SERVICE_JOB_ROOT` 는 안전한 literal segment 로 구성된 비어 있지 않은 Jenkins folder path 여야 합니다. 공란, parent traversal, expression-like segment 는 Job DSL 생성 전에 실패합니다.
- `SEED_SKIP_SERVICE_JOBS=true` 가 아니면 서비스 잡 생성 전에 서비스 파이프라인 검증이 먼저 실행됩니다.

## 컨트롤러 없는 회귀 전략

Jenkins 플러그인 가정, 공개 이미지 버전, 생성되는 파이프라인 구조를 바꾸기 전에는 로컬 phase wrapper 와 PowerShell 하네스를 먼저 실행하세요.

```text
sh scripts/run-phase-validation.sh
pwsh -NoProfile -File scripts/validate-jenkins-job-dsl.ps1
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
pwsh -NoProfile -File scripts/show-jenkins-job-plan.ps1 -Format json
pwsh -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
pwsh -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -OutputPath out/jenkins/public-preset-matrix-seed-job-dsl.groovy
pwsh -NoProfile -File scripts/validate-service-pipelines.ps1
```

`run-phase-validation.sh` 는 전환 gate 이며, `dev` 기본 경로 검증 뒤에 전체 공개 프리셋 Job DSL 하네스를 실행합니다. `validate-jenkins-job-dsl.ps1` 는 `dev`, `staging`, `prod` 개별 프리셋과 전체 공개 프리셋 matrix fixture, `SelectionName` 단독 커스텀 selection, SCM placeholder, 명시적 SCM 값 escaping, 삭제 보호, 서비스 카탈로그 메타데이터를 컨트롤러 없이 검증합니다.

## 선택형 서비스 잡

현재 공개 이미지 기반 샘플 서비스는 전용 Jenkins 빌드 잡이 필요하지 않습니다.

나중에 자체 서비스와 Jenkinsfile 을 추가하면, 계획과 seed DSL 을 다시 생성해서 해당 서비스 잡이 자동으로 나타나게 할 수 있습니다.
