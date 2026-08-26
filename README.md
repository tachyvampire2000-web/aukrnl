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
| `07_tlb_shootdown` | TLB shootdown (с глобальным Shootdown_Lock) |
| `08_timer_preemption` | Таймер, EDF/CBS планировщик |
| `10_channel_ipc` | IPC-каналы, notifications |
| `11_attributes_and_watches` | Атрибуты и watchers |
| `12_package_fs` | Пакетная ФС (OPEN) |
| `13_mac` | MAC (Biba Strict Integrity) + аудит-кольцо |
| `15_watchdog` | Watchdog, политика перезапуска |
| `16_reincarnation` | Reincarnation-контракты |
| `16a_synapse` | Единый сигнальный движок: integrate-and-fire синапсы |
| `17_iommu` | IOMMU-домены |
| `18_driver_model` | Модель драйверов |
| `19_hal` | Граница HAL + reference-бэкенд |
| `app_a_sync_primitives` | Ticket lock, flip cell, wait queue |
| `20_boot` | Boot, ELF-загрузчик |

### Сигналы и политика мандатов

Сигналы и подписки — одна абстракция: `Aura.Synapse`
(integrate-and-fire). Положительные/отрицательные вклады с весами,
фиксируемыми в Tap-мандате, верхний порог (накопление) и нижний
(-спайк), утечка заряда, каскады с ограничением глубины. «Резкий»
сигнал — вырожденный синапс с порогом 1.

Политика мандатов (`Aura.Cap_Policy`): позитивные (Allow) и
негативные (Deny) мандаты, временное окно `[Valid_From, Valid_Until)`,
счётчик использований, обратимая активация/деактивация и необратимый
отзыв по сигналу (синапс-гейт различает срабатывание по верхнему и
нижнему порогу). Наборы политик сворачиваются режимами `Last_Wins`,
`Deny_Wins`, `Allow_Wins`.

### MAC (Mandatory Access Control)

Реализована **Biba Strict Integrity Policy (SIP)**:
- **write-down запрещён**: субъект S не пишет в объект O если O < S
- **read-up запрещён**: субъект S не читает объект O если O > S

Обе аксиомы применяются одновременно. IPC-путь (Channel_Send) вызывает
`Mac_Check_Ipc` перед доставкой сообщения. Аудит-канал — реальный
кольцевой буфер (256 записей) с потокобезопасным доступом.

**Важное уточнение**: MAC в AURA реализует **Biba**, а не Bell-LaPadula.
Bell-LaPadula защищает конфиденциальность (no read-up, no write-down для
уровней секретности). Biba защищает целостность (no read-up, no
write-down для уровней доверенности). В документации ранее неверно
указывалось «Bell-LaPadula/Biba» — реализован только Biba.

### Атомарность HAL

`Atomic_Compare_Exchange_U64` в `aura-hal.adb` реализован через
защищённый объект с `Interrupt_Priority'Last` — что запрещает
прерывания на время операции и обеспечивает атомарность на
однопроцессорной reference-платформе. На реальном SMP-железе
потребуется замена на аппаратную инструкцию (LOCK CMPXCHG / LL+SC).

Все 9 остальных HAL-функций (TLB flush, IPI, IOMMU mapping и т.д.)
явно задокументированы как **intentional no-op** с обоснованием в
комментариях — они не возвращают молчаливый Ok без объяснения.

### Статус Not_Supported

Операции, не реализованные в reference-платформе, честно возвращают
`Not_Supported` или `Elf_Load_Error`. Ни одна незаконченная операция не
возвращает `Ok` безусловно. Исключение: HAL-функции, которые на
reference-платформе являются no-op по дизайну (например, TLB flush),
возвращают `Ok` с документацией «intentional no-op».

## Статус реализации

| Подсистема | Статус |
|---|---|
| HAL CAS | ✅ Атомарный (protected объект + Interrupt_Priority'Last) |
| Планировщик EDF/CBS | ✅ Полноценный EDF с CBS бюджетами |
| Блокировка потоков | ✅ Scheduler_Block_Current/Until (yield-based) |
| Wait_Queue | ✅ Хранит адреса потоков, реальное пробуждение |
| Notification | ✅ Многобитовая маска Signal_Mask |
| Ticket_Lock | ✅ FIFO (двойная гарантия: FIFO_Queuing + билеты) |
| TLB Shootdown | ✅ Глобальный Shootdown_Lock |
| MAC (Biba) | ✅ Audit ring buffer + check на IPC-пути |
| RCU Drop_Object | ✅ Реальное освобождение через Unchecked_Deallocation |
| Entropy_Consume | ✅ Публично объявлена в .ads |
| Thread_Create/Destroy | ✅ Реализованы с CBS-контекстом |
| ELF loader | ✅ ELF64 LE (x86_64, AArch64) |
| Process_Create | ✅ Полная аллокация (VSpace + CNode + Thread) |
| Watchdog race | ✅ Исправлен (Reincarnation_Lock) |
| IOMMU физадрес | ✅ Из Mmio_Base_Phys, не захардкожен |
| Secure_Binding VA | ✅ Из Binding_Context.Requested_Va |
| Cap_Policy Valid_From | ✅ Проверяется всегда (согласовано с Applicable) |
| IO Ring Not_Supported | ✅ Честные Not_Supported для нереализованных ops |
| Proposals metabolism | ✅ Через Cap_Revoke→EBR, не Free напрямую |
| Kill_Process VSpace | ✅ Vspace_Destroy, не просто null |
| Synapse concurrency | ✅ Защищён Synapse_Lock |
| Weak_Ref.Upgrade | ✅ Безопасный порядок: null→epoch→deref |
| Boot/платформенный HAL | 🚧 No-op (reference-платформа, OPEN) |
| SMP > 1 CPU | 🚧 OPEN (требует аппаратного CAS) |
| ELF динамическая линковка | 🚧 OPEN (только статические образы) |

## Сборка

Требуется GNAT ≥ 12 и GPRbuild:

```sh
gprbuild -P aura.gpr
./bin/aura_selftest
```

## Лицензия

GPL-2.0-only. See `COPYING`.
