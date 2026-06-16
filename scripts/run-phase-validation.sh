#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

find_pwsh() {
    for candidate in "${POWERSHELL_BIN:-}" "${PWSH:-}" pwsh "${HOME:-}/.local/bin/pwsh" /usr/local/bin/pwsh /usr/bin/pwsh /opt/microsoft/powershell/7/pwsh
    do
        if [ -z "$candidate" ]; then
            continue
        fi

        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi

        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

pwsh_bin=$(find_pwsh) || {
    printf '%s\n' "PowerShell 7+ was not found. Set POWERSHELL_BIN or put pwsh on PATH." >&2
    exit 127
}

cd "$repo_root"

"$pwsh_bin" -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
"$pwsh_bin" -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
"$pwsh_bin" -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
"$pwsh_bin" -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
"$pwsh_bin" -NoProfile -File scripts/validate-service-pipelines.ps1
"$pwsh_bin" -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
"$pwsh_bin" -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
