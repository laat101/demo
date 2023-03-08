function Get-restapiAccessToken {
    param(
        $existingToken,
        [Parameter(Mandatory = $true)]
        [validateset('Azure', 'MSGraph', 'KeyVault')]
        [string]$tokenType
    )
    
    switch ($tokentype) {
        "Azure" {
            $existingToken = $global:TokenAzure
        }
        "MSGraph" {
            $existingToken = $global:TokenMsGraph
        }
        Default {}
    }
    
    if ($existingToken) {
        # Check token age
        $maxAge = 5 # minutes
        $secondstoadd = $existingToken.expires_in - ($maxAge * 60)
        $comparison = ([math]::round((New-TimeSpan -Start (Get-Date -Date "01/01/1970") -End (Get-Date).ToUniversalTime().AddSeconds($secondstoadd)).TotalSeconds), 0)[0]
        if ($existingToken.expires_on -gt $comparison ) {
            return $existingToken.access_token
        }
    }
    
    switch ($tokentype) {
        "Azure" {
            $body = @{
                grant_type    = "client_credentials"
                client_id     = $Env:clientId
                client_secret = $Env:clientSecret
                resource      = "https://management.azure.com/"
            }
        }
        "MSGraph" {
            $body = @{
                grant_type    = "client_credentials"
                client_id     = $Env:clientId
                client_secret = $Env:clientSecret
                resource      = "https://graph.microsoft.com/"
            }
        }
        "KeyVault" {
            $body = @{
                grant_type    = "client_credentials"
                client_id     = $Env:clientId
                client_secret = $Env:clientSecret
                resource      = "https://vault.azure.net"
            }
        }
        Default {}
    }
        
    try {
        $url = "https://login.microsoftonline.com/{0}/oauth2/token" -f $Env:tenantid
        $request = Invoke-RestMethod -Method Post -Uri $url -Body $body
    }
    catch {
        throw "Unable to connect"
    }
    
    switch ($tokentype) {
        "Azure" {
            Set-Variable TokenAzure -Value $request -Scope global
        }
        "MSGraph" {
            Set-Variable TokenMsGraph -Value $request -Scope global
        }
        "KeyVault" {
            Set-Variable TokenKeyVault -Value $request -Scope global
        }
        Default {}
    }
    return $request.access_token
}