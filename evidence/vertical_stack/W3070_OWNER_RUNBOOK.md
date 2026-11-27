# W3070_OWNER_RUNBOOK — разблокировка T1 одной командой владельца

Статус на 2026-11-27 20:14 +07: SSH-auth `pangolin.reactotron.ru:22022`
(user `t27ssh`) персистентно отказывает (`Permission denied (publickey,password)`)
с 2026-11-26. Инсталлятор Vivado 2024.2.2 доставлен на w3070 и сверен по
SHA-256, payload распакован (`~/vivado_inst/x/`, 781M), ConfigGen пройден
(`~/.Xilinx/install_config.txt`, Vivado ML Standard). Осталось: install →
B-ESTIMATE → отчёт. Всё блокировано только auth.

## Путь A (рекомендуется): восстановить SSH-доступ — 1 команда

Владелец открывает **WSL-терминал на w3070** (Windows: «Ubuntu» или `wsl`)
и вставляет одну команду:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+pEfK25VYt9TA3+1uRGLnqjdB4wdGKwxXFdBcRdaz2 playra@playras-MacBook-Pro.local' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo RESTORED
```

(это публичный ключ агента с Mac — `~/.ssh/id_ed25519.pub`; он лишь
добавляет строку в `authorized_keys`, ничего не удаляет)

После `RESTORED` сказать агенту «go» — дальше без владельца:
один проверочный SSH → запуск launch-скрипта
`evidence/vertical_stack/w3070_install_launch.sh`
(копия с VPS `/root/vivado_inst/w3070_install_launch.sh`,
SHA-256 `4722fd19…a35b59`, + добавлен LOG_GUARD — авто-kill xsetup при
росте логов >2048 МБ, репо-хеш `edccbb9c…ca1501`; механика:
`ssh w3070 'bash -s' < w3070_install_launch.sh` —
sed-trim конфига до Artix-7:1, без ярлыков, nohup) →
install → license-check → правка Tcl на абсолютный путь →
B-ESTIMATE → отчёт с меткой ESTIMATE.

## Путь A2 (самый быстрый): владелец входит с паролем с этого Mac — 1 команда

Сервер принимает password (в отказе указан метод `password`), host-ключи
не менялись (sshd тот же). Из терминала этого Mac:

```bash
cd /Users/playra/t27-lamb-labs && ssh -p 22022 t27ssh@pangolin.reactotron.ru "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+pEfK25VYt9TA3+1uRGLnqjdB4wdGKwxXFdBcRdaz2 playra@playras-MacBook-Pro.local' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys; bash -s" < evidence/vertical_stack/w3070_install_launch.sh
```

Владелец вводит пароль `t27ssh` при prompts → команда (а) восстанавливает
мой ключ (после чего мониторинг и B-ESTIMATE снова агентские), (б) сразу
запускает guarded install (Artix-7-only, LOG_GUARD). Если пароль не принят —
см. путь A (консоль WSL) или диагностику ниже.

## Путь B (fallback, без SSH): владелец запускает install локально

Тот же WSL-терминал, две команды:

```bash
# 1) Install (915G свободно, встанет целиком):
cd ~/vivado_inst/x
sed -i 's|^Destination=.*|Destination=/home/t27ssh/tools/Xilinx|' ~/.Xilinx/install_config.txt
timeout 7200 ./xsetup -a XilinxEULA,3rdPartyEULA -b Install -c ~/.Xilinx/install_config.txt

# 2) B-ESTIMATE (после установки):
cd ~/vivado_inst
sed -i 's|^read_verilog .*|read_verilog /home/t27ssh/vivado_inst/ternary_mac_demo_top.v|' t1_b_estimate_vivado.tcl
~/tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source t1_b_estimate_vivado.tcl -journal b.log -log b_run.log
```

Ограничения честности: мониторинг хода агентом требует SSH (Путь A);
при Пути B агент собирает отчёт из терминального вывода владельца
и файлов, которые владелец передаст (`t1_b_power_estimate.txt`,
`t1_b_utilization.txt`). Числа — только с меткой **ESTIMATE**
(re-synthesis, не routed, не board).

## Если Путь A не срабатывает (диагностика на w3070, WSL-терминал)

```bash
ls -la ~/.ssh/authorized_keys && tail -2 ~/.ssh/authorized_keys
sudo mkdir -p /var/run/sshd 2>/dev/null; pgrep -a sshd || echo NO_SSHD
```

- строка ключа видна в `authorized_keys`, но отказ остаётся → sshd на
  стороне WSL не слушает/пересоздан: `sudo service ssh restart` (нужен sudo;
  в прошлом замере sudo на w3070 отсутствовал — тогда пересоздать линк
  туннеля Pangolin на порт SSH WSL);
- `NO_SSHD` → SSH-сервер в WSL не запущен: `sudo service ssh start`.

Туннель TCP жив (пробы доходят до sshd и получают отказ auth) — проблема
не в Pangolin-транспорте, а в auth/наличии sshd внутри WSL.
