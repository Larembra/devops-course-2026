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
