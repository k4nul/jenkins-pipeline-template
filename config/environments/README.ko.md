# 환경 프리셋

[English](README.md) | 한국어

이 디렉터리에는 검증, 번들 생성, 승격, 값 파일 생성 스크립트에서 반복 인자를 줄이기 위한 재사용 가능한 환경 프리셋이 들어 있습니다.

## 포함된 프리셋

- `dev.psd1`: 개발 친화적인 `web-platform` 기준선
- `staging.psd1`: 사전 운영 검증용 `shared-services` 기준선
- `prod.psd1`: 운영 지향의 `shared-services` 기준선

## 프리셋이 주로 제어하는 값

- `Description`: 생성된 계획에 표시되는 선택 설명
- `ValuesFile`: 기본 값 파일 경로
- `Version`: 기본 이미지 태그 또는 검증용 태그
- `Profile`: 기본 번들 프로필
- `Applications`: 기본 애플리케이션 선택
- `DataServices`: 기본 데이터 서비스 선택
- `IncludeJenkins`: 선택된 번들에 Jenkins 컴포넌트를 포함할지 여부
- `OutputPath`: 번들 생성 워크플로우의 기본 출력 경로
- `ArchivePath`: 번들 생성 또는 승격 워크플로우의 기본 ZIP 경로
- `PromotionExtractPath`: 번들 승격 워크플로우의 기본 압축 해제 경로

현재 포함된 프리셋은 공개 이미지를 사용하므로 `DockerRegistry` 를 설정하지 않습니다. 스크립트는 downstream 템플릿에서 사설 이미지를 도입할 때 레지스트리 override 를 계속 받을 수 있습니다. `ValuesFile` 항목은 추적되는 `.env.example` 파일을 가리키므로 생성된 Jenkins 잡은 기본적으로 공개 안전 런타임 계약을 갖습니다. downstream 에서 비공개 환경별 값을 추가하기 전에는 이 예시 파일을 무시되는 `config/platform-values*.env` 파일로 복사하세요.

## 프리셋 사용 예시

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

`SEED_ENVIRONMENT_PRESETS` 가 비어 있을 때 `job-seed.Jenkinsfile` 이 사용하는
전체 공개 프리셋 matrix 를 미리보거나 export 하려면 `-EnvironmentPreset` 을
생략합니다.

프리셋은 강제 규칙이라기보다 공통 기본값에 가깝습니다. 그래서 명시적으로 인자를 더 주면 프리셋 값을 계속 덮어쓸 수 있습니다.

프리셋을 바꾼 뒤에는 Jenkins Job DSL 검증 하네스를 실행하세요.

```powershell
.\scripts\validate-jenkins-job-dsl.ps1
```

즉 `dev` 를 시작점으로 삼은 뒤에도 아래 항목을 추가 인자로 바꿀 수 있습니다.

- 프로필
- 애플리케이션 목록
- 데이터 서비스 목록
- 출력 경로

프리셋 파일을 바로 고치기 전에 명령줄에서 먼저 실험해보기에 좋습니다.

생성된 계획에는 Jenkins 런타임 잡에서 사용할 저장소 검증, 번들 생성, 승격 명령 문자열이 포함됩니다. 이 저장소에서 바로 실행할 수 있는 컨트롤러 없는 검증 흐름은 [../../docs/testing.md](../../docs/testing.md)를 참고하세요.
