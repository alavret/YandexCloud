# Скрипт для удаления федеративных пользователей их Яндекс Облака 
# Исходный список пользователей берется из Active Directory по LDAP фильтру
# !!! Если в скрипте при вызовах командной консоли yc возникают ошибки, скрипт логирует только факт ошибки. 
# Подробную информацию об ошибке yc нужно получать, вызывая yc отдельно от скрипта !!!

Import-Module ActiveDirectory

# Federation ID
$FED_ID = "xxxxxx"
# LDAP фильтр, по которому загружаются пользователи из AD
$LDAP_FILTER = "(memberOf=CN=YC_Users,OU=Groups,OU=Office,DC=contoso,DC=com)"
# LDAP Base Search (как правило, нужно для работы LDAP фильтра)
$SEARCH_BASE = "DC=yandry,DC=ru"
# Атрибут в AD, который в SAML Response использвается как NameID
$YC_LOGIN_PROP = "userPrincipalName"
# Режим тестового прогона (без удаления пользователей), если $True
$dry_run = $True
# Дублировать вывод диагностики в консоль
$output_log_to_console = $True
# Файл лога (каждый день формируется новый лог)
$Logfile = "C:\Windows\temp\yc_remove_users_" + (Get-Date -f yyyy-MM-dd) + ".log"

function WriteLog
{
    Param ([string]$LogString)

    $Stamp = (Get-Date).toString("yyyy-MM-dd HH:mm:ss")
    $LogMessage = "$Stamp $LogString"
    Add-content $LogFile -value $LogMessage
    if ($output_log_to_console) {
        Write-Output $LogMessage
    }
}

WriteLog "--------------------------------------------------------"
WriteLog "INIT Script running..."
WriteLog "INIT Federation ID - $FED_ID"
WriteLog "INIT Current user - $env:username"
WriteLog "INIT LDAP Filter - $LDAP_FILTER"
WriteLog "INIT AD Attribute, used fro NAMEID - $YC_LOGIN_PROP"
WriteLog "INIT Dry run - $dry_run"


# Вызов yc для выгрузки в переменную-массив списка логинов федеративных пользователей и их ID
[array] $yc_users = yc organization-manager federation saml list-user-accounts --id $FED_ID --jq ".[] | [.id, .saml_user_account.name_id] | @csv" 2>&1
if ($LASTEXITCODE -ne 0) {    
    WriteLog "ERROR Error during execution of 'yc organization-manager federation saml list-user-accounts'. Exit"
    throw "Exception caught ('yc organization-manager federation saml list-user-accounts')."
    Break Script
}


if ($yc_users.Length -eq 0) {
    WriteLog "INFO No users found for fedderation in yc organization. Exit"
    Break Script
}

# Создание из списка федеративных пользователей словаря
$yc_dict = @{}
ForEach ($item in $yc_users) {
    $yc_dict[$item.split(",")[1].Replace("`"","")] = $item.split(",")[0].Replace("`"","")
}

# Выгрузка из AD списка "активных" пользователей и получение значения атрибута-логина
$ad_users = (Get-ADUser -LDAPFilter $LDAP_FILTER -SearchBase $SEARCH_BASE -Properties *).$YC_LOGIN_PROP

# Создание HashSet из обоих списков
$yc_hs = [Collections.Generic.HashSet[string]]::new([String[]]$yc_dict.Keys)
$ad_hs = [Collections.Generic.HashSet[string]]::new([String[]]$ad_users)

# Дублирование HashSet для пользователей YC c целью дальнейшей модификации этого списка
$RemovedUsers = [Collections.Generic.HashSet[string]]::new($yc_hs, $yc_hs.Comparer)
# Поиск в списке федеративных пользователей Облака тех, кто отсутствует в списке пользователей AD
$RemovedUsers.ExceptWith($ad_hs)

if ($RemovedUsers.Count -eq 0) {
    WriteLog "INFO No users to delete. Exit"
    Break Script
}

# Если тестовый прогон, показать командную строку для удаления каждого пользователя
if ($dry_run) {
    ForEach ($item in $RemovedUsers) { 
        WriteLog "INFO Delete __ $item __ user. Command line:"
        WriteLog "INFO yc organization-manager federation saml delete-user-accounts --id $FED_ID --subject-ids $($yc_dict[$item])"
    }
    WriteLog "INFO End running script."
    Break Script
}

# Удаление каждого пользователя по отдельности (технически можно сгруппировать пользователей и удалить одним вызовом)
ForEach ($item in $RemovedUsers) {
    WriteLog "INFO Delete __ $item __ user. Command line:"
    WriteLog "INFO yc organization-manager federation saml delete-user-accounts --id $FED_ID --subject-ids $($yc_dict[$item])"
    $result = yc organization-manager federation saml delete-user-accounts --id $FED_ID --subject-ids $yc_dict[$item] 2>&1
    if ($LASTEXITCODE -ne 0) {  
        WriteLog "ERROR Error during execution 'yc organization-manager federation saml delete-user-accounts' for $item' user."
    }
}

# Проверка факта удаления запрошенных пользователей
WriteLog "INFO Check deletion state."
WriteLog "INFO Start sleep 3 seconds."
# На всякий случай делаем паузу после выполнения последней команды удаления пользователя
Start-Sleep -Seconds 3
[array] $check_users = yc organization-manager federation saml list-user-accounts --id $FED_ID --jq ".[] | [.id, .saml_user_account.name_id] | @csv" 2>&1
if ($LASTEXITCODE -ne 0) {    
    WriteLog "ERROR Error during execution of 'yc organization-manager federation saml list-user-accounts'. Check failed. Exit"    
    Break Script
}

$check_hs = [Collections.Generic.HashSet[string]]::new([String[]]$check_users)
$Orig_RemovedUsers = [Collections.Generic.HashSet[string]]::new($RemovedUsers, $RemovedUsers.Comparer)
$Orig_RemovedUsers.IntersectWith($check_hs)
if ( $Orig_RemovedUsers.Count -eq 0 ) {
    WriteLog "INFO Successfully deleted $($RemovedUsers.Count) users. Exit."
    Break Script
}
ForEach ($item in $Orig_RemovedUsers) {
    WriteLog "WARNING Script couldn't delete __ $item __ user."
}
WriteLog "INFO Exit."
Break Script


 
