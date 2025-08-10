$organization = ""
$projects = @("", "", "")
$targetEnvironments = @("", "", "")    # leave @() to include all envs
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

$results = @()

# normalize env filters to lowercase for case-insensitive match
$targetEnvsNorm = @()
if ($targetEnvironments -and $targetEnvironments.Count -gt 0) {
    $targetEnvsNorm = $targetEnvironments | ForEach-Object { $_.ToLower() }
}

foreach ($project in $projects) {

    $definitionsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?api-version=6.1-preview.4"
    $definitionsResponse = Invoke-RestMethod -Uri $definitionsUrl -Headers $headers
    $allDefinitions = $definitionsResponse.value

    foreach ($definitionSummary in $allDefinitions) {
        $definitionId   = $definitionSummary.id
        $definitionName = $definitionSummary.name
        $pipelineUrl    = "https://dev.azure.com/$organization/$project/_release?definitionId=$definitionId"

        $definitionUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definitionId)?api-version=6.1-preview.4"
        $response = Invoke-RestMethod -Uri $definitionUrl -Headers $headers

        # columns shown once per pipeline (first emitted row)
        $projCol     = $project
        $pipeNameCol = $definitionName
        $pipeUrlCol  = $pipelineUrl
        $printedFirstRowForPipeline = $false

        foreach ($env in $response.environments) {
            if ($null -eq $env) { continue }

            $envName = $env.name
            $envOk = ($targetEnvsNorm.Count -eq 0) -or ($targetEnvsNorm -contains ($envName.ToLower()))
            if (-not $envOk) { continue }

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
        PipelineUrl         = ""
        EnvironmentName     = ""
        PreApprovalGroup    = ""
        PostApprovalGroup   = ""
    }
}

$results | Export-Csv -Path "3.1ReleaseApprovers.csv" -NoTypeInformation -Encoding UTF8
Write-Output "Results exported to 5ReleaseApprovers.csv"
