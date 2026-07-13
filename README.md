# AURA

Гибридное capability-based ядро на Ada 2022.

SPDX-License-Identifier: `GPL-2.0-only`

## Архитектура

AURA — не микроядро: в kernel space остаются namespaces, mount,
attributes/watchers, IoRing, CDT, namespace graph и IPC. Ключевые
подсистемы (по каталогам `src/`):

| Каталог | Подсистема |
|---|---|
| `01_objects_and_capabilities` | Заголовки объектов, эпохи, capability, CDT, weak refs |
| `02_ring_levels` | Ring levels, VSpace |
| `03_namespace` | Пространства имён, mount |
| `05_io_ring` | Потоки, IoRing |
| `06_rcu` | RCU-домены и отложенные операции |
| `07_tlb_shootdown` | TLB shootdown |
| `08_timer_preemption` | Таймер, планировщик |
| `10_channel_ipc` | IPC-каналы, notifications |
| `11_attributes_and_watches` | Атрибуты и watchers |
| `12_package_fs` | Пакетная ФС (OPEN) |
| `13_mac` | MAC (Bell-LaPadula/Biba) |
| `15_watchdog` | Watchdog, политика перезапуска |
| `16_reincarnation` | Reincarnation-контракты |
| `16a_synapse` | Единый сигнальный движок: integrate-and-fire синапсы |
| `17_iommu` | IOMMU-домены |
| `18_driver_model` | Модель драйверов |
| `19_hal` | Граница HAL + reference-бэкенд |
| `app_a_sync_primitives` | Ticket lock, flip cell, wait queue |

### Сигналы и политика мандатов

Сигналы и подписки — одна абстракция: `Aura.Synapse`
(integrate-and-fire). Положительные/отрицательные вклады с весами,
фиксируемыми в Tap-мандате, верхний порог (накопление) и нижний
(-спайк), утечка заряда, каскады с ограничением глубины. «Резкий»
сигнал — вырожденный синапс с порогом 1.

Политика мандатов (`Aura.Cap_Policy`): позитивные (Allow) и
негативные (Deny) мандаты, временное окно `[Valid_From,
Valid_Until)`, счётчик использований, обратимая
активация/деактивация и необратимый отзыв по сигналу (синапс-гейт
различает срабатывание по верхнему и нижнему порогу). Наборы политик
сворачиваются режимами `Last_Wins` («сначала запретить, потом
разрешить» и наоборот), `Deny_Wins`, `Allow_Wins`.

## Статус

Компилируемая база с host/reference-бэкендом HAL (одно-CPU, no-op
платформенные операции). Не загружается на железе: платформенные
бэкенды (x86-64/ARM64), boot, SMP-атомарика — открытые задачи.
Незавершённые операции честно возвращают `Not_Supported` или помечены
`OPEN` в комментариях; они не имитируют успех.

## Сборка

Требуется GNAT ≥ 12 и GPRbuild:

```sh
gprbuild -P aura.gpr
./bin/aura_selftest
```

`aura_selftest` прогоняет smoke-тесты базовых инвариантов (rights,
wait queue, notification, scheduler quantum, attr watchers, cap
policy, synapse) на
reference-бэкенде.

## Лицензия

GPL v2.0 (only) — см. `LICENSE`.
