# === Configuration ===
$organization = ""
$project = ""
$pat = ""
$groupPrincipalName = ""  # Use the exact principalName of the group
$targetEnvironmentNames = @("", "")      # List of stages to update

# === AUTH ===
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{ Authorization = "Basic $base64AuthInfo" }

# === GET Group Descriptor by principalName ===
$groupUrl = "https://vssps.dev.azure.com/$organization/_apis/graph/groups?api-version=7.1-preview.1"
$groupList = Invoke-RestMethod -Uri $groupUrl -Headers $headers

$group = $groupList.value | Where-Object {
    $_.principalName -eq $groupPrincipalName
}

if ($null -eq $group) {
    Write-Error "❌ Group with principalName '$groupPrincipalName' not found."
    return
}

$groupDescriptor = $group.descriptor
$groupId = $group.originId

if (-not $groupId) {
    Write-Error "❌ Unable to resolve originId for group '$groupPrincipalName'."
    return
}

# === Get all release definitions ===
$definitionsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?api-version=6.1-preview.4"
$definitionsResponse = Invoke-RestMethod -Uri $definitionsUrl -Headers $headers
$allDefinitions = $definitionsResponse.value

foreach ($definitionSummary in $allDefinitions) {
    $definitionId = $definitionSummary.id
    $definitionName = $definitionSummary.name
    $definitionUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definitionId)?api-version=6.1-preview.4"

    try {
        $definition = Invoke-RestMethod -Uri $definitionUrl -Headers $headers -Method Get

        $envsUpdated = @()

        foreach ($env in $definition.environments) {
            if ($targetEnvironmentNames -contains $env.name) {
                # Pre-deploy approval: assign group
                $env.preDeployApprovals.approvals = @(
                    @{
                        "rank" = 1
                        "isAutomated" = $false
                        "isNotificationOn" = $false
                        "approver" = @{
                            "displayName" = $group.displayName
                            "id" = $groupId
                        }
                    }
                )

                # Post-deploy approval: disable
                $env.postDeployApprovals.approvals = @(
                    @{
                        "rank" = 1
                        "isAutomated" = $true
                        "isNotificationOn" = $false
                        "approver" = $null
                    }
                )

                $envsUpdated += $env.name
            }
        }

        # Skip PUT if no environments were changed
        if ($envsUpdated.Count -eq 0) {
            continue
        }

        # PUT updated definition
        $bodyJson = $definition | ConvertTo-Json -Depth 100 -Compress
        $updatedDefinition = Invoke-RestMethod -Uri $definitionUrl -Headers $headers -Method Put -Body $bodyJson -ContentType "application/json"

        # Output results
        $webUrl = "https://dev.azure.com/$organization/$project/_release?definitionId=$definitionId"
        Write-Host "✅ Pipeline: $($updatedDefinition.name)"
        Write-Host "   URL: $webUrl"

        foreach ($env in $updatedDefinition.environments) {
            if ($targetEnvironmentNames -contains $env.name) {
                $preApprover = if ($env.preDeployApprovals.approvals[0].isAutomated) {
                    "Automated"
                } else {
                    $env.preDeployApprovals.approvals[0].approver.displayName
                }

                $postApprover = if ($env.postDeployApprovals.approvals[0].isAutomated) {
                    "Automated"
                } else {
                    $env.postDeployApprovals.approvals[0].approver.displayName
                }

                Write-Host "   Stage: $($env.name)"
                Write-Host "     PreApproval Group: $preApprover"
                Write-Host "     PostApproval Group: $postApprover"
            }
        }

        Write-Host ".................................................................................."
    }
    catch {
        Write-Error "❌ Failed to update pipeline '$definitionName' (ID: $definitionId): $_"
    }
}
