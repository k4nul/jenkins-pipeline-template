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

print_command() {
    printf 'command:' >&2
    for arg in "$@"
    do
        printf ' %s' "$arg" >&2
    done
    printf '\n' >&2
}

run_step() {
    label=$1
    shift

    printf '\n==> %s\n' "$label" >&2
    print_command "$@"

    if "$@"
    then
        printf '<== %s passed\n' "$label" >&2
        return 0
    else
        status=$?
        printf 'Phase validation failed during "%s" with exit code %s.\n' "$label" "$status" >&2
        print_command "$@"
        exit "$status"
    fi
}

pwsh_bin=$(find_pwsh) || {
    printf '%s\n' "PowerShell 7+ was not found. Set POWERSHELL_BIN or put pwsh on PATH." >&2
    exit 127
}

cd "$repo_root"

pwsh_version=$("$pwsh_bin" -NoProfile -NoLogo -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true)
if [ -n "$pwsh_version" ]; then
    printf 'Using PowerShell: %s (%s)\n' "$pwsh_bin" "$pwsh_version" >&2
else
    printf 'Using PowerShell: %s\n' "$pwsh_bin" >&2
fi

run_step "dependency inventory" "$pwsh_bin" -NoProfile -File scripts/show-dependency-inventory.ps1 -Format json
run_step "dev Jenkins job plan" "$pwsh_bin" -NoProfile -File scripts/show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format json
run_step "service pipeline plan" "$pwsh_bin" -NoProfile -File scripts/show-service-pipeline-plan.ps1 -Format json
run_step "dev Job DSL export" "$pwsh_bin" -NoProfile -File scripts/export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath out/jenkins/seed-job-dsl.groovy
run_step "service pipeline validation" "$pwsh_bin" -NoProfile -File scripts/validate-service-pipelines.ps1
run_step "aggregate Job DSL validation" "$pwsh_bin" -NoProfile -File scripts/validate-jenkins-job-dsl.ps1 -Format json
run_step "public preset test suite" "$pwsh_bin" -NoProfile -File tests/jenkins-job-dsl.public-presets.ps1
