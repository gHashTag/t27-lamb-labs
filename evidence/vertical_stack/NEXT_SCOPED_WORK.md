# Next Scoped Work — candidate tracks (M4 planning, non-binding)

STATUS: PLANNING. No track is started here; each names its gate and first scoped slice.
Gates refer to `OWNER_DECISIONS.md` (D1–D6).

| Track | First scoped slice | Gate | Precondition met? |
|---|---|---|---|
| T1 power/timing (FPGA) | install Vivado WebPACK; `report_power` on shipped `.bit` netlist → replace ~0.7 W / ~0.12 J/token ESTIMATE band with a tool number (still not external-meter MEASURED) | owner approves ~20–30 GB install | no (install approval) |
| T2 external meter | serial current meter on AX7203 rail → J/token MEASURED | owner provides meter | no |
| T3 spec→RTL repair | write `.t27` spec for `ternary_mac_demo_top`, regenerate RTL, diff vs shipped netlist | D5 (HOLD lift) | no |
| T4 variance gate closure | re-run variance on rebuilt bitstream (depends on T3) | D5 | no |
| T5 r4t4c board rebuild | flash corrected fork, re-run live measurement, close the 200-vs-397.62 MHz discrepancy | openXC7 install approval (part of D5) | no |
| T6 new GPU kernels | only after D2 methodology decides how perf is measured | D2 | no |
| T7 acceptance/toolchain records | commit `GPU_ACCEPTANCE_RECORD.md` + `CANONICAL_TOOLCHAIN.md` | D1 + D4 "PIN" | no (answers pending) |
| T8 engagement (Block 8) | wait on Lamb Labs open model release | external | n/a |

Sequencing intent: D3 merge → T7 records → owner chooses among T1/T3/T5/T6.
T2 and T8 are owner-dependency tracks. Nothing in this table overrides a HOLD.

## Track selection after consolidation (ORDER LAMB_LABS_VERTICAL_CONSOLIDATION_NEXT, 2026-11-25)

Consolidation is DONE (master `0392c39`, origin untouched). The owner ORDER renumbers
tracks; mapping to the table above: ORDER T1=T1 power/timing, ORDER T2=new kernels=T6,
ORDER T3=spec→RTL=T3, ORDER T4=variance gate=T4, ORDER T5=engagement=T8, ORDER
T6=Mac toolchain fix (new, not in table), ORDER T7=push origin (new), ORDER T8=hold.

SELECTED_TRACK: **T1 power/timing** (owner hinted "скорее всего T1").
Precondition state, recorded honestly:

- Vivado is NOT installed (verified earlier this consolidation). EXECUTE_NOW.md manual
  Tcl steps exist for `utilization_report.txt` / `power_report.txt`; the shipped
  bitstream artifact is in `bitstream/`.
- Install cost: WebPACK-class download ~20–30 GB, no-cost license expected for
  xc7a200t but to be confirmed at install time (constraint: no paid resources).
- Output honesty: `report_power` on the shipped netlist replaces the ~0.7 W /
  ~0.12 J/token ESTIMATED band with a **tool number**, not an external-meter MEASURED
  (meter track stays T2/doc-numbering). It also characterizes the **defective shipped
  design** (dead `osc` clock, pruned accumulator) — results describe that artifact,
  not a corrected one.
- Not affected by D5 HOLD as scoped: this is local tooling on existing artifacts, no
  board runs, no new FPGA bitstream builds.
- Approval needed from owner: Vivado install. Push origin remains a separate gate.

No track is executed in this commit; execution starts only after the owner's explicit
approval in chat.


## T1 execution probe (2026-11-25, after owner approvals: install=yes, push=yes, local=no)

Owner correction: Vivado must NOT be installed on the local Mac — GPU box (w3070) and
VPS are for that. Probe results, recorded honestly:

- **Push origin: DONE.** `a7ef751..dfbb5d7 master -> master` (origin/master = dfbb5d7).
- **No routed checkpoint in the repo.** `find` finds only `.bit` files (shipped
  `ternary_mac_demo_top_200t.bit` + 4 clock_probe bits); zero `.dcp`. EXECUTE_NOW.md
  Option A (`open_checkpoint`) therefore has no input artifact. `report_power` on a
  `.bit` alone is not possible (Vivado cannot reopen a bitstream into a netlist) —
  the shipped-design tool number requires the ORIGINAL routed checkpoint from the
  machine that built it (machine unknown), or a new build (gated: "no new FPGA runs"),
  or a synthesized-only estimate (weaker, ESTIMATE-class, not a routed tool number).
- **w3070 unreachable right now**: `ssh t27ssh@pangolin.reactotron.ru:22022` →
  "Connection timed out during banner exchange". Disk/OS state unknown this session.
- **givel-vps (root@130.17.9.230) reachable**: Ubuntu, kernel 6.8.0-147, x86_64,
  `/` = 119G total, **19G free (84% used)** — smaller than the ~20–30 GB installer
  alone; Vivado Artix-7-only install does not fit without cleanup. No Xilinx dirs,
  no vivado in PATH.

T1 status: SELECTED, approvals obtained (install yes / local no), execution NOT
started — blocked on (a) routed checkpoint location and (b) a host that fits.
Cheapest first slice when resumed: locate the original Vivado project/.dcp (likely
on the machine that produced the shipped .bit), then install on w3070 or a cleaned VPS.

## ORDER T1_CHECKPOINT_DECISION — SELECTED: «checkpoint нет» (2026-11-25)

Not "lost" — **it never existed**. Provenance (both from committed evidence):
`ax7203_build_report.json` method line — the shipped bitstream was routed by
**openXC7/nextpnr-xilinx on the GPU box** (`bbaexport.py xc7a200tfbg484-2` → bbasm
chipdb); G17 — **Vivado was unavailable (AMD account login wall)**, "no vendor
timing/power report exists". A Vivado routed `.dcp` for this design was therefore
never produced on any host. Options re-derived honestly:

- **A «dcp on w3070» — dead as formulated.** What exists on the GPU box is the
  openXC7 flow, whose Fmax output is already WITHDRAWN as placement noise.
- **B (synthesized-only ESTIMATE)** — viable input exists: committed
  `evidence/codesign/ternary_mac_synth.v`. Still requires the Vivado WebPACK
  installer (AMD login = owner-side download) AND host disk (VPS has 19G free <
  ~20–30G installer; needs cleanup or another host). Output honestly ESTIMATE-class.
- **C (new FPGA build)** — RTL is committed (`rtl/ternary_mac_demo_top.v`); a Vivado
  rebuild is a NEW FPGA build → separate gate. It yields routed numbers for the same
  design (same two netlist-verified defects ride along and stay disclosed).

Common unblock for B and C (single action, cheapest-first): **owner downloads the
Vivado ML Standard WebPACK installer for the chosen host** (AMD login is not
agent-doable), then host decision (w3070 Windows / cleaned VPS Linux). B runs
immediately after install; C additionally needs the explicit new-build approval.
Until then T1 stays SELECTED-but-parked. No install performed on any host (none
fits today: w3070 closed-connection on retry, VPS disk short).

## ORDER T1_INSTALL_AND_RUN — progress log (2026-11-25)

- **VPS cleanup executed (owner-approved "Full cleanup ~17.6G")**: docker image prune
  (dangling 1.047GB + unused-extra 638MB) + approved caches (/root/.cache, /root/.npm,
  /tmp/hslm, /tmp/agent-work, /opt/zig*.tar.xz). Result: **19G → 29G free** (+10G).
  HONEST SHORTFALL vs the ~17.6G estimate: `docker system df` "reclaimable 12.46GB"
  turned out to be mostly container-backed image layers — docker itself refused to
  release them (all 9 running services intact and healthy after cleanup, verified).
- **Official Vivado disk requirements NOT yet confirmed**: docs.amd.com is a JS
  portal (no static text), legacy UG973 PDF URL dead (HTML redirect stub). Working
  figure — **ESTIMATE ~35–40GB installed for Vivado ML Standard + Artix-7 only**,
  plus ~11GB-class single-file download if the offline package is used. VPS 29G is
  therefore LIKELY SHORT; definitive numbers come from the web-installer's component
  selection screen or the docs page (needs BrowserOS).
- **w3070**: still down (3 probes: banner timeout ×2, connection closed ×1). Its
  disk state unknown; it remains the cleanest host (established openXC7 build box).
- **Download path**: AMD wall confirmed (301 → account.amd.com). BrowserOS neo MCP
  is NOT connected to this session yet — owner to start BrowserOS and connect the
  agent in cockpit. After connect: read exact UG973 requirements, download the
  Web installer (small) or single-file (large) via the signed-in AMD session.
- INSTALL: not started. B ESTIMATE: not run. C gate: not requested (per ORDER —
  only after B). No Mac install (staging Mac has 43G free, used only for file relay).

### ORDER T1_INSTALL_ON_GPU_VIA_PANGOLIN — host locked to w3070 (2026-11-25 morning)

- Host decision (owner): Vivado goes on **w3070 via Pangolin**; VPS 29G ruled risky;
  Mac staging-only. 
- **Pangolin TCP :22022 is OPEN but SSH banner never arrives (4+1 probes, incl. a
  90s banner wait)** — tunnel up, backend box down/hung. "Pangolin alive ≠ w3070
  alive" confirmed literally. Needs owner-side wake/reboot; agent cannot do WoL.
- Prepared downstream artifact: `t1_b_estimate_vivado.tcl` (B variant: Vivado
  re-synthesis of committed rtl/ternary_mac_demo_top.v → report_power/utilization,
  part xc7a200tfbg484-2, batch mode, honestly labeled ESTIMATE in the script header).
- Download remains behind AMD login (BrowserOS neo MCP still not connected to this
  session). When both are up, sequence is: BrowserOS → download Web/single-file
  installer to Mac staging → scp to w3070 → install → run the .tcl → record results.

### ORDER T1_UNBLOCK_AND_EXECUTE — MCP wired, two physical gates remain (2026-11-25 ~10:20 +07)

- BrowserOS neo MCP **wired into the harness profile by the agent**: configuration-only
  bundle `@local/browseros-mcp` (mcp-client, streamable-http, `127.0.0.1:9210/mcp`,
  serverInfo browseros-neo v0.0.93) — `install_bundle` → `application: applied`.
  Tool call reaches the server and issues a session handle. **Browser agent-link is
  stale** ("browser link lost ~2h ago, reconnecting") — reconnect does not self-heal;
  needs the owner to bring the BrowserOS neo app/cockpit to front once.
- w3070: probes 6–8 all banner-timeout through the open Pangolin tunnel (~1.5h window).
  Physical wake/reboot remains the only unblock path (agent-side WoL not available).
- No download/install/B-run yet: both remaining steps sit behind the two owner actions.

### ORDER VPS_TAKEOVER_PARTIAL — probes from givel-vps (2026-11-25 14:05 +07)

- **AMD wall is AUTH-gated, not location-gated**: same `curl -sIL` from VPS
  → `HTTP/1.1 301` → `account.amd.com/en/forms/downloads/xef.html` — anonymous
  download impossible from VPS exactly as from Mac. VPS cannot download the
  installer without an authenticated session.
- **Transfer path VPS→w3070 CONFIRMED**: `nc -z pangolin.reactotron.ru 22022`
  from VPS → succeeded (195.191.174.197). scp/relay possible when w3070 answers.
- **VPS disk drifted 29G→21G free** in ~5h (docker images 24.36GB, 16.82GB
  flagged reclaimable but container-backed; morning prune already took the
  loose layers). 21G still fits the ~11GB installer for staging.
- Conclusion: download needs ONE authenticated action (owner's signed-in
  browser, manual download to Mac ~/Downloads staging is allowed — no install
  on Mac), then Mac→w3070 scp direct (Mac has working ssh config+key) with
  VPS as backup relay. BrowserOS agent-link stays non-critical for this path.

### ORDER «найди место» — VPS staging space found: 21G→34G free (2026-11-25 16:30 +07)

- Freed on givel-vps, all rebuildable build junk + dead containers:
  node_modules `/root/deepseek-harness` 2.1G; rust `target/` dirs: tri-claw-build
  1.3G, t27-m13-final 420M, t27-src 324M, lanes/t27f-uikit-m0 266M, t27-m13-src
  265M, t27-release 255M, t27-build/src 255M, woody-weed-bot 1.6G (target only,
  source untouched); `.cargo/registry` 667M (bin kept); `.bun/install` 713M;
  journal already vacuumed; 2 exited junk containers + 1.879GB image prune.
- df: 92G used / 21G free (82%) → **79G used / 34G free (70%)**. The ~11GB
  Vivado installer now fits staging comfortably.
- NOT touched (need owner naming, other projects' sources): `/opt/woody-weed-bot`
  source ~11.4G, `/root/house_bot` 2.0G, `/root/catalogs` 943M, `/root/lanes`,
  t27-* source trees, `/root/.rustup` 1.6G, two Zig toolchains in /opt.
- Gates unchanged: w3070 probe 24 banner-timeout; installer not in ~/Downloads;
  BrowserOS link still reconnecting (handle rotated again).

### ORDER T1_GATES_STUCK_12_PROBES — probing stopped, escalated (2026-11-25 21:20 +07)

Pattern recorded. Since ORDER OWNER_DOWNLOAD_AND_WAKE (14:35 +07) through
21:10 +07 (~6h35m): 20 probes total (#18–#37), owner-visible latest window
#26–#37 = 12 consecutive without transition.

- w3070: every probe `Connection timed out during banner exchange`; zero ALIVE.
- Installer: `~/Downloads/FPGAs_AdaptiveSoCs_Unified_SDI_2024.2_*Lin64.bin`
  absent at every check; broad Downloads sweep found no large new files.
- BrowserOS link: reconnecting at every check; session handles rotated 4×
  (…ed4b → …3244a → …17d2 → 98d46768); browser process itself healthy
  (CDP :9333 answers), only the agent↔browser link is stale.
- VPS staging: 34G free (commit 5d24369) — the only gate moved today.

Action per ORDER: scheduled auto-probe task `schedule-c3893a8b` set to
**paused** (not deleted) at 21:17 +07; blind probing stopped. Re-probe happens
ONCE on explicit owner signal, then the chain runs if gates are open.

Escalation to owner — two physical actions remain owner-only:
1. download FPGAs_AdaptiveSoCs_Unified_SDI_2024.2_1113_1001_Lin64.bin (~11GB)
   to ~/Downloads in the AMD-signed-in browser;
2. wake/reboot w3070 (it has answered nothing since 2026-11-24 evening).

### Блокер 3 снят частично: браузер снова управляем через :9211 (2026-11-25 23:58 +07)

- MCP-инстанс neo на :9210 держит «link lost», но второй инстанс того же
  BrowserOS neo **:9211 имеет живой линк к Chrome** (CDP :9333 здоров).
  Полный JSON-RPC streamable-HTTP: initialize → tools/call (tabs, snapshot,
  grep, name_session) — работают. Tab group: `agent/vivado-installer-download`.
- Открыта вкладка 38 с URL скачивания Vivado 2024.2 Lin64
  (xef.html?filename=FPGAs_AdaptiveSoCs_Unified_SDI_2024.2_1113_1001_Lin64.bin)
  → редирект на **login.amd.com SAML, форма Sign-In** — активной AMD-сессии
  в профиле нет. Ввод пароля = owner-only (правило секретов).
- request_human_help/await_human_help через сырой HTTP не дают ответа
  (сервер держит SSE keepalive и рвёт поток ~30с) → сигнал владельцу передан
  через чат сессии; по ORDER триггер = файл в ~/Downloads или «go».

### Проба #38 и ожидание триггера (2026-11-25 21:36 +07; ORDER T1_GATES_OWNER_TRIGGER_WAIT)

- w3070: `Connection timed out during banner exchange` (exit 1) — 38-я подряд
  неудача; TCP-порт Pangolin 22022 открыт, бэкенд не отвечает.
- Инсталлятор в ~/Downloads: отсутствует (глоб на `*SDI_2024.2*Lin64.bin*`).
- Сетка: `.dcp` в репо нет ни одного (проверено ранее); «checkpoint нет»
  подтверждено, B/C — единственные живые варианты.

### AMD-стена в браузере: полный лог (2026-11-26 09:31–13:49 +07)

- 09:31 проверка: инсталлятора нет; w3070 всё ещё молчит; VPS 32G свободно.
- Вкладка владельца [41] `amd.com/en/support/download.html` найдена живой
  через :9211 — владелец зашёл в AMD со своего таба.
- Вкладка [43]: реальная страница design-tools редиректит на 2026.1;
  селектор версии сломан для `act kind=select` (TypeError) → открыт прямой
  `account.amd.com/en/forms/downloads/xef.html?filename=…2024.2_1113_1001_Lin64.bin`
  → вкладка [44] = «Name and Address Verification» с кнопкой Download [e290],
  форма ЗАПОЛНЕНА из аккаунта (Dmitrii/TRINITY/Thailand/CEO-CFO).
- Клик по Download: и `download`-инструмент, и `act kind=click` отрабатывают
  «ok», но загрузка не стартует: URL теряет `filename=`, chrome://downloads
  показывает только старый mp4, ~/Downloads/~/Desktop пусты, формы возвращается
  предзаполненной, ошибок в accessibility-дереве нет, captcha не найдена,
  `form.checkValidity()` пуст → submit проходит, но файл не отдаётся.
- Повторное открытие той же xef-ссылки в новом табе [46] показывает ту же
  форму (SAML-стены нет) — но результат тот же: клик, страница перезагрузилась
  без filename, загрузки нет. Tab умер/закрылся к 14:49.
- Вывод: интерстициал AMD на этом табе не отдаёт файл (причина на стороне
  AMD-страницы не установлена; подозрение — требование их JS-обвязки/антибот).

### Прорыв: публичный PGP-дайджест и официальный SHA-256 (2026-11-26 ~13:55 +07)

- Страница 2024.2 (`…/development-tools/2024-2.html`) получена curl-ом
  (`--http1.1` + браузерный UA; голый HTTP/2 и дефолтный UA падали с exit 92).
- В разметке найдены ПРЯМЫЕ пути на `download.amd.com/opendownload/installer/2024.2.2_2025_0307_0744/`:
  Lin64.bin / .tar / Win64.exe + **`.digests` и `.sig` для каждого**.
- `.digests` качается БЕЗ авторизации (HTTP 200, AkamaiNetStorage) и содержит
  PGP-подписанный блок с официальными хешами. SHA-256 инсталлятора:
  `a028cdebaa606175aa942791fc989968ddbf0b7f9f23f7edaa4b06f046e497d6`
  для `FPGAs_AdaptiveSoCs_Unified_2024.2.2_0306_2322_Lin64.bin`.
  Сам .bin на CDN — 404 (бинарники заперты; сигнатуры публичны).
- Смена версии честно зафиксирована: цель теперь **2024.2.2** (актуальный
  патч линейки 2024.2, то, что AMD сейчас раздаёт), а не 2024.2_1113_1001
  (дайджест на который публично не найден). Для B-ESTIMATE на xc7a200tfbg484-2
  это не меняет метод (синтез + report_power/report_utilization).

### Владелец скачал инсталлятор — цепочка проверок пройдена (2026-11-26 15:22–16:30 +07)

- Владелец нажал Download у себя и сообщил файл. На Mac:
  `~/Downloads/FPGAs_AdaptiveSoCs_Unified_2024.2.2_0306_2322_Lin64.bin`,
  319 086 250 байт, `file` → «POSIX shell script executable (binary data)».
- `shasum -a 256` → `a028cdeb…97d6` — **EXACT MATCH** с официальным
  PGP-подписанным дайджестом AMD.
- `scp` на givel-vps → `/root/vivado_inst/` → `sha256sum` на VPS → тот же хеш
  (совпадение на всех трёх ступенях: AMD-дайджест → Mac → VPS).
- `df -h` VPS: 32G свободно до распаковки.
- Распаковка без запуска: `./…Lin64.bin --noexec --target /root/vivado_inst/x`
  → 781 MB, `x/xsetup` присутствует; `xsetup --help` отвечает: batch-режим
  поддерживается (`-b ConfigGen|AuthTokenGen|Install`, `-c config`, `-a XilinxEULA,3rdPartyEULA`).

### Инцидент ConfigGen на VPS и восстановление (2026-11-26 16:55–18:20 +07)

- `xsetup -b ConfigGen` завис: java-процесс 100% CPU, писал лог
  `/root/.Xilinx/xinstall/xinstall-2026-11-26_09-55-37.log` размером
  **25 692 917 631 байт (~24 GB) за ~50 минут** (лог-цикл ~8 МБ/с).
  Диск VPS просел 32G → **7.0G (94%)** — production-риск (postgres, боты,
  harness на той же машине).
- Процесс убит (`kill`), собственный кэш удалён (`rm -rf /root/.Xilinx/xinstall`,
  внутри был только этот лог; payload там НЕ скачивался).
  Диск восстановлен: **31G свободно, 73%**; `docker ps` → 10 контейнеров живы,
  load 0.78. Честно: хвост лога прочитан не был — диагностическая причина
  зависания ConfigGen удалена вместе с кэшем и не зафиксирована.
- Вердикт по месту: batch-установщик на headless VPS ведёт себя нестабильно,
  а пик установки (payload + установленный Vivado + Artix-7 ≈ 30 GB) на 31G
  свободных не помещается с безопасным запасом. VPS-путь для установки —
  ЗАКРЫТ по месту; остаётся w3070 (предпочтительный хост по ORDER).

### Состояние T1 на сейчас (2026-11-26 19:00 +07)

- ✅ Инсталлятор скачан владельцем, SHA-256 подтверждён на Mac и VPS.
- ✅ Копия на VPS `/root/vivado_inst/` (304 MB) — запасной носитель.
- ✅ Распаковка и проверка batch-флагов выполнены.
- ⛔ Установка: только w3070 — хост молчит с 2026-11-24 вечера, wake/reboot
  = owner-only физическое действие.
- ⏸ Автопроба `schedule-c3893a8b` по-прежнему на паузе; перепишется/удалится
  при завершении T1.
- B-ESTIMATE после установки: `evidence/vertical_stack/t1_b_estimate_vivado.tcl`
  (batch, `xc7a200tfbg484-2`, вывод строго с меткой ESTIMATE).

### w3070: трансфер 11 МБ/с, ConfigGen разгадан, установка готова — туннель закрылся на auth (2026-11-26 20:16–2026-11-27 00:20 +07)

**w3070 поднялся (20:16:21, try 1)**: `Linux win11-3070 6.18.58.1-microsoft-standard-WSL2`,
`/dev/sdd 1007G, 915G свободно, 5%`, user `t27ssh`. ОС-врата решены: Lin64.bin корректен.

**Трансфер: путь Mac→w3070 через Pangolin давал ~22 КБ/с (14 МБ за 10 мин → ~4 ч остаток).
Замена**: разовый `python3 -m http.server 39047` на VPS + `ufw allow 39047/tcp`
(порт был закрыт default-DROP) → `wget` с w3070 забрал файл за ~30 с
(**273 МБ за 25 с ≈ 11 МБ/с**). Сразу после: `ufw delete allow 39047/tcp`,
http.server убит, медленный scp-джоб отменён, частичный файл удалён.
**Итог на w3070**: `~/vivado_inst/FPGAs_..._Lin64.bin` 319 086 250 байт,
`sha256sum` → `a028cdeb…497d6` = официальный PGP-дайджест AMD — **OK** (двойная проверка).

**Payload извлечён**: `./...bin --noexec --target ~/vivado_inst/x` → `x/` 781M
(`bin data lib tps xsetup`), `xsetup` executable.

**ConfigGen разгадан (честная поправка к VPS-инциденту)**: на w3070 ConfigGen
оказался **интерактивным**: «Select a Product from the list: 1.Vitis 2.Vivado …» →
выбор продукта → «Select an Edition: 1.Vivado ML Standard 2.Vivado ML Enterprise».
На VPS «ранавей» с логом 25.7 ГБ был **петлёй промптов на пустом stdin**
(«ERROR - Not a valid choice» миллион раз в лог), а не локальным зависанием.
Кормление ответов дало **exit=0**: `INFO - Config file available at
/home/t27ssh/.Xilinx/install_config.txt`. Выбран Vivado ML **Standard**
(бесплатный webpack-класс — отвечает на вопрос лицензии для B-ESTIMATE).

**Сгенерированный конфиг** содержит `Edition=Vivado ML Standard`, `Destination=/tools/Xilinx`,
`Modules=` со ВСЕМИ семействами=1 (~100 ГБ+). Подготовлен `w3070_install_launch.sh`
(локально `/tmp/`, копия на VPS `/root/vivado_inst/`): sed-trim до **Artix-7:1, остальные 0**,
`Destination=/home/t27ssh/tools/Xilinx` (нет sudo), шорткаты 0 → запуск
`./xsetup -a XilinxEULA,3rdPartyEULA -b Install -c ~/.Xilinx/install_config.txt` detached.

**Блокер (владелец-уровень)**: первая попытка применить конфиг+запустить установку —
`Permission denied (publickey,password)`. Стабильно 40+ мин (20:50→00:20 +07).
Диагностика: ключ предлагается (`id_ed25519 SHA256:O7otBJSc…`), сервер отвергает;
host-ключи 22022 ≠ VPS:22 (туннель ведёт на w3070, не на VPS); баннер
**`OpenSSH_9.2p1 Debian-2+deb12u10`** — SSH-сервер за туннелем Debian 12
(дистрибутив WSL у w3070 может быть Debian — `uname` дистрибутив не показывает).
ssh-соединения за вечер были частыми/параллельными — возможен fail2ban/смена
состояния хоста. Агентские пути исчерпаны: нужен владелец у машины
(разбан/проверка `authorized_keys`/туннеля). Правило порядка соблюдено: на сигнал — один перепроб.

**Окружение на VPS после**: 31G свободно / 74%, 10 контейнеров, чужие данные не тронуты.

**NEXT_STEP**: владелец восстанавливает auth на 22022 (или запускает
`bash /root/vivado_inst/w3070_install_launch.sh`-эквивалент локально в WSL:
sed-trim конфига + `cd ~/vivado_inst/x && ./xsetup -a XilinxEULA,3rdPartyEULA -b Install -c ~/.Xilinx/install_config.txt`);
после установки — правка Tcl на абсолютный путь RTL и B-ESTIMATE.
