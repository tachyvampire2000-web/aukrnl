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
| `17_iommu` | IOMMU-домены |
| `18_driver_model` | Модель драйверов |
| `19_hal` | Граница HAL + reference-бэкенд |
| `app_a_sync_primitives` | Ticket lock, flip cell, wait queue |

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
wait queue, notification, scheduler quantum, attr watchers) на
reference-бэкенде.

## Лицензия

GPL v2.0 (only) — см. `LICENSE`.
