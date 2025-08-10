$organization = ""
$pat = ""
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))

$groupUrl = "https://vssps.dev.azure.com/$organization/_apis/graph/groups?api-version=7.1-preview.1"

$response = Invoke-RestMethod -Uri $groupUrl -Headers @{Authorization = "Basic $base64AuthInfo"}

$response.value | Select-Object principalName, displayName, descriptor | Format-Table -AutoSize
