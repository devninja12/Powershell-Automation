$organization = "amtesudevops"
$project = "codetolab"
$pat = "5XNyyFjN5FhX377vQhu1A8Ax8sKtQ9vK4FzBAmjgGXlrtGoL7VT3JQQJ99BEACAAAAAAAAAAAAASAZDO2RFr"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

# === Auth Header ===
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

# === Step 1: List all release definitions ===
$definitionsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?api-version=6.1-preview.4"

try {
    $definitionsResponse = Invoke-RestMethod -Uri $definitionsUrl -Headers @{ Authorization = "Basic $base64AuthInfo" } -Method Get

    Write-Host "`n--- Release Pipelines in Project '$project' ---`n"

    foreach ($definition in $definitionsResponse.value) {
        Write-Host "ID:   $($definition.id)"
        Write-Host "Name: $($definition.name)"
        Write-Host "Path: $($definition.path)"
        Write-Host "----------------------------------"
    }

} catch {
    Write-Error "Failed to list release definitions. Check your PAT, organization, or project name."
    exit
}

# === Step 2: For each definition, get details and check for stage "ade" ===


Write-Host "`n--- Pipelines with stage 'test' ---`n"
foreach ($definition in $definitionsResponse.value) {
    $definitionId = $definition.id
    $definitionName = $definition.name
    $definitionDetailsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definition.id)?api-version=6.1-preview.4"

    try {
        $definitionDetails = Invoke-RestMethod -Uri $definitionDetailsUrl -Headers @{ Authorization = "Basic $base64AuthInfo" } -Method Get
    } catch {
        Write-Error "❌ Error retrieving definition details for pipeline ID $definitionId. $_"
        continue
    }

    try {
        $adeStage = $definitionDetails.environments | Where-Object { $_.name -eq "ade" }
    } catch {
        Write-Error "❌ Error locating 'test' stage in pipeline $definitionName. $_"
        continue
    }

    if ($adeStage) {
        Write-Host "Pipeline Name: $definitionName"
        Write-Host "Pipeline ID:   $definitionId"
        Write-Host "Stage Found:   ade"

        try {
            $preApprovals = $adeStage.preDeployApprovals.approvals
            if ($preApprovals -and $preApprovals.Count -gt 0) {
                Write-Host "Pre-Deployment Approvals:"
                foreach ($approval in $preApprovals) {
                    $approverName = $approval.approver.displayName
                    $approvalId = $approval.id
                    Write-Host " - Approval ID: $approvalId, Approver: $approverName"
                }
            } else {
                Write-Host "No pre-deployment approvals found for stage 'ade'."
            }
        } catch {
            Write-Error "❌ Error accessing pre-deployment approvals for '$definitionName'. $_"
            continue
        }

        try {
            $postApprovals = $adeStage.postDeployApprovals.approvals
            Write-Host "`n[DEBUG] postDeployApprovals object:"
            Write-Host "postDeployApprovals type: $($adeStage.postDeployApprovals.GetType().Name)"
            Write-Host "postDeployApprovals.approvals type: $($postApprovals.GetType().Name)"
            Write-Host "postDeployApprovals.approvals count: $($postApprovals.Count)"

            Write-Host "`n[DEBUG] postDeployApprovals.approvals content:"
            $postApprovals | ForEach-Object {
                $approverName = if ($_.approver) { $_.approver.displayName } else { "None" }
                Write-Host " - ID: $($_.id), Approver: $approverName, Type: $($_.approvalType)"
            }

            $hasValidApprovers = $postApprovals | Where-Object { $_.approver -and $_.approver.displayName }

            if ($hasValidApprovers) {
                Write-Host "Rebuilding post-approval objects..."

                # Rebuild post-approvals from pre-approvals
                $newPostApprovals = @()
                for ($j = 0; $j -lt $preApprovals.Count; $j++) {
                    try {
                        $preApproval = $preApprovals[$j]
                        $newApproval = [PSCustomObject]@{
                            rank         = $preApproval.rank
                            approver     = $preApproval.approver
                            approvalType = $preApproval.approvalType
                            isAutomated  = $preApproval.isAutomated
                        }
                        $newPostApprovals += $newApproval
                        Write-Host " → Created new post-approval from pre-approval: $($preApproval.approver.displayName)"
                    } catch {
                        Write-Error "❌ Failed to clone pre-approval at index $j. $_"
                    }
                }

                # Replace entire postDeployApprovals object
                $adeStage.postDeployApprovals = [PSCustomObject]@{
                    approvals     = $newPostApprovals
                    approvalType  = $adeStage.preDeployApprovals.approvalType
                    isAutomated   = $adeStage.preDeployApprovals.isAutomated
                }


                # Update the environment in the definition
                try {
                    for ($i = 0; $i -lt $definitionDetails.environments.Count; $i++) {
                        if ($definitionDetails.environments[$i].id -eq $adeStage.id) {
                            $definitionDetails.environments[$i] = $adeStage
                            break
                        }
                    }
                } catch {
                    Write-Error "❌ Error replacing environment in release definition. $_"
                    continue
                }

                # Serialize and send update
                try {
                    $body = $definitionDetails | ConvertTo-Json -Depth 100
                } catch {
                    Write-Error "❌ Failed to convert release definition to JSON. $_"
                    continue
                }

                $updateUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definition.id)?api-version=6.1-preview.4"
                try {
                    Invoke-RestMethod -Uri $updateUrl -Headers @{
                        Authorization = "Basic $base64AuthInfo"
                        "Content-Type" = "application/json"
                    } -Method Put -Body $body
                    Write-Host "✅ Post-deployment approvals updated successfully for pipeline ID $($definition.id)."
                } catch {
                    Write-Error "❌ Failed to PUT updated release definition. $_"
                }
            } else {
                Write-Host "Post-deployment approvals not enabled."
            }
        } catch {
            Write-Error "❌ Error processing post-deployment approvals. $_"
        }

        Write-Host "--------------------------------------"
    }
}