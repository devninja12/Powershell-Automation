$organization = "amtesudevops"
$project = @("", "")
$targetEnvironments = @("", "")
$pat = "3mVwcORrXgphnmZVOg3XZETU6F0epBoPLqAHRgi0FyijKMvuhx5FJQQJ99BFACAAAAAAAAAAAAASAZDO3Nxh"

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

# === Get all release definitions ===
$definitionsUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions?api-version=6.1-preview.4"
$definitionsResponse = Invoke-RestMethod -Uri $definitionsUrl -Headers $headers
$allDefinitions = $definitionsResponse.value

foreach ($definitionSummary in $allDefinitions) {
    $definitionId = $definitionSummary.id
    $definitionName = $definitionSummary.name
    $definitionUrl = "https://vsrm.dev.azure.com/$organization/$project/_apis/release/definitions/$($definitionId)?api-version=6.1-preview.4"

        try {
                $response.environments | ForEach-Object {
                    Write-Output "Environment: $($_.name)"
                    $_.preDeployApprovals.approvals | ForEach-Object {
                        Write-Output "  Approver: $($_.approver.displayName) ($($_.approver.id))"
                    }
                }
        }
}

