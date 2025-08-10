# === Configuration ===
$organization = ""
$project = ""
$pat = ""
$groupPrincipalName = ""  # Use the exact principalName of the group here
$targetEnvironmentName = ""

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


# Get all release definitions but DON'T output them
$definitionsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?api-version=6.1-preview.4"
$definitionsResponse = Invoke-RestMethod -Uri $definitionsUrl -Headers $headers
$allDefinitions = $definitionsResponse.value  # <-- No output here

foreach ($definitionSummary in $allDefinitions) {
    $definitionId = $definitionSummary.id
    $definitionName = $definitionSummary.name
    $definitionUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definitionId)?api-version=6.1-preview.4"

    try {
        $definition = Invoke-RestMethod -Uri $definitionUrl -Headers $headers -Method Get

        $targetEnvironment = $definition.environments | Where-Object { $_.name -eq $targetEnvironmentName }
        if ($null -eq $targetEnvironment) {
            # Skip pipelines without the target environment silently or with minimal info
            continue
        }

        # Update approvals for the target environment
        $targetEnvironment.PostDeployApprovals.approvals = @(
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

        # Convert updated definition to JSON
        $bodyJson = $definition | ConvertTo-Json -Depth 100 -Compress
        
        # PUT updated definition and capture updated response
        $updatedDefinition = Invoke-RestMethod -Uri $definitionUrl -Headers $headers -Method Put -Body $bodyJson -ContentType "application/json"

        # Get updated approval group name
        $updatedEnv = $updatedDefinition.environments | Where-Object { $_.name -eq $targetEnvironmentName }
        $updatedApprovalGroup = $updatedEnv.postDeployApprovals.approvals[0].approver.displayName

        # Output ONLY what you want here
        $webUrl = "https://dev.azure.com/$organization/$project/_release?definitionId=$definitionId"

        Write-Host "✅ Pipeline: $($updatedDefinition.name)"
        Write-Host "   URL: $webUrl"
        Write-Host "   Approval Group: $updatedApprovalGroup"
        Write-Host ".................................................................................."
    }
    catch {
        Write-Error "❌ Failed to update pipeline '$definitionName' (ID: $definitionId): $_"
    }
}



