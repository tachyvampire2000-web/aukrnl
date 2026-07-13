# MANIFEST — материализация спецификации TACHY (Ada/SPARK) в файлы

Это транскрипция Ada-кода из `tachy_spec_ada.md` (сама спецификация, приложена рядом как `SOURCE_SPEC.md`) в реальную структуру файлов и папок по GNAT-конвенции именования (`Tachy.Foo_Bar` → `tachy-foo_bar.ads`). **Это не проверенный компилятором результат.** В среде генерации не было доступного GNAT — компиляция не запускалась ни разу; всё написанное ниже — результат сверки структуры вручную, тем же способом, каким проверялись находки в самой беседе.

## Структура

```
tachy_port/
├── MANIFEST.md              -- этот файл
├── SOURCE_SPEC.md           -- исходная спецификация (для сверки)
├── tachy_port.gpr           -- минимальный GNAT-проект (см. ниже)
└── src/
    ├── 00_purpose_and_conventions/
    ├── app_a_sync_primitives/
    ├── 01_objects_and_capabilities/
    └── ...  (одна папка на главу документа, §0..§22)
```

Один пакет документа = один `.ads` (либо пара `.ads`+`.adb`, где нужно тело). Внутри каждой главы также могут быть:

- `generic_instances.ads_fragment` — generic-инстанциации главы, не завёрнутые в собственный пакет в источнике (например, `package Revoke_Stacks is new Ada.Containers.Bounded_Vectors (...)`); не самостоятельный compilation unit, нужно перенести содержимое в то место, куда встраивается вызывающий пакет.
- `chapter_fragments.ada_fragment` — код главы, показанный в источнике вне какой-либо пакетной обёртки вообще (например, операции CDT — `Cap_Mint`, `Cap_Revoke` — в главе 1, где документ даёт последовательность деклараций раздела, а не единый `package`). Тоже не самостоятельный compilation unit.

## Находки этого прохода (компиляционно значимые)

Три класса проблем обнаружены и исправлены при подготовке `tachy_spec_ada.md` (см. переписку до этого архива); ниже — то, что обнаружилось *дополнительно*, именно при попытке материализовать документ в реальные compilation units.

### Новое: 13 пакетов, где полное императивное тело стоит прямо под `package X is` вместо `package body X is`

Ada не допускает `begin ... end Name;` — тело подпрограммы со статьями исполнения — непосредственно в объявлении пакета (`package X is`); такое тело обязано находиться в `package body X is ... end X;`. Expression-функции (`is (...)`) — исключение, они законны прямо в спеке; проблема только там, где тело — императивное (`is` → декларативная часть → `begin` → операторы → `end`).

Обнаружено двумя независимыми проходами (по признаку голого `begin` вне `declare`-expression и по признаку повторного объявления одного имени подпрограммы внутри одной спеки) в следующих 13 пакетах — для каждого этот архив даёт настоящую `.ads`+`.adb` пару вместо одного файла:

- `Tachy.Attr`
- `Tachy.Channel`
- `Tachy.Driver`
- `Tachy.Entropy`
- `Tachy.Fault`
- `Tachy.Iommu`
- `Tachy.Mac`
- `Tachy.Secure_Binding`
- `Tachy.Thread`
- `Tachy.Timer`
- `Tachy.Tlb_Shootdown`
- `Tachy.Watchdog`

Разделение сделано механически: сигнатура остаётся в `.ads` (терминирована `;`, с сохранением исходных `with Pre/Post/Global` аспектов), тело переносится в `.adb` без изменений по существу.

### Новое: 10 фрагментов кода, которые сами оканчиваются на `end <ИмяПакета>;`, не открывая этот пакет заново

В нескольких местах документ даёт дополнительный код уже закрытого ранее пакета отдельным фрагментом дальше по тексту (обычно следующий подраздел той же главы), и этот фрагмент сам оканчивается повторным `end <ИмяПакета>;` — притом что открытия `package <ИмяПакета> is` в этом же фрагменте нет. Это не создаёт проблему в самом markdown (условно понятно по контексту прозы, что это продолжение), но при механическом извлечении Ada-кода такой фрагмент выглядит как пакет без открытия. Обнаружено и правильно присоединено к исходному пакету (декларации — в `.ads`, тела — в `.adb`, через тот же детектор, что и для пункта выше):

- `Tachy.Attr` — doc-lines 4321-4439
- `Tachy.Capability.Validity` — doc-lines 1610-1625
- `Tachy.Fault` — doc-lines 3792-3833
- `Tachy.Io_Ring` — doc-lines 2530-2571, 3131-3167
- `Tachy.Mac` — doc-lines 4848-4855
- `Tachy.Namespace` — doc-lines 2015-2062
- `Tachy.Rcu` — doc-lines 3292-3317
- `Tachy.Reincarnation` — doc-lines 5452-5463
- `Tachy.Synapse` — doc-lines 5793-5898
- `Tachy.Capability.Validity` — также получил обратно тело `Check_Valid_Fast` (doc-lines 1135-1159), которое в источнике дано как самостоятельный, корректно оформленный фрагмент без проблемы «конца без начала» — просто физически отделено от своей спеки прозой раздела.

Ни один из этих 10+1 случаев не является ошибкой сам по себе (это нормальный документ-стиль «вот ещё код к тому же пакету дальше по тексту»), но материализация в отдельные compilation units требует явно решить, где заканчивается один пакет и начинается материал следующего раздела — что и сделано здесь.

## Не найдено новых компиляционных проблем, кроме перечисленного выше

Отдельно проверено и НЕ подтверждено как проблема (то есть это ложные срабатывания первичных детекторов, разобранные по ходу работы):

- `Tachy.Capability.Validity.Check_Valid` и `Tachy.Flip_Cell.Is_Normal` — «двойное объявление» на самом деле законный паттерн public-спека + private-реализация как expression-function в той же спеке.
- `Tachy.Ticket_Lock.Unlock` — тело есть, просто оформлено как примитив `protected body Instance` (документ уже даёт этот `package body` отдельным top-level юнитом), а не как обычная процедура верхнего уровня.

## Замеченные (но не новые) пробелы реализации

При проверке «объявлено, но нигде не реализовано» по всем 37 top-level единицам всплыл более широкий список имён, чем 13+10 случаев выше. Подавляющее большинство — не находка этого прохода, а то, что сам документ уже честно фиксирует как открытый вопрос, просто разными способами разметки:

- **Абстрактные примитивы** (`is abstract;`) — вся `Hardware_Abstraction` в §18.6 (`Tachy.Driver`: `Allocate_Iommu_Domain`, `Validate_Mmio`, `Rdrand`, `Send_Tlb_Shootdown_Ipi` и ещё ~20 подобных). Это осознанная объектная модель — dispatching-интерфейс, реализуемый платформой/драйвером ниже уровня, который эта спецификация специфицирует; не пробел.
- **Уже помечено `OPEN`/todo в самом тексте документа**: `Tachy.Cap_Node.Alloc`, `Tachy.Package_Fs.Package_Mount`/`Package_Unmount` — рядом с декларацией есть явный комментарий «тело не реализовано... не додумывается», иногда с планом реализации как текстом, не кодом.
- **Уже названо в T-Ada таблице открытых вопросов самой спецификации** (см. §23 `SOURCE_SPEC.md`): `Tachy.Weak_Ref.{Downgrade, Upgrade}` — родственно T-Ada-06 (формальное доказательство порядка операций не выполнено; здесь дополнительно нет и самой реализации, не только доказательства).
- **Реально не реализовано нигде и не названо явно в T-Ada-таблице** — это единственная категория ниже, которую стоит считать genuinely новым наблюдением, а не просто перепроверкой известного:
  - `Tachy.Rcu`: тела примитивов `protected type Rcu_Queue` (`Push`, `Drain`) и `protected type Rcu_Domain` (`Read_Lock`, `Read_Unlock`, `Call_Rcu`) и топ-левел `Execute` — ни один `protected body` для `Rcu_Queue`/`Rcu_Domain` не дан нигде в документе (весь документ содержит всего 3 `protected body`: `Instance` (Ticket_Lock), `Wait_Queue_Instance`, `Wait_Token` — RCU среди них нет).
  - `Tachy.Capability.Validity.{Check_Right, Current_Tick}` — объявлены с `Global => null`, реализация не дана (в отличие от соседней `Check_Valid`, у которой есть declare-expression в `private`).
  - `Tachy.Thread.Sched_Ctx_Create`, `Tachy.Entropy.Saturating_Add_U64`.

Эти пункты не исправлены в этом архиве (в отличие от 13+10 находок выше) — они не компиляционные баги, а содержательные пробелы реализации, и решение о том, как их закрывать, требует понимания конкретной платформы/протокола, которое не мне додумывать за автора. Если материализация в файлы будет использоваться как основа для реальной сборки, эти имена стоит внести в таблицу T-Ada (§23 источника) наравне с T-Ada-01..10, прежде чем компилировать.

## Содержимое по главам

### 0. Назначение и принципы / пакетная структура

- `src/00_purpose_and_conventions/tachy.ads` — package Tachy
- `src/00_purpose_and_conventions/tachy-option.ads` — package Tachy.Option
- `src/00_purpose_and_conventions/generic_instances.ads_fragment` — 2 generic-инстанциации главы: Phys_Addr_Option_Base, Thread_Capability — не самостоятельный compilation unit, см. MANIFEST
- `src/00_purpose_and_conventions/chapter_fragments.ada_fragment` — 4 фрагмент(ов) кода главы вне пакетной обёртки

### A. Примитивы синхронизации

- `src/app_a_sync_primitives/tachy-ticket_lock.ads` — package Tachy.Ticket_Lock
- `src/app_a_sync_primitives/tachy-ticket_lock.adb` — package body Tachy.Ticket_Lock (дано в источнике как отдельное тело)
- `src/app_a_sync_primitives/tachy-flip_cell.ads` — package Tachy.Flip_Cell
- `src/app_a_sync_primitives/tachy-per_cpu.ads` — package Tachy.Per_Cpu
- `src/app_a_sync_primitives/tachy-slot_map.ads` — package Tachy.Slot_Map
- `src/app_a_sync_primitives/tachy-slot_map.adb` — package body Tachy.Slot_Map (дано в источнике как отдельное тело)
- `src/app_a_sync_primitives/chapter_fragments.ada_fragment` — 4 фрагмент(ов) кода главы вне пакетной обёртки

### 1. Объекты и мандаты

- `src/01_objects_and_capabilities/tachy-object.ads` — package Tachy.Object
- `src/01_objects_and_capabilities/tachy-cap_node.ads` — package Tachy.Cap_Node
- `src/01_objects_and_capabilities/tachy-capability.ads` — package Tachy.Capability
- `src/01_objects_and_capabilities/tachy-weak_ref.ads` — package Tachy.Weak_Ref
- `src/01_objects_and_capabilities/tachy-cap_object_ref_pkg.ads` — package Tachy.Cap_Object_Ref_Pkg
- `src/01_objects_and_capabilities/tachy-rights.ads` — package Tachy.Rights
- `src/01_objects_and_capabilities/tachy-capability-validity.ads` — package Tachy.Capability.Validity; включает 1 декларативный фрагмент(ов), данный в источнике позже, отдельно от исходного закрытия пакета
- `src/01_objects_and_capabilities/tachy-capability-validity.adb` — package body Tachy.Capability.Validity — 1 тело/тела, данные в источнике отдельно и позже (Check_Valid_Fast)
- `src/01_objects_and_capabilities/generic_instances.ads_fragment` — 3 generic-инстанциации главы: Thread_Weak_Ref_Base, Device_Object_Capability, Revoke_Stacks — не самостоятельный compilation unit, см. MANIFEST
- `src/01_objects_and_capabilities/chapter_fragments.ada_fragment` — 19 фрагмент(ов) кода главы вне пакетной обёртки

### 2. Ring Levels

- `src/02_ring_levels/tachy-ring.ads` — package Tachy.Ring
- `src/02_ring_levels/chapter_fragments.ada_fragment` — 1 фрагмент(ов) кода главы вне пакетной обёртки

### 3. Пространство имён

- `src/03_namespace/tachy-namespace.ads` — package Tachy.Namespace; включает 1 декларативный фрагмент(ов), данный в источнике позже, отдельно от исходного закрытия пакета
- `src/03_namespace/generic_instances.ads_fragment` — 2 generic-инстанциации главы: Cap_Token_Maps, Layer_Keys — не самостоятельный compilation unit, см. MANIFEST
- `src/03_namespace/chapter_fragments.ada_fragment` — 7 фрагмент(ов) кода главы вне пакетной обёртки

### 4. Память: Untyped

- `src/04_untyped_memory/tachy-untyped.ads` — package Tachy.Untyped
- `src/04_untyped_memory/chapter_fragments.ada_fragment` — 1 фрагмент(ов) кода главы вне пакетной обёртки

### 4a. Secure Bindings

- `src/04a_secure_bindings/tachy-secure_binding.ads` — package Tachy.Secure_Binding — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/04a_secure_bindings/tachy-secure_binding.adb` — package body Tachy.Secure_Binding — 2 тел, перенесённых из спеки (Resolve_External_Effect, Secure_Binding_Create)

### 5. Асинхронный ввод-вывод: IoRing

- `src/05_io_ring/tachy-io_ring.ads` — package Tachy.Io_Ring; включает 1 декларативный фрагмент(ов), данный в источнике позже, отдельно от исходного закрытия пакета; плюс декларативная часть 1 смешанного фрагмента-продолжения (тела той же части — в .adb)
- `src/05_io_ring/tachy-io_ring.adb` — package body Tachy.Io_Ring — 1 тело/тела из фрагментов-продолжений (Object_Destroy_Vspace)
- `src/05_io_ring/tachy-thread.ads` — package Tachy.Thread — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/05_io_ring/tachy-thread.adb` — package body Tachy.Thread — 1 тел, перенесённых из спеки (Sanitize_Fields)
- `src/05_io_ring/generic_instances.ads_fragment` — 5 generic-инстанциации главы: Sqe_Cells, Bitmap_Vectors, Inflight_Vectors, Batch_Target_Vectors, Migration_Slot_Vectors — не самостоятельный compilation unit, см. MANIFEST
- `src/05_io_ring/chapter_fragments.ada_fragment` — 14 фрагмент(ов) кода главы вне пакетной обёртки

### 6. Синхронизация: RCU

- `src/06_rcu/tachy-rcu.ads` — package Tachy.Rcu; плюс декларативная часть 1 смешанного фрагмента-продолжения (тела той же части — в .adb)
- `src/06_rcu/tachy-rcu.adb` — package body Tachy.Rcu — 1 тело/тела из фрагментов-продолжений (Call)
- `src/06_rcu/chapter_fragments.ada_fragment` — 3 фрагмент(ов) кода главы вне пакетной обёртки

### 7. TLB Shootdown

- `src/07_tlb_shootdown/tachy-tlb_shootdown.ads` — package Tachy.Tlb_Shootdown — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/07_tlb_shootdown/tachy-tlb_shootdown.adb` — package body Tachy.Tlb_Shootdown — 2 тел, перенесённых из спеки (Vspace_Unmap, Tlb_Shootdown_Handler)

### 8. Таймерный preemption

- `src/08_timer_preemption/tachy-timer.ads` — package Tachy.Timer — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/08_timer_preemption/tachy-timer.adb` — package body Tachy.Timer — 1 тел, перенесённых из спеки (Timer_Interrupt_Handler)

### 9. Fault-Delegation

- `src/09_fault_delegation/tachy-fault.ads` — package Tachy.Fault — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки); плюс декларативная часть 1 смешанного фрагмента-продолжения (тела той же части — в .adb)
- `src/09_fault_delegation/tachy-fault.adb` — package body Tachy.Fault — 1 тел, перенесённых из спеки (Thread_Set_Fault_Handler); 1 тело/тела из фрагментов-продолжений (Thread_Resume)
- `src/09_fault_delegation/chapter_fragments.ada_fragment` — 1 фрагмент(ов) кода главы вне пакетной обёртки

### 10. Channel IPC

- `src/10_channel_ipc/tachy-channel.ads` — package Tachy.Channel — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/10_channel_ipc/tachy-channel.adb` — package body Tachy.Channel — 4 тел, перенесённых из спеки (Channel_Send, Channel_Recv, Cap_Wait_Any, Task_Force_Decrement_Budget)

### 11. Атрибуты и живые запросы

- `src/11_attributes_and_watches/tachy-attr.ads` — package Tachy.Attr — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки); плюс декларативная часть 1 смешанного фрагмента-продолжения (тела той же части — в .adb)
- `src/11_attributes_and_watches/tachy-attr.adb` — package body Tachy.Attr — 1 тел, перенесённых из спеки (Sanitize_Fields); 3 тело/тела из фрагментов-продолжений (Attr_Watch_Create, Attr_Unwatch, Notify_Watchers)
- `src/11_attributes_and_watches/chapter_fragments.ada_fragment` — 1 фрагмент(ов) кода главы вне пакетной обёртки

### 12. PackageFs — PUnion

- `src/12_package_fs/tachy-package_fs.ads` — package Tachy.Package_Fs

### 13. MAC: мандатные метки

- `src/13_mac/tachy-mac.ads` — package Tachy.Mac — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки); включает 1 декларативный фрагмент(ов), данный в источнике позже, отдельно от исходного закрытия пакета
- `src/13_mac/tachy-mac.adb` — package body Tachy.Mac — 1 тел, перенесённых из спеки (Set_Mandatory_Label)
- `src/13_mac/tachy-causal.ads` — package Tachy.Causal
- `src/13_mac/generic_instances.ads_fragment` — 1 generic-инстанциации главы: Audit_Locks — не самостоятельный compilation unit, см. MANIFEST
- `src/13_mac/chapter_fragments.ada_fragment` — 3 фрагмент(ов) кода главы вне пакетной обёртки

### 14. Kernel_Error — полный enum

- `src/14_kernel_error/tachy-kernel_error_pkg.ads` — package Tachy.Kernel_Error_Pkg
- `src/14_kernel_error/tachy-entropy.ads` — package Tachy.Entropy — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/14_kernel_error/tachy-entropy.adb` — package body Tachy.Entropy — 3 тел, перенесённых из спеки (Entropy_Consume, Entropy_Replenish, Entropy_Feed)

### 15. Watchdog Capability

- `src/15_watchdog/tachy-watchdog.ads` — package Tachy.Watchdog — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/15_watchdog/tachy-watchdog.adb` — package body Tachy.Watchdog — 5 тел, перенесённых из спеки (Heartbeat_Touch, Watchdog_Create, Watchdog_Destroy, Apply_Watchdog_Policy, Watchdog_Tick)

### 16. Надзор и перезапуск: Reincarnation_Contract

- `src/16_reincarnation/tachy-reincarnation.ads` — package Tachy.Reincarnation; включает 1 декларативный фрагмент(ов), данный в источнике позже, отдельно от исходного закрытия пакета
- `src/16_reincarnation/chapter_fragments.ada_fragment` — 1 фрагмент(ов) кода главы вне пакетной обёртки

### 16a. Synapse

- `src/16a_synapse/tachy-synapse.ads` — package Tachy.Synapse; плюс декларативная часть 1 смешанного фрагмента-продолжения (тела той же части — в .adb)
- `src/16a_synapse/tachy-synapse.adb` — package body Tachy.Synapse — 3 тело/тела из фрагментов-продолжений (Synapse_Apply_Delta, Synapse_Signal, Apply_Decay_If_Due)
- `src/16a_synapse/generic_instances.ads_fragment` — 2 generic-инстанциации главы: Sealed_Cap_Vectors, Fire_Depth_Cells — не самостоятельный compilation unit, см. MANIFEST
- `src/16a_synapse/chapter_fragments.ada_fragment` — 4 фрагмент(ов) кода главы вне пакетной обёртки

### 17. IOMMU: Iommu_Domain

- `src/17_iommu/tachy-iommu.ads` — package Tachy.Iommu — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/17_iommu/tachy-iommu.adb` — package body Tachy.Iommu — 4 тел, перенесённых из спеки (Resolve_External_Effect, Iommu_Domain_Create, Iommu_Attach_Device, Iommu_Map)

### 18. Драйверная модель (PRM)

- `src/18_driver_model/tachy-driver.ads` — package Tachy.Driver — спека (тела вынесены в .adb: см. новый баг «тело в спеке», MANIFEST §Находки)
- `src/18_driver_model/tachy-driver.adb` — package body Tachy.Driver — 6 тел, перенесённых из спеки (State, Set_State, Resolve_External_Effect, Prm_Request_Resource, Respawn_Driver_Process, Rebind_Driver_Caps)

### 21. Cache-Line Discipline

- `src/21_cache_line_discipline/chapter_fragments.ada_fragment` — 1 фрагмент(ов) кода главы вне пакетной обёртки

## Как этим пользоваться

1. Это не готовый к сборке кернел. Прежде чем пытаться компилировать, нужно закрыть T-Ada-01..10 (см. §23 `SOURCE_SPEC.md`) и пункты из раздела «Замеченные пробелы реализации» выше — иначе `gprbuild` упрётся в отсутствующие тела на первом же файле, где они есть.
2. `tachy_port.gpr` перечисляет все папки `src/*` как source dirs и включает `-gnat2022`, тот же режим, который сама спецификация называет для своих проверок. Флаг `-gnatwa` (все предупреждения) добавлен как разумный дефолт, не как требование источника.
3. Файлы с расширением `.ads_fragment`/`.ada_fragment` — не compilation units. Переименовывать в `.ads`/`.adb` и пытаться скомпилировать напрямую не стоит: их содержимое либо должно влиться в место использования (generic-инстанциации), либо в какой-то реальный пакет, которого сам документ для этого места не задаёт (orphan-фрагменты вроде CDT-операций в главе 1).
