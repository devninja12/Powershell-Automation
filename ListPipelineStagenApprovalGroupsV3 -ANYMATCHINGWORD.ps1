$organization = ""
$projects = @("", "")
# Fuzzy filters: pass substrings or wildcards; case-insensitive. E.g., "ade","prod" or "*ade*"
$targetEnvironments = @("", "")    # leave @() to include all envs
$pat = ""

# Auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{ Authorization = "Basic $base64AuthInfo" }

function Get-ApprovalName {
    param($a)
    if ($null -eq $a) { return "Automated" }
    if ($a.PSObject.Properties.Name -contains "isAutomated" -and $a.isAutomated) { return "Automated" }
    if ($a.approver -and $a.approver.displayName) { return $a.approver.displayName }
    return "Automated"
}

# Build case-insensitive wildcard patterns; if no * provided, wrap with *...*
$envFilters = @()
if ($targetEnvironments -and $targetEnvironments.Count -gt 0) {
    $envFilters = $targetEnvironments | ForEach-Object {
        $p = $_.Trim()
        if ($p -match '[\*\?]') { $p } else { "*$p*" }
    }
}

# Helper: does env name match any filter?
function Test-EnvMatch {
    param([string]$envName, [string[]]$patterns)
    if (-not $patterns -or $patterns.Count -eq 0) { return $true }
    foreach ($pat in $patterns) {
        if ($envName -ilike $pat) { return $true }
    }
    return $false
}

$results = @()

foreach ($project in $projects) {

    $definitionsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?api-version=6.1-preview.4"
    $definitionsResponse = Invoke-RestMethod -Uri $definitionsUrl -Headers $headers
    $allDefinitions = $definitionsResponse.value

    foreach ($definitionSummary in $allDefinitions) {
        $definitionId   = $definitionSummary.id
        $definitionName = $definitionSummary.name
        $pipelineUrl    = "https://dev.azure.com/$organization/$project/_release?definitionId=$definitionId"

        # hyperlink formula for Excel
        $pipelineLink   = "=HYPERLINK(`"$pipelineUrl`")"

        $definitionUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definitionId)?api-version=6.1-preview.4"
        $response = Invoke-RestMethod -Uri $definitionUrl -Headers $headers

        # columns shown once per pipeline (first emitted row)
        $projCol     = $project
        $pipeNameCol = $definitionName
        $pipeUrlCol  = $pipelineLink
        $printedFirstRowForPipeline = $false

        foreach ($env in $response.environments) {
            if ($null -eq $env) { continue }

            $envName = $env.name
            if (-not (Test-EnvMatch -envName $envName -patterns $envFilters)) { continue }

            # collect pre approver names
            $preNames = @()
            if ($env.preDeployApprovals -and $env.preDeployApprovals.approvals) {
                foreach ($a in $env.preDeployApprovals.approvals) {
                    $preNames += (Get-ApprovalName $a)
                }
            }
            if ($preNames.Count -eq 0) { $preNames = @("Automated") }

            # collect post approver names
            $postNames = @()
            if ($env.postDeployApprovals -and $env.postDeployApprovals.approvals) {
                foreach ($a in $env.postDeployApprovals.approvals) {
                    $postNames += (Get-ApprovalName $a)
                }
            }
            if ($postNames.Count -eq 0) { $postNames = @("Automated") }

            # emit single row per environment with pre & post columns
            $results += [PSCustomObject]@{
                Project             = $projCol
                ReleasePipelineName = $pipeNameCol
                EnvironmentName     = $envName
                PreApprovalGroup    = ($preNames | Select-Object -Unique) -join ", "
                PostApprovalGroup   = ($postNames | Select-Object -Unique) -join ", "
                PipelineUrl         = $pipeUrlCol
            }

            if (-not $printedFirstRowForPipeline) {
                $printedFirstRowForPipeline = $true
                $projCol = ""; $pipeNameCol = ""; $pipeUrlCol = ""
            }
        }
    }

    # blank row between projects
    $results += [PSCustomObject]@{
        Project             = ""
        ReleasePipelineName = ""
        EnvironmentName     = ""
        PreApprovalGroup    = ""
        PostApprovalGroup   = ""
        PipelineUrl         = ""
    }
}

$results | Export-Csv -Path "1.11ReleaseApprovers.csv" -NoTypeInformation -Encoding UTF8
Write-Output "Results exported to 1.ReleaseApprovers.csv"
