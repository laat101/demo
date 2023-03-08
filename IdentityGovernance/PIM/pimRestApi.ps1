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
#endregion

#region get Azure Subscription
$subDisplayName = $Env:subscriptionName
[uri]$Uri = 'https://management.azure.com/subscriptions?api-version=2020-01-01'
$results = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $SecureTokenAzure -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
$id = ($results.value | where-object { $_.displayName -eq $subDisplayName }).id
#endregion

#region register a governance resouce (subscription)
$values = @()
[uri]$Uri = "https://graph.microsoft.com/beta/privilegedAccess/azureResources/resources/"
$result = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $secureTokenGraph -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
$values += $result.value
while ($result.'@odata.nextLink') {
    [uri]$Uri = $result.'@odata.nextLink'
    $result = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $secureTokenGraph -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
    $values += $result.value
}
$pimobj = ($values | Where-Object { $_.type -eq "subscription" -or $_.type -eq "managementgroup" -and $_.externalId -eq $id })

if ($pimobj) {
    write-verbose -Message "PIM Object Found, PIM id: $($pimobj)"
}
else {
    # Register Subscription or Management Group
    $Body = '{"externalId": "{0}"}' -f $id
    [uri]$Uri = "https://graph.microsoft.com/beta/privilegedAccess/azureResources/resources/register"
    $result = Invoke-RestMethod -Method Post -Body $Body -Uri $Uri -Authentication Bearer -Token $secureTokenGraph -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
}
#endregion

#region get roledefenitions

$roleName = "Backup Reader"
[uri]$Uri = "https://graph.microsoft.com/beta/privilegedAccess/azureResources/resources/{0}/roleDefinitions" -f $pimobj.id
$results = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $secureTokenGraph -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
$roleDefinitions = $results.value

# $roleDefinitions | Sort-Object displayName | ft displayName

$roleDefinitionId = ($roleDefinitions | where-object { $_.displayName -eq $roleName }).id
#endregion

#region get PIM role configuration
$resourceId = $pimobj.id
$values = @()
[uri]$Uri = "https://graph.microsoft.com/beta/privilegedAccess/azureResources/roleSettings?`$filter=(resource/id+eq+%27$resourceId%27)&`$orderby=lastUpdatedDateTime+desc"
$result = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $secureTokenGraph -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
$values += $result.value
while ($result.'@odata.nextLink') {
    [uri]$Uri = $result.'@odata.nextLink'
    $result = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $secureTokenGraph -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
    $values += $result.value
}

# $values | Where-Object{$_.isDefault -eq $false}

$PIMrolesetting = $values | where-object { $_.roleDefinitionId -eq $roleDefinitionId }
#endregion

#region configure PIM Role
$Groupname = "EM4S-DEMO-Contributor"
[uri]$Uri = "https://graph.microsoft.com/beta/groups?`$filter=(displayName eq '$($Groupname)')&`$count=true"
$results = Invoke-RestMethod -Method Get -Uri $Uri -Headers $graphHeaders -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1
$AadObject = $results.value[0]

$approvers = @(@{
        "id"          = $AadObject.id
        "description" = $Groupname
        "isBackup"    = $false
        "userType"    = "Group"
    })

$body = @'
{
    "properties": {
        "rules": [
            {
                "isExpirationRequired": false,
                "maximumDuration": "P365D",
                "id": "Expiration_Admin_Eligibility",
                "ruleType": "RoleManagementPolicyExpirationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Eligibility"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Admin",
                "isDefaultRecipientsEnabled": false,
                "notificationLevel": "All",
                "id": "Notification_Admin_Admin_Eligibility",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Eligibility"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Requestor",
                "isDefaultRecipientsEnabled": true,
                "notificationLevel": "All",
                "id": "Notification_Requestor_Admin_Eligibility",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Eligibility"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Approver",
                "isDefaultRecipientsEnabled": true,
                "notificationLevel": "All",
                "id": "Notification_Approver_Admin_Eligibility",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Eligibility"
                }
            },
            {
                "enabledRules": [],
                "id": "Enablement_Admin_Eligibility",
                "ruleType": "RoleManagementPolicyEnablementRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Eligibility"
                }
            },
            {
                "isExpirationRequired": false,
                "maximumDuration": "P180D",
                "id": "Expiration_Admin_Assignment",
                "ruleType": "RoleManagementPolicyExpirationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "enabledRules": [
                    "MultiFactorAuthentication",
                    "Justification"
                ],
                "id": "Enablement_Admin_Assignment",
                "ruleType": "RoleManagementPolicyEnablementRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Admin",
                "isDefaultRecipientsEnabled": false,
                "notificationLevel": "All",
                "id": "Notification_Admin_Admin_Assignment",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Requestor",
                "isDefaultRecipientsEnabled": true,
                "notificationLevel": "All",
                "id": "Notification_Requestor_Admin_Assignment",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Approver",
                "isDefaultRecipientsEnabled": true,
                "notificationLevel": "All",
                "id": "Notification_Approver_Admin_Assignment",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "Admin",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "isExpirationRequired": false,
                "maximumDuration": "PT12H",
                "id": "Expiration_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyExpirationRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "enabledRules": [
                    "MultiFactorAuthentication",
                    "Justification",
                    "Ticketing"
                ],
                "id": "Enablement_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyEnablementRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "setting": {
                    "isApprovalRequired": true,
                    "isApprovalRequiredForExtension": false,
                    "isRequestorJustificationRequired": true,
                    "approvalMode": "SingleStage",
                    "approvalStages": [
                        {
                            "approvalStageTimeOutInDays": 1,
                            "isApproverJustificationRequired": true,
                            "escalationTimeInMinutes": 0,
                            "primaryApprovers": <-approvers->,
                            "isEscalationEnabled": false
                        }
                    ]
                },
                "id": "Approval_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyApprovalRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "isEnabled": false,
                "claimValue": "",
                "id": "AuthenticationContext_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyAuthenticationContextRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Admin",
                "isDefaultRecipientsEnabled": false,
                "notificationLevel": "All",
                "id": "Notification_Admin_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Requestor",
                "isDefaultRecipientsEnabled": true,
                "notificationLevel": "All",
                "id": "Notification_Requestor_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            },
            {
                "notificationType": "Email",
                "recipientType": "Approver",
                "isDefaultRecipientsEnabled": true,
                "notificationLevel": "All",
                "id": "Notification_Approver_EndUser_Assignment",
                "ruleType": "RoleManagementPolicyNotificationRule",
                "target": {
                    "caller": "EndUser",
                    "operations": [
                        "All"
                    ],
                    "level": "Assignment"
                }
            }
        ]
    }
}
'@.Replace("<-approvers->", ($approvers | ConvertTo-Json -Depth 100 -AsArray))

$headers = @{
    'Content-Type' = 'application/json'
}
[uri]$Uri = "https://management.azure.com$id/providers/Microsoft.Authorization/roleManagementPolicies/$($PIMrolesetting.roleDefinitionId)?api-version=2020-10-01"
$result = Invoke-RestMethod -Method Patch -Headers $headers -body $body -Uri $Uri -Authentication Bearer -Token $secureTokenAzure
#endregion

#region PIM assignment
[uri]$Uri = "https://management.azure.com$id/providers/Microsoft.Authorization/roleEligibilityScheduleRequests?api-version=2020-10-01"
$results = Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $SecureTokenAzure -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1

$datenow = [datetime]::now.ToUniversalTime()
$startdate = $datenow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$enddate = $datenow.AddMonths(12).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$roleDefinitionIdLong = "$id/providers/Microsoft.Authorization/roleDefinitions/$roleDefinitionId"
$guid = ([guid]::NewGuid()).Guid
$json = @'
{
    "properties": {
        "principalId": "<SUBJECTID>",
        "roleDefinitionId": "<ROLEDEFINITIONID>",
        "requestType": "AdminAssign",
        "scheduleInfo": {
            "startDateTime": "<STARTDATE>",
            "expiration": {
              "type": "AfterDuration",
              "endDateTime": null,
              "duration": null
            }
        },
        "condition": null,
        "conditionVersion": null
    }
}
'@.Replace('<RESOURCEID>', $ResourceId).Replace('<ROLEDEFINITIONID>', $roleDefinitionIdLong).Replace('<SUBJECTID>', $AadObject.id).Replace('<STARTDATE>', $startdate).Replace('<ENDDATE>', $enddate)
[uri]$Uri = "https://management.azure.com$id/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$($guid)?api-version=2020-10-01"
$results = Invoke-RestMethod -Method Put -Uri $Uri -body $json -Authentication Bearer -Token $SecureTokenAzure -ErrorAction Stop -RetryIntervalSec 1 -MaximumRetryCount 1 -ContentType "application/json"
#endregion