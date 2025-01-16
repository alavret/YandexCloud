# Скрипт для удаления федеративной учётной записи из организации Яндекс Облака при её отключении/удалении из Active Directory
Скрипт использует утилиту командной строки `yc` для работы с федеративными пользователями Яндекс Облака.
Для выполнения операции удаления пользователя используется сервисная учётная запись с правами:
- `organization-manager.federations.userAdmin` - разрешение необходимо для удаления федеративного пользователя.
- `organization-manager.federations.viewer` - разрешение необходимо для листинга федеративных пользователей.
> [!NOTE]
> Для настройки работы скрипта с нуля требуются:
> - права на работу с сервисными учетками облака (создание, управление разрешениями).
> - права на работу с учетками Active Directory для запуска скрипта под выделенной учеткой.

## Реализация
### Устанавливаем `yc` ([справка](https://yandex.cloud/ru/docs/cli/operations/install-cli#windows_1)). 
> [!WARNING]
> Желательно для установки и настройки профиля `yc` выбрать работу не из `Powershell`, а из коммандной строки (`Command Prompt`).

Выполняем в коммандной строке:
```
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://storage.yandexcloud.net/yandexcloud-yc/install.ps1'))" && SET "PATH=%PATH%;%USERPROFILE%\yandex-cloud\bin"
```
Соглашаемся с добавлением в переменную среды `PATH` пути до утилиты.

### Создание первого профиля ([справка](https://yandex.cloud/ru/docs/cli/operations/authentication/user))
> [!NOTE] 
> Первый профиль будет временным и будет удален после настройки работы от имени сервисного эккаунта.

Запускаем настройку утилиты. В процессе настройки будет создан профиль для указанного пользователя Яндекс Облака. Необходимо выбрать пользователя, имеющего права на создание учётных записей и модификацию их прав на уровне организации.
> [!CAUTION] Шаги ниже для учетки в Яндекс Паспорте. Если вы выбрали настроку утилиты от имени федеративного эккаунта, используйте шаги в [этой](https://yandex.cloud/ru/docs/cli/operations/authentication/federated-user) инструкции.
- Получаем OAuth токен для указанного пользователя. Открываем страницу  https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb и аутентифицируемся от имени выбранного пользователя в Yandex Cloud. Сохраняем полученную строку-токен в буфере обмена.
Запускем
```
yc init
```
и следуем подсказкам для инициализации профиля.

> [!WARNING] 
> В процессе инициализации будут запрошенны параметры Cloud и Folder. Эти параметры влияют на размещение создаваемого сервисного эккаунта. Выбирайте их в соответствии с вашей политикой размещения таких объектов в вашей организации Яндекс Облака.
> Если нет предпочтений, используйте значения по умолчанию.

Параметр Zone можно не настраивать.

### Создание сервисной учетки и настройка её профиля в yc ([справка](https://yandex.cloud/ru/docs/cli/operations/authentication/service-account))
Выполняем в командной строке (создается учетка `sa-robot`):
```
yc iam service-account create --name sa-robot
```
Запишите параметр `id` созданной учетки.

Запрашиваем id нашей организации:
```
yc organization-manager organization list
```
Выписываем нужный id в первой колонке таблицы.
sdas
Выдаем права сервисной учетке:
```
yc organization-manager organization add-access-binding org-id --role organization-manager.federations.userAdmin --subject serviceAccount:sa-id

yc organization-manager organization add-access-binding org-id --role organization-manager.federations.viewer --subject serviceAccount:sa-id

```
> [!NOTE] где `org-id` - id организации, `sa-id` - id сервисной учетки, Например:
>```
>yc organization-manager organization add-access-binding bpfi6o0mxxxxxxcf1610 --role organization-manager.federations.userAdmin --subject serviceAccount:aje2s7xxxxxxslmrio5
>```

Далее создаем ключ для нового сервисного эккаунта.
```
yc iam key create --service-account-name sa-robot --output key.json
```
Создаем новый профиль для работы `yc` от имени сервисного эккаунта:
```
yc config profile create sa-profile
yc config set service-account-key key.json
```
Желательно удалить файл-ключ сервисного эккаунта:
```
del key.json
```

Проверяем, что новый профиль активен:
```
yc config profile list
```
Рядом с профилем `sa-profile` должно стоять слово `Active`.
Если профиль неактивен, активируем его:
```
yc config profile activate sa-profile
```

Удаляем первый профиль `default` (и все остальные профили, если они есть):
```
yc config profile delete default
```
Проверяем работу от имени учётной сервисной учетки путём запроса списка федеративный пользователей.
Для этого запрашиваем `id` федерации:
```
yc organization-manager federation saml list --organization-id org-id
```
Копируем `id` федерации и используем егов следующей команде:
```
yc organization-manager federation saml list-user-accounts --id fed-id --organization-id org-id
```
Команда должна вывести список пользователей.

Если возникла ошибка, нужно проверить разрешения сервисной учётной записи. Для этого можно воспользоваться графической консолью по адресу https://center.yandex.cloud/organization/acl и визуально просмотреть и отредактировать разрешения для сервисной учетки.

## Использование `yc` в скрипте Powershell
В срипте необходимо использовать следующую команду для вывода в переменную всех пользователей с их идентификаторами:
```
 [array] $yc_users = yc organization-manager federation saml list-user-accounts --id fed_id --organization-id org_id --jq ".[] | [.id, .saml_user_account.name_id] | @csv"
```

Далее необходимо запросить список пользователей AD, которые должны реплицироваться в облако и сравнить два списка.
Те пользователи, что должны быть исключены из облака, необходимо у далить командой:
```
yc organization-manager federation saml delete-user-accounts --id fed_id --organization-id org_id --subject-ids user_id
```
где `user_id` - id удаляемого из облака федеративного пользователя.



