#region Access Tokens
import-module C:\repos\demo\General\Get-restapiAccessToken.ps1
$tokenGraph = Get-restapiAccessToken -tokenType MSGraph -existingToken $tokenGraph
$secureTokenGraph = ConvertTo-SecureString -String $tokenGraph -AsPlainText -Force

$tokenAzure = Get-restapiAccessToken -tokenType Azure -existingToken $tokenAzure
$secureTokenAzure = ConvertTo-SecureString -String $tokenAzure -AsPlainText -Force

$graphHeaders = @{
    "Authorization" = "Bearer $tokenGraph"
    "Content-Type"  = "application/json"
}

$azureHeaders = @{
    "Authorization" = "Bearer $tokenAzure"
    "Content-Type"  = "application/json"
}
#endregion

#region Get Catalogs @REST
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs'
$restResults = (Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders).value
$restResults
#endregion

#region Create Catalog @REST
$CatalogName = "DEMO-AzureMeetup-REST"
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs?$filter=displayName eq ''{0}''' -f $CatalogName
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders

if ($results.value[0].displayName -ne $CatalogName) {
    Write-Host -ForegroundColor green "Creating Entitlement Management catalog: $CatalogName"
    [uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs'
    [hashtable]$Body = @{
        DisplayName         = $CatalogName
        Description         = "This is my Demo catalog"
        IsExternallyVisible = $false
    }
    $jsonBody = $Body | ConvertTo-Json -Depth 100
    $result = Invoke-RestMethod -Method Post -Uri $Uri -Body $Body -Token $secureTokenGraph -Authentication Bearer
}
else {
    Write-Host -ForegroundColor blue "Catalog already there: $CatalogName"
}
#endregion

#region Add Owner to catalog @REST
# Get Catalog
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs?$filter=displayName eq ''{0}''' -f $CatalogName
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$catalog = $results.value[0]

# Get Catalog role assignments
[uri]$Uri = 'https://graph.microsoft.com/beta/roleManagement/entitlementManagement/roleAssignments?$filter=appScopeId eq ''/AccessPackageCatalog/{0}''' -f $catalog.Id
$result = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$ExistingRoleAssignment = $result.value
$ExistingRoleAssignment

# Entitlement Management roles
$CatalogRoleId = "ae79f266-94d4-4dab-b730-feca7e132178" # Owner
$CatalogRoleId = "44272f93-9762-48e8-af59-1b5351b1d6b3" # Reader
$CatalogRoleId = "7f480852-ebdc-47d4-87de-0d8498384a83" # Access Package Manager
$CatalogRoleId = "e2182095-804a-4656-ae11-64734e9b7ae5" # Access Package Assignment Manager

[hashtable]$Body = @{
    principalId      = $Env:MyObjectId
    roleDefinitionId = $CatalogRoleId
    appScopeId       = "/AccessPackageCatalog/{0}" -f $catalog.id
}

$jsonBody = ConvertTo-Json -InputObject $Body -Depth 100
[uri]$Uri = 'https://graph.microsoft.com/beta/roleManagement/entitlementManagement/roleAssignments'
$result = Invoke-RestMethod -Method Post -Uri $Uri -Body $jsonBody -Headers $graphHeaders
$result
#endregion

#region create group in Azure Active Directory
$Groupnames = @("EM4S-DEMO-Contributor", "EM4S-DEMO-Reviewers")
foreach ($GroupName in $Groupnames) {
    $Owners = @("https://graph.microsoft.com/v1.0/servicePrincipals/$Env:SpnObjectId")
    $Body = @{
        description         = "This group is for the Dutch Azure Meetup demo."
        displayName         = $GroupName
        mailNickname        = $Groupname
        mailEnabled         = $false
        securityEnabled     = $true
        "owners@odata.bind" = $owners
        isAssignableToRole  = $false
    }
    $jsonBody = $Body | ConvertTo-Json -Depth 100

    # Check if group exists
    [uri]$Uri = 'https://graph.microsoft.com/v1.0/groups?$filter=startswith(displayName,''{0}'')' -f $Groupname
    $results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
    if ($results.value[0].displayName -eq $Groupname) {
        write-host "Group exists"
    }
    else {
        [uri]$Uri = "https://graph.microsoft.com/v1.0/groups"
        $results = Invoke-RestMethod -Method Post -Body $jsonBody -Uri $Uri -Headers $graphHeaders
    }
}

# Add member to reviewers group
$Groupname = "EM4S-DEMO-Reviewers"
[uri]$Uri = 'https://graph.microsoft.com/v1.0/groups?$filter=startswith(displayName,''{0}'')' -f $Groupname
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$Group = $results.value

$jsonBody = @'
{
    "members@odata.bind": [
      "https://graph.microsoft.com/v1.0/directoryObjects/<-id->"
      ]
}
'@.Replace('<-id->', $Env:MyObjectId)
[uri]$Uri = "https://graph.microsoft.com/v1.0/groups/{0}" -f $Group.id
$results = Invoke-RestMethod -Method Patch -Uri $Uri -Body $jsonBody -Headers $graphHeaders





#endregion

#region Add Resource to Catalog
# get Catalog
$CatalogName = "DEMO-AzureMeetup-REST"
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs?$filter=displayName eq ''{0}''' -f $CatalogName
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$Catalog = $results.value[0]

# get Group
$Groupname = "EM4S-DEMO-Contributor"
[uri]$Uri = 'https://graph.microsoft.com/v1.0/groups?$filter=startswith(displayName,''{0}'')' -f $Groupname
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$Group = $results.value

[hashtable]$AccessPackageResource = @{
    displayName  = $Group.displayName
    description  = $Group.description
    resourceType = 'AadGroup'
    originId     = $Group.Id
    originSystem = 'AadGroup'
}

[hashtable]$Body = @{
    catalogId             = $Catalog.id
    requestType           = 'AdminAdd'
    justification         = ''
    accessPackageResource = $AccessPackageResource
}

[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageResourceRequests'
$BodyJson = ConvertTo-Json -InputObject $Body -Depth 100
$results = Invoke-RestMethod -Method Post -Uri $Uri -Body $BodyJson -Headers $graphHeaders
#endregion

#region Create Access Package
$CatalogName = "DEMO-AzureMeetup-REST"
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs?$filter=displayName eq ''{0}''' -f $CatalogName
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$Catalog = $results.value[0]
$AccessPackageName = "Dutch Azure Meetup Access Package"
[hashtable]$Body = @{
    catalogId   = $Catalog.id
    displayName = $AccessPackageName
    description = "This is a Access Package is for the Dutch Azure Meetup demo."
}

$BodyJson = ConvertTo-Json -InputObject $Body -Depth 100
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages'
$results = Invoke-RestMethod -Method Post -Uri $Uri -Body $BodyJson -Headers $graphHeaders
$AccessPackage = $results
#endregion

#region Catalog resource to the Access Package
# Get Catalog resources
$Groupname = "EM4S-DEMO-Contributor"
[uri]$Uri = "https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs/{0}/accessPackageResources" -f $catalog.id
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders

$EmResource = $results.value | Where-Object { $_.displayName -eq $Groupname }
$EmResource

[hashtable]$AccessPackageResource = @{
    id           = $EmResource.id
    resourceType = $EmResource.resourceType
    originId     = $EmResource.originId
    originSystem = $EmResource.originSystem
}

[hashtable]$Body = @{
    accessPackageResourceRole  = @{
        originId              = "Member_$($EmResource.originId)"
        displayName           = 'Member'
        originSystem          = $EmResource.originSystem
        accessPackageResource = $AccessPackageResource
    }
    accessPackageResourceScope = @{
        originId     = $EmResource.originId
        originSystem = $EmResource.originSystem
    }
}
$jsonBody = ConvertTo-Json -InputObject $Body -Depth 100
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages/{0}/accessPackageResourceRoleScopes' -f $AccessPackage.id
$results = Invoke-RestMethod -Method Post -Uri $Uri -Body $jsonBody -Headers $graphHeaders
$results
#endregion

#region Add Access Package Policy
# get Access Package
$AccessPackageName = "Dutch Azure Meetup Access Package"
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages?$filter=displayName eq ''{0}''' -f $AccessPackageName 
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$AccessPackage = $results.value

# get Group
$Groupname = "EM4S-DEMO-Reviewer"
[uri]$Uri = 'https://graph.microsoft.com/v1.0/groups?$filter=startswith(displayName,''{0}'')' -f $Groupname
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$ReviewersGroup = $results.value

# Body

[array]$Reviewers = @{
    '@odata.type' = '#microsoft.graph.groupMembers'
    isBackup      = $false
    id            = $ReviewersGroup.Id
    description   = $ReviewersGroup.DisplayName
}

$AccessReviewSettings = [ordered]@{
    isEnabled                       = $true
    recurrenceType                  = 'quarterly'
    reviewerType                    = 'Reviewers'
    startDateTime                   = (get-date).AddDays(1)
    durationInDays                  = 16
    reviewers                       = $Reviewers
    isAccessRecommendationEnabled   = $true
    isApprovalJustificationRequired = $false
    accessReviewTimeoutBehavior     = 'removeAccess'
}

$RequestorSettings = [ordered]@{
    scopeType         = 'AllExistingDirectoryMemberUsers'
    acceptRequests    = $true
    allowedRequestors = @()
}

[array]$ApprovalStages = @(
    [ordered]@{
        approvalStageTimeOutInDays      = 7
        isApproverJustificationRequired = $false
        isEscalationEnabled             = $false
        escalationTimeInMinutes         = 0
        primaryApprovers                = $Reviewers
        escalationApprovers             = @()
    }
)

$RequestApprovalSettings = [ordered]@{
    isApprovalRequired               = $true
    isApprovalRequiredForExtension   = $true
    isRequestorJustificationRequired = $true
    approvalMode                     = 'SingleStage'
    approvalStages                   = $ApprovalStages
}

$AssignmentPolicy = [ordered]@{
    accessPackageId         = $AccessPackage.id
    displayName             = "DemoPolicy"
    description             = "This is a demo policy"
    accessReviewSettings    = $AccessReviewSettings
    canExtend               = $true
    expiration              = @{type = "noExpiration" }
    durationInDays          = $AssignmentDuration
    expirationDateTime      = $null
    requestorSettings       = $RequestorSettings
    requestApprovalSettings = $RequestApprovalSettings
}

$jsonBody = $AssignmentPolicy | ConvertTo-Json -Depth 100
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageAssignmentPolicies'
$results = Invoke-RestMethod -Method Post -Uri $Uri -Body $jsonBody -Headers $graphHeaders

#endregion

#region Create Hyperlink
# get Access Package
$AccessPackageName = "Dutch Azure Meetup Access Package"
[uri]$Uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages?$filter=displayName eq ''{0}''' -f $AccessPackageName 
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders
$AccessPackage = $results.value

$url  = 'https://myaccess.microsoft.com/{0}#/access-packages/{1}' -f $Env:domainname, $AccessPackage.Id
$url | Set-Clipboard
#endregion

#region CleanUp
# Group Cleanup
$Groupname = "EM4S-DEMO-Contributor"
[uri]$Uri = 'https://graph.microsoft.com/v1.0/groups?$filter=startswith(displayName,''{0}'')' -f $Groupname
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders

[uri]$Uri = 'https://graph.microsoft.com/v1.0/groups/{0}' -f $results.value[0].id
Invoke-RestMethod -Method Delete -Uri $Uri -Headers $graphHeaders
#endregion

#region Usefull links
"https://github.com/MicrosoftDocs/azure-docs/tree/main/articles/active-directory/governance"
"https://identity-man.eu/"
#endregion