# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- Гипервизор: VirtualBox 7.x, ОС: Ubuntu Server 24.04.5 LTS (64-bit), образ `ubuntu-24.04.5-live-server-amd64.iso`
- Оперативная память: 2048 МБ
- Процессоры: 2 ядра
- Диск: 25 ГБ, динамический (VDI), разметка Use an entire disk (LVM)
- После установки корень расширен: `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` (около 23 ГБ)
- Имя узла: `devops-vm`, полное имя: `devops-vm.devops.local`

## 2. Сетевые интерфейсы
| Адаптер | Тип | Интерфейс | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | enp0s3 | 10.0.2.15/24 (DHCP) | доступ в Интернет, репозитории пакетов |
| 2 | Host-only (VirtualBox Host-Only Ethernet Adapter) | enp0s8 | 192.168.56.101/24 (DHCP) | прямой доступ с хоста, имя devops.local |

Хост: в файл `C:\Windows\System32\drivers\etc\hosts` добавлена строка `192.168.56.101 devops.local`.
Гость: `sudo hostnamectl set-hostname devops-vm`, в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm`.

## 3. Правило проброса портов
Адаптер 1 (NAT), правило `ssh`: TCP, адрес хоста 127.0.0.1, порт хоста 2222, адрес гостя пусто, порт гостя 2222 (изначально 22, изменён после смены порта SSH).

## 4. Учётные записи
| Имя | Группы | Аутентификация |
|---|---|---|
| student | student, sudo (создан установщиком) | пароль, только локальная консоль; по SSH запрещён директивой `AllowUsers devops` |
| devops | devops, sudo | по ключу ed25519; пароль задан только для sudo |

Создание: `sudo adduser devops && sudo usermod -aG sudo devops`.
Ключ на хосте: `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`.
Открытый ключ размещён в `/home/devops/.ssh/authorized_keys` (права: каталог 700, файл 600).
Клиентский `~/.ssh/config` на хосте:
```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH
- Файл конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf` (основной `sshd_config` не изменялся, резервная копия `/etc/ssh/sshd_config.backup`)
- Директивы:
```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```
- Конфликт: в `/etc/ssh/sshd_config.d/50-cloud-init.conf` стояло `PasswordAuthentication yes` (побеждает, так как читается раньше). Исправление:
  `sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf`
- Активация по сокету отключена, иначе порт остаётся 22:
```
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
```
- Проверка: `sudo sshd -t`, `sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"`, `sudo ss -tlnp | grep sshd` (ожидается 0.0.0.0:2222).

## 6. Правила межсетевого экрана
Политики: `default deny incoming`, `default allow outgoing`.
```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw enable
```
Правила для 2222 создаются до `ufw enable`. Итог: 80/tcp ALLOW, 443/tcp ALLOW, 2222/tcp LIMIT (для IPv4 и IPv6). Правило `ufw allow ssh` не используется (оно относится к порту 22).

## 7. Снимки состояния
| Наименование | Состояние | Момент создания |
|---|---|---|
| 01-clean-install | чистая установка, оба адаптера, SSH на порту 22 | 12.10.2026 22:20 |
| 02-keys-configured | пользователь devops, вход по ключу, `~/.ssh/config` | 26.10.2026 01:09 |
| 03-ssh-hardened | усиленный SSH, порт 2222, проброс 2222→2222 | 26.10.2026 01:30 |

Примечание: при откате на 01-clean-install правило проброса в VirtualBox нужно привести в соответствие (порт гостя 22 до смены порта SSH, 2222 после).

## 8. Веб-сервер

- Пакет: `nginx` (версия 1.24.0 из репозитория Ubuntu 24.04), установка: `sudo apt update && sudo apt install -y nginx`.
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`, активируется символической ссылкой `/etc/nginx/sites-enabled/devops-site` (`sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/`). Ссылка стандартного ресурса `/etc/nginx/sites-enabled/default` удалена (`sudo rm /etc/nginx/sites-enabled/default`).
- Содержимое конфигурации: два блока `server`. Первый слушает порты 80 (IPv4 и IPv6), `server_name devops.local`, выполняет `return 301 https://$host$request_uri;`. Второй слушает порты 443 ssl (IPv4 и IPv6), `server_name devops.local`, `ssl_certificate /etc/ssl/certs/devops.crt`, `ssl_certificate_key /etc/ssl/private/devops.key`, `ssl_protocols TLSv1.2 TLSv1.3`, `root /var/www/devops-site`, `index index.html`, `location / { try_files $uri $uri/ =404; }`, `error_page 404 /404.html`, журналы `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`. Заголовок HSTS не добавляется.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`, права 755 для каталогов и 644 для файлов. Каталог создаётся командами `sudo mkdir -p /var/www/devops-site` и `sudo chown -R devops:devops /var/www/devops-site`. Содержимое доставляется из каталога `site/` репозитория сценарием `scripts/deploy.sh` (`rsync -az --delete --chmod=D755,F644`).
- Сертификат: самоподписанный, `/etc/ssl/certs/devops.crt` (владелец root, права 644). Закрытый ключ: `/etc/ssl/private/devops.key` (владелец root, права 600). Команда формирования: `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"`. Срок действия: 365 дней.
- Применение конфигурации: `sudo nginx -t && sudo systemctl reload nginx` (без `restart`).
- Межсетевой экран: порты 80/tcp и 443/tcp разрешены (см. раздел 6).
- Доверие клиента к сертификату: на хостовой системе `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`, запросы выполняются с параметром `--cacert ~/devops.crt`.
