# MANIFEST — Материализация спецификации AURA (Ada/SPARK) в файлы

Актуальный манифест архитектуры ядра **AURA**, собранного и
протестированного в среде GNAT 13.3.0 / GPRbuild.

> **Примечание о точности**: этот документ был приведён в соответствие
> с фактическим состоянием кода в рамках работы по дорожной карте
> дефектов (60 пунктов). Предыдущие версии содержали ряд неверных
> утверждений — они исправлены ниже.

## Структура репозитория

```
aura_kernel/
├── README.md               -- Вводное описание ядра и сборки
├── docs/
│   └── MANIFEST.md         -- Этот файл (описание архитектуры)
├── aura.gpr                -- Определение проекта GPRbuild
└── src/
    ├── 00_purpose_and_conventions/   -- Базовые типы и опции ядра
    ├── app_a_sync_primitives/        -- Примитивы: Ticket_Lock, Wait_Queue, Flip_Cell, Cap_Policy
    ├── 01_objects_and_capabilities/  -- Объекты, Weak_Ref, Cap_Node, CDT, права
    ├── 02_ring_levels/               -- Ring levels, VSpace
    ├── 03_namespace/                 -- Пространства имён и mount
    ├── 04_untyped_memory/            -- Нетипизированная физическая память
    ├── 04a_secure_bindings/          -- Защищённые аппаратные привязки
    ├── 05_io_ring/                   -- Thread, Io_Ring
    ├── 06_rcu/                       -- RCU (Epoch-Based Reclamation)
    ├── 07_tlb_shootdown/             -- TLB shootdown с Shootdown_Lock
    ├── 08_timer_preemption/          -- Таймер, EDF/CBS планировщик
    ├── 09_fault_delegation/          -- Делегирование fault-ов в userspace
    ├── 10_channel_ipc/               -- IPC-каналы, Notification
    ├── 11_attributes_and_watches/    -- Атрибуты и watchers
    ├── 12_package_fs/                -- Пакетная ФС
    ├── 13_mac/                       -- MAC (Biba), аудит-кольцо
    ├── 14_kernel_error/              -- Коды ошибок, Entropy
    ├── 15_watchdog/                  -- Watchdog, политика перезапуска
    ├── 16_reincarnation/             -- Reincarnation-контракты
    ├── 16a_synapse/                  -- Синапс (integrate-and-fire)
    ├── 17_iommu/                     -- IOMMU-домены
    ├── 18_driver_model/              -- Драйверная модель (PRM)
    ├── 19_hal/                       -- HAL + reference-бэкенд
    ├── 20_boot/                      -- Boot + ELF loader
    ├── 21_proposals/                 -- Объектный метаболизм
    └── 99_instances/                 -- Глобальные инстанциирования
```

## Реализованные подсистемы

### 1. Атомарный CAS (HAL)

`Atomic_Compare_Exchange_U64` в `aura-hal.adb` реализован через
защищённый объект с `Interrupt_Priority'Last`. На reference-платформе
(однопроцессорной) это обеспечивает атомарность путём запрета
прерываний. На реальном SMP требуется аппаратный LOCK CMPXCHG/LL+SC.

Все прочие HAL-функции явно документированы как **intentional no-op**.
Они **не** возвращают молчаливый `Ok` — каждая содержит комментарий с
обоснованием и описанием того, что нужно сделать на реальном железе.

### 2. EDF/CBS планировщик

`Aura.Sched` реализует **Earliest Deadline First (EDF)** с **Constant
Bandwidth Server (CBS)** бюджетами. Функция `Scheduler_Tick` реально
декрементирует бюджет, перезаряжает его при наступлении конца периода и
возвращает `Preempt` при CBS-throttling. `Schedule` выбирает поток с
наименьшим дедлайном среди готовых.

### 3. Wait_Queue с реальным пробуждением

`Aura.Wait_Queue.Instance` хранит адреса (`Thread_Handle =
System.Address`) ожидающих потоков, а не только счётчик. Метод
`Wake_All_With_Signal` обходит сохранённые адреса и вызывает
глобальный callback `Wake_Proc` (устанавливается планировщиком).
Метод `Wake_With_Token` доставляет пробуждение адресно по токену.

### 4. Notification (многобитовая маска)

`Notification_Signal` принимает параметр `Signal_Mask :
Interfaces.Unsigned_64` и выставляет именно переданные биты в
`Pending`. Ранее код жёстко выставлял бит 0 (`or 1`).

### 5. Ticket_Lock с FIFO-порядком

FIFO-порядок обеспечивается двумя независимыми механизмами:
- Ada FIFO_Queuing (ARM D.4, default GNAT)
- Поля `Next_Ticket`/`Now_Serving`/`My_Ticket` реально используются
  в теле entry (в отличие от исходного кода, где они инкрементировались
  без влияния на guard).

### 6. MAC — только Biba (исправление документации)

**Исправлено**: в предыдущей документации утверждалось «Bell-LaPadula/Biba».

Реализована исключительно **Biba Strict Integrity Policy**:
- write-down запрещён: S не может писать в O < S
- read-up запрещён: S не может читать O > S

Bell-LaPadula (конфиденциальность) не реализован. MAC-проверки
реально вызываются из IPC-пути (`Mac_Check_Ipc` в Channel_Send).
Аудит-канал — реальный кольцевой буфер (256 записей), не заглушка.

### 7. RCU Drop_Object

`Execute` в `aura-rcu.adb` обрабатывает все четыре case-ветки
включая `Drop_Object`, который ранее был `null` (no-op). Теперь
освобождает объект через `Unchecked_Deallocation` — вызывается только
после подтверждения отсутствия читателей (EBR-гарантия).

### 8. Entropy_Consume

`Entropy_Consume` объявлена в `aura-entropy.ads` и доступна публично.
Ранее реализация была только в `.adb` (недоступна внешним пакетам).

### 9. Thread_Create / Thread_Destroy

Добавлены в `aura-thread.ads`/`.adb`. Thread_Create создаёт поток с
CBS-контекстом; Thread_Destroy зачищает оба слота Flip_Cell перед
освобождением (предотвращает use-after-free через старый снимок).

### 10. ELF загрузчик (ELF64)

`Aura.Elf` в `src/20_boot/` реализует парсинг заголовка ELF64
(little-endian, EM_X86_64/EM_AARCH64), обход PT_LOAD сегментов и
отображение каждого в VSpace процесса через `Vspace_Map`.
Использует код ошибки `Elf_Load_Error`.

### 11. Process_Create

Реализован в `aura-capability-validity.adb`: аллоцирует VSpace,
корневой CNode, boot-поток и Process_Context. Ранее возвращал
`Not_Supported`.

### 12. Kill_Process освобождает VSpace

`Aura.Reincarnation.Kill_Process` вызывает `Vspace_Destroy` вместо
простого `Proc.Vspace := null`. Устраняет утечку памяти.

### 13. Respawn_From_Template заполняет VSpace

`Respawn_From_Template` отображает образ из шаблона в новый VSpace
через `Vspace_Map_Template` и копирует начальные мандаты из шаблона
в новый CNode. Ранее создавал пустой VSpace без образа.

### 14. Proposals Metabolism через EBR

`Aura.Proposals.Metabolism.Metabolise_Cap` использует `Cap_Revoke →
Retire → EBR`, а не прямой `Aura.Cap_Node.Free`. Это гарантирует,
что объект не освобождается при наличии живых мандатов.

### 15. Cap_Policy.Applicable — оба временных поля

`Applicable` проверяет `Valid_From` всегда (не только когда
`Valid_Until = 0`). Согласовано с `Check_Temporal_Validity` в
`aura-capability-validity.adb`.

## Intentional no-op (reference-платформа)

Следующие компоненты являются intentional no-op на reference-платформе.
Каждый явно задокументирован в коде с обоснованием:

- `Hal_Local_Tlb_Flush` — нет прямого управления TLB на хост-ОС
- `Hal_Send_Tlb_Shootdown_Ipi` — нет IPI на однопроцессорной платформе
- `Hal_Unmap_Segment` — нет реальных таблиц страниц
- `Hal_Iommu_Map/Unmap/Tlb_Invalidate_All` — нет реального IOMMU
- `Platform_Irq_Ack` — нет прямого управления контроллером прерываний
- `Spin_Loop_Hint` — PAUSE/YIELD не нужен на хост-ОС
- `Hal_Allocate_Iommu_Domain` — монотонный счётчик вместо HW domain
- IO Ring Read/Write/Attr_Watch/Mount/Device_Query — `Not_Supported`
- `Sweep_Expired_Mounts` — временные маунты OPEN

## Открытые задачи (OPEN)

- Boot на реальном железе (x86_64, AArch64)
- SMP > 1 CPU (аппаратный CAS, per-CPU run queues)
- Реальные таблицы страниц (Vspace_Map на железе)
- ELF динамическая линковка / PIE
- Bell-LaPadula конфиденциальность (если потребуется)
- Namespace временные маунты (Sweep_Expired_Mounts)
