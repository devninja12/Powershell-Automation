# Define variables
$organizationName = "amtesudevops"
$personalAccessToken = "dmfw3kbwepi6wmzftn2j3mhdxn3nu33jt35apusj7j7eqvxdwonq"
$latestAgentVersion = "2.218.0"  # Replace with the latest agent version
$agentPackageUrl = "https://vstsagentpackage.azureedge.net/agent/2.218.0/vsts-agent-win-x64-2.218.0.zip"  # Example URL

# Base64 encode the PAT for authentication
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$personalAccessToken"))

# Define API endpoint for retrieving deployment pools
$deploymentPoolsUrl = "https://dev.azure.com/$organizationName/_apis/distributedtask/pools?poolType=deployment&api-version=6.0"

# Retrieve deployment pools
try {
    $deploymentPoolsResponse = Invoke-RestMethod -Uri $deploymentPoolsUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
} catch {
    Write-Host "Error retrieving deployment pools: $_"
    exit
}

# Check if we have results
if ($deploymentPoolsResponse.value.Count -eq 0) {
    Write-Host "No deployment pools found."
    exit
}

# Loop through each deployment pool and retrieve agent details
foreach ($pool in $deploymentPoolsResponse.value) {
    $agentsUrl = "https://dev.azure.com/$organizationName/_apis/distributedtask/pools/$($pool.id)/agents?api-version=6.0"

    try {
        $agentsResponse = Invoke-RestMethod -Uri $agentsUrl -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
    } catch {
        Write-Host "Error retrieving agents for pool $($pool.id): $_"
        continue
    }

    if ($agentsResponse.value.Count -gt 0) {
        Write-Host "Updating agents in Deployment Pool: $($pool.name)"
        foreach ($agent in $agentsResponse.value) {
            Write-Host "    Updating Agent: $($agent.name) (Current Version: $($agent.version))"
            # Note: You need to have a method to access each target machine and perform the update
            # Example:
            # Invoke-RestMethod -Uri "$agentUpdateUrl" -Method Post -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $updateBody
            # Alternatively, use PowerShell Remoting or other methods to install the updated agent package

            # Here, you should implement the logic to remotely update the agents, such as using WinRM, SSH, or other methods to run the installer on each agent machine.
        }
        Write-Host ""
    }
}

Write-Host "Script completed."
