$ErrorActionPreference = 'Stop'

function Get-ApiErrorText {
    param($ErrorRecord)

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }

    return $ErrorRecord.Exception.Message
}

$tenantId = (Read-Host 'Entra tenant ID').Trim()
$clientId = (Read-Host 'Service principal client ID').Trim()
$workspaceId = (Read-Host 'DEV workspace ID').Trim()
$secureSpSecret = Read-Host 'Entra client secret' -AsSecureString
$spSecret = [System.Net.NetworkCredential]::new('', $secureSpSecret).Password
$githubPat = $null
$tokenResponse = $null
$headers = $null

try {
    if ([string]::IsNullOrWhiteSpace($tenantId) -or
        [string]::IsNullOrWhiteSpace($clientId) -or
        [string]::IsNullOrWhiteSpace($workspaceId) -or
        [string]::IsNullOrWhiteSpace($spSecret)) {
        throw 'Tenant ID, client ID, workspace ID, and client secret are all required.'
    }

    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
            -Method Post `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                client_id     = $clientId
                client_secret = $spSecret
                scope         = 'https://api.fabric.microsoft.com/.default'
                grant_type    = 'client_credentials'
            }
    }
    catch {
        throw "Entra token request failed: $(Get-ApiErrorText $_)"
    }

    if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
        throw 'Entra returned no access token.'
    }

    $headers = @{ Authorization = "Bearer $($tokenResponse.access_token)" }

    try {
        $connections = Invoke-RestMethod `
            -Uri 'https://api.fabric.microsoft.com/v1/connections' `
            -Headers $headers
    }
    catch {
        throw "Could not list Fabric connections: $(Get-ApiErrorText $_)"
    }

    $githubConnections = @($connections.value | Where-Object {
        $_.connectionDetails.type -eq 'GitHubSourceControl'
    })

    if ($githubConnections.Count -gt 0) {
        Write-Host 'GitHub connections available to this service principal:'
        $githubConnections |
            Select-Object displayName, id, @{Name = 'Repository'; Expression = { $_.connectionDetails.path }} |
            Format-Table -AutoSize
        $connectionId = (Read-Host 'Enter the connection ID to use').Trim()
    }
    else {
        Write-Host 'No GitHub source-control connection is available to this service principal.'
        $securePat = Read-Host 'GitHub fine-grained PAT for ravidyarev/gittest' -AsSecureString
        $githubPat = [System.Net.NetworkCredential]::new('', $securePat).Password

        $connectionBody = @{
            connectivityType = 'ShareableCloud'
            displayName = 'gittest GitHub source control'
            connectionDetails = @{
                type = 'GitHubSourceControl'
                creationMethod = 'GitHubSourceControl.Contents'
                parameters = @(
                    @{
                        dataType = 'Text'
                        name = 'url'
                        value = 'https://github.com/ravidyarev/gittest'
                    }
                )
            }
            credentialDetails = @{
                credentials = @{
                    credentialType = 'Key'
                    key = $githubPat
                }
            }
        }

        try {
            $connection = Invoke-RestMethod `
                -Uri 'https://api.fabric.microsoft.com/v1/connections' `
                -Method Post `
                -Headers $headers `
                -ContentType 'application/json' `
                -Body ($connectionBody | ConvertTo-Json -Depth 10)
        }
        catch {
            throw "Could not create the Fabric GitHub connection: $(Get-ApiErrorText $_)"
        }

        $connectionId = $connection.id
        Write-Host "Created connection ID: $connectionId"
    }

    if ([string]::IsNullOrWhiteSpace($connectionId)) {
        throw 'A connection ID is required.'
    }

    $gitCredentialsBody = @{
        source = 'ConfiguredConnection'
        connectionId = $connectionId
    } | ConvertTo-Json

    try {
        $configured = Invoke-RestMethod `
            -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/myGitCredentials" `
            -Method Patch `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body $gitCredentialsBody
    }
    catch {
        throw "Could not assign the GitHub connection to the DEV workspace: $(Get-ApiErrorText $_)"
    }

    Write-Host "Git credential source set to: $($configured.source)"

    $verified = Invoke-RestMethod `
        -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/myGitCredentials" `
        -Headers $headers

    Write-Host "Verified Git credential source: $($verified.source)"
    Write-Host "Verified connection ID: $($verified.connectionId)"
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Remove-Variable spSecret, githubPat, tokenResponse, headers -ErrorAction SilentlyContinue
}