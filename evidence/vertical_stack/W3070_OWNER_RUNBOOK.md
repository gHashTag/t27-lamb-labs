# W3070_OWNER_RUNBOOK — разблокировка T1 одной командой владельца

Статус на 2026-11-27 17:35 +07: SSH-auth **восстановлен** (Путь A2
выполнен владельцем, агентский ключ в `authorized_keys`). AuthTokenGen
пройден владельцем интерактивно (токен до 2026-12-04). НО install
падает: `downloadlink` AMD-entitlement отвечает **400 BadRequest**
(детали в NEXT_SCOPED_WORK.md). Осталось: устранить 400 (шаг «AMD
профиль» ниже) → install → B-ESTIMATE → отчёт.

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
# 1) Install (915G свободно, встанет целиком). ВАЖНО: -c ПЕРВЫМ аргументом —
#    парсер 2024.2.2 молча отбрасывает флаги после -b Install:
cd ~/vivado_inst/x
sed -i 's|^Destination=.*|Destination=/home/t27ssh/tools/Xilinx|' ~/.Xilinx/install_config.txt
timeout 7200 ./xsetup -c ~/.Xilinx/install_config.txt -a XilinxEULA,3rdPartyEULA -b Install

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

## Если install падает на «downloadlink code: BadRequest» (актуальный блокер)

oauth-validate проходит («Authenticated user admin@t27.ai successfully»),
а `https://xilinx.entitlenow.com/wi/v1/downloadlink` стабильно 400.
По форумам AMD типовая причина — **неполный профиль аккаунта**: entitlement
не выдаёт загрузки, пока в профиле не заполнены все обязательные поля.

**Шаг владельца (2 мин, в браузере, где уже залогинен в AMD):**
1. Открыть https://account.amd.com → профиль (Account Details).
2. Проверить и заполнить ВСЕ обязательные поля: имя, фамилия,
   адрес, город, индекс, страна, телефон. Сохранить.
3. Сказать агенту «профиль готов» → агент ретраит install (1 мин до
   вердикта; токен уже на w3070, повторный AuthTokenGen не нужен).

**Если профиль полный, а 400 остаётся** — два фолбэка:
- письмо на websupport@xilinx.com (AR 44043): точный текст ошибки
  `Unexpected Exception for: https://xilinx.entitlenow.com/wi/v1/downloadlink,
  code: BadRequest`, лог `~/.Xilinx/xinstall/xinstall-*.log` с w3070 —
  это документированный путь при compliance-hold аккаунта;
- скачать в браузере **FULL IMAGE Vivado ML Standard 2024.2.2**
  (~60–90 ГБ tarball со страницы загрузки AMD) → агент ставит из
  локального payload — downloadlink вообще не вызывается.
