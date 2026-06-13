# Jenkins

[English](README.md) | 한국어

이 디렉터리에는 저장소 자체를 위한 범용 Jenkins 자동화가 들어 있습니다. 특정 회사 서비스 파이프라인이 아니라, 저장소 단위의 검증과 번들 전달 흐름에 초점을 맞춘 구성입니다.

## 주요 잡

- `repository-validation.Jenkinsfile`: 저장소 구조와 렌더링 결과를 검증
- `bundle-delivery.Jenkinsfile`: 번들을 렌더링, 검증, 아카이브
- `bundle-promotion.Jenkinsfile`: 전달된 번들을 다시 검증하고 선택적으로 배포
- `job-seed.Jenkinsfile`: 공통 잡 계획을 바탕으로 Jenkins 폴더와 파이프라인 잡을 생성

## Jenkins 에 필요한 것

Jenkins agent 에는 다음이 준비되어 있으면 좋습니다.

- PowerShell 또는 `pwsh`
- `git`
- 클러스터 검증 및 매니페스트 흐름을 위한 `kubectl`
- Helm 컴포넌트를 위한 `helm`

각 Jenkinsfile 앞단에는 agent readiness preflight 가 있어서, 필요한 도구가 없으면 초반에 더 명확하게 실패합니다.

## Jenkins 설정 순서 예시

1. 저장소 단위 잡 계획 미리보기:

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
```

2. Job DSL 생성:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

3. 생성된 DSL 과 SCM 설정 검토
4. Jenkins 에서 DSL 적용
5. 팀 단위 활성화 전에 `repository-validation` 먼저 실행

## 중요한 기본값

- 기본 샘플 애플리케이션은 공개 이미지를 사용하므로 서비스별 이미지 빌드 잡이 필수가 아닙니다.
- 서비스 단위 잡은 해당 서비스에 실제 Jenkinsfile 이 있고, 카탈로그에서도 활성화되어 있을 때만 나타납니다.
- `job-seed.Jenkinsfile` 의 프리셋 목록은 기본 공란이며, 이는 `config/environments` 에 있는 프리셋을 모두 사용하겠다는 의미입니다.
- `job-seed.Jenkinsfile` 의 SCM URL 과 브랜치 스펙 기본값은 비어 있습니다. `SEED_REPO_URL` 과 `SEED_BRANCH_SPEC` 를 제공하기 전까지 생성된 DSL 은 공개용 placeholder 를 사용합니다.
- `SEED_APPLY_JOB_DSL=true` 에서 `SEED_REMOVED_JOB_ACTION=DELETE` 를 사용하려면 `SEED_CONFIRM_REMOVED_JOB_DELETE=true` 확인 값도 필요합니다.
- dry-run 이 아닌 delivery 와 promotion 배포는 Jenkins 승인 프롬프트와 bootstrap secret/status 검증이 필요합니다.

Jenkins 에서 생성된 DSL 을 적용하기 전에는 다음 값을 설정하세요.

- `SEED_REPO_URL`
- `SEED_BRANCH_SPEC`
- `SEED_SCM_CREDENTIALS_ID`
- `SEED_JOB_ROOT` 같은 선택형 폴더 루트

## 커스텀 selection 예시

환경 프리셋 대신 커스텀 selection 을 쓰고 싶다면:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 `
  -SelectionName sandbox `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -RepoUrl https://github.com/example-org/example-repo.git `
  -BranchSpec '*/<branch-or-pattern>' `
  -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

함께 보면 좋은 파일:

- `JOB_BLUEPRINT.ko.md`
- `scripts/show-jenkins-job-plan.ps1`
- `scripts/export-jenkins-job-dsl.ps1`
