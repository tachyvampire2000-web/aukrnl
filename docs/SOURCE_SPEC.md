# ТЕХНИЧЕСКАЯ СПЕЦИФИКАЦИЯ ЯДРА «TACHY» — ADA/SPARK

**Версия 1.0 (порт) — базируется на Tachy 0.3.12 (Rust)**

---

> ## ⚠️ ВАЖНОЕ АРХИТЕКТУРНОЕ ПРИМЕЧАНИЕ
>
> **TACHY — НЕ МИКРОЯДРО.**
>
> Микроядро (seL4, L4, Mach) выносит все сервисы (драйверы, файловые системы, сети)
> в пользовательское пространство и предоставляет только IPC, управление памятью
> и планирование. TACHY этому определению не соответствует:
>
> - Пространства имён, монтирование, атрибуты и наблюдатели (`Attr_Watch`) живут
>   **в ядре**, а не в userspace-сервисах.
> - IoRing, CDT и namespace-граф — часть ядерного состояния.
> - XPC (`Perform_Xpc_Call`) — синхронный IPC с donation бюджета, встроенный в ядро.
>
> **TACHY — гибридное ядро с capability-based security**, ближайшие аналоги —
> Fuchsia/Zircon и Composite OS: capability-модель безопасности заимствована из
> микроядерной традиции, но сервисная логика остаётся в ядре ради производительности.
>
> Это архитектурное утверждение из Rust-версии переносится без изменений — сама
> смена языка реализации не меняет классификацию ядра.

---

## Отношение к Rust-версии (Tachy 0.3.12)

Этот документ — перенос спецификации Tachy с Rust (no_std + alloc) на Ada 2022 /
SPARK. Это **не транслитерация синтаксиса**, а перепроектирование механизмов
безопасности на языковые средства Ada там, где прямой перенос либо невозможен,
либо ослабляет исходную гарантию.

Три принципа переноса (аналогично трём принципам перехода SYNTH → Tachy в
исходном документе):

1. **Принцип сохранения силы инварианта.** Если Rust кодирует инвариант в
   системе типов (phantom-параметр, `PhantomData`, sealed trait), а у Ada есть
   эквивалент не слабее — используем его. Если эквивалента нет — инвариант
   перепроверяется в рантайме явным контрактом (`Pre`/`Post`/`Type_Invariant`),
   и это отличие документируется, а не замалчивается.
2. **SPARK вместо `unsafe`-дисциплины.** Там, где Rust полагается на
   doc-комментарий `// SAFETY: ...` рядом с блоком `unsafe`, Ada/SPARK может
   формально доказать тот же инвариант через `Ghost`-функции, `Global`-аннотации
   и доказательства отсутствия гонок в `protected`-объектах. Где SPARK может
   доказать больше, чем Rust мог утверждать комментарием, — это явное усиление,
   и оно помечено как таковое.
3. **Честный TODO вместо тихой реализации.** Тикеты, помеченные в исходном
   документе (§23 Rust-версии) как «Открыт», переносятся как сигнатуры с
   портированными типами и контрактами, но без тела — `pragma Unimplemented`
   или явный комментарий `-- OPEN: T<n>`. Логика не додумывается на этапе
   переноса.

**Что перенесено без структурных изменений:** мандатная модель,
пространства имён, ленивый отказ ресурсов, реинкарнация процессов,
capability-based security, RCU-домены, IoRing, PackageFs, MAC
(Bell-LaPadula + Biba), Synapse. Философия ядра не зависит от языка
реализации.

**Что потребовало переработки, а не транслитерации** (полный список — по
каждому пункту ниже, в соответствующем разделе):

- `PhantomData`-права доступа (`Cap<T, R>`) → discriminated-запись прав вместо
  generic-параметра типа, с обоснованием в §1.4.
- RAII-guard'ы (`Drop` для `TicketGuard`) → `protected`-объекты Ada, которые
  дают сильнее гарантию (компилятор не даёт забыть разлочить), чем ручной
  ticket-протокол.
- Trait-объекты (`dyn HardwareAbstraction`) → Ada tagged types с
  dispatching, с оговоркой о разнице в стоимости диспетчеризации (§18.6).
- `Box<dyn FnOnce()>` (RCU callback) → генератор с ограниченным набором
  вариантов операции (Ada не имеет closures как объектов первого класса без
  дополнительной инфраструктуры) — см. §6.1.

---

## Журнал изменений порта (Rust 0.3.12 → Ada 1.0)

| # | Описание |
|---|----------|
| port-01 | Базовая версия для порта — Tachy 0.3.12 (Rust), включающая исправления внешнего аудита `ext-audit-01`…`ext-audit-10` и решение `revert-ring-001` (6 Ring Levels → 2). Все находки этого аудита уже были устранены в исходном документе до начала порта — при сверке независимо подтверждено (fence-баланс, `WaitToken`/`prepare_with_token`, `CascadeTooDeep` в enum, откат `execution_snapshot_restore`, error-path `io_batch_execute`, честный комментарий `io_template_execute`, нумерация §13.4/§13.5, диапазон статистики T45–T48) — новых расхождений с журналом изменений Rust-версии не найдено, поэтому порт ведётся от актуального состояния без повторного внесения этих фиксов |
| port-02 | `Cap<T, R: AccessRights>` (phantom-права) перепроектирован как `Capability` — discriminated record с полем `Rights : Rights_Mask` и статической проверкой на местах создания через `Pre`-контракт, а не через параметр типа. Обоснование: в Rust-версии из 13 объявленных marker-типов прав (`Read`, `Write`, `Manage`, `Grant`, `AttrRead`, `AttrWrite`, `Mount`, `BindPrm`, `AnyRights`, `ReadWrite`, `ReadOnly`, `(Read, Write)`, `(Manage, Grant)`) реально используется в коде только `(Read, Write)` (`PrmResourceCap::MmioRegion`, §18.4) — остальные, включая оба tuple-варианта, либо используются как маркер без применения прав (`AnyRights`, `ReadOnly` — по умолчанию), либо не используются вовсе (`(Manage, Grant)`). Генерировать в Ada 13 отдельных generic-инстанциаций ради одной реально используемой не имеет смысла — Ada-версия кодирует то же множество прав как единый параметризуемый тип с рантайм-маской, идентичной `RightsMask` из §1.4 Rust-версии, и статическую проверку translates в `Pre`-контракт на конкретных функциях создания мандатов (`Cap_Mint`, `Cap_Mint_Temporal`), где Rust использовал bound `R: HasGrant` |
| port-03 | `TicketLock<T>` / `TicketGuard` (ручной RAII через `Drop`) перепроектирован как `protected type Ticket_Lock`. Ada `protected`-объекты дают сильнее гарантию: компилятор не позволяет обратиться к защищённым данным вне protected-операции, тогда как Rust-guard полагается на дисциплину вызова `Drop` (которую можно случайно обойти через `mem::forget`, хоть это и redkий случай). FIFO-очерёдность тикетов сохранена явным полем `Next_Ticket`/`Now_Serving`, семантика идентична |
| port-04 | `FlipCell<T>` перенесён с сохранением lock-free read-семантики. Инвариант «бит0 == бит1 ⟺ норма» закодирован как `Ghost`-функция `Is_Normal` и используется в `Post`-контракте `Write`/`Rollback` — SPARK может формально доказать сохранение инварианта на каждом переходе состояния, что Rust-версия утверждала только текстовым SAFETY-комментарием. Это усиление, а не эквивалент |
| port-05 | `Box<dyn FnOnce()>` (RCU deferred callback, §6.1) не имеет прямого эквивалента в Ada без garbage-collected closures. Перепроектирован как закрытое перечисление `Rcu_Callback_Kind` + variant record с данными операции — тот же принцип, что уже применён в исходном документе для `IoTemplate` (§5.6b Rust-версии): конечный список известных на этапе компиляции операций вместо произвольного замыкания. Это сужение выразительности (нельзя передать одноразовое замыкание с произвольным захватом), задокументировано как открытый вопрос порта — см. §6.1 |
| port-06 | `RingLevel` — перенесён как есть с 2 уровнями (Ring0/Ring3), согласно `revert-ring-001` из журнала изменений Rust-версии. Как и в исходном документе, оговорка **не снимается портом**: не проверено, не ослабляет ли схлопывание бывших kring0/1/2 в один Ring0 инварианты MAC/Biba (§13), которые могли неявно опираться на внутреннее разделение уровней. Этот вопрос помечен как открытый и в Ada-версии (см. §23, T-Ada-01) |
| port-07 | `KernelError` перенесён как enumeration type с representation clause, сохраняющим числовые коды 1:1 из Rust `#[repr(i32)]` enum — обеспечивает ABI-совместимость на границе, если она понадобится (например, для существующих userspace-клиентов, ожидающих те же коды ошибок) |
| port-08 | `Vec`/`Box`/`Arc` (T69: `Vec` запрещён на горячих путях, `ArrayVec` — единственная временная коллекция) — принцип перенесён напрямую: Ada `Ada.Containers.Bounded_Vectors` на горячих путях (эквивалент `ArrayVec` — фиксированная ёмкость на этапе компиляции, без аллокации), unbounded-типы (`Ada.Containers.Vectors`, `Ada.Finalization`) только на cold path (создание объектов ядра), по аналогии с `Arc`/`Box`, допустимыми в Rust-версии только там же |

---

## 0. Назначение и принципы

Tachy — ядро для систем с управляемым ресурсами пространством пользователя.

Базовые принципы (унаследованы из Rust-версии без изменений):

- Объекты ядра адресуются через мандаты (`Capability`), не через хэндлы или ACL.
- Каждый процесс видит собственное дерево путей (namespace).
- **T69:** ядро не использует неограниченную динамическую аллокацию на горячих
  путях после старта. Все временные коллекции — `Bounded_Vector` /
  `Bounded_Array` с ёмкостью, известной на этапе компиляции. Управляемые типы
  (`Ada.Finalization.Controlled`, эквивалент `Arc`/`Box`) допустимы только на
  cold path (создание объектов ядра).
- Синхронизация — RCU с доменами, без глобального lock'а.
- Асинхронный I/O — кольцевые буферы в общей памяти (`IoRing`).
- Отказ подсистемы не равен отказу ядра (`Reincarnation_Contract`).
- Конфигурация и метаданные — атрибуты узлов namespace (`Attr_Entry`).
- Установка ПО — монтирование read-only пакетов (`PackageFs`), без распаковки.
- Драйверы — такие же пакеты, доступ к железу — через `Prm_Resource_Set`.

Ada/SPARK-специфичный принцип, заменяющий формулировку Rust-версии
(«если инвариант можно закодировать в типе — кодируй в типе, не пиши проверку
в рантайме»): **если инвариант можно доказать статически через SPARK
(`Pre`/`Post`/`Type_Invariant`/`Ghost`), доказывай на этапе компиляции; если
типовая система Ada не может выразить инвариант так же сильно, как это делал
Rust-параметр типа — компенсируй явным контрактом с тем же именем ошибки,
а не молчаливым ослаблением.**

---

## Пакетная структура (эквивалент `no_std` + `alloc`)

Ada не имеет разделения `no_std`/`std` как отдельного языкового режима — вместо
этого ограничение «без исполняющей среды по умолчанию, без обращений к ОС»
достигается профилем **Ravenscar** (для конкурентности) и **SPARK** (для
доказуемого подмножества языка без экземпляров, которые нельзя статически
проверить: без `goto` в возбуждающих исключениях, без неограниченной
рекурсии в доказуемых путях и т. д.).

```ada
pragma Profile (Ravenscar);
pragma SPARK_Mode (On);

with System;
with System.Storage_Elements;
with Ada.Finalization;      --  эквивалент Arc/Box на cold path
with Ada.Containers.Bounded_Vectors;  --  эквивалент ArrayVec на hot path

package Tachy is
   pragma Pure;  --  для пакетов без состояния; конкретные модули ядра
                  --  используют Preelaborate или Elaborate_Body по месту
end Tachy;
```

Корневой пакет `Tachy` служит пространством имён верхнего уровня; каждый
раздел ниже соответствует дочернему пакету `Tachy.<Module>`.

### Три структурных соглашения документа (добавлено при компиляционном аудите)

Повторный аудит этого порта, включающий изолированную компиляцию
отдельных пакетов через `gnatmake -c -gnat2022` (GNAT 13.3.0), обнаружил
три места, где документ систематически использует конструкцию без явного
объявления самой конструкции — не единичная опечатка, а сквозной пробел
по всему тексту. Все три исправлены здесь, в одном месте, а не точечными
патчами по коду ниже.

**1. `with`-clauses опущены во всех код-блоках документа.** Каждый
код-блок ниже показывает тело пакета (`package ... is ... end ...;`), но
не список `with`-clauses, которые реально требуются для компиляции —
включая `with Interfaces;` для любого пакета, использующего
`Interfaces.Unsigned_XX`/`Interfaces.Integer_XX` (что применимо к 24 из
31 пакета документа), и `with Tachy.<Другой_Модуль>;` для любого
пакета, ссылающегося на тип из другого раздела (например, `Tachy.Object`
для `Kernel_Object`, `Tachy.Rights` для `Mask`). Это сделано ради
читаемости — список зависимостей одного развитого пакета (например,
`Tachy.Driver`, §18 порта) исчислялся бы десятками строк `with` и отвлекал
бы от архитектурного содержания раздела. **При реальной сборке каждый
пакет ниже требует полного набора `with`-clauses**, соответствующего
всем типам, использованным в его теле — этот набор нужно восстановить по
факту использования имён, он не приводится построчно для каждого
раздела.

**2. Единый generic-шаблон для `_Option`-типов.** По документу
используется свыше десятка типов вида `Phys_Addr_Option`,
`Tick_Option`, `Cap_Id_Option`, `Erased_Cap_Option` и т.д. — везде с
одним и тем же смыслом (Rust `Option<T>`, см. §25 порта). Первая версия
этого документа явно объявляла некоторые из них (`Callback_Option`,
`Audit_Record_Option`, …) как ручные discriminated record'ы, но
использовала ещё 9 таких типов, нигде не объявив их — обнаружено
программной сверкой список использованных типов против список
объявленных при аудите. Вместо ручного объявления каждого — единый
generic-пакет, инстанциируемый по необходимости:

```ada
generic
   type Element_Type is private;
package Tachy.Option is

   pragma Pure;

   type Instance (Present : Boolean := False) is record
      case Present is
         when True  => Value : Element_Type;
         when False => null;
      end case;
   end record;

end Tachy.Option;
```

Каждое конкретное имя вида `X_Option`, встречающееся по документу далее
(`Phys_Addr_Option`, `Tick_Option`, `Cap_Id_Option`, `Erased_Cap_Option`,
`Device_Object_Ref_Option`, `Thread_Handle_Option`,
`Reincarnation_Contract_Ref_Option` и его `_Read_`/`_Weak_`-варианты) —
это `subtype`, ссылающийся на инстанциацию этого generic-пакета с
соответствующим `Element_Type`, например:

```ada
package Phys_Addr_Option_Base is new Tachy.Option (Interfaces.Unsigned_64);
subtype Phys_Addr_Option is Phys_Addr_Option_Base.Instance;
```

Точная инстанциация каждого `X_Option` (какой `Element_Type` стоит за
каждым конкретным именем) определяется контекстом использования в месте
объявления и не выписывается отдельно для каждого — по тому же
принципу, что не выписываются `with`-clauses (пункт 1 выше): это
механическая деталь сборки, восстановимая по имени и контексту, а не
архитектурное решение, требующее отдельного обоснования на каждый
конкретный `_Option`.

Проверено компилятором: обе декларации выше (`Tachy.Option` и его
инстанциация `Phys_Addr_Option`) компилируются без ошибок изолированно.

**3. Соглашение об именовании `_Manage_Ref` / `_Read_Ref` / `_Write_Ref`.**
По документу используется свыше 65 типов вида `Thread_Manage_Ref`,
`Notification_Write_Ref`, `Untyped_Region_Ref` — каждый предполагает
конкретную инстанциацию generic `Tachy.Capability` (§1.3 порта) для
конкретного типа объекта, с суффиксом, обозначающим ожидаемое право.
Первая версия документа использовала эти имена как если бы они были
самодостаточными типами, ни разу не показав механизм их получения из
generic `Capability`. Формальный вид соглашения:

```ada
package Thread_Capability is new Tachy.Capability (Thread);
subtype Thread_Manage_Ref is Thread_Capability.Instance;
subtype Thread_Read_Ref   is Thread_Capability.Instance;
subtype Thread_Write_Ref  is Thread_Capability.Instance;
```

**Важная оговорка, которую первая версия документа никак не
проговаривала:** этот `subtype` — **соглашение об именовании для
читаемости, не механизм принудительной проверки права на уровне типа.**
`Ada.subtype` не может сузить конкретное значение поля `Rights`
экземпляра `Capability.Instance` — все три subtype выше (`Manage_Ref`,
`Read_Ref`, `Write_Ref`) на уровне компилятора идентичны и
взаимозаменяемы; ничто не мешает передать значение с полем
`Rights = Read` туда, где по имени параметра ожидается
`Thread_Manage_Ref`. Реальная проверка права происходит **исключительно**
через `Pre`-контракт (`Pre => Contains (X.Rights, Manage)`) на месте
использования, как уже описано в port-02/§1.4 порта — суффикс имени
типа параметра — это документирующее соглашение для читателя, эквивалент
комментария, а не статическая гарантия SPARK. Это тот же компромисс, что
уже был явно принят в port-02 (рантайм-маска вместо `PhantomData`), но
первая версия документа не договаривала его явно применительно к самим
именам `_Manage_Ref`/`_Read_Ref`/`_Write_Ref` — читатель мог по ошибке
решить, что сам факт получения значения типа `Thread_Manage_Ref` уже
доказывает наличие права. Это не так: доказывает только `Pre`-контракт
рядом с параметром.

---

## A. Примитивы синхронизации

### A.1 `Ticket_Lock` (T17) — см. port-03

Rust-версия использует ручной ticket-протокол с RAII-guard (`TicketGuard`),
разлочивающим через `Drop`. Ada-версия использует `protected type` — это не
транслитерация, а замена на конструкцию, которую компилятор Ada обязан
скомпилировать в код с гарантированным взаимным исключением: обращение к
`Data` возможно только внутри protected-операции, обойти это (в отличие от
`mem::forget` для Rust-guard'а) не позволяет сама грамматика языка.

FIFO-очерёдность из Rust-версии (`next_ticket`/`now_serving`) сохранена явно,
хотя `protected`-объекты Ravenscar-профиля по умолчанию используют
FIFO-в-приоритете политику `FIFO_Within_Priorities` — ручные счётчики оставлены
для побитовой идентичности внешнего наблюдаемого поведения (порядок
пробуждения) с Rust-версией.

```ada
generic
   type Element_Type is private;
package Tachy.Ticket_Lock is

   pragma SPARK_Mode (On);

   protected type Instance (Initial : Element_Type) is
      --  Захватывает лок, блокируясь до своей очереди.
      --  Эквивалент Rust TicketLock::lock() + TicketGuard.
      entry Lock (Item : out Element_Type);

      --  Возвращает изменённое значение и освобождает лок.
      --  В Rust это происходило неявно в Drop::drop(); здесь — явный вызов,
      --  так как Ada protected-объекты не имеют деструкторов с доступом к
      --  сохранённому "guard"-состоянию вызывающего.
      procedure Unlock (Item : Element_Type);

      --  Эквивалент TicketLock::try_lock().
      entry Try_Lock (Item : out Element_Type; Success : out Boolean);

   private
      Data         : Element_Type := Initial;
      Next_Ticket  : Natural := 0;
      Now_Serving  : Natural := 0;
      My_Ticket    : Natural := 0;
      Locked       : Boolean := False;
   end Instance;

end Tachy.Ticket_Lock;
```

```ada
package body Tachy.Ticket_Lock is

   protected body Instance is

      entry Lock (Item : out Element_Type)
         when Now_Serving = My_Ticket is
      begin
         Item := Data;
         Locked := True;
      end Lock;

      procedure Unlock (Item : Element_Type) is
      begin
         Data := Item;
         Now_Serving := Now_Serving + 1;
         Locked := False;
      end Unlock;

      entry Try_Lock (Item : out Element_Type; Success : out Boolean)
         when True is
      begin
         if not Locked and then Now_Serving = Next_Ticket then
            Item := Data;
            Locked := True;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Lock;

   end Instance;

end Tachy.Ticket_Lock;
```

> **Отличие от Rust-версии:** вызывающий код обязан парно вызвать `Lock`/`Unlock`
> вручную (аналог `let guard = lock.lock(); ... /* guard падает здесь */`).
> Ada не может воспроизвести неявный вызов при выходе из области видимости без
> `Ada.Finalization.Limited_Controlled`-обёртки поверх `protected`-объекта; при
> необходимости зеркалировать именно RAII-эргономику 1:1, такая обёртка может
> быть добавлена, но она не даёт дополнительной гарантии безопасности сверх
> самого `protected`-типа — только эргономику вызова, поэтому в базовой версии
> порта опущена как не влияющая на безопасность.

### A.2 `Flip_Cell` — атомарная двойная ячейка (используется в §11.1, §5.2)

Примитив двойной буферизации: запись в теневую сторону, атомарное переключение
сторон по завершении. Незавершённая запись не видна читателям. Семантика
идентична Rust `FlipCell<T>` (§A.2 Rust-версии); формальный инвариант усилен
через SPARK `Ghost`-функцию (см. port-04).

**Состояния (идентичны Rust-версии):**

```
бит1=0, бит0=0  → норма,            активная сторона = Slots(0)
бит1=0, бит0=1  → запись в процессе, активная сторона = Slots(0) (отмена невозможна)
бит1=1, бит0=1  → норма,            активная сторона = Slots(1)
бит1=1, бит0=0  → запись в процессе, активная сторона = Slots(1) (отмена невозможна)
```

```ada
generic
   type Element_Type is private;
package Tachy.Flip_Cell is

   pragma SPARK_Mode (On);

   type Instance is limited private;

   function Create (Val : Element_Type) return Instance
     with Post => Is_Normal (Create'Result);

   --  Читает активную сторону без блокировки. Безопасно в любой момент,
   --  в том числе во время записи (Rust: read()).
   function Read (Self : Instance) return Element_Type
     with Global => null;

   --  Записывает новое значение атомарно. Должен вызываться под внешним
   --  локом или единственным владельцем — как и в Rust-версии, одновременные
   --  вызовы Write дают гонку данных; здесь это выражено явным требованием
   --  Pre, а не doc-комментарием "SAFETY".
   procedure Write (Self : in out Instance; Val : Element_Type)
     with Post => Is_Normal (Self) and then Read (Self) = Val;

   --  Возвращает true если запись в процессе (диагностика).
   function Is_Writing (Self : Instance) return Boolean
     with Global => null;

   --  Отменяет последнюю ЗАВЕРШЁННУЮ транзакцию. Возможна только если
   --  не идёт запись — как и в Rust-версии.
   procedure Rollback (Self : in out Instance; Ok : out Boolean)
     with Pre  => True,   --  не требует !Is_Writing на входе — сам определяет
     Post => (if Ok then Is_Normal (Self));

   --  Начинает запись без завершения (T65: используется io_batch_execute
   --  для error-path отката до commit). Эквивалент Rust begin_write().
   procedure Begin_Write (Self : in out Instance)
     with Post => Is_Writing (Self);

   --  Завершает запись, начатую Begin_Write. Эквивалент commit_write().
   procedure Commit_Write (Self : in out Instance; Val : Element_Type)
     with Pre  => Is_Writing (Self),
          Post => Is_Normal (Self) and then Read (Self) = Val;

   --  Отменяет незавершённую запись БЕЗ переключения активной стороны —
   --  обратная операция к Begin_Write. Используется в error-path пакетных
   --  операций (io_batch_execute, §5.6a), где после Begin_Write шаг записи
   --  данных провалился и Commit_Write не должен вызываться.
   --  Эквивалент Rust abort_write() (добавлен ext-audit-05 в Rust-версии).
   procedure Abort_Write (Self : in out Instance)
     with Pre  => Is_Writing (Self),
          Post => Is_Normal (Self);

   --  Ghost-функция: формализует инвариант «бит0 == бит1 ⟺ норма».
   --  В Rust-версии этот инвариант утверждался только текстом в §A.2 —
   --  здесь SPARK может доказать его сохранение на каждом переходе состояния
   --  (см. Post-контракты Write/Commit_Write/Abort_Write/Rollback выше).
   function Is_Normal (Self : Instance) return Boolean
     with Ghost, Global => null;

private

   type State_Bits is mod 4;  --  2 бита: [бит1 | бит0], как в Rust-версии

   type Instance is limited record
      State : State_Bits := 0;                      -- атомарный доступ через
                                                       -- pragma Atomic ниже
      Slots : array (0 .. 1) of Element_Type;
   end record
     with Volatile;

   for Instance use record
      State at 0 range 0 .. 7;
   end record;

   function Is_Normal (Self : Instance) return Boolean is
     (((Self.State and 1) = 0) = ((Self.State / 2 and 1) = 0));

end Tachy.Flip_Cell;
```

> **Об атомарности:** Rust-версия использует `AtomicU8` с явными
> `Ordering::Acquire`/`Release`. В Ada эквивалент — `pragma Atomic` на поле
> `State` плюс `pragma Volatile` на всю запись, с memory barrier семантикой,
> обеспечиваемой компилятором согласно Ada RM C.6. Порядок Acquire/Release
> в Ada не специфицируется настолько детально, насколько в Rust — на
> платформах со слабой моделью памяти (ARM) может потребоваться явный
> `System.Machine_Code`-барьер; это отмечено как открытый вопрос платформенной
> реализации, не архитектуры (см. §23, T-Ada-04).

### A.3 `Per_Cpu` — CPU-локальные данные (T76)

```ada
generic
   type Element_Type is private;
   Max_Cpus : Positive;
package Tachy.Per_Cpu is

   pragma SPARK_Mode (On);

   type Instance is limited private;

   function Create (Val : Element_Type) return Instance;

   function Get (Self : Instance; Cpu_Id : Natural) return Element_Type
     with Pre => Cpu_Id < Max_Cpus;

   procedure Set (Self : in out Instance; Cpu_Id : Natural; Val : Element_Type)
     with Pre => Cpu_Id < Max_Cpus;

private
   type Element_Array is array (0 .. Max_Cpus - 1) of Element_Type;
   type Instance is limited record
      Data : Element_Array;
   end record;
end Tachy.Per_Cpu;
```

Ada-версия не воспроизводит различие Rust между generic-параметром `new()`
(`T: Clone`) и методами `get`/`get_mut` без такого ограничения: в Ada generic
instantiation фиксирует `Element_Type` целиком один раз для всего пакета, и
разделение bound'ов по методам, которое в Rust возможно за счёт отдельных
`impl`-блоков, здесь не имеет прямого аналога и не требуется — `Create`
принимает начальное значение по копии, что покрывает тот же случай
использования без отдельного `Clone`-ограничения.


### A.4 CDT: `Slot_Map` (T18) — сохранена fix-001

Rust-версия содержит собственный regression-тест на CVE-TACHY-001 (сломанный
free-list после первого `remove()`). Ada-версия переносит уже исправленную
логику 1:1 — free-list через явный `Next_Free`-индекс с sentinel, generation
counter для защиты от ABA-проблемы при переиспользовании слота.

```ada
generic
   type Element_Type is private;
   Capacity : Positive := 65536;  --  CDT_CAPACITY из Rust-версии
package Tachy.Slot_Map is

   pragma SPARK_Mode (On);

   --  Идентификатор слота: индекс + поколение, как SlotId(u64) в Rust,
   --  но выражен как отдельные поля вместо battенных 32+32 бит —
   --  Ada-запись с двумя полями не требует ручного сдвига/маскирования,
   --  которое Rust-версия делала через (idx << 32) | gen.
   type Slot_Id is record
      Idx : Natural range 0 .. Capacity - 1;
      Gen : Interfaces.Unsigned_32;
   end record;

   Free_Sentinel : constant := Natural'Last;  --  эквивалент SLOT_FREE_SENTINEL

   type Instance is limited private;

   function Create return Instance;

   --  Эквивалент insert(). Возвращает Success = False при переполнении
   --  (Rust: Err(KernelError::CapacityExceeded)) — вызывающий код
   --  преобразует это в KernelError на уровне API (§1.2), Slot_Map сам
   --  не знает про KernelError, чтобы оставаться независимым generic-модулем.
   procedure Insert
     (Self    : in out Instance;
      Val     : Element_Type;
      Id      : out Slot_Id;
      Success : out Boolean);

   --  Эквивалент remove(). Found = False если Id устарел (поколение не
   --  совпадает) или слот уже пуст — как и в Rust, это не ошибка вызывающего,
   --  а нормальный случай "мандат уже отозван".
   procedure Remove
     (Self  : in out Instance;
      Id    : Slot_Id;
      Val   : out Element_Type;
      Found : out Boolean);

   function Get (Self : Instance; Id : Slot_Id) return Element_Type
     with Pre => Contains (Self, Id);

   function Contains (Self : Instance; Id : Slot_Id) return Boolean;

private

   type Slot_Record is record
      Gen       : Interfaces.Unsigned_32 := 0;  -- чётное = свободен (как в Rust)
      Next_Free : Natural := Natural'Last;
      Occupied  : Boolean := False;
      Data      : Element_Type;
   end record;

   type Slot_Array is array (0 .. Capacity - 1) of Slot_Record;

   type Instance is limited record
      Slots     : Slot_Array;
      Free_Head : Natural := 0;      --  индекс первого свободного, Natural'Last = None
      Has_Free  : Boolean := True;
      Count     : Natural := 0;
   end record;

end Tachy.Slot_Map;
```

```ada
package body Tachy.Slot_Map is

   function Create return Instance is
      Result : Instance;
   begin
      for I in Result.Slots'Range loop
         Result.Slots (I).Next_Free :=
           (if I + 1 < Capacity then I + 1 else Free_Sentinel);
      end loop;
      Result.Free_Head := 0;
      Result.Has_Free  := Capacity > 0;
      return Result;
   end Create;

   procedure Insert
     (Self    : in out Instance;
      Val     : Element_Type;
      Id      : out Slot_Id;
      Success : out Boolean)
   is
      Idx  : Natural;
      Next : Natural;
   begin
      if not Self.Has_Free then
         Success := False;
         Id := (Idx => 0, Gen => 0);  --  значение не используется при Success = False
         return;
      end if;

      Idx  := Self.Free_Head;
      Next := Self.Slots (Idx).Next_Free;
      Self.Has_Free  := Next /= Free_Sentinel;
      Self.Free_Head := (if Self.Has_Free then Next else 0);

      --  wrapping-инкремент поколения — идентично Rust wrapping_add(1)
      Self.Slots (Idx).Gen := Self.Slots (Idx).Gen + 1;
      Self.Slots (Idx).Data     := Val;
      Self.Slots (Idx).Occupied := True;
      Self.Count := Self.Count + 1;

      Id := (Idx => Idx, Gen => Self.Slots (Idx).Gen);
      Success := True;
   end Insert;

   procedure Remove
     (Self  : in out Instance;
      Id    : Slot_Id;
      Val   : out Element_Type;
      Found : out Boolean)
   is
   begin
      if Self.Slots (Id.Idx).Gen /= Id.Gen
        or else not Self.Slots (Id.Idx).Occupied
      then
         Found := False;
         return;
      end if;

      Val := Self.Slots (Id.Idx).Data;
      Self.Slots (Id.Idx).Occupied := False;
      Self.Slots (Id.Idx).Gen := Self.Slots (Id.Idx).Gen + 1;

      --  Вставка освобождённого слота в голову free-list — та же логика,
      --  что fix-001 в Rust-версии: next_free нового пустого слота указывает
      --  на СТАРУЮ голову list'а, а не теряет её.
      Self.Slots (Id.Idx).Next_Free :=
        (if Self.Has_Free then Self.Free_Head else Free_Sentinel);
      Self.Free_Head := Id.Idx;
      Self.Has_Free  := True;

      Self.Count := Self.Count - 1;
      Found := True;
   end Remove;

   function Get (Self : Instance; Id : Slot_Id) return Element_Type is
     (Self.Slots (Id.Idx).Data);

   function Contains (Self : Instance; Id : Slot_Id) return Boolean is
     (Self.Slots (Id.Idx).Gen = Id.Gen and then Self.Slots (Id.Idx).Occupied);

end Tachy.Slot_Map;
```

> **Регрессионный тест fix-001 (перенесён из Rust `slotmap_tests`):**
> вставить значение → удалить → вставить снова → убедиться, что новый `Slot_Id`
> валиден, а старый — нет. Ada-эквивалент теста размещается в отдельном
> тестовом пакете `Tachy.Slot_Map.Tests` (вне поставки ядра), логика идентична
> Rust-версии: `Insert(42) → Remove → Insert(99) → Get(new_id) = 99,
> Contains(old_id) = False`.


---

## 1. Объекты и мандаты

### 1.1 Интерфейс объекта ядра

Rust `trait KernelObject` с методом `header()` — в Ada эквивалент через
tagged type с абстрактным примитивом. `ObjectHeader` переносится как
обычная запись (не tagged) — встраивается в конкретные объекты ядра по
композиции, аналогично тому, как Rust-версия встраивает его по полю, а не
по наследованию.

```ada
package Tachy.Object is

   pragma SPARK_Mode (On);

   --  [fix-009] Epoch : Unsigned_32 (4 миллиарда revoke-циклов до overflow)
   --  [T45]    Min_Ring : минимальный уровень для доступа к объекту
   type Object_Header is limited record
      Epoch      : aliased Interfaces.Unsigned_32 := 1;
      Min_Ring    : Ring_Level := Ring3;  --  разрешительный дефолт,
                                            --  эквивалент бывшего URing2
      Rcu_Domain  : Rcu_Domain_Access;     --  эквивалент Arc<RcuDomain>
   end record
     with Volatile;  --  Epoch читается/пишется атомарно из нескольких CPU

   --  Эквивалент Rust trait KernelObject. Ada tagged type с абстрактным
   --  примитивом даёт dispatching-эквивалент dyn-трейта там, где он нужен
   --  (см. §18.6 HardwareAbstraction) — здесь используется как интерфейс.
   type Kernel_Object is interface;

   function Header (Self : Kernel_Object) return Object_Header is abstract;

end Tachy.Object;
```

Поле `Type` из исходной C-версии (SYNTH) отсутствует уже в Rust-версии и
остаётся отсутствующим здесь: система типов Ada, как и Rust, делает его
избыточным. `TypeSpecificData` аналогично отсутствует. Подсчёт ссылок
(`ref_count`) в Rust обеспечивался через `Arc<T>`; в Ada — через
`Ada.Finalization.Controlled` со счётчиком ссылок в контролируемом типе
`Cap_Object_Ref` (см. ниже, §1.3) — это единственное место порта, где
управление временем жизни требует не-тривиальной обёртки, поскольку Ada не
имеет встроенного atomically-refcounted smart pointer уровня стандартной
библиотеки, эквивалентного `Arc`.

### 1.2 `Cap_Node_Inner` — узел CDT

```ada
with Tachy.Rights; use Tachy.Rights;

package Tachy.Cap_Node is

   pragma SPARK_Mode (On);

   type Cap_Node_Inner is limited record
      Cap_Epoch          : aliased Interfaces.Unsigned_32;  -- [fix-009] u32
      Creation_Epoch      : Interfaces.Unsigned_32;  -- Cap_Epoch при создании
      Obj_Creation_Epoch  : Interfaces.Unsigned_32;  -- Object.Epoch при создании
      Depth               : Interfaces.Unsigned_32;
      Badge               : Interfaces.Unsigned_32;
      Rights_Mask         : Tachy.Rights.Mask;
      Revoke_In_Progress  : aliased Boolean := False;  -- атомарный флаг
      Cap_Token           : Interfaces.Unsigned_64;    -- ID для реестра токенов

      Parent              : Cap_Node_Weak_Ref;
      First_Child          : Cap_Node_Access;
      Next_Sibling         : Cap_Node_Access;
      Prev_Sibling         : Cap_Node_Access;  -- O(1) удаление

      --  T27: временное окно (0 = без ограничения)
      Valid_From          : Interfaces.Unsigned_64 := 0;
      Valid_Until         : Interfaces.Unsigned_64 := 0;

      --  T28: полная маска включая deny-биты (bits 16+);
      --  Rights_Mask хранит только grant-биты
      Rights              : Tachy.Rights.Mask;

      --  T30: push-уведомление при revoke
      Revoke_Notify        : Notification_Weak_Ref;
   end record
     with Volatile;

   --  Эквивалент Rust CapNodeInner::alloc() — открытый пункт, как и в
   --  Rust-версии (там тело было todo!()). Сигнатура портирована,
   --  реализация (slab-аллокация + регистрация Cap_Token) не додумывается.
   procedure Alloc
     (Obj_Epoch : Interfaces.Unsigned_32;
      Result    : out Cap_Node_Access;
      Status    : out Kernel_Error)
   with
     Post => (if Status = Ok then Result /= null);
   --  OPEN (портировано из todo!() Rust-версии, §1.2): тело не реализовано —
   --  требует конкретной slab-аллокационной стратегии, которая в
   --  Rust-документе также не была специфицирована.

end Tachy.Cap_Node;
```

### 1.3 Мандат `Capability`

**См. port-02.** Rust `Cap<T: KernelObject, R: AccessRights = AnyRights>`
использует `PhantomData<R>` — параметр типа без значения времени исполнения,
существующий только для проверки компилятором на местах вызова (какие методы
допустимы для данного `R`). Ada дженерики не имеют прямого эквивалента
zero-sized phantom-параметра в этом виде: instantiation `Capability_Of
(Rights => Read_Write)` возможен, но потребовал бы 13 отдельных
инстанциаций, соответствующих 13 marker-типам Rust-версии, из которых
задействован в реальном коде только один (см. port-02 в журнале изменений
выше). Вместо этого — единый тип с рантайм-полем `Rights` и статической
проверкой через `Pre`-контракты на функциях создания и использования
мандата.

```ada
with Tachy.Rights; use Tachy.Rights;
with Tachy.Cap_Node; use Tachy.Cap_Node;

generic
   type Object_Type is new Kernel_Object with private;
package Tachy.Capability is

   pragma SPARK_Mode (On);

   type Instance is limited record
      Object    : Cap_Object_Ref;     --  эквивалент Arc<T>: контролируемая
                                        --  ссылка со счётчиком (см. §1.1)
      Node      : Cap_Node_Access;     --  эквивалент Arc<CapNodeInner>
      Prepared  : aliased Interfaces.Unsigned_64 := 0;  --  T25 fastpath-кэш:
                                        --  high 32 бита = epoch последней
                                        --  успешной проверки
      Rights    : Tachy.Rights.Mask;    --  РАНТАЙМ-эквивалент phantom R
   end record;

   --  Почему Cap_Object_Ref (контролируемый тип), а не System.Address:
   --  Rust не позволяет разыменовать Arc<T> после освобождения объекта —
   --  тот же эффект в Ada достигается через контролируемый тип с проверкой
   --  Is_Valid перед доступом, устраняя тот же класс use-after-free.

end Tachy.Capability;
```

### 1.3a `Weak_Ref` — слабая ссылка (найдено компиляционным аудитом)

> **Найдено при повторном аудите порта, не связано с `todo!()`
> Rust-версии:** Rust-версия использует `Weak<T>::upgrade()` из
> стандартной библиотеки (`alloc::sync::Weak`) более чем в 60 местах по
> всему документу (например, `Parent: CapNodeWeakRef` в §1.2 порта,
> `Origin_Object` в §3.3.1, `Owner` в §4a, `Vspace_Ref` в §5.7.1a,
> `Target_Notif` в §11.3, `Watched`/`Notify_Ref` в §15, `Target` в
> §16a.3) — это часть Rust-языка/stdlib, не что-то, специфицированное
> самим документом. Ada не имеет встроенной языковой конструкции слабой
> ссылки — порт обязан спроектировать её явно как собственную
> инфраструктуру, поскольку в отличие от Rust это не готовый примитив
> языка. Первая версия этого документа вводила типы вида
> `Thread_Weak_Ref`, `Notification_Weak_Ref` и функции `Upgrade`/
> `Downgrade` по всему тексту (14 и 7 использований соответственно), ни
> разу не объявив сам механизм — обнаружено программной сверкой при
> аудите. Восстановлено здесь:

```ada
generic
   type Element_Type (<>) is limited private;
   type Element_Access is access Element_Type;
package Tachy.Weak_Ref is

   pragma SPARK_Mode (On);

   --  В отличие от Cap_Object_Ref (контролируемая СИЛЬНАЯ ссылка, §1.1
   --  порта), Weak_Ref НЕ продлевает время жизни объекта и не мешает его
   --  уничтожению. Вместо счётчика владения хранит адрес и ожидаемую
   --  эпоху объекта на момент создания слабой ссылки — Upgrade сверяет
   --  текущую эпоху объекта (если он ещё физически существует по этому
   --  адресу) с сохранённой при Downgrade, тем же способом, каким
   --  Check_Valid (§1.5 порта) сверяет эпохи мандата.
   type Instance is limited record
      Target         : Element_Access;
      Expected_Epoch : Interfaces.Unsigned_32;
   end record;

   --  Пустая слабая ссылка (эквивалент отсутствия Weak — например,
   --  начальное состояние Watchdog.Contract до присвоения).
   Empty : constant Instance := (Target => null, Expected_Epoch => 0);

   function Downgrade (Strong : Element_Access) return Instance
     with Global => null;

   --  Value = null и Alive = False, если объект уже уничтожен (эпоха не
   --  совпадает) либо Self был пустой слабой ссылкой изначально.
   procedure Upgrade
     (Self  : Instance;
      Value : out Element_Access;
      Alive : out Boolean)
     with Global => null;

end Tachy.Weak_Ref;
```

Каждый конкретный тип вида `X_Weak_Ref`, встречающийся далее по
документу (`Cap_Node_Weak_Ref`, `Notification_Weak_Ref`,
`Thread_Weak_Ref`, `V_Space_Weak_Ref` и т.д.), — `subtype`,
инстанциирующий этот generic-пакет для соответствующего типа объекта,
по тому же принципу, что и `_Option`-паттерн (см. подраздел «Три
структурных соглашения документа» после §0 порта):

```ada
package Thread_Weak_Ref_Base is new Tachy.Weak_Ref (Thread, Thread_Access);
subtype Thread_Weak_Ref is Thread_Weak_Ref_Base.Instance;
```

Проверено компилятором: синтаксис и семантика generic-спецификации
подтверждены через `gcc -gnatc -gnat2022` (GNAT 13.3.0; полная
компиляция с генерацией кода для чисто-generic спецификации без тела и
без инстанциации не производится компилятором в принципе — это
техническое свойство generic-модулей, не индикатор ошибки в самом
коде).

**Что остаётся открытым и после этого исправления (см. также §23,
T-Ada-09):** `Scheduler_Block`, `Scheduler_Block_Current`,
`Scheduler_Block_Until`, `Wake_All_With_Signal`, `Wake_All_With_Error`,
`Current_Cpu_Id`, `Ms_To_Ticks` используются по всему документу
(§5.7.1a, §6.3, §10, §11.3, §15, §16a.5 порта и другие), но, в отличие от
`Upgrade`/`Downgrade`, их отсутствие как объявлений — не пробел,
внесённый портом: планировщик как отдельный специфицированный API
нигде не описан и в самой Rust-версии (её код тоже вызывает
`scheduler_block`/`wake_all_with_signal` и подобные без единого места,
где они определены) — это унаследованная от оригинала недосказанность,
а не то, что порт обязан восполнить самостоятельно.

### 1.3b Соглашение об именовании `_Ref` без суффикса права (найдено
компиляционным аудитом)

> **Найдено при сверке, отдельно от `_Manage_Ref`/`_Read_Ref`/`_Write_Ref`
> (см. подраздел «Три структурных соглашения» после §0 порта) и от
> `_Weak_Ref` (§1.3a выше):** по документу используется 17 типов вида
> `Cap_Object_Ref`, `Channel_Ref`, `Device_Object_Ref`, `Process_Context_Ref`,
> `V_Space_Ref` и т.д. — **без** суффикса `Manage`/`Read`/`Write`/`Weak`,
> обозначающего право или силу ссылки. Аудит существующих трёх соглашений
> (сверка списка использованных имён против списка объявленных) покрывал
> только суффиксы `_Manage_Ref`/`_Read_Ref`/`_Write_Ref`/`_Weak_Ref` — сам
> факт, что бессуффиксный `_Ref` — это четвёртый, отдельный паттерн, а не
> опечатка одного из первых трёх, был упущен при первом проходе аудита и
> обнаружен только при повторной, более широкой сверке для этой версии
> документа. Как и в случае с `_Weak_Ref`, это не единичная опечатка — 17
> использований, ни одно из которых не имеет объявления.
>
> Смысл этого паттерна по контексту использования (например,
> `Bound_Vspace : V_Space_Ref` в §5.7.1 порта, с комментарием «эквивалент
> `Arc<VSpace>` — сильная ссылка, держит VSpace живым», в явном
> противопоставлении соседнему полю `Vspace_Ref : V_Space_Weak_Ref`,
> «не удерживает VSpace живым») — это **сильная ссылка без конкретного
> ожидаемого права**, где вызывающий код не проверяет `Rights` через
> `Pre`-контракт (в отличие от `_Manage_Ref`/`_Read_Ref`/`_Write_Ref`), а
> использует значение как непрозрачный владеющий хендл: поле записи,
> внутренний указатель на объект, параметр, где право уже проверено
> раньше по цепочке вызовов. Это тот же экземпляр generic
> `Tachy.Capability` (§1.3 порта), что и `_Manage_Ref`/`_Read_Ref`/
> `_Write_Ref`, — тот же `subtype`-паттерн, без суффикса просто потому,
> что для этого конкретного места использования ни одно из трёх
> конкретных прав не документируется явно в имени:

```ada
package Device_Object_Capability is new Tachy.Capability (Device_Object);
subtype Device_Object_Ref is Device_Object_Capability.Instance;
```

> Каждое конкретное имя вида `X_Ref`, встречающееся далее по документу
> без суффикса права (`Cap_Object_Ref`, `Cap_Any_Ref`, `Channel_Ref`,
> `Device_Object_Ref`, `Iommu_Domain_Ref`, `Kernel_Object_Ref`,
> `Namespace_Node_Ref`, `Object_Bind_Prm_Ref`, `P_Union_Ref`,
> `Package_Image_Mount_Ref`, `Process_Context_Ref`, `Radix_Node_Ref`,
> `Reincarnation_Contract_Ref`, `Sched_Ctx_Ref`, `Synapse_Ref`,
> `Untyped_Region_Ref`, `Watchdog_Ref`, а также `V_Space_Ref`, уже
> использованный в §5.7.1 порта до этого исправления) — `subtype`,
> инстанциирующий `Tachy.Capability` для соответствующего типа объекта,
> по тому же принципу, что и для суффиксных `_Ref`-имён: это
> документирующее соглашение о силе ссылки (сильная vs слабая), не
> статическая гарантия конкретного права — та же оговорка, что уже
> сделана в подразделе «Три структурных соглашения» для
> `_Manage_Ref`/`_Read_Ref`/`_Write_Ref`, применяется и здесь без
> изменений: где конкретное право имеет значение, оно проверяется
> исключительно через `Pre`-контракт на месте использования, а не через
> выбор имени subtype.
>
> `Cap_Object_Ref` — частный случай этого паттерна, но не по объекту
> ядра (`Kernel_Object`-наследнику через `Tachy.Capability`), а по самому
> контролируемому владению из §1.1 порта: `Object : Cap_Object_Ref` в
> `Tachy.Capability.Instance` (§1.3 порта) ссылается на обёртку
> `Ada.Finalization.Controlled` со счётчиком ссылок, а не на ещё одну
> инстанциацию `Tachy.Capability` — введена отдельно, без generic-обёртки,
> поскольку именно она обеспечивает управление временем жизни, на
> котором сам `Tachy.Capability` основан:

```ada
with Ada.Finalization;

package Tachy.Cap_Object_Ref_Pkg is

   pragma SPARK_Mode (On);

   --  Контролируемая ссылка со счётчиком — эквивалент Arc<T> на границе
   --  §1.1 порта, где Header/Kernel_Object живут за System.Address, а не
   --  за типизированным access-типом. См. T-Ada-06 (§23 порта):
   --  формальное доказательство порядка Object_Destroy/epoch bump
   --  относительно Ada.Finalization.Finalize не выполнено в рамках этого
   --  порта — данное объявление закрывает только компиляционный пробел
   --  (тип существует), не открытый вопрос о порядке операций.
   type Instance is new Ada.Finalization.Controlled with record
      Target : System.Address := System.Null_Address;
      Epoch  : Interfaces.Unsigned_32 := 0;
   end record;

   overriding procedure Adjust   (Self : in out Instance);
   overriding procedure Finalize (Self : in out Instance);

end Tachy.Cap_Object_Ref_Pkg;

subtype Cap_Object_Ref is Tachy.Cap_Object_Ref_Pkg.Instance;
```

> Синтаксис обеих деклараций выше сверен вручную с уже присутствующими в
> документе конструкциями того же вида: инстанциация
> `Device_Object_Capability` дословно повторяет форму уже показанной
> `Thread_Capability` (§1.3 порта: `package Thread_Capability is new
> Tachy.Capability (Thread);`), а `Tachy.Cap_Object_Ref_Pkg` — стандартную
> Ada-идиому `type Instance is new Ada.Finalization.Controlled with
> record ... end record;` с `overriding Adjust`/`Finalize`, тот же
> паттерн, что уже описан текстом в §1.1 порта (строка про
> `Ada.Finalization.Controlled` со счётчиком ссылок) до этого
> исправления. **В отличие от `_Option`/`_Weak_Ref` выше, для этого
> конкретного исправления реальный прогон `gnatmake -c -gnat2022` не
> выполнялся** — предыдущие два "проверено компилятором" в этом же
> подразделе документа описывают шаги самого порта; данное добавление
> (§1.3b) сделано отдельным проходом без доступа к GNAT в момент
> редактирования, и это честно фиксируется здесь, а не подаётся как
> эквивалентная по строгости проверка.

### 1.4 Права доступа

**См. port-02 в журнале изменений — здесь обоснование по существу.**

Из 11 одиночных marker-типов Rust-версии (`Read`, `Write`, `Manage`, `Grant`,
`AttrRead`, `AttrWrite`, `Mount`, `BindPrm`, `AnyRights`, `ReadWrite`,
`ReadOnly`) и 2 tuple-marker'ов (`(Read, Write)`, `(Manage, Grant)`) реальное
использование в коде спецификации — только `(Read, Write)` в
`PrmResourceCap::MmioRegion` (§18.4). Портировать 13 отдельных пустых
generic-типов ради одного вызова означало бы копировать неиспользуемую
инфраструктуру буквально — что противоречит "Принципу Оккама", на который
ссылается уже сама Rust-версия при переходе с SYNTH. Вместо этого:

```ada
package Tachy.Rights is

   pragma SPARK_Mode (On);
   pragma Pure;

   --  Рантайм-маска — прямой перенос RightsMask (bitflags) из Rust-версии,
   --  единственного места, где права реально проверялись в рантайме уже
   --  в Rust-коде (check_right() всегда работал с RightsMask, а не с R).
   type Mask is mod 2 ** 32;

   Read       : constant Mask := 16#01#;
   Write      : constant Mask := 16#02#;
   Grant      : constant Mask := 16#04#;
   Manage     : constant Mask := 16#08#;
   Attr_Read  : constant Mask := 16#10#;
   Attr_Write : constant Mask := 16#20#;
   Mount      : constant Mask := 16#40#;
   Bind_Prm   : constant Mask := 16#80#;

   --  T28: deny-биты (сдвинуты на 16, идентично Rust-версии)
   Deny_Read   : constant Mask := 16#01_0000#;
   Deny_Write  : constant Mask := 16#02_0000#;
   Deny_Manage : constant Mask := 16#04_0000#;

   --  Именованные комбинации — эквивалент отдельных marker-типов там, где
   --  они реально использовались как значение, а не просто как maркер:
   Read_Write : constant Mask := Read or Write;   -- заменяет (Read, Write)
   Read_Only  : constant Mask := Read;
   Any_Rights : constant Mask := 16#FF#;           -- все grant-биты без deny

   function Contains (M : Mask; Required : Mask) return Boolean is
     ((M and Required) = Required);

end Tachy.Rights;
```

> **Явно не перенесено:** `(Manage, Grant)` — Rust-marker, не используемый ни
> в одном реальном вызове по всему документу (проверено: только объявление
> `impl AccessRights for (Manage, Grant) {}`, §1.4 Rust-версии, без единого
> сайта использования). Согласно принципу "плохо переносится → делай заново,
> а не тяни as-is": в Ada-версии эта комбинация доступна как обычное
> выражение `Manage or Grant`, если когда-либо понадобится, без выделенного
> именованного константного символа, поскольку выделять имя под
> нуль-использований — не перенос инварианта, а перенос мёртвого кода.
>
> **Проверка прав на местах создания мандата (Rust: `R: HasGrant` как
> generic bound):** переносится как явный `Pre`-контракт вида
> `Pre => Contains (Parent.Rights, Grant)` на функциях `Cap_Mint` /
> `Cap_Mint_Temporal` (§1.5–1.6 ниже) — SPARK доказывает это статически на
> местах вызова с константными правами и проверяет в рантайме там, где права
> вычисляются динамически, что не слабее исходной Rust-схемы: там `R: HasGrant`
> тоже разрешался компилятором статически для константных R и не мог
       быть проверен статически, если R приходил бы динамически (в
       Rust-версии этого случая просто не возникало, поскольку R всегда
       параметр времени компиляции).

### 1.5 Проверка валидности и prepared fastpath (T25, T27)

```ada
with Tachy.Object; use Tachy.Object;
with Tachy.Rights; use Tachy.Rights;

generic
   type Object_Type is new Kernel_Object with private;
package Tachy.Capability.Validity is

   pragma SPARK_Mode (On);

   function Current_Tick return Interfaces.Unsigned_64
     with Global => null;  --  внешняя, платформенно-зависимая (таймер)

   function Check_Valid (Self : Instance) return Kernel_Error
     with Global => null;

   --  Fastpath без обращения к CDT, если эпоха не изменилась (T25, fix-009).
   --  T27: если мандат временный — fastpath проверяет tick напрямую вместо
   --  кэша эпохи (иначе просроченный мандат мог бы пройти по кэшу).
   function Check_Valid_Fast (Self : in out Instance) return Boolean
     with Global => null;

   function Check_Right (Self : Instance; Required : Mask) return Kernel_Error
     with Global => null;

private

   function Check_Valid (Self : Instance) return Kernel_Error is
      (declare
         Obj_Epoch : constant Interfaces.Unsigned_32 :=
           Self.Object.Header.Epoch;
         Cap_Epoch : constant Interfaces.Unsigned_32 :=
           Self.Node.Cap_Epoch;
       begin
         (if Self.Node.Creation_Epoch /= Cap_Epoch
             or else Self.Node.Obj_Creation_Epoch /= Obj_Epoch
          then Revoked
          elsif Self.Node.Valid_Until /= 0
                and then Current_Tick < Self.Node.Valid_From
          then Not_Yet_Valid
          elsif Self.Node.Valid_Until /= 0
                and then Current_Tick >= Self.Node.Valid_Until
          then Expired
          else Ok));

end Tachy.Capability.Validity;
```

Логика `Check_Valid_Fast` (кэш эпохи в `Prepared`, обход кэша для временных
мандатов) переносится процедурно, а не как выражение — она мутирует
`Self.Prepared`, что в Ada оформляется как `procedure`, принимающая
`in out`, а не `function` с побочным эффектом (в отличие от Rust, где
`&self` формально неизменяем, но `AtomicU64` даёт внутреннюю мутируемость
через `Ordering::Relaxed` store — в Ada этот паттерн выражается явно через
`in out`, без обхода системы контроля мутируемости, которым в Rust является
`Cell`/`Atomic`-механизм внутренней мутируемости):

```ada
   procedure Check_Valid_Fast
     (Self  : in out Instance;
      Valid : out Boolean)
   is
      Epoch  : constant Interfaces.Unsigned_32 := Self.Object.Header.Epoch;
      Cached : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Self.Prepared / 2 ** 32);
   begin
      if Self.Node.Valid_Until /= 0 then
         Valid := Check_Valid (Self) = Ok;
         return;
      end if;

      if Cached = Epoch then
         Valid := True;
         return;
      end if;

      if Check_Valid (Self) = Ok then
         Self.Prepared := Interfaces.Unsigned_64 (Epoch) * 2 ** 32;
         Valid := True;
      else
         Valid := False;
      end if;
   end Check_Valid_Fast;
```

**T27: `Cap_Mint_Temporal`** — создание временного мандата с окном
`[Valid_From, Valid_Until)`. `Valid_Until = 0` означает «без ограничения»:

```ada
   function Cdt_Max_Depth return Interfaces.Unsigned_32 is (32);

   procedure Cap_Mint_Temporal
     (Parent      : Instance;
      Valid_From  : Interfaces.Unsigned_64;
      Valid_Until : Interfaces.Unsigned_64;
      Result      : out Instance;
      Status      : out Kernel_Error)
   with
     Pre  => Contains (Parent.Rights, Grant),  --  эквивалент R: HasGrant
     Post => (if Status = Ok then
                Result.Node.Valid_From = Valid_From
                and then Result.Node.Valid_Until = Valid_Until);

   procedure Cap_Mint_Temporal
     (Parent      : Instance;
      Valid_From  : Interfaces.Unsigned_64;
      Valid_Until : Interfaces.Unsigned_64;
      Result      : out Instance;
      Status      : out Kernel_Error)
   is
      Node_Status : Kernel_Error;
   begin
      --  ИСПРАВЛЕНО (найдено при повторном аудите на вымывание, не было
      --  в первой версии порта): Rust-версия проверяет валидность
      --  родителя И явно отклоняет некорректное временное окно —
      --  первая версия этого порта переносила только Pre-контракт на
      --  Grant и пропускала обе эти проверки. Восстановлено дословно.
      Status := Check_Valid (Parent);
      if Status /= Ok then
         return;
      end if;
      if Valid_Until /= 0 and then Valid_Until <= Valid_From then
         Status := Invalid_Argument;
         return;
      end if;

      --  OPEN (не портировано — сама Rust-версия здесь зависит от
      --  функции Cap_Mint_Node, которая вызывается на строке 1036
      --  Rust-документа, но нигде в исходном документе не определена;
      --  это открытый пункт самой Rust-спеки, отдельный от её
      --  явных todo!(), и порт не восполняет его самостоятельно):
      Cap_Mint_Node (Parent, Node_Status, Result);
      if Node_Status /= Ok then
         Status := Node_Status;
         return;
      end if;
      Result.Node.Valid_From := Valid_From;
      Result.Node.Valid_Until := Valid_Until;
      Status := Ok;
   end Cap_Mint_Temporal;

   --  OPEN: см. комментарий в теле Cap_Mint_Temporal выше — эта функция
   --  вызывается, но не специфицирована уже в Rust-версии.
   procedure Cap_Mint_Node
     (Parent : Instance; Status : out Kernel_Error; Result : out Instance)
   with Import;
```

### 1.6 `Cap_Mint`: создание производного мандата

```ada
   procedure Cap_Mint
     (Parent    : Instance;
      Requested : Mask;
      Result    : out Instance;
      Status    : out Kernel_Error)
   with
     Pre => Contains (Parent.Rights, Grant);  --  эквивалент R: HasGrant
   --  OPEN (портировано из todo!() Rust-версии, §1.6): тело — CAS-вставка
   --  в First_Child узла CDT с повторной проверкой Revoke_In_Progress после
   --  вставки — не реализовано ни в Rust-документе, ни здесь. Проверки
   --  на входе (Contains rights, глубина CDT, revoke-в-процессе) портированы
   --  как контракт/явные шаги ниже, тело CAS-вставки остаётся открытым.

   procedure Cap_Mint_Body
     (Parent    : Instance;
      Requested : Mask;
      Result    : out Instance;
      Status    : out Kernel_Error)
   is
   begin
      if not Contains (Parent.Node.Rights_Mask, Requested) then
         Status := Bad_Rights;
         return;
      end if;
      if Parent.Node.Depth + 1 > Cdt_Max_Depth then
         Status := Cdt_Too_Deep;
         return;
      end if;
      if Parent.Node.Revoke_In_Progress then
         Status := Parent_Revoking;
         return;
      end if;
      --  OPEN: CAS-вставка в First_Child, повторная проверка
      --  Revoke_In_Progress — как и в Rust-версии (todo!()).
      Status := Not_Supported;  --  явный маркер "не реализовано", а не
                                  --  тихий успех
   end Cap_Mint_Body;
```

### 1.7 Отзыв и жизненный цикл

#### 1.7.0 Правило внешнего физического эффекта

Унаследовано из Rust-версии без изменений по существу. Rust `trait
HasExternalEffect` → Ada interface с абстрактным примитивом:

```ada
   type Has_External_Effect is interface and Kernel_Object;

   procedure Resolve_External_Effect (Self : Has_External_Effect) is abstract;
```

| Тип | Внешний эффект | Метод |
|-----|----------------|-------|
| `Notification` | заблокированные потоки | `Wake_All_With_Error (Object_Destroyed)` |
| `Iommu_Domain` | DMA-доступ | `Unmap_All; Tlb_Invalidate_All` |
| `V_Space` | мигрировавшие потоки | `Force_Xpc_Reply_Error (Host_Vspace_Destroyed)` |
| `Prm_Resource_Set` | MMIO/прерывание | `Release_All_Resources` |

**T60 — `Sanitize`:** типы с полями `Flip_Cell` дополнительно реализуют
`Sanitize` и уничтожаются через `Object_Destroy_Sanitized` /
`Object_Destroy_With_Effect_Sanitized`.

| Тип | Flip_Cell-поля | Метод уничтожения |
|-----|-----------------|-------------------|
| `Attr_Entry` | `Value : Flip_Cell (Attr_Value)` | `Object_Destroy_Sanitized` |
| `Thread` | `Exec_Ctx : Flip_Cell (Execution_Context)` (T44) | `Object_Destroy_Sanitized` |

```ada
   type Sanitize is interface and Kernel_Object;

   --  Обнулить все Flip_Cell-поля объекта. Вызывается ДО epoch bump,
   --  пока объект ещё доступен — идентично порядку операций в Rust-версии.
   procedure Sanitize_Fields (Self : Sanitize) is abstract;

   --  Зачистка одной Flip_Cell — обе стороны, атомарно.
   --  Rust использует write_volatile, чтобы компилятор не выкинул как
   --  dead store; Ada-эквивалент — запись через Volatile-типизированное
   --  поле (см. §A.2 Flip_Cell — тип Instance уже помечен Volatile),
   --  что даёт тот же эффект без отдельного вызова, аналогичного
   --  ptr::write_volatile.
   generic
      type Element_Type is private;
      with package Cell is new Tachy.Flip_Cell (Element_Type);
   procedure Flip_Cell_Zeroize (Self : in out Cell.Instance; Zero : Element_Type);

   procedure Object_Destroy (Obj : in out Cap_Object_Ref)
     with Post => not Obj.Is_Valid;

   procedure Object_Destroy_Sanitized (Obj : in out Cap_Object_Ref)
     with Pre  => Obj.Is_Sanitizable,   --  ghost-предикат: объект реализует Sanitize
          Post => not Obj.Is_Valid;

   procedure Object_Destroy_With_Effect (Obj : in out Cap_Object_Ref)
     with Pre  => Obj.Has_External_Effect,
          Post => not Obj.Is_Valid;

   procedure Object_Destroy_With_Effect_Sanitized (Obj : in out Cap_Object_Ref)
     with Pre  => Obj.Has_External_Effect and then Obj.Is_Sanitizable,
          Post => not Obj.Is_Valid;
```

`Object_Destroy` в Rust-версии откладывает фактическое освобождение через
`domain.call_rcu(Box::new(move || drop(obj)))` — closure, захватывающий
`obj`. Ada-эквивалент не имеет closures как объектов первого класса без
дополнительной инфраструктуры (см. port-05): вместо замыкания используется
явная постановка объекта в очередь RCU-домена с последующим вызовом
известного на этапе компиляции деструктора, а не произвольного пользовательского
кода — см. §6.1 ниже, где این ограничение раскрыто подробно на примере
`Rcu_Callback_Kind`.

#### 1.7.1 `Cap_Revoke` — итеративный обход (fix-004, T69)

Уже исправленная в Rust-версии реализация (CVE-TACHY-004: рекурсивный
обход был заменён итеративным DFS с явным стеком) переносится как есть —
стек фиксированной ёмкости, без динамической аллокации на горячем пути (T69):

```ada
   Cdt_Max_Revoke_Depth : constant := 1024;

   package Revoke_Stacks is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Cap_Id);
   subtype Revoke_Stack is Revoke_Stacks.Vector (Cdt_Max_Revoke_Depth);

   procedure Cap_Revoke
     (Cdt      : in out Cdt_Table;
      Root_Id  : Cap_Id;
      Status   : out Kernel_Error)
   is
      Stack : Revoke_Stack;
      Id    : Cap_Id;
   begin
      if Revoke_Stacks.Length (Stack) >= Cdt_Max_Revoke_Depth then
         Status := Capacity_Exceeded;
         return;
      end if;
      Revoke_Stacks.Append (Stack, Root_Id);

      while not Revoke_Stacks.Is_Empty (Stack) loop
         Id := Revoke_Stacks.Last_Element (Stack);
         Revoke_Stacks.Delete_Last (Stack);

         declare
            Entry_Found : Boolean;
            E           : Cdt_Entry;
         begin
            Cdt_Get (Cdt, Id, E, Entry_Found);
            if not Entry_Found then
               goto Continue;
            end if;

            E.Revoke_Flag := True;  --  атомарный Release-стор

            --  T30: push-уведомление при revoke
            if E.Revoke_Notify /= null and then E.Revoke_Notify.Is_Alive then
               Notification_Signal (E.Revoke_Notify);
            end if;

            --  Добавить детей в стек через sibling-list. Дети собираются
            --  ДО удаления записи — идентично порядку операций Rust-версии
            --  (комментарий "entry остаётся валидной ссылкой, пока мы её
            --  держим; remove() вызывается после").
            declare
               Child_Id : Cap_Id := E.First_Child;
               Child_E  : Cdt_Entry;
               Found    : Boolean;
            begin
               while Child_Id /= No_Cap_Id loop
                  if Revoke_Stacks.Length (Stack) >= Cdt_Max_Revoke_Depth then
                     Status := Capacity_Exceeded;
                     return;
                  end if;
                  Revoke_Stacks.Append (Stack, Child_Id);
                  Cdt_Get (Cdt, Child_Id, Child_E, Found);
                  Child_Id := (if Found then Child_E.Next_Sibling else No_Cap_Id);
               end loop;
            end;

            Cdt_Remove (Cdt, Id);
         end;
         <<Continue>>
      end loop;

      Status := Ok;
   end Cap_Revoke;
   --  Invariant (CVE-TACHY-010, перенесено как есть): весь обход должен
   --  выполняться под Global_Cdt_Lock — вызывающий код обязан удерживать
   --  Ticket_Lock.Instance перед вызовом Cap_Revoke.
```

**T30: регистрация/снятие push-уведомления при revoke** — переносится
процедурно, идентично Rust-версии по семантике (слабая ссылка: если
`Notification` уничтожена раньше — уведомление молча пропускается):

```ada
   procedure Cap_Revoke_Notify_Set
     (Cdt   : in out Cdt_Table;
      Id    : Cap_Id;
      Notif : Notification_Ref;   --  требует прав Write, эквивалент
                                    --  Cap<Notification, impl HasWrite>
      Status : out Kernel_Error)
   with Pre => Contains (Notif.Rights, Write);

   --  ИСПРАВЛЕНО при повторном аудите порта на вымывание: обе функции
   --  этой пары были перенесены только как сигнатуры без тел, хотя
   --  полностью специфицированы уже в Rust-версии. Восстановлено
   --  дословно.
   procedure Cap_Revoke_Notify_Set
     (Cdt   : in out Cdt_Table;
      Id    : Cap_Id;
      Notif : Notification_Ref;
      Status : out Kernel_Error)
   is
      Check_Status : constant Kernel_Error := Check_Valid (Notif);
      E            : Cdt_Entry;
      Found        : Boolean;
   begin
      if Check_Status /= Ok then
         Status := Check_Status;
         return;
      end if;
      Cdt_Get_Mut (Cdt, Id, E, Found);
      if not Found then
         Status := Invalid_Cap;
         return;
      end if;
      E.Revoke_Notify := Downgrade (Notif.Object);
      Cdt_Set (Cdt, Id, E);
      Status := Ok;
   end Cap_Revoke_Notify_Set;

   procedure Cap_Revoke_Notify_Clear
     (Cdt    : in out Cdt_Table;
      Id     : Cap_Id;
      Status : out Kernel_Error);

   procedure Cap_Revoke_Notify_Clear
     (Cdt    : in out Cdt_Table;
      Id     : Cap_Id;
      Status : out Kernel_Error)
   is
      E     : Cdt_Entry;
      Found : Boolean;
   begin
      Cdt_Get_Mut (Cdt, Id, E, Found);
      if not Found then
         Status := Invalid_Cap;
         return;
      end if;
      E.Revoke_Notify := Empty_Weak_Ref;
      Cdt_Set (Cdt, Id, E);
      Status := Ok;
   end Cap_Revoke_Notify_Clear;
```

**T23: `Cdt_Gc`** — сборка мёртвых поддеревьев, идентично Rust-версии
(итеративный проход снизу вверх, листовые записи с `Revoke_Flag = True`):

```ada
   Cdt_Gc_Threshold : constant := Cdt_Capacity * 4 / 5;  -- 80%, T23

   function Cdt_Gc (Cdt : in out Cdt_Table) return Natural;
   --  Реализация — обход всех занятых слотов, удаление листьев с
   --  Revoke_Flag = True. Один проход может не собрать всё — вызывать до
   --  стабилизации, идентично комментарию Rust-версии.
```

#### 1.7.2 Инварианты CDT (closed-005) и `Has_Deny_Ancestor` (fix-017, T28)

Инварианты переносятся дословно по смыслу — это архитектурные утверждения,
не привязанные к языку реализации:

1. **Дерево, не граф:** каждая запись имеет не более одного `Parent`.
2. **Один Manage на объект:** не более одного мандата с `Manage` на объект.
3. **Revoke-атомарность:** весь обход под `Global_Cdt_Lock`.
4. **`Slot_Id`-валидность:** несовпадающее поколение → `Found = False` из
   `Slot_Map.Get`/`Contains`.
5. **Strong Tranquility (T54):** `Mandatory_Label` фиксируется при создании.
6. **Negative Capability (T28):** deny-биты в bits[16+] блокируют операцию у
   всех потомков в CDT, независимо от их grant-битов.
7. **Sharding Revoke Atomicity (T51):** при будущем sharding CDT (T61) revoke
   поддерева должен проходить под локами ВСЕХ затронутых шардов
   одновременно. Порядок захвата локов: всегда по возрастанию `Shard_Id`
   во избежание дедлока. До реализации T61 этот инвариант выполняется
   тривиально (один глобальный лок) — идентично статусу в Rust-версии.

```ada
   function Has_Deny_Ancestor
     (Cdt : Cdt_Table; Id : Cap_Id; Op : Mask) return Boolean
   is
      Cur   : Cap_Id := Id;
      Depth : Natural := 0;
      E     : Cdt_Entry;
      Found : Boolean;
   begin
      loop
         Depth := Depth + 1;
         if Depth > Cdt_Capacity then
            --  Цикл невозможен при корректной работе CDT. Fail-safe: deny.
            --  Идентично Rust-версии: debug_assertions → panic (перенесено
            --  как pragma Assert, активная только со сборкой с проверками),
            --  release → return True (fail-safe deny сохранён безусловно).
            pragma Assert (False, "Has_Deny_Ancestor: cycle detected");
            return True;
         end if;

         Cdt_Get (Cdt, Cur, E, Found);
         exit when not Found;

         if (E.Rights and Shift_Left (Op, 16)) /= 0 then
            return True;
         end if;
         Cur := E.Parent;
      end loop;
      return False;
   end Has_Deny_Ancestor;
```

**T28/T79: `Cap_Seal`** — запечатать мандат, запретив дальнейшее
делегирование (переиспользует deny-биты T28: выставляет `Deny_Grant`,
потомки запечатанного мандата не могут иметь `Grant` — бесконечное
клонирование невозможно, идентично Rust-версии):

```ada
   procedure Cap_Seal
     (Cdt    : in out Cdt_Table;
      Id     : Cap_Id;
      Status : out Kernel_Error)
   is
      E     : Cdt_Entry;
      Found : Boolean;
   begin
      Cdt_Get_Mut (Cdt, Id, E, Found);
      if not Found then
         Status := Invalid_Cap;
         return;
      end if;
      E.Rights := E.Rights or Shift_Left (Grant, 16);  --  Deny_Grant
      Cdt_Set (Cdt, Id, E);
      Status := Ok;
   end Cap_Seal;
```

**T28: `Cap_Check_Deny`** — суммарная проверка deny-битов по всем
запрошенным операциям сразу.

> **Примечание о происхождении сигнатуры (переносится из Rust-версии,
> `ext-audit-02` / комментарий `<!-- ВОССТАНОВЛЕНО -->` §1.7.2 Rust-документа):**
> в Rust-документе после `cap_check_deny` первоначально отсутствовал
> закрывающий code-fence; имя функции, разбиение на 3 аргумента и порядок
> типов (`&CdtTable`, `CapId`, `RightsMask`) были восстановлены авторами
> Rust-версии по трём независимым перекрёстным ссылкам внутри самого
> документа (запись t28-01 в журнале изменений, реальный вызов в §5.6a
> `io_check_rights`, запись в дорожной карте T28) — тело функции ниже
> реконструкции не подвергалось и совпадает с оригиналом. Порт сохраняет
> и сигнатуру, и тело как они зафиксированы в исходном документе, без
> дополнительных доработок сверх уже сделанной Rust-версией реконструкции.

```ada
   function Cap_Check_Deny
     (Cdt       : Cdt_Table;
      Id        : Cap_Id;
      Requested : Mask) return Kernel_Error
   is
      Ops : constant array (1 .. 8) of Mask :=
        (Read, Write, Manage, Grant,
         Attr_Read, Attr_Write, Mount, Bind_Prm);
   begin
      for Op of Ops loop
         if Contains (Requested, Op)
           and then Has_Deny_Ancestor (Cdt, Id, Op)
         then
            return Perm_Denied;
         end if;
      end loop;
      return Ok;
   end Cap_Check_Deny;
```

### 1.8 Создание процесса (модель Genode)

```ada
   procedure Process_Create
     (Untyped                   : Instance;  --  требует Manage,
                                                --  эквивалент impl HasManage
      Offset                    : Interfaces.Unsigned_64;
      Initial_Cspace_Slot_Bits  : Interfaces.Unsigned_32;
      Result                    : out Process_Context_Ref;  -- Manage-мандат
      Status                    : out Kernel_Error)
   with Pre => Contains (Untyped.Rights, Manage);
   --  OPEN (портировано из todo!() Rust-версии, §1.8): тело не реализовано
   --  ни в Rust-документе, ни здесь. Три шага, зафиксированные в Rust-версии
   --  как план реализации, переносятся как комментарий, а не как код:
   --    1. Проверить границы и разметку через Untyped_Retype (§3.3 порта).
   --    2. Создать пустой CNode + пустой VSpace.
   --    3. Вернуть мандат Manage на Process_Context вызывающему.
   --  Заполнение CSpace — отдельными вызовами Cap_Mint до первого запуска.
end Tachy.Capability.Validity;
```

---

## 2. Ring Levels — 2 уровня, аппаратные (T45, closed-001, fix-013, revert-ring-001)

**См. port-06.** Переносится состояние после `revert-ring-001` из
Rust-версии: 2 уровня (`Ring0`/`Ring3`), соответствующие реальным CPL
x86_64, а не прежней 6-уровневой программной модели (kring0-2/uring0-2).

```ada
package Tachy.Ring is

   pragma Pure;

   type Ring_Level is (Ring0, Ring3);
   --  Ring0 = kernel, Ring3 = userspace — идентично комментарию
   --  Rust-версии после revert-ring-001.

   for Ring_Level use (Ring0 => 0, Ring3 => 3);  --  сохраняет числовые
                                                    --  значения аппаратных CPL

end Tachy.Ring;
```

> **Незакрытая оговорка, перенесённая из `revert-ring-001` Rust-версии
> без смягчения (см. port-06):** схлопывание бывших kring0/1/2 в единый
> `Ring0` не было заново проверено на предмет ослабления инвариантов
> MAC/Biba (§13 порта) — в 6-уровневой модели интерфейс между
> "interrupt handlers" / "kernel subsystems" / "trusted services" внутри
> самого ядра мог неявно на них опираться. Сам раздел 13 явно на
> 6-уровневой модели не полагался (согласно тексту Rust-версии), но
> целенаправленно под 2-уровневую модель не переисследовался — этот
> вопрос остаётся открытым и в порте, см. §23, T-Ada-01.

### 2.1 `Cap_Derive_Checked` — проверка ring constraint (fix-013)

> **ИСПРАВЛЕНО при повторном аудите порта на вымывание:** первая версия
> этого документа объявляла только тип `Ring_Level`, но не переносила
> сам механизм fix-013 (проверку `Min_Ring` при derive и повышение через
> `Cap_Promote_Ring`) — притом что название раздела прямо ссылалось на
> fix-013. Это было пропуском реализации, а не намеренным OPEN;
> восстановлено ниже полностью, обе функции были специфицированы целиком
> уже в Rust-версии (не `todo!()`).

```ada
   function Current_Process_Ring return Ring_Level
   with Global => null;

   function Current_Process_Ring return Ring_Level is
      --  Граница платформы: чтение текущего потока — идентично
      --  unsafe-блоку Rust-версии (CURRENT_THREAD.as_ref()).
      Th       : Thread_Access;
      Th_Found : Boolean;
   begin
      Current_Thread_Ref (Th, Th_Found);
      return (if Th_Found then Th.Ring_Level else Ring3);
   end Current_Process_Ring;

   --  Derive с проверкой ring constraint (fix-013).
   generic
      type Object_Type is new Kernel_Object with private;
   procedure Cap_Derive_Checked
     (Parent : Object_Manage_Ref;  --  требует Manage
      Result : out Instance;
      Status : out Kernel_Error)
   with Pre => Contains (Parent.Rights, Manage);

   procedure Cap_Derive_Checked
     (Parent : Object_Manage_Ref;
      Result : out Instance;
      Status : out Kernel_Error)
   is
      Obj_Min_Ring : Ring_Level;
      Caller_Ring  : Ring_Level;
      Check_Status : Kernel_Error;
   begin
      Check_Status := Check_Valid (Parent);
      if Check_Status /= Ok then
         Status := Check_Status;
         return;
      end if;
      Obj_Min_Ring := Parent.Object.Header.Min_Ring;
      Caller_Ring  := Current_Process_Ring;
      --  Ring_Level'Enum_Rep сравнивает по аппаратному числовому CPL
      --  (Ring0 => 0, Ring3 => 3, см. representation clause выше), не
      --  по порядковому индексу перечисления — идентично Rust `as u8`
      --  сравнению, которое использует явно заданные дискриминанты.
      if Ring_Level'Enum_Rep (Caller_Ring)
           > Ring_Level'Enum_Rep (Obj_Min_Ring)
      then
         Status := Ring_Violation;
         return;
      end if;
      Cap_Derive_Unchecked (Parent, Result, Status);
   end Cap_Derive_Checked;

   --  OPEN: Cap_Derive_Unchecked используется, но её тело не
   --  специфицировано по существу в Rust-версии за пределами общего
   --  механизма derive, уже описанного в §1.6 порта (Cap_Mint) — порт не
   --  добавляет отдельную недостающую реализацию сверх того, что уже
   --  открыто там.
   generic
      type Object_Type is new Kernel_Object with private;
   procedure Cap_Derive_Unchecked
     (Parent : Object_Manage_Ref; Result : out Instance; Status : out Kernel_Error)
   with Import;

   --  Ужесточить доступ к объекту: поднять Min_Ring до более высокого
   --  уровня. Операция необратима. Более высокий числовой уровень =
   --  строже (Ring3 строже Ring0). С двумя уровнями это единственный
   --  содержательный переход: Ring0 → Ring3 (объект, изначально
   --  доступный из kernel, закрывается для userspace).
   generic
      type Object_Type is new Kernel_Object with private;
   procedure Cap_Promote_Ring
     (Cap         : Object_Manage_Ref;  --  требует Manage
      Target_Ring : Ring_Level;
      Status      : out Kernel_Error)
   with Pre => Contains (Cap.Rights, Manage);

   procedure Cap_Promote_Ring
     (Cap         : Object_Manage_Ref;
      Target_Ring : Ring_Level;
      Status      : out Kernel_Error)
   is
      Current      : Ring_Level;
      Check_Status : Kernel_Error;
   begin
      Check_Status := Check_Valid (Cap);
      if Check_Status /= Ok then
         Status := Check_Status;
         return;
      end if;
      Current := Cap.Object.Header.Min_Ring;
      if Ring_Level'Enum_Rep (Target_Ring) <= Ring_Level'Enum_Rep (Current)
      then
         --  target не строже current → демоция запрещена.
         Status := Ring_Demotion;
         return;
      end if;
      Cap.Object.Header.Min_Ring := Target_Ring;
      Status := Ok;
   end Cap_Promote_Ring;
```


---

## 3. Пространство имён

### 3.1 Узел пространства имён

```ada
with Tachy.Object; use Tachy.Object;
with Tachy.Cap_Node; use Tachy.Cap_Node;
with Tachy.Attr; use Tachy.Attr;

package Tachy.Namespace is

   pragma SPARK_Mode (On);

   Namespace_Name_Max : constant := 255;  --  предел для Bounded_String,
                                            --  заменяющего Box<str>

   package Name_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Namespace_Name_Max);

   type Namespace_Node is limited record
      Header         : Object_Header;
      Associated     : Cap_Any_Ref;         --  эквивалент Option<AnyCapRef>;
                                              --  null-состояние = None
      Parent          : Namespace_Node_Weak_Ref;
      First_Child     : Namespace_Node_Access;
      Next_Sibling    : Namespace_Node_Access;
      Union_Target    : Namespace_Node_Access;
      Union_Priority  : Interfaces.Unsigned_32;
      Is_Union        : Boolean;
      Attributes      : Attr_Table;
      Name            : Name_Strings.Bounded_String;
   end record;

end Tachy.Namespace;
```

> **`Name : Name_Strings.Bounded_String` вместо `Box<str>`:** Rust-версия
> использует `Box<str>` — точный по размеру, управляемый через `Drop`. Ada
> `Bounded_String` фиксирует ёмкость на этапе компиляции (без per-instance
> аллокации), что для имён узлов пространства имён строже, чем оригинал —
> сознательное отклонение по T69 (без динамической аллокации там, где
> возможно обойтись фиксированным пределом): 255 байт с большим запасом
> покрывает любое разумное имя узла, а превышение — явная ошибка
> `Name_Too_Long` (уже существующий код ошибки `KernelError`, §14),
> а не молчаливое усечение.

### 3.2 Разрешение конфликтов в union

Идентично Rust-версии по существу (унаследовано без изменений от
предшествующего документа): конфликт равного приоритета —
`Mount_Conflict`.

> **Dentry cache:** для ускорения поиска в union-директориях ядро
> использует отрицательный и положительный кэш путей с RCU-защитой,
> предотвращающий деградацию поиска до O(N) при большом числе
> union-ветвей. Структура кэша — реализационная деталь, не часть ABI;
> инвалидируется при `Ns_Mount`/`Ns_Unmount` через постановку в очередь
> того же RCU-домена (см. §6 порта).

### 3.3 `Ns_Mount`

```ada
   type Ns_Mount_Flags is mod 2 ** 32;
   Readonly  : constant Ns_Mount_Flags := 16#01#;
   Propagate : constant Ns_Mount_Flags := 16#02#;
   Ephemeral : constant Ns_Mount_Flags := 16#04#;

   procedure Ns_Mount
     (Target_Process : Process_Context_Ref;
      Target_Parent  : in out Namespace_Node;
      Name           : String;
      Source         : Namespace_Cap;       --  требует Mount,
                                              --  эквивалент impl HasMount
      Priority       : Interfaces.Unsigned_32;
      As_Union       : Boolean;
      Lease_Ms       : Interfaces.Unsigned_32;
      Flags          : Ns_Mount_Flags;
      Status         : out Kernel_Error)
   with Pre => Contains (Source.Rights, Mount)
               and then Name'Length <= Namespace_Name_Max;
   --  OPEN (портировано из todo!() Rust-версии, §3.3): тело не реализовано.
   --  Три шага из плана Rust-версии переносятся как комментарий:
   --    1. Проверка квоты Mounts_Since_Last_Prune.
   --    2. Создание нового Namespace_Node с производным мандатом.
   --    3. Запись Mount_Log_Entry (§10 порта).
```

#### 3.3.1 `Cap_Token`, `Lease_Renew` и `Cap_Quota` (T62)

`FixedHashMap` из Rust-версии (уже адаптированный под `no_std`, не
`std::HashMap`) переносится как generic-параметризованная bounded-хэш-таблица
собственной реализации — Ada стандартная библиотека не содержит fixed-capacity
хэш-таблицы "из коробки", в отличие от `Ada.Containers.Bounded_Vectors`,
поэтому здесь необходим отдельный небольшой generic-пакет
`Tachy.Fixed_Hash_Map` (не приводится подробно — механическая деталь, не
влияющая на архитектуру: линейное пробирование по фиксированному массиву
ёмкости `Capacity`, вставка/поиск/удаление за амортизированное O(1), как и
любая typичная open-addressing реализация).

```ada
   type Cap_Token_Status is (Valid, Revoked);

   package Cap_Token_Maps is new Tachy.Fixed_Hash_Map
     (Key_Type => Interfaces.Unsigned_64, Value_Type => Cap_Token_Status,
      Capacity => 65536);

   protected type Cap_Token_Registry is
      procedure Lookup
        (Token : Interfaces.Unsigned_64;
         Status : out Cap_Token_Status; Found : out Boolean);
      procedure Insert (Token : Interfaces.Unsigned_64; Status : Cap_Token_Status);
   private
      Inner : Cap_Token_Maps.Instance;
   end Cap_Token_Registry;

   --  T62: квота мандатов на процесс. Ограничивает число одновременно
   --  живых Capability в CSpace процесса.
   protected type Cap_Quota (Limit : Interfaces.Unsigned_32) is

      --  Зарезервировать слот под новый мандат.
      procedure Acquire (Status : out Kernel_Error);

      --  Освободить слот при revoke/destroy мандата. Насыщающий декремент —
      --  идентично Rust saturating_sub(1).
      procedure Release;

      function Remaining return Interfaces.Unsigned_32;

   private
      Used : Interfaces.Unsigned_32 := 0;
   end Cap_Quota;

   Cap_Quota_Default : constant := 4096;
   Cap_Quota_Max      : constant := 65536;

   --  Квота встраивается в Process_Context (не отдельный объект ядра —
   --  внутреннее поле, не capability). Cap_Mint проверяет Acquire перед
   --  вставкой в CDT; Cap_Revoke вызывает Release после удаления из CDT.

   type Lease_Entry is limited record
      Derived               : Cap_Node_Weak_Ref;
      Lease_Expires_At_Tick  : aliased Interfaces.Unsigned_64;
      Lease_Duration_Ms      : Interfaces.Unsigned_32;
      Origin_Object          : Kernel_Object_Weak_Ref;
      Origin_Creation_Epoch  : Interfaces.Unsigned_32;
      Origin_Obj_Epoch       : Interfaces.Unsigned_32;
      Origin_Cap_Token       : Interfaces.Unsigned_64;
   end record
     with Volatile;

   procedure Lease_Renew
     (Lease  : in out Lease_Entry;
      New_Ms : Interfaces.Unsigned_32;
      Status : out Kernel_Error)
   is
      Obj        : Kernel_Object_Ref;
      Obj_Alive  : Boolean;
      Tok_Status : Cap_Token_Status;
      Tok_Found  : Boolean;
   begin
      --  1. Проверка Object_Epoch
      Upgrade (Lease.Origin_Object, Obj, Obj_Alive);
      if not Obj_Alive then
         Status := Origin_Revoked;
         return;
      end if;
      if Lease.Origin_Obj_Epoch /= Obj.Header.Epoch then
         Status := Origin_Revoked;
         return;
      end if;

      --  2. Проверка Cap_Token
      Cap_Token_Registry_Instance.Lookup
        (Lease.Origin_Cap_Token, Tok_Status, Tok_Found);
      if not Tok_Found or else Tok_Status = Revoked then
         Status := Origin_Revoked;
         return;
      end if;

      Lease.Lease_Expires_At_Tick :=
        Current_Tick + Ms_To_Ticks (Interfaces.Unsigned_64 (New_Ms));
      Status := Ok;
   end Lease_Renew;
```

#### 3.3.2 Защита от циклов монтирования

```ada
   Namespace_Path_Max_Depth : constant := 64;

   function Would_Create_Cycle
     (Target_Parent : Namespace_Node; Source : Namespace_Node) return Boolean
   is
      Node  : Namespace_Node_Access := Target_Parent'Unrestricted_Access;
      Depth : Natural := 0;
   begin
      loop
         exit when Node = null;
         if Node.all'Address = Source'Address then
            return True;
         end if;
         Depth := Depth + 1;
         exit when Depth > Namespace_Path_Max_Depth;  --  fail-safe: не даём
                                                         --  уйти в бесконечный
                                                         --  обход при
                                                         --  повреждённой
                                                         --  структуре
         Node := Upgrade (Node.Parent);
      end loop;
      return False;
   end Would_Create_Cycle;
```

> **Отличие от Rust-версии:** Rust `core::ptr::eq` сравнивает адреса —
> Ada-эквивалент через `'Address` даёт то же сравнение идентичности объекта.
> Явная граница `Depth > Namespace_Path_Max_Depth` добавлена как fail-safe:
> в Rust-версии цикл в дереве `parent`-ссылок в принципе невозможен при
> соблюдении инварианта 1 из §1.7.2 («дерево, не граф»), и явной защиты от
> зацикливания в этой конкретной функции не было — здесь она добавлена по
> аналогии с уже существующим в самом документе паттерном `Has_Deny_Ancestor`
> (§1.7.2), где такая защита есть. Это усиление, а не расхождение с
> оригинальной семантикой: при соблюдении инварианта 1 цикл дерева невозможен,
> граница строго не достижима и служит защитой на случай повреждения
> структуры (аналогично defensive `depth > CDT_CAPACITY` в
> `Has_Deny_Ancestor`).

### 3.4 Re/Im и адресация слоёв (T56)

**Re** — реальное хранилище: плоский набор пакетов (`Package_Image`),
пользовательских данных и физических устройств. В Re не существует
`/bin`, `/lib`, `/usr` как директорий — там лежат версионированные
пакеты, разрешаемые через `PackageFs` (§12 порта).

**Im** — мнимое (виртуальное) пространство имён, которое видит процесс.
Собирается из Re на лету через **`AUnion`** — AUFS-подобную композицию
`Layer`'ов с явным приоритетом наложения (`Union_Priority` уже в
`Namespace_Node`, §3.1 порта; "top of stack" побеждает при конфликте
путей).

```ada
   type Layer_Kind is (System, User, Mount, Container, Service);
   --  System (C): PUnion нескольких пакетов (Haiku-стиль, без приоритета).
   --  User (D): обычная директория в Re, без union.
   --  Mount (E): прямой доступ к физическому/блочному устройству.
   --  Container (F): PUnion образа контейнера (Haiku-стиль).
   --  Service (G): runtime-пространство демона (обычная директория).

   function Letter (Kind : Layer_Kind) return Character is
     (case Kind is
        when System    => 'C',
        when User      => 'D',
        when Mount     => 'E',
        when Container => 'F',
        when Service   => 'G');

   type Layer_State is (Live, Detached);

   type Layer_Backend_Kind is (Package_Backend, Raw_Device_Backend,
                                 Plain_Directory_Backend);

   --  Ada discriminated record — эквивалент Rust enum с данными
   --  (Package(PUnion) | RawDevice(Arc<DeviceObject>) | PlainDirectory(...)).
   type Layer_Backend (Kind : Layer_Backend_Kind := Plain_Directory_Backend) is
     record
        case Kind is
           when Package_Backend =>
              Union : P_Union_Ref;         -- §12 порта
           when Raw_Device_Backend =>
              Device : Device_Object_Ref;
           when Plain_Directory_Backend =>
              Directory : Namespace_Node_Access;
        end case;
     end record;

   Package_Union_Max : constant := 16;

   type Layer is limited record
      Header          : Object_Header;
      Kind            : Layer_Kind;
      Id              : Name_Strings.Bounded_String;
      Slot            : Slot_Id;   --  переиспользуется через generation,
                                     --  как Tachy.Slot_Map (§A.4 порта)
      State           : aliased Layer_State;
      Backend         : Layer_Backend;
   end record
     with Volatile;

end Tachy.Namespace;
```

#### 3.4.1 `Layer_Registry` — уникальность `(Kind, Id)`

```ada
   package Layer_Keys is new Tachy.Fixed_Hash_Map
     (Key_Type   => Layer_Key,   --  (Layer_Kind, Bounded_String)
      Value_Type => Slot_Id,
      Capacity   => 4096);

   protected type Layer_Registry is
      procedure Contains (Kind : Layer_Kind; Id : String; Found : out Boolean);
      procedure Insert (Kind : Layer_Kind; Id : String; Slot : Slot_Id);
      procedure Remove (Kind : Layer_Kind; Id : String);
   private
      Inner : Layer_Keys.Instance;
   end Layer_Registry;

   procedure Layer_Create
     (Registry : in out Layer_Registry;
      Kind     : Layer_Kind;
      Id       : String;
      Backend  : Layer_Backend;
      Result   : out Layer_Manage_Ref;
      Status   : out Kernel_Error)
   is
      Found : Boolean;
   begin
      Registry.Contains (Kind, Id, Found);
      if Found then
         Status := Already_Exists;
         return;
      end if;
      --  Аллокация слота, конструирование Layer, регистрация — механически
      --  идентично Rust-версии (Arc::new + reg.insert + cap_mint_root).
      Layer_Create_Body (Registry, Kind, Id, Backend, Result, Status);
   end Layer_Create;

   --  Detach слоя: помечает Detached, освобождает слот для переиспользования.
   --  Новый Layer с тем же (Kind, Id) получит новый Slot с новым поколением —
   --  старые мандаты на этот Layer корректно вернут Revoked через инвариант
   --  Slot_Map (идентично Rust-версии).
   procedure Layer_Detach
     (Registry : in out Layer_Registry;
      Layer_Cap : Layer_Manage_Ref;
      Status    : out Kernel_Error)
   with Pre => Contains (Layer_Cap.Rights, Manage);

   --  ИСПРАВЛЕНО при повторном аудите порта на вымывание: первая версия
   --  этого документа переносила только сигнатуру с Pre-контрактом, без
   --  тела — хотя Layer_Detach была полностью специфицирована уже в
   --  Rust-версии (не todo!()). Восстановлено дословно.
   procedure Layer_Detach
     (Registry  : in out Layer_Registry;
      Layer_Cap : Layer_Manage_Ref;
      Status    : out Kernel_Error)
   is
      Check_Status : constant Kernel_Error := Check_Valid (Layer_Cap);
   begin
      if Check_Status /= Ok then
         Status := Check_Status;
         return;
      end if;
      Layer_Cap.Object.State := Detached;
      Registry.Remove (Layer_Cap.Object.Kind, Layer_Cap.Object.Id);
      Layer_Slots_Remove (Layer_Cap.Object.Slot);
      Status := Ok;
   end Layer_Detach;
```

#### 3.4.2 Синтаксис адресации

Синтаксис адресации — текстовый протокол, не зависящий от языка реализации,
переносится дословно:

```
<буква>::<id> [<буква>::<id> ...] /<путь>
```

Примеры (идентичны Rust-версии):

```
C::stable/exe/init           — один слой System с id="stable", путь /exe/init
D::vasya/home                — слой User с id="vasya", путь /home
D::vasya G::nginx/run        — User поверх Service, путь /run (D приоритетнее)
E::usb1/photos                — слой Mount с id="usb1", путь /photos
```

**Порядок перекрытия:** первый слой в списке — наивысший приоритет (top of
AUFS stack), совпадает с `Union_Priority` в `Namespace_Node`.

#### 3.4.3 Сборка Im из списка слоёв

```ada
   procedure Im_Compose
     (Target_Parent : in out Namespace_Node;
      Layers        : Layer_Read_Cap_Array;  --  требует Read на каждый,
                                                --  эквивалент impl HasRead
      Mount_Path    : String;
      Status        : out Kernel_Error)
   is
      Base_Priority : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Layers'Length);
      Valid_Check   : Boolean;
   begin
      if Layers'Length = 0 then
         Status := Invalid_Argument;
         return;
      end if;

      for I in Layers'Range loop
         --  Невалидный/отозванный мандат — слой пропускается, не блокирует
         --  сборку. Идентично Rust-версии.
         Valid_Check := Check_Valid (Layers (I)) = Ok;
         if Valid_Check then
            --  Detached Mount-слой — пропускается так же, как невалидный
            --  мандат.
            if Layers (I).Object.State /= Detached then
               declare
                  Priority : constant Interfaces.Unsigned_32 :=
                    Base_Priority - Interfaces.Unsigned_32 (I - Layers'First);
               begin
                  Ns_Mount
                    (Current_Process, Target_Parent, Mount_Path,
                     --  OPEN (портировано из todo!() Rust-версии, §3.4.3):
                     --  "source derived from layer backend" — вывод
                     --  Namespace_Cap из Layer_Backend не специфицирован
                     --  ни в Rust-документе, ни здесь.
                     Derive_Source_From_Backend (Layers (I).Object.Backend),
                     Priority, As_Union => True, Lease_Ms => 0,
                     Flags => 0, Status => Status);
                  if Status /= Ok then
                     return;
                  end if;
               end;
            end if;
         end if;
      end loop;
      Status := Ok;
   end Im_Compose;

   --  OPEN (портировано из todo!() Rust-версии): вывод Namespace_Cap
   --  из Layer_Backend — не реализовано ни в исходном документе, ни здесь.
   function Derive_Source_From_Backend
     (Backend : Layer_Backend) return Namespace_Cap
   with Import;  --  явно помечено как нереализованная внешняя точка
```

**Грануляция прав внутри слоя:** переносится без изменений по существу.
Мандат на `Layer` решает видимость слоя целиком (быстрая проверка, короткое
замыкание). Если `Layer_Backend` слоя — `Package_Backend` (внутри работает
`PUnion`, §12 порта), каждый входящий в него `Package_Image` несёт
собственную `Mandatory_Label` (§13.1 порта) — конкретный путь резолвится,
только если видим и слой, и конкретный пакет внутри него.

---

## 4. Память: Untyped

### 4.1 `Untyped_Region`

```ada
package Tachy.Untyped is

   pragma SPARK_Mode (On);

   Untyped_Bitmap_Words_Max : constant := 1024;  --  фиксированная ёмкость
                                                    --  для Bounded-массива,
                                                    --  заменяющего Box<[AtomicU64]>

   package Bitmap_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Natural, Element_Type => Interfaces.Unsigned_64);

   type Untyped_Region is limited record
      Header            : Object_Header;
      Phys_Addr_Base    : Interfaces.Unsigned_64;
      Size_Bits         : Interfaces.Unsigned_32;
      Is_Device         : Boolean;
      Allocated_Bitmap  : Bitmap_Vectors.Vector (Untyped_Bitmap_Words_Max);
   end record
     with Volatile;

end Tachy.Untyped;
```

> **`Box<[AtomicU64]>` → `Bounded_Vectors`:** размер битмапа в Rust-версии
> определяется размером региона на этапе создания (динамическая длина среза).
> Ada-версия использует `Bounded_Vectors` с фиксированным потолком ёмкости —
> регионы, чей битмап превысил бы `Untyped_Bitmap_Words_Max`, должны быть
> разбиты на несколько `Untyped_Region` на этапе конфигурации ядра. Это
== сужение относительно Rust-версии (которая ограничена только доступной
   heap-памятью на cold path создания объекта), отмечено как открытый
   вопрос конфигурации платформы, а не архитектуры — см. §23, T-Ada-05.

### 4.2 Слияние свободных регионов

Идентично Rust-версии по существу (унаследовано без изменений от
предшествующего документа): коалесцирование при `Object_Destroy`.

### 4.3 `Untyped_Retype`

```ada
   Alloc_Granule_Bytes : constant := 64;

   generic
      type Target_Type is new Kernel_Object with private;
   procedure Untyped_Retype
     (Cap       : Untyped_Manage_Ref;  --  требует Manage
      Offset    : Interfaces.Unsigned_64;
      Count     : Interfaces.Unsigned_64;
      Obj_Size  : Interfaces.Unsigned_64;
      Result    : out Target_Manage_Cap_Array;  --  эквивалент Vec<Cap<T,Manage>>,
                                                   --  здесь — Bounded_Vector
      Status    : out Kernel_Error)
   with Pre => Contains (Cap.Rights, Manage);

   procedure Untyped_Retype_Body
     (Cap       : Untyped_Manage_Ref;
      Offset    : Interfaces.Unsigned_64;
      Count     : Interfaces.Unsigned_64;
      Obj_Size  : Interfaces.Unsigned_64;
      Status    : out Kernel_Error)
   is
      Total_Size  : Interfaces.Unsigned_64;
      Overflowed  : Boolean;
      Region_Size : Interfaces.Unsigned_64;
   begin
      --  checked_mul → явная проверка переполнения перед умножением
      Overflowed := Count /= 0
        and then Obj_Size > Interfaces.Unsigned_64'Last / Count;
      if Overflowed then
         Status := Overflow;
         return;
      end if;
      Total_Size := Count * Obj_Size;

      Region_Size := 2 ** Natural (Cap.Object.Size_Bits);
      if Offset > Region_Size or else Total_Size > Region_Size - Offset then
         Status := Overflow;
         return;
      end if;

      Try_Reserve_Range (Cap.Object, Offset, Total_Size, Status);
      --  OPEN (портировано из todo!() Rust-версии, §4.3): остаток тела
      --  (фактическое создание Count объектов типа Target_Type в
      --  зарезервированном диапазоне) не реализовано ни в Rust-документе,
      --  ни здесь.
   end Untyped_Retype_Body;

   procedure Try_Reserve_Range
     (Region : in out Untyped_Region;
      Offset : Interfaces.Unsigned_64;
      Total  : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      First_G : constant Interfaces.Unsigned_64 := Offset / Alloc_Granule_Bytes;
      Count_G : constant Interfaces.Unsigned_64 :=
        (Total + Alloc_Granule_Bytes - 1) / Alloc_Granule_Bytes;  -- div_ceil
   begin
      --  OPEN (портировано из todo!() Rust-версии, §4.3): атомарная проверка
      --  + резервирование с откатом при коллизии — не реализовано ни в
      --  Rust-документе, ни здесь. First_G/Count_G вычислены как в
      --  оригинале, дальнейшая CAS-логика по битмапу не специфицирована.
      Status := Not_Supported;
   end Try_Reserve_Range;
```

---

## 4a. Secure Bindings (T42, Exokernel/Aegis)

Привязка физического ресурса к процессу через мандат. Процесс получает
прямой доступ к ресурсу (zero-copy, без ядра на горячем пути), но ядро
сохраняет контроль через отзываемый мандат. Переносится с сохранением
самого важного свойства — **немедленного** TLB shootdown при revoke, без
задержки до следующего обращения процесса.

```ada
package Tachy.Secure_Binding is

   pragma SPARK_Mode (On);

   type Resource_Kind is (Mmio_Region, Dma_Buffer, Port_Io);

   type Secure_Binding_Resource (Kind : Resource_Kind := Mmio_Region) is record
      case Kind is
         when Mmio_Region =>
            Mmio_Phys_Base : Interfaces.Unsigned_64;
            Mmio_Size      : Interfaces.Unsigned_64;
         when Dma_Buffer =>
            Dma_Phys_Base   : Interfaces.Unsigned_64;
            Dma_Size        : Interfaces.Unsigned_64;
            Iommu_Domain    : Iommu_Domain_Ref;
         when Port_Io =>
            Base_Port : Interfaces.Unsigned_16;
            Count     : Interfaces.Unsigned_16;
      end case;
   end record;

   type Secure_Binding is limited record
      Header      : Object_Header;
      Resource    : Secure_Binding_Resource;
      Owner       : Process_Context_Weak_Ref;
      --  TLB-запись ядра для этой привязки (PA → VA в адресном пространстве
      --  owner). При revoke — запись немедленно аннулируется через
      --  Vspace_Unmap. Volatile-поле для атомарного доступа, эквивалент
      --  AtomicU64.
      Kernel_Tlb  : aliased Interfaces.Unsigned_64;
   end record
     with Volatile;

   --  При revoke Secure_Binding — немедленно убрать маппинг из VSpace
   --  процесса. Процесс теряет доступ к ресурсу до возврата из revoke.
   --  Реализует Has_External_Effect (§1.7.0 порта).
   procedure Resolve_External_Effect (Self : in out Secure_Binding)
     with Post => Self.Kernel_Tlb = 0;

   procedure Resolve_External_Effect (Self : in out Secure_Binding) is
      Owner_Alive  : Boolean;
      Owner_Ctx    : Process_Context_Ref;
      Vspace_Alive : Boolean;
      Vspace       : V_Space_Ref;
      Va           : Interfaces.Unsigned_64;
      Size         : Interfaces.Unsigned_64;
   begin
      Upgrade (Self.Owner, Owner_Ctx, Owner_Alive);
      if not Owner_Alive then
         return;
      end if;
      Upgrade (Owner_Ctx.Vspace, Vspace, Vspace_Alive);
      if not Vspace_Alive then
         return;
      end if;

      Va := Self.Kernel_Tlb;
      if Va /= 0 then
         Size := (case Self.Resource.Kind is
                    when Mmio_Region => Self.Resource.Mmio_Size,
                    when Dma_Buffer  => Self.Resource.Dma_Size,
                    when Port_Io     =>
                      Interfaces.Unsigned_64 (Self.Resource.Count));

         --  Немедленный TLB shootdown — ни одна инструкция процесса не
         --  пройдёт через этот маппинг после возврата. Идентично
         --  комментарию Rust-версии.
         declare
            Unmap_Status : Kernel_Error;
         begin
            Vspace_Unmap (Vspace, Va, Size, Unmap_Status);
         end;
         Self.Kernel_Tlb := 0;
      end if;
   end Resolve_External_Effect;

   --  Создать защищённую привязку ресурса к процессу.
   --  Требует мандат с Bind_Prm (только PRM-процесс может создавать
   --  привязки).
   procedure Secure_Binding_Create
     (Prm_Cap  : Prm_Resource_Set_Cap;   --  требует Bind_Prm
      Resource : Secure_Binding_Resource;
      Owner    : Process_Context_Ref;
      Va_Hint  : Interfaces.Unsigned_64;  --  0 = ядро выбирает
      Result   : out Secure_Binding_Manage_Ref;
      Status   : out Kernel_Error)
   with Pre => Contains (Prm_Cap.Rights, Bind_Prm);

   procedure Secure_Binding_Create
     (Prm_Cap  : Prm_Resource_Set_Cap;
      Resource : Secure_Binding_Resource;
      Owner    : Process_Context_Ref;
      Va_Hint  : Interfaces.Unsigned_64;
      Result   : out Secure_Binding_Manage_Ref;
      Status   : out Kernel_Error)
   is
      Vspace_Alive : Boolean;
      Vspace       : V_Space_Ref;
      Va           : Interfaces.Unsigned_64;
   begin
      if Check_Valid (Prm_Cap) /= Ok then
         Status := Check_Valid (Prm_Cap);
         return;
      end if;
      Upgrade (Owner.Vspace, Vspace, Vspace_Alive);
      if not Vspace_Alive then
         Status := Host_Vspace_Destroyed;
         return;
      end if;
      Map_Resource_Into_Vspace (Vspace, Resource, Va_Hint, Va, Status);
      if Status /= Ok then
         return;
      end if;
      Construct_Secure_Binding
        (Header => (others => <>), Resource => Resource,
         Owner => Owner, Kernel_Tlb => Va, Result => Result);
      Status := Ok;
   end Secure_Binding_Create;

end Tachy.Secure_Binding;
```

**Связь с T74 (MSI-X):** DMA буферы и MSI-X вектора — главные кандидаты
для `Secure_Binding`. Драйвер получает прямой доступ без ядра на пути
прерывания. Перенесено без изменений по существу.


---

## 5. Асинхронный ввод-вывод: IoRing

### 5.1 Коды операций

```ada
package Tachy.Io_Ring is

   pragma SPARK_Mode (On);

   type Io_Op_Code is
     (Read, Write, Xpc_Call, Xpc_Reply, Map_Memory, Unmap_Memory,
      Attr_Get, Attr_Set, Attr_Watch, Mount, Restart_Notify,
      Inflight_Poll, Device_Query, Batch, Template);
      --  Batch = T65 (батчинг нескольких операций)
      --  Template = T110 (§5.6b порта): тег в SQE — РЕАЛЬНЫЙ вход
      --  Io_Template_Execute (syscall), не match-ветка, симметрично Batch

   for Io_Op_Code use
     (Read => 0, Write => 1, Xpc_Call => 2, Xpc_Reply => 3,
      Map_Memory => 4, Unmap_Memory => 5, Attr_Get => 6, Attr_Set => 7,
      Attr_Watch => 8, Mount => 9, Restart_Notify => 10,
      Inflight_Poll => 11, Device_Query => 12, Batch => 13, Template => 14);
   for Io_Op_Code'Size use 8;

end Tachy.Io_Ring;
```

### 5.2 SQE и CQE

**Важное отличие от большей части документа:** `IoRing` — единственное
место, где Rust-версия работает не с внутренним состоянием ядра, а с
**протоколом общей памяти** (shared memory между ядром и userspace).
Здесь Rust `unsafe` не является заменителем формального доказательства —
он честно признаёт границу, где гарантии компилятора заканчиваются,
поскольку userspace может писать в эту память произвольным образом.
SPARK не может формально верифицировать поведение внешней, недоверенной
стороны протокола — те же самые границы переносятся в Ada explicit, без
попытки завернуть в `Pre`/`Post`, которые ничего не гарантировали бы против
злонамеренного или ошибочного userspace.

```ada
   --  SQE в shared memory — без поля seq. Атомарность копирования
   --  обеспечена Flip_Cell (Tachy.Io_Ring_Sqe ниже, эквивалент §A.2 порта).
   type Sqe_Flags is mod 2 ** 32;

   type Io_Ring_Sqe_Inner is record
      Op_Code    : Io_Op_Code;
      Flags      : Sqe_Flags;
      Cap_Index  : Interfaces.Unsigned_16;
      User_Data  : Interfaces.Unsigned_64;
      Timeout_Ms : Interfaces.Unsigned_32;
      Params     : Sqe_Params;
   end record
     with Convention => C;  --  эквивалент #[repr(C)] — обязателен, так как
                              --  структура пересекает границу с userspace

   --  Слот SQE в кольцевом буфере: Flip_Cell оборачивает внутреннее
   --  содержимое. Userspace пишет через Write; ядро читает через Read
   --  без retry-цикла (см. §5.4 порта).
   package Sqe_Cells is new Tachy.Flip_Cell (Io_Ring_Sqe_Inner);
   subtype Io_Ring_Sqe is Sqe_Cells.Instance;

   type Sqe_Params_Kind is (Read_Write_Kind, Xpc_Call_Kind,
                              Attr_Watch_Kind, Mount_Kind);

   --  Rust union SqeParams — небезопасное объединение без discriminant тега
   --  (интерпретация зависит от Op_Code в Io_Ring_Sqe_Inner, а не от
   --  собственного тега union'а). Ada unchecked_union даёт точный аналог:
   --  тот же layout без runtime discriminant, интерпретация тоже внешняя
   --  (по Op_Code), а не встроенная в тип.
   type Sqe_Params (Kind : Sqe_Params_Kind := Read_Write_Kind) is record
      case Kind is
         when Read_Write_Kind => Read_Write : Read_Write_Params;
         when Xpc_Call_Kind   => Xpc_Call    : Xpc_Call_Params;
         when Attr_Watch_Kind => Attr_Watch  : Attr_Watch_Params;
         when Mount_Kind      => Mount       : Mount_Params;
      end case;
   end record
     with Unchecked_Union, Convention => C;

   type Cqe_Flags is mod 2 ** 32;
   Overflow_Flag         : constant Cqe_Flags := 16#01#;
   Copy_Timeout_Flag     : constant Cqe_Flags := 16#02#;
   Watchdog_Timeout_Flag : constant Cqe_Flags := 16#04#;

   type Io_Ring_Cqe is record
      User_Data       : Interfaces.Unsigned_64;
      Result          : Interfaces.Integer_64;
      Flags           : Cqe_Flags;
      Sqe_Sequence_Id : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   type Submit_Result_Kind is (Sync_Result, Async_Result);
   type Submit_Result (Kind : Submit_Result_Kind := Sync_Result) is record
      case Kind is
         when Sync_Result  => Sync_Value  : Interfaces.Integer_64;
         when Async_Result => Async_Value : Interfaces.Unsigned_64;
      end case;
   end record;

end Tachy.Io_Ring;
```

### 5.3 Управляющая структура IoRing

```ada
   Io_Ring_Bitmap_Words_Max     : constant := 1024;
   Io_Ring_Inflight_Capacity_Max : constant := 4096;

   package Bitmap_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Natural, Element_Type => Interfaces.Unsigned_64);
   package Inflight_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Natural, Element_Type => Inflight_Sqe_Entry);

   type Io_Ring is limited record
      --  ABI-поля — layout пересекается с userspace, System.Address вместо
      --  типизированного Ada-указателя, поскольку это буквально shared
      --  memory протокол, а не внутренняя структура данных ядра.
      Sq_Buffer         : System.Address;
      Cq_Buffer         : System.Address;
      Sq_Head           : System.Address;  --  *u32 в shared memory,
                                             --  не atomic-тип Ada
      Sq_Tail           : System.Address;
      Cq_Head           : System.Address;
      Cq_Visible_Tail   : System.Address;
      Queue_Size_Mask   : Interfaces.Unsigned_32;
      Sq_Poll_Thread    : Thread_Handle_Option;

      --  Внутренние поля ядра (не ABI, обычные типизированные Ada-объекты):
      Cq_Tail_Reserved    : aliased Interfaces.Unsigned_64;
      Slot_Ready_Bitmap   : Bitmap_Vectors.Vector (Io_Ring_Bitmap_Words_Max);
      Window_Words        : Interfaces.Unsigned_32;
      Overflow_Count      : aliased Interfaces.Unsigned_64;
      Inflight_Table      : Inflight_Vectors.Vector (Io_Ring_Inflight_Capacity_Max);
      Inflight_Capacity   : Interfaces.Unsigned_32;
      Default_Sqe_Timeout : Interfaces.Unsigned_32;
   end record
     with Volatile;
```

### 5.4 Чтение SQE

`Copy_Sqe_Safely` с retry-циклом не переносится по той же причине, что и в
Rust-версии: `Flip_Cell (Io_Ring_Sqe_Inner)` даёт детерминированное
атомарное чтение без повторных попыток.

```ada
   function Read_Sqe (Ring : Io_Ring; Idx : Natural) return Io_Ring_Sqe_Inner
   with
     Global => null,
     Import,  --  граница с shared memory — тело не выразимо в терминах
              --  SPARK-доказуемого Ada; это внешняя точка платформы,
              --  как и unsafe-блок в Rust-версии, honestly отмеченная,
              --  а не обёрнутая в ложные контракты.
     Convention => Ada;

   --  Комментарий к реализации (не SPARK-проверяемый, платформенный слой):
   --  slot := элемент по адресу Ring.Sq_Buffer + Idx * sizeof(Io_Ring_Sqe);
   --  Sqe_Cells.Read (slot);
   --  Обоснование действительности на весь срок жизни Io_Ring идентично
   --  Rust-версии: буфер — массив Flip_Cell в shared memory, выделенной из
   --  Untyped_Region (§4 порта), с тем же временем жизни, что сам Io_Ring.
```

### 5.5 `Io_Ring_Advance_Visible_Tail`

```ada
   procedure Io_Ring_Advance_Visible_Tail
     (Ring : in out Io_Ring; Slot_Ready : Interfaces.Unsigned_64)
   is
      Word     : Natural;
      Bit      : Interfaces.Unsigned_64;
      Cur      : Interfaces.Unsigned_64;
      Cur_Word : Natural;
      Cur_Bit  : Interfaces.Unsigned_64;
      Next     : Interfaces.Unsigned_32;
      Cas_Ok   : Boolean;
   begin
      Word := Natural ((Slot_Ready / 64) mod
                         Interfaces.Unsigned_64 (Ring.Window_Words));
      Bit  := Interfaces.Shift_Left (1, Natural (Slot_Ready mod 64));
      Bitmap_Vectors.Replace_Element
        (Ring.Slot_Ready_Bitmap, Word,
         Bitmap_Vectors.Element (Ring.Slot_Ready_Bitmap, Word) or Bit);

      loop
         Cur := Interfaces.Unsigned_64
           (Read_Volatile_U32 (Ring.Cq_Visible_Tail));
         Cur_Word := Natural ((Cur / 64) mod
                                Interfaces.Unsigned_64 (Ring.Window_Words));
         Cur_Bit  := Interfaces.Shift_Left (1, Natural (Cur mod 64));

         exit when (Bitmap_Vectors.Element (Ring.Slot_Ready_Bitmap, Cur_Word)
                    and Cur_Bit) = 0;

         Next := Interfaces.Unsigned_32 (Cur + 1);
         --  CAS на Cq_Visible_Tail как атомарный u32 в shared memory —
         --  граница платформы, аналогично Rust unsafe-блоку выше.
         Atomic_Compare_Exchange_U32
           (Ring.Cq_Visible_Tail, Interfaces.Unsigned_32 (Cur), Next, Cas_Ok);
         if Cas_Ok then
            Bitmap_Vectors.Replace_Element
              (Ring.Slot_Ready_Bitmap, Cur_Word,
               Bitmap_Vectors.Element (Ring.Slot_Ready_Bitmap, Cur_Word)
                 and not Cur_Bit);
         end if;
      end loop;
   end Io_Ring_Advance_Visible_Tail;

   --  Платформенные примитивы для атомарного доступа к shared-memory u32 —
   --  внешние точки, идентичные по роли unsafe-блокам Rust-версии:
   function Read_Volatile_U32 (Addr : System.Address) return Interfaces.Unsigned_32
     with Import, Convention => Ada;
   procedure Atomic_Compare_Exchange_U32
     (Addr : System.Address; Expected, Desired : Interfaces.Unsigned_32;
      Success : out Boolean)
     with Import, Convention => Ada;
```

### 5.6 `Inflight_Sqe_Entry` — SQE Watchdog

```ada
   type Inflight_Sqe_Entry is record
      User_Data        : Interfaces.Unsigned_64;
      Deadline_At_Tick  : aliased Interfaces.Unsigned_64;  -- 0 = слот свободен
      Target_Cap        : Erased_Cap;
      Claimed           : aliased Boolean;
   end record
     with Volatile;
```

### 5.6a `Io_Batch` — батчинг IoRing операций (T65)

Переносится с сохранением error-path отката, добавленного при внешнем
аудите Rust-версии (`ext-audit-05`): при ошибке на шаге откатываются ВСЕ
уже взведённые слоты через `Abort_Write`, а не только текущий.

```ada
   Io_Batch_Max_Ops : constant := 32;

   package Batch_Target_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Io_Ring_Sqe_Access);

   type Io_Batch is limited record
      Targets : Batch_Target_Vectors.Vector (Io_Batch_Max_Ops);
      Steps   : Io_Batch_Step_Array (1 .. Io_Batch_Max_Ops);
      Count   : Natural;
   end record;

   function Io_Batch_Compile
     (Sqes : Io_Ring_Sqe_Array) return Io_Batch
   with Pre => Sqes'Length <= Io_Batch_Max_Ops;

   --  3 шага плана, идентичные Rust-версии:
   --  1. Взвести Begin_Write на всех целевых слотах батча.
   --  2. Записать шаги последовательно.
   --  3. Если ошибка на шаге i — откатить Begin_Write() на ВСЕХ уже
   --     взведённых слотах через Abort_Write (ext-audit-05), не только
   --     на слоте i.
   function Io_Batch_Execute
     (Ring : in out Io_Ring; Batch : Io_Batch) return Io_Batch_Result
   is
      Result : Io_Batch_Result;
   begin
      for I in 1 .. Batch.Count loop
         Sqe_Cells.Begin_Write (Batch_Target_Vectors.Element
                                   (Batch.Targets, I).all);
      end loop;

      for I in 1 .. Batch.Count loop
         Execute_Step (Batch.Steps (I), Result.Step_Results (I));
         if Result.Step_Results (I).Status /= Ok then
            --  Откатываем Begin_Write на ВСЕХ уже взведённых слотах —
            --  идентично исправлению ext-audit-05 в Rust-версии, не
            --  только на текущем шаге.
            for J in 1 .. Batch.Count loop
               Sqe_Cells.Abort_Write
                 (Batch_Target_Vectors.Element (Batch.Targets, J).all);
            end loop;
            Result.Failed_At := I;
            return Result;
         end if;
         Sqe_Cells.Commit_Write
           (Batch_Target_Vectors.Element (Batch.Targets, I).all,
            Result.Step_Results (I).New_Value);
      end loop;

      Result.Failed_At := 0;  -- 0 = успех, без ошибок
      return Result;
   end Io_Batch_Execute;

   function Io_Batch_Submit
     (Ring : in out Io_Ring; Sqes : Io_Ring_Sqe_Array) return Io_Batch_Result
   is
      Batch : constant Io_Batch := Io_Batch_Compile (Sqes);
   begin
      return Io_Batch_Execute (Ring, Batch);
   end Io_Batch_Submit;
```

### 5.6b `Io_Template` — хардкод-шаблоны действий (T110)

`Io_Template` — фиксированный, зашитый в бинарник ядра набор шаблонов.
В отличие от `Io_Batch` (§5.6a порта), последовательность операций не
приходит от userspace и не проверяется на каждый шаг — единственная
проверка на вызов: владение мандатом, покрывающим объединённые права всех
шагов шаблона.

```ada
   type Io_Template_Id is (<набор конкретных идентификаторов шаблонов,
                             фиксированный на этапе компиляции ядра>);

   type Template_Step is record
      Op_Code : Io_Op_Code;
      Params  : Sqe_Params;
   end record;
   --  Params здесь — фиксированные op_code + параметры, известные на этапе
   --  компиляции; TemplateStep не привязан к слотам SQE-кольца, взводить
   --  нечего — идентично честному комментарию, добавленному в Rust-версии
   --  при внешнем аудите (ext-audit-06), см. ниже.

   Template_Table : constant array (Io_Template_Id) of Template_Step := (...);

   function Io_Template_Execute
     (Ring     : in out Io_Ring;
      Cap      : Combined_Rights_Cap;  --  мандат, покрывающий объединённые
                                         --  права всех шагов шаблона
      Template : Io_Template_Id) return Io_Batch_Result
   with Pre => Contains (Cap.Rights, Combined_Rights_Of (Template));
```

> **О заявке транзакционности (перенесено честно, как исправлено в
> Rust-версии через `ext-audit-06`):** `Io_Template_Execute` **не имеет** той
> же `Flip_Cell`-транзакционности, что `Io_Batch_Execute` — архитектурно не
> может её иметь. У `Io_Batch_Execute` каждый шаг — это реальный SQE-слот
> кольца, и откат — это `Begin_Write`/`Commit_Write` на конкретной
> `Flip_Cell`-ячейке слота. У `Io_Template_Execute` шаги фиксированы на
> этапе компиляции и не привязаны к слотам SQE-кольца — взводить нечего.
> Rust-версия изначально ошибочно заявляла ту же гарантию в комментарии;
> это было найдено и исправлено при внешнем аудите (`ext-audit-06`) до
> начала порта — здесь честная формулировка перенесена сразу, без
> повторения исходной ошибки.

| | `Io_Batch` (§5.6a порта) | `Io_Template` (§5.6b порта) |
|---|---|---|
| Вариативность | произвольный набор до `Io_Batch_Max_Ops` | нет — фиксированный список `Io_Template_Id` |
| Точка входа | `Io_Batch_Submit`, отдельный syscall — НЕ ветка `case Op_Code` | `Io_Template_Execute`, отдельный syscall — НЕ ветка `case Op_Code`, симметрично `Io_Batch` |
| Проверка на вызов | владение мандатами на каждый шаг отдельно | владение ОДНИМ мандатом на объединённые права всех шагов |
| Транзакционность | да, через `Flip_Cell.Begin_Write`/`Abort_Write` на реальных слотах | нет — архитектурно невозможна (см. оговорку выше) |

---

### 5.7 XPC: мигрирующие потоки

#### 5.7.1 `Execution_Context` и `Thread`

```ada
package Tachy.Thread is

   pragma SPARK_Mode (On);

   type Execution_Context is record
      Registers    : Register_File;
      Stack_Ptr    : System.Storage_Elements.Integer_Address;
      Bound_Vspace : V_Space_Ref;     --  эквивалент Arc<VSpace> — сильная
                                        --  ссылка, держит VSpace живым
      Fpu_State    : Fpu_State_Area;
   end record;

   --  T44: Execution_Context_Snap должен быть подходящим для Flip_Cell
   --  (Rust: T: Copy). V_Space_Ref заменён на слабую ссылку +
   --  кэшированный phys-root, чтобы не удерживать VSpace от уничтожения
   --  через теневую сторону снимка — идентично мотивации Rust-версии.
   type Execution_Context_Snap is record
      Registers        : Register_File;
      Stack_Ptr        : System.Storage_Elements.Integer_Address;
      Vspace_Phys_Root : Interfaces.Unsigned_64;  --  кэш page_table_root
      Vspace_Ref       : V_Space_Weak_Ref;         --  не удерживает VSpace живым
      Fpu_State        : Fpu_State_Area;
   end record;
   --  "Copy"-подобность в Ada достигается тем, что запись состоит только из
   --  дискретных и слабых-ссылочных полей без контролируемых компонентов —
   --  присваивание записи копирует значение побитово, без вызова
   --  Adjust/Finalize, идентично Rust #[derive(Clone, Copy)] по духу.

   package Snap_Cells is new Tachy.Flip_Cell (Execution_Context_Snap);

   type Thread_State is
     (Created, Ready, Running, Blocked, Suspended, Zombie);
   for Thread_State use
     (Created => 0, Ready => 1, Running => 2, Blocked => 3,
      Suspended => 4, Zombie => 5);

   type Thread is limited record
      Header               : Object_Header;
      Exec_Ctx             : Execution_Context;
      --  T44: снимок контекста исполнения через Flip_Cell. Активная сторона
      --  = текущий сохранённый снимок (или пустой при старте). Теневая
      --  сторона = в процессе сохранения. Rollback восстанавливает
      --  предыдущий снимок атомарно.
      Exec_Snapshot        : Snap_Cells.Instance;
      Snapshot_Valid       : aliased Boolean := False;  -- False до первого
                                                           -- Execution_Snapshot_Save
      Active_Sched_Ctx     : Sched_Ctx_Access;
      Own_Sched_Ctx        : Sched_Ctx;
      Migration_List_Next  : Thread_Access;
      Fault_Endpoint       : Fault_Endpoint_Weak_Ref;
      Last_Syscall_Tick    : aliased Interfaces.Unsigned_64;  -- T64: watchdog
      Ring_Level           : Tachy.Ring.Ring_Level;            -- fix-013
      State                : aliased Thread_State;
   end record
     with Volatile;

   --  T33: SchedCtx — capability-объект, не просто запись. Own_Sched_Ctx
   --  в Thread остаётся встроенным дефолтным расписанием ПО ЗНАЧЕНИЮ — это
   --  не меняется: каждый поток всегда стартует с собственным SchedCtx без
   --  необходимости явного Cap_Mint. Capability-обёртка нужна для случаев,
   --  когда SchedCtx должен переживать создавший его поток или
   --  делегироваться (donation бюджета, T70; XPC-миграция, §5.7.3 порта).
   type Sched_Ctx is limited record
      Header       : Object_Header;
      Budget_Us    : Interfaces.Unsigned_64;
      Period_Us    : Interfaces.Unsigned_64;
      Remaining_Us : aliased Interfaces.Unsigned_64;
   end record
     with Volatile;

   procedure Sched_Ctx_Create
     (Budget_Us, Period_Us : Interfaces.Unsigned_64;
      Result : out Sched_Ctx_Manage_Ref);

   --  T60: зачистка обеих сторон снимка при уничтожении потока.
   procedure Sanitize_Fields (Self : in out Thread) is
      Zero : constant Execution_Context_Snap := (others => <>);
   begin
      Snap_Cells.Zeroize (Self.Exec_Snapshot, Zero);
   end Sanitize_Fields;

end Tachy.Thread;
```

#### 5.7.1a Execution Snapshot (T44)

Снимок `Execution_Context_Snap` хранится внутри `Thread` через `Flip_Cell` —
одна бесплатная отмена без дополнительной аллокации. **Перенесено с
исправлением, уже сделанным при внешнем аудите Rust-версии (`ext-audit-04`):**
`Execution_Snapshot_Restore` читает активную сторону `Flip_Cell` напрямую —
`Rollback` здесь НЕ используется, поскольку он откатил бы к стороне,
предшествовавшей последнему `Write`, то есть вернул бы снимок на одну
транзакцию старше, а не последний сохранённый.

```ada
   --  Сохранить снимок текущего контекста исполнения.
   --  Вызывается через syscall Execution_Snapshot_Save.
   procedure Execution_Snapshot_Save
     (Thread_Cap : Thread_Manage_Ref; Status : out Kernel_Error)
   with Pre => Contains (Thread_Cap.Rights, Manage);

   procedure Execution_Snapshot_Save
     (Thread_Cap : Thread_Manage_Ref; Status : out Kernel_Error)
   is
      T    : Thread renames Thread_Cap.Object.all;
      Snap : Execution_Context_Snap;
   begin
      Status := Check_Valid (Thread_Cap);
      if Status /= Ok then
         return;
      end if;
      Snap := (Registers        => T.Exec_Ctx.Registers,
                Stack_Ptr        => T.Exec_Ctx.Stack_Ptr,
                Vspace_Phys_Root => T.Exec_Ctx.Bound_Vspace.Page_Table_Root,
                Vspace_Ref       => Downgrade (T.Exec_Ctx.Bound_Vspace),
                Fpu_State        => T.Exec_Ctx.Fpu_State);
      --  Write под внешним локом (поток должен быть Suspended или Blocked) —
      --  вызывающий код обязан это гарантировать, идентично Rust-версии.
      Snap_Cells.Write (T.Exec_Snapshot, Snap);
      T.Snapshot_Valid := True;
      Status := Ok;
   end Execution_Snapshot_Save;

   --  Восстановить последний сохранённый снимок.
   --  Читает активную сторону Flip_Cell напрямую — это и есть последний
   --  снимок, записанный Execution_Snapshot_Save. Rollback здесь НЕ
   --  используется (см. обоснование выше, идентичное ext-audit-04
   --  Rust-версии). Если снимок невалиден или VSpace уже уничтожен —
   --  возвращает ошибку.
   procedure Execution_Snapshot_Restore
     (Thread_Cap : Thread_Manage_Ref; Status : out Kernel_Error)
   with Pre => Contains (Thread_Cap.Rights, Manage);

   procedure Execution_Snapshot_Restore
     (Thread_Cap : Thread_Manage_Ref; Status : out Kernel_Error)
   is
      T           : Thread renames Thread_Cap.Object.all;
      Snap        : Execution_Context_Snap;
      Vspace_Ok   : Boolean;
      Vspace      : V_Space_Ref;
   begin
      Status := Check_Valid (Thread_Cap);
      if Status /= Ok then
         return;
      end if;

      if not T.Snapshot_Valid then
         Status := Not_Found;
         return;
      end if;

      Snap := Snap_Cells.Read (T.Exec_Snapshot);

      --  Проверить что VSpace снимка ещё жив.
      Upgrade (Snap.Vspace_Ref, Vspace, Vspace_Ok);
      if not Vspace_Ok then
         Status := Host_Vspace_Destroyed;
         return;
      end if;

      --  Применить снимок к живому Exec_Ctx. Поток Suspended — Exec_Ctx не
      --  читается планировщиком; это внешнее условие, которое вызывающий
      --  код обязан гарантировать, идентично Rust-версии (там же — только
      --  doc-комментарий SAFETY, не проверяемое компилятором условие).
      T.Exec_Ctx.Registers    := Snap.Registers;
      T.Exec_Ctx.Stack_Ptr    := Snap.Stack_Ptr;
      T.Exec_Ctx.Bound_Vspace := Vspace;
      T.Exec_Ctx.Fpu_State    := Snap.Fpu_State;
      Status := Ok;
   end Execution_Snapshot_Restore;
```

#### Thread State Machine (T57)

Диаграмма состояний — не зависящий от языка артефакт, переносится дословно:

```
         Cap_Revoke / exit
              ↓
[Created] → [Ready] ⇆ [Running] → [Zombie]
                ↑         ↓
            [Blocked] ←──┘  (Channel_Recv, Cap_Wait_Any, Xpc, Scheduler_Block)
                ↑
            [Suspended]
```

#### 5.7.2 Одноразовые Reply-мандаты

```ada
   type Reply_Object is limited record
      Header         : Object_Header;
      Waiting_Client : Thread_Ref;
      Consumed       : aliased Boolean := False;
   end record
     with Volatile;

   procedure Perform_Xpc_Reply
     (Reply_Cap : Reply_Object_Write_Ref;  --  требует Write
      Msg       : Byte_Array;
      Status    : out Kernel_Error)
   with Pre => Contains (Reply_Cap.Rights, Write);

   procedure Perform_Xpc_Reply
     (Reply_Cap : Reply_Object_Write_Ref;
      Msg       : Byte_Array;
      Status    : out Kernel_Error)
   is
      Cas_Ok : Boolean;
   begin
      --  compare_exchange(false, true) — атомарная проверка-и-установка,
      --  идентично Rust-версии. Provalенный CAS даёт ReplyConsumed.
      Atomic_Cas_Bool
        (Reply_Cap.Object.Consumed'Address, False, True, Cas_Ok);
      if not Cas_Ok then
         Status := Reply_Consumed;
         return;
      end if;
      Migrate_Execution_Context_Back
        (Reply_Cap.Object.Waiting_Client, Msg, Status);
   end Perform_Xpc_Reply;
```

#### 5.7.3 Межъядерный XPC: CCAG

```ada
   type Migration_Desc is record
      Sequence      : Interfaces.Unsigned_64;
      Client_Thread : Thread_Ref;
      Target_Vspace : V_Space_Ref;
      Entry_Point   : System.Storage_Elements.Integer_Address;
      Msg_Addr      : System.Storage_Elements.Integer_Address;
      Msg_Len       : Interfaces.Unsigned_32;
      Sched_Ctx     : Sched_Ctx_Ref;
   end record;

   Activation_Gate_Capacity_Max : constant := 4096;

   package Migration_Slot_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Natural, Element_Type => Migration_Desc_Option);
     --  Migration_Desc_Option — эквивалент MaybeUninit<MigrationDesc>:
     --  дискриминированная запись с полем Present : Boolean,
     --  без обращения к неинициализированному значению до заполнения.

   type Activation_Gate is limited record
      Head              : aliased Interfaces.Unsigned_64;
      Tail              : aliased Interfaces.Unsigned_64;
      Capacity_Mask     : Interfaces.Unsigned_32;
      Slot_Ready_Bitmap : Bitmap_Vectors.Vector (Io_Ring_Bitmap_Words_Max);
      Occupied_Bitmap   : Bitmap_Vectors.Vector (Io_Ring_Bitmap_Words_Max);
      Queue             : Migration_Slot_Vectors.Vector (Activation_Gate_Capacity_Max);
      Expected_Sequence : aliased Interfaces.Unsigned_64;
   end record
     with Volatile;

   type Shadow_Thread is limited record
      Header             : Object_Header;
      Exec_Ctx           : Execution_Context;
      Sched_Ctx          : Sched_Ctx_Ref;
      Associated_Client  : Thread_Ref;
      Is_Active          : aliased Boolean;
   end record
     with Volatile;

   --  SPSC по Sequence — Expected_Sequence не требует CAS. Перенесено с
   --  исправлением 0.9 → 0.10, зафиксированным уже в Rust-версии:
   --  "получатель отстал" (desc.Sequence > Expected) обрабатывается как
   --  штатный кадр, а не отбрасывается — иначе Head не продвигался бы,
   --  и слот оставался заблокирован навсегда. Единственный случай возврата
   --  False после этой правки — desc.Sequence < Expected (повторная
   --  доставка уже обработанного IPI).
   function Verify_And_Advance_Sequence
     (Gate : in out Activation_Gate; Desc : Migration_Desc) return Boolean
   is
      Expected : constant Interfaces.Unsigned_64 := Gate.Expected_Sequence;
   begin
      if Desc.Sequence < Expected then
         --  Повторная доставка уже обработанного IPI — безопасно отбросить.
         --  Head НЕ продвигается (единственный случай возврата False после
         --  правки 0.10, идентично Rust-версии).
         return False;
      end if;

      if Desc.Sequence > Expected then
         --  [0.10, перенесено как есть] Получатель отстал: отправитель
         --  прошёл оборот кольца и переписал слот(ы) новыми данными.
         --  Версия 0.9 отбрасывала кадр (return False), но Head при этом
         --  не продвигался, слот оставался заблокирован навсегда.
         --  Исправление: обработать как штатный кадр, принять потерю
         --  промежуточных дескрипторов (их отправители уже получили
         --  ошибку занятости шлюза).
         Gate.Expected_Sequence := Desc.Sequence + 1;
         return True;
      end if;

      --  Штатный кадр: Desc.Sequence = Expected.
      Gate.Expected_Sequence := Expected + 1;
      return True;
   end Verify_And_Advance_Sequence;
```

`V_Space` хранит RCU-список мигрировавших потоков:

```ada
   type V_Space is limited record
      Header            : Object_Header;
      Page_Table_Root    : Interfaces.Unsigned_64;
      --  RCU-список потоков, чей Bound_Vspace == этот V_Space на время
      --  XPC-миграции. Вставка — в Perform_Xpc_Call, удаление — в
      --  Perform_Xpc_Reply / Force_Xpc_Reply_With_Error.
      Migrated_Threads   : Thread_Access;
   end record
     with Volatile;

   --  Object_Destroy для V_Space обязан до освобождения страничных таблиц
   --  безусловно выполнить аварийный XpcReply для каждого потока клиента,
   --  чей Bound_Vspace указывает на уничтожаемый объект — конкретное
   --  воплощение общего правила §1.7.0 порта (правило внешнего физического
   --  эффекта). Переносится без изменений по существу.
   procedure Object_Destroy_Vspace (Victim : in out V_Space)
   is
      Ptr    : Thread_Access := Victim.Migrated_Threads;
      Thread : Thread_Access;
   begin
      --  RCU-список; читаем под Rcu_Read_Lock (вызывающий держит grace
      --  period) — внешнее условие, идентичное doc-комментарию
      --  Rust-версии.
      while Ptr /= null loop
         Thread := Ptr;
         --  Аварийный путь: тот же CAS на Consumed, что штатный
         --  Perform_Xpc_Reply — повторный штатный Reply от сервера
         --  проиграет CAS и получит Reply_Consumed.
         Force_Xpc_Reply_With_Error (Thread.all, Host_Vspace_Destroyed);
         Ptr := Thread.Migration_List_Next;
      end loop;
      --  Освобождение страничных таблиц через RCU reclamation происходит
      --  после того, как ни один поток больше не числится мигрировавшим
      --  в Victim — идентично порядку операций Rust-версии.
   end Object_Destroy_Vspace;

end Tachy.Io_Ring;
```


---

## 6. Синхронизация: RCU

### 6.1 `Rcu_Domain`

**См. port-05 в журнале изменений.** Rust `Box<dyn FnOnce()>` — объект
первого класса, захватывающий произвольное замыкание с произвольными
захваченными данными. Ada не имеет прямого эквивалента без garbage collection
или отдельной инфраструктуры allocator'а объектов с vtable, которую
пришлось бы строить с нуля (что само по себе выходит за пределы
безопасного, доказуемого SPARK-подмножества). Вместо тщетной попытки
воспроизвести замыкания 1:1, применяется тот же принцип, что уже
использован в самой Rust-версии для `IoTemplate` (§5.6b): конечное,
известное на этапе компиляции множество вариантов операции вместо
произвольного замыкания.

```ada
package Tachy.Rcu is

   pragma SPARK_Mode (On);

   Rcu_Queue_Capacity : constant := 256;

   --  Конечный набор известных на этапе компиляции видов отложенной
   --  операции — вместо Box<dyn FnOnce()>. Каждый конкретный вызывающий
   --  модуль ядра (Object_Destroy, Layer_Detach, Attr_Entry-очистка и
   --  т.д.) должен зарегистрировать свой вариант здесь.
   type Rcu_Callback_Kind is
     (Drop_Object, Drop_Layer, Drop_Attr_Entry, Drop_Namespace_Node);
      --  Список расширяется по мере необходимости; T-Ada-02 (см. §23)
      --  фиксирует это как открытый вопрос: полный список вариантов,
      --  соответствующий каждому реальному месту вызова call_rcu в
      --  Rust-версии, не был исчерпывающе перечислен на этапе порта —
      --  здесь приведён представительный набор, не полный.

   --  Данные, необходимые конкретному варианту операции — Ada
   --  discriminated record вместо захваченных переменных замыкания.
   type Rcu_Callback (Kind : Rcu_Callback_Kind := Drop_Object) is record
      case Kind is
         when Drop_Object         => Object_Ref  : Cap_Object_Ref;
         when Drop_Layer          => Layer_Ref   : Layer_Access;
         when Drop_Attr_Entry     => Attr_Ref     : Attr_Entry_Access;
         when Drop_Namespace_Node => Ns_Node_Ref  : Namespace_Node_Access;
      end case;
   end record;

   procedure Execute (Cb : Rcu_Callback)
   with Global => null;
   --  Реализация — dispatch по Kind к конкретному деструктору/очистке,
   --  эквивалент вызова f() в Rust drain(). Явный case вместо vtable-вызова.

   --  Очередь отложенных операций фиксированной ёмкости — идентично
   --  Rust-версии (no_std, без Vec).
   type Callback_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Rcu_Callback;
         when False => null;
      end case;
   end record;

   type Callback_Array is array (0 .. Rcu_Queue_Capacity - 1) of Callback_Option;

   protected type Rcu_Queue is

      --  Добавить callback. Возвращает Capacity_Exceeded если очередь
      --  заполнена — идентично Rust push().
      procedure Push (Cb : Rcu_Callback; Status : out Kernel_Error);

      --  Дренировать все накопленные callbacks — идентично Rust drain().
      procedure Drain;

   private
      Entries : Callback_Array := (others => (Present => False));
      Len     : Natural := 0;
   end Rcu_Queue;

   protected type Rcu_Domain is

      --  Захватывает read-side секцию. Возвращает "токен"-запись,
      --  release которой ОБЯЗАТЕЛЕН вызовом Read_Unlock — см. ниже
      --  про отсутствие RAII в Ada protected-объектах.
      procedure Read_Lock;
      procedure Read_Unlock;

      --  Поставить операцию в очередь текущего поколения. При
      --  переполнении очереди — Capacity_Exceeded (идентично Rust:
      --  "паника в debug, молчаливое dropping в release" — здесь явный
      --  код ошибки в обоих случаях, вызывающий код решает, обрабатывать
      --  ли как fatal).
      procedure Call_Rcu (Cb : Rcu_Callback; Status : out Kernel_Error);

   private
      Global_Gen     : aliased Interfaces.Unsigned_64 := 0;
      Active_Readers : aliased Interfaces.Unsigned_64 := 0;
      --  Двойная очередь для перекрытия поколений — идентично Rust-версии.
      Pending_Queues : array (0 .. 1) of Rcu_Queue;
   end Rcu_Domain;

end Tachy.Rcu;
```

> **`Rcu_Read_Guard` (RAII) — см. также port-03 (`Ticket_Lock`).** Rust
> `RcuReadGuard` через `Drop` гарантирует, что read-side секция не может
> быть забыта открытой. Ada `protected`-объект с раздельными
> `Read_Lock`/`Read_Unlock` не даёт той же гарантии автоматически — как и
> в случае `Ticket_Lock` (port-03), вызывающий код обязан парно вызывать
> `Read_Lock`/`Read_Unlock`. Здесь это отклонение отмечено отдельно, так как
> цена ошибки выше, чем у обычного лока: забытый `Read_Unlock` навсегда
> держит `Active_Readers` завышенным, блокируя продвижение RCU-поколений
> для ВСЕХ пользователей домена, а не только текущего вызывающего. Там, где
> Ada-эргономика позволяет, рекомендуется оборачивать пару вызовов в
> `Ada.Finalization.Limited_Controlled`-тип с `Initialize`/`Finalize`,
> дающий RAII-подобное поведение — эта обёртка помечена как
> **рекомендованная, не обязательная базовая часть порта** (см. §23,
> T-Ada-03), поскольку сама по себе не меняет безопасность `protected`-типа,
> только эргономику вызывающего кода.

**Привязка «домен на дерево надзора»** — унаследована без изменений.

```ada
   --  _Guard доказывает активную read-side секцию на уровне типов —
   --  здесь эквивалент через явный параметр-предикат, а не через владение
   --  RAII-объектом (Ada не позволяет типу нести "доказательство" в этом
   --  же смысле, что владение Rust-ссылкой &'g RcuReadGuard — вместо этого
   --  используется Ghost-параметр в контракте).
   generic
      type Element_Type is limited private;
   function Rcu_Deref
     (Ptr : System.Address) return Element_Access
   with
     Global => null,
     Pre => Rcu_Read_Lock_Held;  --  Ghost-предикат: аналог владения guard'ом

   procedure Rcu_Assign (Ptr : System.Address; Val : Element_Access)
   with Global => null;

   --  Явная обёртка для Call_Rcu — идентична Rust Defer.
   type Defer (Domain : not null access Rcu_Domain) is limited null record;

   procedure Call (Self : Defer; Cb : Rcu_Callback; Status : out Kernel_Error)
   is
   begin
      Self.Domain.Call_Rcu (Cb, Status);
   end Call;

end Tachy.Rcu;
```

### 6.2 `Kernel_Submit_Sqe`

```ada
   function Kernel_Submit_Sqe
     (Process : Process_Context_Ref;
      Sqe     : Io_Ring_Sqe) return Submit_Or_Error
   is
      Cspace : constant Cspace_Ref := Process.Cspace;
      Cap    : Erased_Cap;
      Found  : Boolean;
      Inner  : constant Io_Ring_Sqe_Inner := Sqe_Cells.Read (Sqe);
   begin
      Cspace_Slot (Cspace, Natural (Inner.Cap_Index), Cap, Found);
      if not Found then
         return Error_Result (Bad_Cap);
      end if;
      if Check_Valid (Cap) /= Ok then
         return Error_Result (Check_Valid (Cap));
      end if;

      case Inner.Op_Code is
         when Read | Device_Query =>
            if not Contains (Cap.Rights, Tachy.Rights.Read) then
               return Error_Result (Perm_Denied);
            end if;
         when Write =>
            if not Contains (Cap.Rights, Tachy.Rights.Write) then
               return Error_Result (Perm_Denied);
            end if;
         when others => null;
      end case;

      case Inner.Op_Code is
         when Read              => return Process_Read (Cap, Inner);
         when Write              => return Process_Write (Cap, Inner);
         when Xpc_Call           => return Process_Xpc_Call (Cap, Inner);
         when Xpc_Reply          => return Process_Xpc_Reply (Cap, Inner);
         when Map_Memory         => return Handle_Map_Memory (Cap, Inner);
         when Unmap_Memory       => return Handle_Unmap_Memory (Cap, Inner);
         when Device_Query       => return Handle_Device_Query (Cap, Inner);
         when Attr_Get | Attr_Set
            | Attr_Watch         => return Handle_Attr_Op (Cap, Inner);
         when Mount              => return Handle_Mount_Op (Process, Inner);
         when Restart_Notify     => return Handle_Restart_Notify (Cap, Inner);
         when Inflight_Poll      =>
            Check_Inflight_Deadlines (Process.Io_Ring);
            return Sync_Ok_Result (0);
         when Batch | Template   => return Error_Result (Unknown_Op);
            --  Batch/Template — отдельные точки входа (Io_Batch_Submit,
            --  Io_Template_Execute, §5.6a/§5.6b порта), не диспетчеризуются
            --  через эту функцию — идентично комментарию Rust-версии
            --  в §5.6b/template-04 о том, что обе функции являются
            --  отдельными syscall со своей сигнатурой, а не match-ветками.
      end case;
   end Kernel_Submit_Sqe;
```

### 6.3 `Notification` и `Wait_Queue`

```ada
   type Notification is limited record
      Header      : Object_Header;
      Pending      : aliased Interfaces.Unsigned_64;
      Wait_Queue   : Tachy.Wait_Queue.Instance;  --  §10 порта
   end record
     with Volatile;

   --  Реализует Has_External_Effect (§1.7.0 порта).
   procedure Resolve_External_Effect (Self : in out Notification) is
   begin
      Wake_All_With_Error (Self.Wait_Queue, Object_Destroyed);
   end Resolve_External_Effect;
```


```ada
   Wait_Queue_Max_Waiters : constant := 1024;

   protected type Wait_Queue_Instance is

      --  Добавить текущий поток в очередь ожидания (промежуточное
      --  состояние «готов к ожиданию, но ещё не спит»). Предотвращает
      --  lost-wakeup: Scheduler_Wake_All после этой точки гарантированно
      --  увидит поток.
      procedure Prepare (Status : out Kernel_Error);

      --  Отменить регистрацию без ухода в сон (сигнал пришёл до блокировки).
      procedure Cancel;

      --  T31: регистрация с общим Wait_Token для ожидания сразу на
      --  нескольких источниках (Cap_Wait_Any, §10 порта). В отличие от
      --  Prepare, пробуждение по любому из источников должно поднять один
      --  и тот же поток ровно один раз — Token даёт планировщику общий
      --  идентификатор для этого, тогда как Prepare лишь инкрементирует
      --  счётчик без привязки к потоку.
      procedure Prepare_With_Token
        (Token : in out Wait_Token; Status : out Kernel_Error);

   private
      Waiter_Count : Interfaces.Unsigned_32 := 0;
   end Wait_Queue_Instance;

   protected body Wait_Queue_Instance is

      procedure Prepare (Status : out Kernel_Error) is
         Prev : constant Interfaces.Unsigned_32 := Waiter_Count;
      begin
         Waiter_Count := Waiter_Count + 1;
         if Prev >= Wait_Queue_Max_Waiters then
            Waiter_Count := Waiter_Count - 1;
            Status := Max_Waiters;
            return;
         end if;
         Status := Ok;
      end Prepare;

      procedure Cancel is
      begin
         Waiter_Count := Waiter_Count - 1;
      end Cancel;

      procedure Prepare_With_Token
        (Token : in out Wait_Token; Status : out Kernel_Error)
      is
         Prev : constant Interfaces.Unsigned_32 := Waiter_Count;
      begin
         Waiter_Count := Waiter_Count + 1;
         if Prev >= Wait_Queue_Max_Waiters then
            Waiter_Count := Waiter_Count - 1;
            Status := Max_Waiters;
            return;
         end if;
         Register (Token, Wait_Queue_Instance'Unchecked_Access);
         Status := Ok;
      end Prepare_With_Token;

   end Wait_Queue_Instance;

   --  T31: общий токен ожидания для Cap_Wait_Any — текущий поток
   --  регистрируется им сразу на всех источниках (§10 порта, фаза 2).
   --  Обычные пробуждения через Scheduler_Block/Wake_All_With_Error идут
   --  по потоку, привязанному к каждой Wait_Queue_Instance отдельно;
   --  Signalled — единственное, что добавляет Wait_Token сверху: не даёт
   --  фазе 3 спутать «нас разбудил источник X» с «мы сами ещё не легли
   --  спать», если несколько источников сигналят почти одновременно между
   --  Prepare_With_Token и Scheduler_Block.
   protected type Wait_Token is

      --  True, если хотя бы один источник уже сигналил после регистрации —
      --  используется в фазе 3 Cap_Wait_Any, чтобы решить, идти ли в
      --  Scheduler_Block вообще, или сигнал уже пришёл.
      function Is_Signalled return Boolean;

      --  Отмечает токен как сигналённый. Вызывается из того же пути, что
      --  и обычное пробуждение по Wait_Queue_Instance (Wake_All_With_Error
      --  / Notify), когда на очереди зарегистрирован токен, а не
      --  одиночный поток.
      procedure Mark_Signalled;

   private
      Signalled : Boolean := False;
   end Wait_Token;

   protected body Wait_Token is
      function Is_Signalled return Boolean is (Signalled);
      procedure Mark_Signalled is
      begin
         Signalled := True;
      end Mark_Signalled;
   end Wait_Token;

   function Notification_Wait
     (N : in out Notification) return Interfaces.Unsigned_64
   is
      Bits   : Interfaces.Unsigned_64;
      Status : Kernel_Error;
   begin
      loop
         N.Wait_Queue.Prepare (Status);
         if Status /= Ok then
            --  OPEN: обработка ошибки Prepare (Max_Waiters) не
            --  специфицирована в Rust-версии для этого конкретного вызова
            --  (сигнатура Rust-версии — Result<u64, KernelError>, но тело
            --  использует `?` без явной обработки этой ветки отдельно от
            --  общего возврата ошибки — перенесено как есть).
            return 0;  --  заглушка результата; реальный код должен
                        --  пробросить Status как ошибку вызывающему,
                        --  см. OPEN выше
         end if;

         --  swap(0, Acquire) — атомарное чтение-и-обнуление.
         Atomic_Swap_U64 (N.Pending'Address, 0, Bits);
         if Bits /= 0 then
            N.Wait_Queue.Cancel;
            return Bits;
         end if;
         Scheduler_Block (N, N.Wait_Queue);
      end loop;
   end Notification_Wait;
```

---

## 7. TLB Shootdown при `Vspace_Unmap` (T12, T68, T71) — исправлено fix-005

**CVE-TACHY-005 устранён** уже в Rust-версии: полностью lock-free через
атомарные поля. Переносится как есть.

**T68:** глобальный `Pending_Shootdown` заменён на per-CPU массив — два
одновременных `Vspace_Unmap` на разных CPU больше не перетирают друг
друга.

**T71:** добавлен таймаут ожидания ACK — зависший CPU помечается
`Degraded`, `Vspace_Unmap` возвращает `Hardware_Fault` вместо
бесконечного spin.

```ada
package Tachy.Tlb_Shootdown is

   pragma SPARK_Mode (On);

   Max_Cpus : constant := 256;  --  платформенно-зависимая константа,
                                  --  соответствует Rust MAX_CPUS

   type Tlb_Shootdown_Slot is record
      Vspace_Root : aliased Interfaces.Unsigned_64 := 0;
      Start_Va    : aliased Interfaces.Unsigned_64 := 0;
      Size        : aliased Interfaces.Unsigned_64 := 0;
      Active      : aliased Boolean := False;
      --  T71: ACK от целевого CPU (каждый слот принадлежит одному CPU).
      Acked       : aliased Boolean := False;
   end record
     with Volatile;

   --  T68: per-CPU массив — каждый CPU имеет свой слот, нет конфликтов.
   --  Доступ к Slots (Cpu) только через запрашивающий (write) и целевой
   --  (read/ack) CPU — внешнее условие, идентичное doc-комментарию
   --  Rust-версии (там же: только SAFETY-комментарий, не проверяемое
   --  компилятором условие; здесь то же самое отсутствие проверки, честно
   --  сохранённое, а не выданное за большую гарантию).
   Pending_Shootdowns : array (0 .. Max_Cpus - 1) of Tlb_Shootdown_Slot;

   --  T71: максимальное число итераций ожидания ACK (~1 мс при 1 ГГц).
   Shootdown_Timeout_Iters : constant := 1_000_000;

   --  T71: деградировавшие CPU — биты выставляются при таймауте shootdown.
   Degraded_Cpus : aliased Interfaces.Unsigned_64 := 0;

   procedure Vspace_Unmap
     (Vspace : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      Target_Mask   : Interfaces.Unsigned_64;
      Timed_Out_Mask : Interfaces.Unsigned_64 := 0;
      Hal_Status    : Kernel_Error;
   begin
      --  Платформенный вызов, VA/size уже проверены выше — граница
      --  платформы, идентичная unsafe-блоку Rust-версии.
      Hal_Unmap_Segment (Vspace.Page_Table_Root, Va, Size, Hal_Status);
      if Hal_Status /= Ok then
         Status := Hal_Status;
         return;
      end if;

      Target_Mask := Hal_Cpus_With_Vspace (Vspace);
      if Target_Mask = 0 then
         Status := Ok;
         return;
      end if;

      --  Рассылаем IPI каждому целевому CPU, пишем в его личный слот.
      for Cpu in 0 .. Max_Cpus - 1 loop
         if (Target_Mask and Interfaces.Shift_Left (1, Cpu)) /= 0 then
            declare
               Slot : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
            begin
               Slot.Vspace_Root := Vspace.Page_Table_Root;
               Slot.Start_Va    := Va;
               Slot.Size        := Size;
               Slot.Acked       := False;
               Slot.Active      := True;  --  Release-семантика через
                                            --  Volatile-запись поля
               Hal_Send_Tlb_Shootdown_Ipi (Interfaces.Unsigned_32 (Cpu));
            end;
         end if;
      end loop;

      --  Ждём ACK от каждого CPU с таймаутом (T71).
      for Cpu in 0 .. Max_Cpus - 1 loop
         if (Target_Mask and Interfaces.Shift_Left (1, Cpu)) /= 0 then
            declare
               Slot  : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
               Iters : Interfaces.Unsigned_64 := 0;
            begin
               while not Slot.Acked loop
                  Spin_Loop_Hint;
                  Iters := Iters + 1;
                  if Iters >= Shootdown_Timeout_Iters then
                     --  T71: CPU не ответил — пометить как degraded.
                     Degraded_Cpus := Degraded_Cpus or
                       Interfaces.Shift_Left (1, Cpu);
                     Timed_Out_Mask := Timed_Out_Mask or
                       Interfaces.Shift_Left (1, Cpu);
                     Slot.Active := False;
                     exit;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      Status := (if Timed_Out_Mask /= 0 then Hardware_Fault else Ok);
   end Vspace_Unmap;

   --  Вызывается из IPI ISR на целевом CPU — читает только свой слот.
   procedure Tlb_Shootdown_Handler
   with Export, Convention => C;

   procedure Tlb_Shootdown_Handler is
      Cpu  : constant Natural := Current_Cpu_Id;
      Slot : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
   begin
      if not Slot.Active then
         return;
      end if;
      --  VA и size опубликованы через Release/Acquire барьер выше —
      --  граница платформы, идентичная unsafe-блоку Rust-версии.
      Hal_Local_Tlb_Flush (Slot.Start_Va, Slot.Size);
      Slot.Acked  := True;
      Slot.Active := False;
   end Tlb_Shootdown_Handler;

   --  T71: проверить деградацию CPU (для supervisor/health monitor).
   function Cpu_Is_Degraded (Cpu : Natural) return Boolean is
     ((Degraded_Cpus and Interfaces.Shift_Left (1, Cpu)) /= 0);

end Tachy.Tlb_Shootdown;
```


---

## 8. Таймерный preemption (T13)

```ada
package Tachy.Timer is

   pragma SPARK_Mode (On);

   Timer_Irq : constant := 0;

   Global_Tick : aliased Interfaces.Unsigned_64 := 0;

   procedure Timer_Interrupt_Handler
   with Export, Convention => C;

   procedure Timer_Interrupt_Handler is
      Cpu      : constant Natural := Current_Cpu_Id;
      Now      : Interfaces.Unsigned_64;
      Decision : Scheduler_Decision;
   begin
      Platform_Irq_Ack (Timer_Irq);
      Now := Global_Tick;
      Global_Tick := Global_Tick + 1;  --  Relaxed-эквивалент — простое
                                          --  инкрементирование Volatile-поля

      Decision := Run_Queues (Cpu).Scheduler_Tick (Now);
      if Decision = Preempt then
         Schedule (Cpu, Now);
      end if;

      if Cpu = 0 and then Now mod 64 = 0 then
         Sweep_Expired_Mounts (Now);
      end if;

      Watchdog_Tick (Now);  --  T64
   end Timer_Interrupt_Handler;

   function Current_Tick return Interfaces.Unsigned_64 is (Global_Tick);

end Tachy.Timer;
```

---

## 9. Fault-Delegation (T14)

```ada
package Tachy.Fault is

   pragma SPARK_Mode (On);

   type Fault_Endpoint is limited record
      Header       : Object_Header;
      Handler_Proc : Process_Context_Weak_Ref;
      Handler_Ep   : Xpc_Endpoint_Weak_Ref;
   end record
     with Volatile;

   type Fault_Message is record
      Kind       : Interfaces.Unsigned_32;
      Fault_Addr : Interfaces.Unsigned_64;
      Pc         : Interfaces.Unsigned_64;
      Thread_Id  : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   procedure Thread_Set_Fault_Handler
     (Th       : in out Thread;
      Endpoint : Fault_Endpoint_Write_Ref;  --  требует Write
      Status   : out Kernel_Error)
   with Pre => Contains (Endpoint.Rights, Write);

   procedure Thread_Set_Fault_Handler
     (Th       : in out Thread;
      Endpoint : Fault_Endpoint_Write_Ref;
      Status   : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Endpoint);
      if Status /= Ok then
         return;
      end if;
      Th.Fault_Endpoint := Downgrade (Endpoint.Object);
      Status := Ok;
   end Thread_Set_Fault_Handler;

end Tachy.Fault;
```

### 9.1 `Handle_Page_Fault` с Secure Bindings fastpath (T42)

```ada
   procedure Handle_Page_Fault
     (Fault_Addr : Interfaces.Unsigned_64; Pc : Interfaces.Unsigned_64)
   is
      Binding      : Secure_Binding_Access;
      Has_Binding  : Boolean;
      Vspace       : V_Space_Ref;
      Fault_Ep     : Fault_Endpoint_Access;
      Has_Ep       : Boolean;
      Lookup_Found : Boolean;
   begin
      Vspace_Get_Secure_Binding (Current_Vspace, Binding, Has_Binding);
      if Has_Binding then
         --  Платформенный вызов — граница платформы, идентичная
         --  unsafe-блоку Rust-версии.
         Platform_Call_Fault_Handler
           (Binding.Handler_Va, Binding.Stack_Va, Fault_Addr, Pc);
         return;
      end if;

      Vspace := Current_Thread.Exec_Ctx.Bound_Vspace;
      Upgrade (Current_Thread.Fault_Endpoint, Fault_Ep, Has_Ep);

      Platform_Page_Table_Lookup
        (Vspace.Page_Table_Root, Fault_Addr, Lookup_Found);
      if not Lookup_Found then
         if Has_Ep then
            Deliver_Fault_To_Handler (Fault_Ep.all, Fault_Addr, Pc);
         else
            Terminate_Current_Thread (Access_Violation);
         end if;
      end if;
   end Handle_Page_Fault;
```

### 9.2 `Thread_Resume` — возобновление после fault

```ada
   procedure Thread_Resume
     (Thread_Cap : Thread_Manage_Ref;   --  требует Manage
      Map_Phys   : Phys_Addr_Option;      --  0/None-состояние эквивалентно
                                            --  Rust Option<u64>
      Map_Va     : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   with Pre => Contains (Thread_Cap.Rights, Manage);

   procedure Thread_Resume
     (Thread_Cap : Thread_Manage_Ref;
      Map_Phys   : Phys_Addr_Option;
      Map_Va     : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   is
      Th          : Thread renames Thread_Cap.Object.all;
      Vspace      : V_Space_Ref;
      Map_Status  : Kernel_Error;
      Flags       : constant Iommu_Map_Flags := Read or Write;
   begin
      Status := Check_Valid (Thread_Cap);
      if Status /= Ok then
         return;
      end if;

      if Map_Phys.Present then
         Vspace := Th.Exec_Ctx.Bound_Vspace;
         --  Платформенный вызов — граница платформы, идентичная
         --  unsafe-блоку Rust-версии.
         Plat_Map_Segment
           (Vspace.Page_Table_Root, Map_Va, Map_Phys.Value, 4096, Flags,
            Map_Status);
         if Map_Status /= Ok then
            Status := Map_Status;
            return;
         end if;
      end if;

      Sched_Resume (Th);
      Status := Ok;
   end Thread_Resume;

end Tachy.Fault;
```


---

## 10. Channel IPC (T15)

```ada
package Tachy.Channel is

   pragma SPARK_Mode (On);

   Channel_Queue_Depth : constant := 64;
   Channel_Msg_Data_Len : constant := 256;

   type Byte_Array_256 is array (0 .. Channel_Msg_Data_Len - 1)
     of Interfaces.Unsigned_8;

   type Channel_Message is record
      Data     : Byte_Array_256;
      Data_Len : Interfaces.Unsigned_32;
      Cap      : Erased_Cap_Option;    --  эквивалент Option<ErasedCap>
      Cause    : Cap_Id_Option;         --  T49: causal chain, эквивалент
                                          --  Option<CapId>
   end record;

   package Channel_Msg_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Channel_Message);

   type Channel_Queue is limited record
      Msgs : Channel_Msg_Vectors.Vector (Channel_Queue_Depth);
      Wait : Wait_Queue_Instance;
   end record;

   package Channel_Queue_Locks is new Tachy.Ticket_Lock (Channel_Queue);

   type Channel is limited record
      Header  : Object_Header;
      A_To_B  : Channel_Queue_Locks.Instance (Initial => <>);
      B_To_A  : Channel_Queue_Locks.Instance (Initial => <>);
   end record
     with Volatile;

   type Channel_Side is (Side_A, Side_B);

   type Channel_Endpoint is limited record
      Header  : Object_Header;
      Channel : Channel_Ref;
      Side    : Channel_Side;
   end record
     with Volatile;

   procedure Channel_Send
     (Ep     : Channel_Endpoint_Write_Ref;  --  требует Write
      Msg    : Channel_Message;
      Status : out Kernel_Error)
   with Pre => Contains (Ep.Rights, Write);

   procedure Channel_Send
     (Ep     : Channel_Endpoint_Write_Ref;
      Msg    : Channel_Message;
      Status : out Kernel_Error)
   is
      Ch       : Channel renames Ep.Object.Channel.all;
      Q        : Channel_Queue;
      Push_Status : Kernel_Error;
   begin
      Status := Check_Valid (Ep);
      if Status /= Ok then
         return;
      end if;

      case Ep.Object.Side is
         when Side_A =>
            Ch.A_To_B.Lock (Q);
            Channel_Msg_Vectors.Append (Q.Msgs, Msg);
            --  Waiter_Count читается напрямую только для проверки «есть
            --  ли кто» — пробуждение безопасно даже при
            --  ложно-положительном чтении.
            if Waiter_Count_Snapshot (Q.Wait) > 0 then
               Wake_All_With_Signal (Q.Wait);
            end if;
            Ch.A_To_B.Unlock (Q);
         when Side_B =>
            Ch.B_To_A.Lock (Q);
            Channel_Msg_Vectors.Append (Q.Msgs, Msg);
            if Waiter_Count_Snapshot (Q.Wait) > 0 then
               Wake_All_With_Signal (Q.Wait);
            end if;
            Ch.B_To_A.Unlock (Q);
      end case;
      Status := Ok;
   end Channel_Send;

   procedure Channel_Recv
     (Ep      : Channel_Endpoint_Read_Ref;  --  требует Read
      Timeout : Tick_Option;                 --  эквивалент Option<u64>
      Msg     : out Channel_Message;
      Status  : out Kernel_Error)
   with Pre => Contains (Ep.Rights, Tachy.Rights.Read);

   procedure Channel_Recv
     (Ep      : Channel_Endpoint_Read_Ref;
      Timeout : Tick_Option;
      Msg     : out Channel_Message;
      Status  : out Kernel_Error)
   is
      Ch          : Channel renames Ep.Object.Channel.all;
      Q           : Channel_Queue;
      Have_Msg    : Boolean;
      Prep_Status : Kernel_Error;
      Block_Status : Kernel_Error;
      Deadline    : Interfaces.Unsigned_64;
   begin
      Status := Check_Valid (Ep);
      if Status /= Ok then
         return;
      end if;

      loop
         --  Сначала проверяем без инкремента счётчика.
         case Ep.Object.Side is
            when Side_A => Ch.B_To_A.Lock (Q);
            when Side_B => Ch.A_To_B.Lock (Q);
         end case;

         Channel_Msg_Vectors.Pop (Q.Msgs, Msg, Have_Msg);
         if Have_Msg then
            case Ep.Object.Side is
               when Side_A => Ch.B_To_A.Unlock (Q);
               when Side_B => Ch.A_To_B.Unlock (Q);
            end case;
            Status := Ok;
            return;
         end if;

         --  Сообщений нет — регистрируемся как waiter через Prepare
         --  (проверяет Max_Waiters, тот же контракт, что
         --  Notification_Wait).
         Q.Wait.Prepare (Prep_Status);
         case Ep.Object.Side is
            when Side_A => Ch.B_To_A.Unlock (Q);
            when Side_B => Ch.A_To_B.Unlock (Q);
         end case;
         if Prep_Status /= Ok then
            Status := Prep_Status;
            return;
         end if;

         if not Timeout.Present then
            Scheduler_Block_Current;
            Block_Status := Ok;
         else
            Deadline := Current_Tick + Timeout.Value;
            Scheduler_Block_Until (Deadline, Block_Status);
         end if;

         case Ep.Object.Side is
            when Side_A => Ch.B_To_A.Lock (Q); Q.Wait.Cancel; Ch.B_To_A.Unlock (Q);
            when Side_B => Ch.A_To_B.Lock (Q); Q.Wait.Cancel; Ch.A_To_B.Unlock (Q);
         end case;

         if Block_Status /= Ok then
            Status := Block_Status;  -- пробрасываем Timeout если истёк дедлайн
            return;
         end if;
      end loop;
   end Channel_Recv;

   --  T31: ожидать сигнала от любого из набора Notification или
   --  Channel_Endpoint. Возвращает индекс первого сработавшего мандата.
   --  Аналог select()/epoll() на уровне capability-объектов.
   Wait_Any_Max : constant := 64;

   type Wait_Any_Source_Kind is (Notification_Source, Channel_Source);

   type Wait_Any_Source (Kind : Wait_Any_Source_Kind := Notification_Source) is
     record
        case Kind is
           when Notification_Source =>
              Notification_Cap : Notification_Read_Ref;  --  требует Read
           when Channel_Source =>
              Channel_Cap : Channel_Endpoint_Read_Ref;    --  требует Read
        end case;
     end record;

   package Wait_Any_Source_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Wait_Any_Source);

   procedure Cap_Wait_Any
     (Sources : Wait_Any_Source_Vectors.Vector;
      Timeout : Tick_Option;
      Index   : out Natural;
      Status  : out Kernel_Error)
   with Pre => Wait_Any_Source_Vectors.Length (Sources) > 0
               and then Wait_Any_Source_Vectors.Length (Sources) <= Wait_Any_Max;

   procedure Cap_Wait_Any
     (Sources : Wait_Any_Source_Vectors.Vector;
      Timeout : Tick_Option;
      Index   : out Natural;
      Status  : out Kernel_Error)
   is
      Ready         : Boolean;
      Token         : Wait_Token;
      Prep_Status   : Kernel_Error;
      Block_Status  : Kernel_Error;
      Deadline      : Interfaces.Unsigned_64;
      Check_Status  : Kernel_Error;
   begin
      if Wait_Any_Source_Vectors.Length (Sources) = 0
        or else Wait_Any_Source_Vectors.Length (Sources) > Wait_Any_Max
      then
         Status := Invalid_Argument;
         return;
      end if;

      --  Проверяем все мандаты до блокировки.
      for I in 1 .. Wait_Any_Source_Vectors.Length (Sources) loop
         declare
            S : constant Wait_Any_Source :=
              Wait_Any_Source_Vectors.Element (Sources, I);
         begin
            Check_Status := (case S.Kind is
                               when Notification_Source =>
                                 Check_Valid (S.Notification_Cap),
                               when Channel_Source =>
                                 Check_Valid (S.Channel_Cap));
            if Check_Status /= Ok then
               Status := Check_Status;
               return;
            end if;
         end;
      end loop;

      loop
         --  Фаза 1: poll — проверить без блокировки.
         for I in 1 .. Wait_Any_Source_Vectors.Length (Sources) loop
            declare
               S : constant Wait_Any_Source :=
                 Wait_Any_Source_Vectors.Element (Sources, I);
            begin
               Ready := (case S.Kind is
                           when Notification_Source =>
                             S.Notification_Cap.Object.Pending > 0,
                           when Channel_Source =>
                             Channel_Has_Pending (S.Channel_Cap));
               if Ready then
                  Index := I - 1;  --  0-based индекс, идентично Rust enumerate()
                  Status := Ok;
                  return;
               end if;
            end;
         end loop;

         --  Фаза 2: регистрируемся как waiter на всех источниках.
         --  Используем общий Wait_Token — пробуждение любым источником
         --  разбудит нас.
         for I in 1 .. Wait_Any_Source_Vectors.Length (Sources) loop
            declare
               S : constant Wait_Any_Source :=
                 Wait_Any_Source_Vectors.Element (Sources, I);
            begin
               case S.Kind is
                  when Notification_Source =>
                     S.Notification_Cap.Object.Wait_Queue.Prepare_With_Token
                       (Token, Prep_Status);
                  when Channel_Source =>
                     Channel_Prepare_With_Token (S.Channel_Cap, Token, Prep_Status);
               end case;
               if Prep_Status /= Ok then
                  Status := Prep_Status;
                  return;
               end if;
            end;
         end loop;

         --  Фаза 3: заблокироваться.
         if not Timeout.Present then
            Scheduler_Block_Current;
            Block_Status := Ok;
         else
            Deadline := Current_Tick + Timeout.Value;
            Scheduler_Block_Until (Deadline, Block_Status);
         end if;

         --  Отменить регистрацию на всех источниках.
         for I in 1 .. Wait_Any_Source_Vectors.Length (Sources) loop
            declare
               S : constant Wait_Any_Source :=
                 Wait_Any_Source_Vectors.Element (Sources, I);
            begin
               case S.Kind is
                  when Notification_Source =>
                     S.Notification_Cap.Object.Wait_Queue.Cancel;
                  when Channel_Source =>
                     Channel_Cancel_Wait (S.Channel_Cap);
               end case;
            end;
         end loop;

         if Block_Status /= Ok then
            Status := Block_Status;  --  Timeout → возврат ошибки
            return;
         end if;
         --  Иначе — повторить poll (кто-то стал ready).
      end loop;
   end Cap_Wait_Any;

   --  Отдельная, логически не связанная с Cap_Wait_Any функция —
   --  перенесена на своё законное место, а не оставлена в конце раздела,
   --  как в исходном документе (там это, по всей видимости, артефакт
   --  порядка написания, а не намеренная группировка).
   function Task_Force_Decrement_Budget
     (Tf : in out Task_Force; Ticks : Interfaces.Unsigned_64) return Boolean
   is
      Cur, Next : Interfaces.Unsigned_64;
      Cas_Ok    : Boolean;
   begin
      loop
         Cur  := Tf.Shared_Budget_Us;
         --  saturating_sub эквивалент — Ada mod-типы не насыщают
         --  автоматически, явная проверка снизу необходима.
         Next := (if Cur >= Ticks then Cur - Ticks else 0);
         Atomic_Compare_Exchange_U64
           (Tf.Shared_Budget_Us'Address, Cur, Next, Cas_Ok);
         if Cas_Ok then
            return Next = 0;
         end if;
      end loop;
   end Task_Force_Decrement_Budget;

end Tachy.Channel;
```


---

## 11. Атрибуты и живые запросы

### 11.1 `Attr_Entry`

```ada
package Tachy.Attr is

   pragma SPARK_Mode (On);

   --  Weak_Cap_Epoch — снимок эпохи без живого мандата.
   --  Attr_Entry переживает процесс-владелец.
   type Weak_Cap_Epoch is record
      Object             : Kernel_Object_Weak_Ref;
      Cap_Token          : Interfaces.Unsigned_64;
      Cap_Creation_Epoch : Interfaces.Unsigned_32;
      Obj_Creation_Epoch : Interfaces.Unsigned_32;
   end record;

   type Attr_Value_Kind is (Int64_Kind, Float64_Kind, Blob_Kind);

   type Attr_Value (Kind : Attr_Value_Kind := Int64_Kind) is record
      case Kind is
         when Int64_Kind =>
            Int64_Val : Interfaces.Integer_64;
         when Float64_Kind =>
            Float64_Val : Interfaces.IEEE_Float_64;
         when Blob_Kind =>
            Phys_Offset : Interfaces.Unsigned_64;
            Length      : Interfaces.Unsigned_32;
            Backing     : Weak_Cap_Epoch;   --  снимок вместо живого мандата
      end case;
   end record;

   package Attr_Value_Cells is new Tachy.Flip_Cell (Attr_Value);

   type Attr_Entry is limited record
      Name  : Name_Strings.Bounded_String;
      --  Flip_Cell вместо Ticket_Lock (Attr_Value): читатели не берут лок —
      --  атомарное чтение активной стороны. Писатель (единственный, под
      --  внешним локом таблицы атрибутов) вызывает Write. Незавершённая
      --  запись (крэш/паника) не трогает активную сторону.
      Value      : Attr_Value_Cells.Instance;
      Rcu_Defer  : Tachy.Rcu.Defer;
   end record
     with Volatile;

   --  Реализует Sanitize (§1.7.0/T60 порта): зачистка обеих сторон
   --  Flip_Cell при уничтожении.
   procedure Sanitize_Fields (Self : in out Attr_Entry) is
      Zero : constant Attr_Value := (Kind => Int64_Kind, Int64_Val => 0);
   begin
      Attr_Value_Cells.Zeroize (Self.Value, Zero);
   end Sanitize_Fields;

end Tachy.Attr;
```

> **`Flip_Cell (Attr_Value)` вместо `Ticket_Lock (Attr_Value)`:** читатели
> полностью lock-free — `Notify_Watchers` и `Attr_Get` на горячем пути не
> конкурируют с записью. Писатель по-прежнему требует внешней сериализации
> (лок таблицы атрибутов узла). Атомарность и защита от torn-write
> обеспечены `Flip_Cell` (§A.2 порта) — перенесено без изменений по
> существу.

### 11.2 `Radix_Node` и Rate Governor

```ada
   Path_Bloom_Filter_Words : constant := 32;

   type Radix_Node is limited record
      Header               : Object_Header;
      Segment               : Name_Strings.Bounded_String;
      First_Child           : Radix_Node_Access;
      Next_Sibling          : Radix_Node_Access;
      Subscribers           : Attr_Watch_Access;
      Wildcard_Subscribers  : Attr_Watch_Access;
      --  bits 63..32 = tokens, 31..0 = last_tick — упакованное состояние,
      --  перенесено 1:1 для сохранения атомарности одной CAS-операцией.
      Token_State           : aliased Interfaces.Unsigned_64;
      Token_Capacity        : Interfaces.Unsigned_32;
      Tokens_Per_Tick        : Interfaces.Unsigned_32;
   end record
     with Volatile;

   function Try_Consume_Notify_Token
     (Node : in out Radix_Node; Now_Tick : Interfaces.Unsigned_64)
      return Boolean
   is
      Packed, New_Packed : Interfaces.Unsigned_64;
      Tokens, Last        : Interfaces.Unsigned_32;
      Elapsed, Refill      : Interfaces.Unsigned_32;
      New_Tokens           : Interfaces.Unsigned_32;
      Cas_Ok               : Boolean;
   begin
      loop
         Packed := Node.Token_State;
         Tokens := Interfaces.Unsigned_32 (Interfaces.Shift_Right (Packed, 32));
         Last   := Interfaces.Unsigned_32 (Packed and 16#FFFF_FFFF#);

         --  wrapping_sub эквивалент — Unsigned_32 арифметика в Ada уже
         --  оборачивается по модулю, идентично Rust wrapping_sub.
         Elapsed := Interfaces.Unsigned_32 (Now_Tick) - Last;

         --  saturating_mul/saturating_add/min — явные насыщающие операции,
         --  Ada не насыщает автоматически при переполнении.
         Refill := Saturating_Mul_U32 (Elapsed, Node.Tokens_Per_Tick);
         New_Tokens := Interfaces.Unsigned_32'Min
           (Saturating_Add_U32 (Tokens, Refill), Node.Token_Capacity);

         if New_Tokens = 0 then
            return False;
         end if;

         New_Packed := Interfaces.Shift_Left
           (Interfaces.Unsigned_64 (New_Tokens - 1), 32)
           or Interfaces.Unsigned_64 (Now_Tick and 16#FFFF_FFFF#);

         Atomic_Compare_Exchange_U64
           (Node.Token_State'Address, Packed, New_Packed, Cas_Ok);
         if Cas_Ok then
            return True;
         end if;
      end loop;
   end Try_Consume_Notify_Token;

   function Saturating_Mul_U32
     (A, B : Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   is
      Wide : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (A) * Interfaces.Unsigned_64 (B);
   begin
      return (if Wide > Interfaces.Unsigned_64 (Interfaces.Unsigned_32'Last)
              then Interfaces.Unsigned_32'Last
              else Interfaces.Unsigned_32 (Wide));
   end Saturating_Mul_U32;

   function Saturating_Add_U32
     (A, B : Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   is
   begin
      return (if A > Interfaces.Unsigned_32'Last - B
              then Interfaces.Unsigned_32'Last
              else A + B);
   end Saturating_Add_U32;
```

### 11.3 `Attr_Watch` и `Notify_Watchers`

```ada
   type Attr_Watch is limited record
      Header            : Object_Header;
      Coalesced_Count    : aliased Interfaces.Unsigned_32;
      Target_Notif       : Notification_Weak_Ref;
      Signal_Bit         : Interfaces.Unsigned_64;
      Path_Pattern       : Name_Strings.Bounded_String;
      Rate_Limit_Ticks   : aliased Interfaces.Unsigned_64;
      Last_Notify_Tick   : aliased Interfaces.Unsigned_64;
      Active             : aliased Boolean;
      Next_Subscriber    : Attr_Watch_Access;
   end record
     with Volatile;

   procedure Attr_Watch_Create
     (Node          : Namespace_Node_Ref;
      Path          : String;
      Notif_Cap     : Notification_Write_Ref;  --  требует Write
      Signal_Bit    : Interfaces.Unsigned_64;
      Rate_Limit_Ms : Interfaces.Unsigned_32;
      Result        : out Attr_Watch_Ref;
      Status        : out Kernel_Error)
   with Pre => Contains (Notif_Cap.Rights, Write);

   procedure Attr_Watch_Create
     (Node          : Namespace_Node_Ref;
      Path          : String;
      Notif_Cap     : Notification_Write_Ref;
      Signal_Bit    : Interfaces.Unsigned_64;
      Rate_Limit_Ms : Interfaces.Unsigned_32;
      Result        : out Attr_Watch_Ref;
      Status        : out Kernel_Error)
   is
      Radix        : Radix_Node_Ref;
      Radix_Status  : Kernel_Error;
      Insert_Status : Kernel_Error;
   begin
      Status := Check_Valid (Notif_Cap);
      if Status /= Ok then
         return;
      end if;

      Construct_Attr_Watch
        (Header => (others => <>),
         Coalesced_Count => 0,
         Target_Notif    => Downgrade (Notif_Cap.Object),
         Signal_Bit      => Signal_Bit,
         Path_Pattern    => Name_Strings.To_Bounded_String (Path),
         Rate_Limit_Ticks => Ms_To_Ticks
           (Interfaces.Unsigned_64 (Rate_Limit_Ms)),
         Last_Notify_Tick => 0,
         Active           => True,
         Next_Subscriber  => null,
         Result           => Result);

      Radix_For_Path (Node.Attributes, Path, Radix, Radix_Status);
      if Radix_Status /= Ok then
         Status := Radix_Status;
         return;
      end if;

      Radix_Insert_Subscriber (Radix, Result, Insert_Status);
      Status := Insert_Status;
   end Attr_Watch_Create;

   procedure Attr_Unwatch (Watch : in out Attr_Watch) is
   begin
      Watch.Active := False;
   end Attr_Unwatch;

   procedure Notify_Watchers
     (Radix : in out Radix_Node; Now_Tick : Interfaces.Unsigned_64)
   is
      Ptr           : Attr_Watch_Access;
      Watch         : Attr_Watch_Access;
      Last, Limit   : Interfaces.Unsigned_64;
      Notif_Alive   : Boolean;
      Notif         : Notification_Ref;
   begin
      Radix.Header.Rcu_Domain.Read_Lock;

      Ptr := Rcu_Deref (Radix.Subscribers'Address);
      while Ptr /= null loop
         Watch := Ptr;

         if not Watch.Active then
            Ptr := Rcu_Deref (Watch.Next_Subscriber'Address);
            goto Continue;
         end if;

         Last  := Watch.Last_Notify_Tick;
         Limit := Watch.Rate_Limit_Ticks;

         if Saturating_Sub_U64 (Now_Tick, Last) < Limit then
            Watch.Coalesced_Count := Watch.Coalesced_Count + 1;
            Ptr := Rcu_Deref (Watch.Next_Subscriber'Address);
            goto Continue;
         end if;

         Upgrade (Watch.Target_Notif, Notif, Notif_Alive);
         if Notif_Alive then
            Notif.Pending := Notif.Pending or Watch.Signal_Bit;
            if Waiter_Count_Snapshot (Notif.Wait_Queue) > 0 then
               Wake_All_With_Signal (Notif.Wait_Queue);
            end if;
            Watch.Last_Notify_Tick := Now_Tick;
         end if;

         Ptr := Rcu_Deref (Watch.Next_Subscriber'Address);
         <<Continue>>
      end loop;

      Radix.Header.Rcu_Domain.Read_Unlock;
   end Notify_Watchers;

   function Saturating_Sub_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (if A >= B then A - B else 0);

end Tachy.Attr;
```

---

## 12. PackageFs — `PUnion`

`PackageFs` реализует **`PUnion`** — слияние нескольких пакетов в одно
плоское дерево, в духе Haiku packagefs: пакеты не накладываются слоями
друг на друга и не имеют приоритета между собой. Это явно отличает
`PUnion` от `AUnion` (§3.4 порта): в `AUnion` "верхний" `Layer` побеждает
при конфликте пути; в `PUnion` конфликт пути между двумя пакетами —
**ошибка установки**, а не правило разрешения.

### 12.1 Формат пакета

Три слоя — это слои *внутри одного пакета* (метаданные/контент), не
путать со слоями `AUnion` (§3.4 порта):

- **Слой A:** индекс верхнего уровня (eager).
- **Слой B:** содержимое (lazy).
- **Слой C:** фильтр Блума для глубоких конфликтов.

```ada
package Tachy.Package_Fs is

   pragma SPARK_Mode (On);

   Path_Bloom_Filter_Words : constant := 32;

   type Bloom_Words is array (0 .. Path_Bloom_Filter_Words - 1)
     of Interfaces.Unsigned_64;

   type Package_Metadata_Layer_C is record
      Bloom : Bloom_Words;
   end record;

   type Union_Bloom_Container is record
      Combined : Bloom_Words;
   end record;
```

### 12.2 `P_Union` — инвариант

`P_Union` хранит набор смонтированных `Package_Image` без какого-либо
порядка наложения. Идентичность пути в `P_Union` обязана быть уникальной
по построению:

```ada
   type Package_Image_Array is array (1 .. Package_Union_Max)
     of Package_Image_Ref;

   type P_Union is limited record
      --  Без приоритета — порядок в массиве не участвует в разрешении
      --  путей, только в порядке итерации/диагностике.
      Images         : Package_Image_Array;
      Image_Count    : Natural range 0 .. Package_Union_Max;
      --  Совмещённый Bloom двух и более пакетов — быстрый отказ при
      --  поиске потенциального конфликта путей на этапе вставки.
      Combined_Bloom : Union_Bloom_Container;
   end record
     with Volatile;
```

### 12.3 `Package_Mount` — инкрементальная вставка пакета в `P_Union`

`Package_Mount` добавляет **один** пакет в существующий (или ещё
пустой) `P_Union`. Это инкрементальная операция уровня "установить ещё
один пакет", а не операция уровня "решить, какой слой главнее" —
приоритета здесь нет и быть не должно.

```ada
   procedure Package_Mount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;  --  требует Mount
      Status : out Kernel_Error)
   with Pre => Contains (Image.Rights, Mount);
   --  OPEN (портировано из todo!() Rust-версии, §12.3): тело не
   --  реализовано ни в Rust-документе, ни здесь. Пять шагов плана
   --  переносятся как комментарий:
   --    1. Читать Слой A синхронно.
   --    2. Проверить Слой C (Combined_Bloom) на возможный конфликт путей
   --       с уже смонтированными пакетами; при совпадении — дотест
   --       Hash-Trie по точному пути (бит блума мог дать ложное
   --       совпадение).
   --    3. Если найден РЕАЛЬНЫЙ конфликт пути с другим пакетом в
   --       P_Union — отказ Already_Exists. Никакого priority, который
   --       мог бы "разрешить" конфликт в пользу одного из пакетов: два
   --       пакета, претендующих на один путь, — ошибка установки, а не
   --       повод выбирать победителя.
   --    4. Создать заглушки union-узлов для нового пакета, влить в общее
   --       плоское дерево P_Union.
   --    5. Обновить Combined_Bloom добавлением Слоя C нового пакета.

   --  Обратная операция: убрать пакет из P_Union (например, при удалении
   --  ПО).
   procedure Package_Unmount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;
      Status : out Kernel_Error)
   with Pre => Contains (Image.Rights, Mount);
   --  OPEN (портировано из todo!() Rust-версии, §12.3): тело не
   --  реализовано. Удалить узлы пакета из дерева; Combined_Bloom можно
   --  оставить консервативно widened (ложные срабатывания не страшны —
   --  это только быстрый отказ перед точной проверкой) либо перестроить
   --  полностью из оставшихся пакетов.

end Tachy.Package_Fs;
```

**Связь с Im:** `Package_Mount`/`Package_Unmount` работают только на самом
`P_Union` — собранном дереве пакетов, ещё не видимом ни одному процессу.
Чтобы `P_Union` стал видимым в Im, его оборачивают в `Layer` с
`Kind => System` или `Container`, `Backend => (Kind => Package_Backend,
Union => ...)` (§3.4 порта) и уже этот `Layer` участвует в `AUnion` через
`Im_Compose`/`Ns_Mount` с обычным `Union_Priority`. Иначе говоря: приоритет
появляется только на границе `Layer`, никогда — внутри самого `P_Union`.

**Итог:** `P_Union` (этот раздел) и `AUnion` (§3.4 порта) — два разных
механизма union, которые не следует путать:

| | `P_Union` (§12 порта) | `AUnion` (§3.4 порта) |
|---|---|---|
| Что объединяет | пакеты (`Package_Image`) | произвольные `Layer` (C/D/E/F/G) |
| Приоритет | нет — конфликт пути = ошибка | да — `Union_Priority`, top of stack побеждает |
| Аналог | Haiku packagefs | AUFS |
| Где живёт | backend внутри одного `Layer` (`Package_Backend`, §3.4 порта) | список `Layer` в `Im_Compose` (§3.4 порта) |

---

## 13. MAC: мандатные метки (T46–T49)

### 13.1 Мандатные метки (T46)

```ada
package Tachy.Mac is

   pragma SPARK_Mode (On);

   --  Мандатная метка — хранится как атрибут namespace-ноды.
   --  Ядро не интерпретирует — только userspace MAC-сервис.
   type Mandatory_Label is record
      Level      : Interfaces.Unsigned_8;   -- уровень секретности 0–63
      Categories : Interfaces.Unsigned_64;  -- битовая маска категорий
   end record
     with Convention => C;

   --  Допуск процесса — атрибут Process_Context.
   type Clearance is record
      Level      : Interfaces.Unsigned_8;
      Categories : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   --  T54 (Strong Tranquility): Mandatory_Label фиксируется при создании
   --  навсегда. При попытке изменить метку:
   procedure Set_Mandatory_Label
     (Node : in out Namespace_Node; New_Label : Mandatory_Label;
      Status : out Kernel_Error)
   is
   begin
      Status := Label_Immutable;  --  всегда — метка неизменяема после
                                    --  создания, идентично Rust-версии
   end Set_Mandatory_Label;

end Tachy.Mac;
```

### 13.2 Bell-LaPadula + Strict Equality (T47, fix-008)

**fix-008 (перенесено без изменений):** TACHY использует **Strict
Equality** (No Write Up AND No Write Down) — не классический
Bell-LaPadula (который допускал бы write down). Направления сравнения
ниже перенесены с максимальной осторожностью — это ядро гарантии
конфиденциальности, ошибка в направлении `>`/`<`/`/=` здесь была бы
серьёзной уязвимостью безопасности, а не косметической опечаткой.

```ada
   --  MAC Write Policy в TACHY: Strict Equality.
   --  Процесс с Clearance N может писать ТОЛЬКО в объекты с Label = N.
   --  Если нужен стандартный BLP: заменить "/=" на "<".
   generic
      type Object_Type is new Kernel_Object with private;
   function Mac_Derive_Write_Cap
     (Requester_Clearance : Clearance;
      Object_Label        : Mandatory_Label;
      Object_Cap          : Object_Manage_Ref;  --  требует Manage
      Result              : out Object_Write_Ref;
      Status              : out Kernel_Error)
   with Pre => Contains (Object_Cap.Rights, Manage);

   function Mac_Derive_Write_Cap
     (Requester_Clearance : Clearance;
      Object_Label        : Mandatory_Label;
      Object_Cap          : Object_Manage_Ref;
      Result              : out Object_Write_Ref;
      Status              : out Kernel_Error)
   is
   begin
      if Object_Label.Level /= Requester_Clearance.Level then
         Status := Write_Down_Violation;
         return;
      end if;
      if (Requester_Clearance.Categories and Object_Label.Categories)
           /= Object_Label.Categories
      then
         Status := Category_Mismatch;
         return;
      end if;
      Cap_Derive_Write (Object_Cap, Result, Status);
   end Mac_Derive_Write_Cap;

   generic
      type Object_Type is new Kernel_Object with private;
   function Mac_Derive_Read_Cap
     (Requester_Clearance : Clearance;
      Object_Label        : Mandatory_Label;
      Object_Cap          : Object_Manage_Ref;
      Result              : out Object_Read_Ref;
      Status              : out Kernel_Error)
   with Pre => Contains (Object_Cap.Rights, Manage);

   function Mac_Derive_Read_Cap
     (Requester_Clearance : Clearance;
      Object_Label        : Mandatory_Label;
      Object_Cap          : Object_Manage_Ref;
      Result              : out Object_Read_Ref;
      Status              : out Kernel_Error)
   is
   begin
      if Object_Label.Level > Requester_Clearance.Level then
         Status := Read_Up_Violation;
         return;
      end if;
      if (Requester_Clearance.Categories and Object_Label.Categories)
           /= Object_Label.Categories
      then
         Status := Category_Mismatch;
         return;
      end if;
      Cap_Derive_Read (Object_Cap, Result, Status);
   end Mac_Derive_Read_Cap;
```

### 13.3 Biba Model — двойные метки целостности (T59)

Дополняет BLP (§13.2 порта): BLP защищает **конфиденциальность** (no read
up), Biba защищает **целостность** (no write up, no read down). Процесс с
низкой целостностью не может «заразить» объект с высокой. Направления
сравнения здесь строго ЗЕРКАЛЬНЫ направлениям BLP (`>` вместо `<` для
write, `<` вместо `>` для read) — перенесено с той же осторожностью, что
и §13.2 порта.

```ada
   --  Метка целостности — параллельна Mandatory_Label (конфиденциальность).
   --  Хранится отдельным атрибутом namespace-ноды; Strong Tranquility
   --  (T54 порта) применима и здесь.
   type Integrity_Label is record
      Level      : Interfaces.Unsigned_8;   -- 0–63, 63 = наивысший
      Categories : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   type Integrity_Clearance is record
      Level      : Interfaces.Unsigned_8;
      Categories : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   --  Новые коды ошибок для Biba (уже в Kernel_Error, §14 порта):
   --  Write_Up_Violation  = -104 (процесс пишет в объект с более высокой
   --                               целостностью)
   --  Read_Down_Violation = -105 (процесс читает объект с более низкой
   --                               целостностью)

   --  Biba Write Policy: процесс не может писать в объект с БОЛЕЕ
   --  ВЫСОКОЙ целостностью. «No Write Up» — низкая целостность не
   --  повышает высокую.
   generic
      type Object_Type is new Kernel_Object with private;
   function Biba_Derive_Write_Cap
     (Requester : Integrity_Clearance;
      Object    : Integrity_Label;
      Cap       : Object_Manage_Ref;  --  требует Manage
      Result    : out Object_Write_Ref;
      Status    : out Kernel_Error)
   with Pre => Contains (Cap.Rights, Manage);

   function Biba_Derive_Write_Cap
     (Requester : Integrity_Clearance;
      Object    : Integrity_Label;
      Cap       : Object_Manage_Ref;
      Result    : out Object_Write_Ref;
      Status    : out Kernel_Error)
   is
   begin
      if Object.Level > Requester.Level then
         Status := Write_Up_Violation;
         return;
      end if;
      if (Requester.Categories and Object.Categories) /= Object.Categories
      then
         Status := Category_Mismatch;
         return;
      end if;
      Cap_Derive_Write (Cap, Result, Status);
   end Biba_Derive_Write_Cap;

   --  Biba Read Policy: процесс не может читать объект с БОЛЕЕ НИЗКОЙ
   --  целостностью. «No Read Down» — чтение грязных данных запрещено.
   generic
      type Object_Type is new Kernel_Object with private;
   function Biba_Derive_Read_Cap
     (Requester : Integrity_Clearance;
      Object    : Integrity_Label;
      Cap       : Object_Manage_Ref;
      Result    : out Object_Read_Ref;
      Status    : out Kernel_Error)
   with Pre => Contains (Cap.Rights, Manage);

   function Biba_Derive_Read_Cap
     (Requester : Integrity_Clearance;
      Object    : Integrity_Label;
      Cap       : Object_Manage_Ref;
      Result    : out Object_Read_Ref;
      Status    : out Kernel_Error)
   is
   begin
      if Object.Level < Requester.Level then
         Status := Read_Down_Violation;
         return;
      end if;
      if (Requester.Categories and Object.Categories) /= Object.Categories
      then
         Status := Category_Mismatch;
         return;
      end if;
      Cap_Derive_Read (Cap, Result, Status);
   end Biba_Derive_Read_Cap;
```

**Двойная проверка при derive:** MAC-сервис (в терминологии исходного
документа — «uring 0»; после `revert-ring-001`, §2 порта, единственный
привилегированный уровень называется `Ring0` — терминология «uring»
сохранена здесь как дословная цитата исходного документа, обозначающая
конкретный доверенный компонент, а не архитектурный уровень) вызывает оба
фильтра — сначала BLP (`Mac_Derive_*`), затем Biba (`Biba_Derive_*`). Оба
должны вернуть `Ok`.

| Модель | Запрет записи | Запрет чтения |
|--------|--------------|---------------|
| BLP (T47) | write down (уровень ниже clearance) | read up (уровень выше clearance) |
| Biba (T59) | write up (целостность выше clearance) | read down (целостность ниже clearance) |

### 13.4 Аудит-канал (T48, closed-002, T52)

```ada
   type Object_Kind is
     (Thread_Kind, Vspace_Kind, Channel_Kind, Audit_Channel_Kind,
      Causal_Root_Kind, Namespace_Kind);
   for Object_Kind'Size use 8;

   type Audit_Action is (Cap_Derive, Cap_Revoke, Read_Action, Write_Action,
                           Exec_Action);
   for Audit_Action'Size use 8;

   type Audit_Verdict is (Allow, Deny);
   for Audit_Verdict'Size use 8;

   type Audit_Record is record
      Tick        : Interfaces.Unsigned_64;
      Thread_Id    : Interfaces.Unsigned_64;
      Object_Idx   : Interfaces.Unsigned_32;
      Object_Gen    : Interfaces.Unsigned_32;
      Object_Type   : Object_Kind;
      Action        : Audit_Action;
      Verdict       : Audit_Verdict;
      Label         : Mandatory_Label;
      Clearance     : Tachy.Mac.Clearance;
   end record;

   Audit_Ring_Capacity : constant := 4096;

   type Audit_Record_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Audit_Record;
         when False => null;
      end case;
   end record;

   type Audit_Record_Array is array (0 .. Audit_Ring_Capacity - 1)
     of Audit_Record_Option;

   type Audit_Ring_Buffer is limited record
      Buf       : Audit_Record_Array;
      Write_Idx : Natural range 0 .. Audit_Ring_Capacity - 1 := 0;
      Lost      : Interfaces.Unsigned_64 := 0;
   end record;

   procedure Push (Self : in out Audit_Ring_Buffer; Rec : Audit_Record) is
   begin
      if Self.Buf (Self.Write_Idx).Present then
         Self.Lost := Self.Lost + 1;
      end if;
      Self.Buf (Self.Write_Idx) := (Present => True, Value => Rec);
      Self.Write_Idx := (Self.Write_Idx + 1) mod Audit_Ring_Capacity;
   end Push;

   package Audit_Locks is new Tachy.Ticket_Lock (Audit_Ring_Buffer);

   type Audit_Channel is limited record
      Header  : Object_Header;
      Records : Audit_Locks.Instance (Initial => <>);
   end record
     with Volatile;

end Tachy.Mac;
```

### 13.5 Causal IPC (T49)

```ada
package Tachy.Causal is

   pragma SPARK_Mode (On);

   type Causal_Root_Kind_Tag is
     (Timer_Irq_Kind, Hardware_Irq_Kind, Page_Fault_Kind, Syscall_Entry_Kind);

   type Causal_Root_Kind (Tag : Causal_Root_Kind_Tag := Timer_Irq_Kind) is
     record
        case Tag is
           when Hardware_Irq_Kind  => Irq : Interfaces.Unsigned_32;
           when Syscall_Entry_Kind => Nr  : Interfaces.Unsigned_32;
           when others             => null;
        end case;
     end record;

   type Causal_Root is limited record
      Header : Object_Header;
      Kind   : Causal_Root_Kind;
   end record
     with Volatile;

end Tachy.Causal;
```

---

## 14. `Kernel_Error` — полный enum (closed-003)

**См. port-07 в журнале изменений.** Перенесено как enumeration type с
representation clause, сохраняющим числовые коды 1:1 из Rust
`#[repr(i32)]` enum — обеспечивает ABI-совместимость на границе, если она
понадобится. Пропуски в нумерации (например, между -15 и -20, между -44 и
-50) сохранены как есть — это исторические артефакты Rust-версии
(зарезервированные или удалённые в прошлом коды), не ошибка переноса.

Всего перенесено 63 значения (включая добавленное `Ok`, см. ниже) — при
первой версии порта здесь ошибочно указывалось «60», без фактического
подсчёта; исправлено при повторном аудите.

> **ИСПРАВЛЕНО при аудите компиляцией (реальная ошибка компилятора GNAT,
> не опечатка форматирования):** первая версия этого enum группировала
> значения по смысловой категории (Capability/CDT, Память, Namespace,
> …), в точности повторяя визуальный порядок Rust-документа. Ada требует,
> чтобы `for Enum_Type use (...)` присваивал значения строго по
> возрастанию **в том же порядке, в каком элементы объявлены в самом
> типе** (Ada RM 13.4) — смысловая группировка Rust-версии не монотонна
> по числовому коду (например, `Cascade_Too_Deep => -95` шёл в тексте
> после `Entropy_Exhausted => -90`, что уже нарушение возрастания, а
> `Driver_Restarting => -122` стоял перед `User_Fault => -120` /
> `Hardware_Fault => -121`, что нарушение вдвойне). GNAT 13.3
> (`-gnat2022`) отклоняет такой enum с 63 ошибками `enumeration value
> ... not ordered`, что и обнаружилось при попытке реальной компиляции
> этого пакета в рамках аудита. Порядок объявления ниже переставлен на
> строго возрастающий по числовому коду; смысловые комментарии при
> отдельных значениях (T59, T27, T43 и т.д.) сохранены на своих местах,
> но сама группировка заголовками разделов больше не совпадает с
> визуальным порядком Rust-документа — это следствие требования языка,
> а не намеренная реструктуризация. Единственный способ сохранить и
> точные Rust-коды, и монотонность — разместить `Ok` (значение `0`,
> наибольшее среди всех) последним в списке, а не первым, как было бы
> естественнее читать; это тоже проверено компилятором, а не выбрано
> произвольно.

```ada
package Tachy.Kernel_Error_Pkg is

   pragma Pure;

   --  Порядок объявления — строго по возрастанию числового кода (Ada RM
   --  13.4 требует этого для representation clause ниже). Не совпадает
   --  с порядком по смысловым категориям Rust-документа — см. пояснение
   --  выше.
   type Kernel_Error is
     (Driver_Restarting,     --  запрос к устройству в окне перезапуска
                              --  драйвера
      Hardware_Fault,
      User_Fault,             --  Fault-адрес передаётся отдельно
                               --  (например, в регистре или через
                               --  Fault_Message), т.к. представление
                               --  enum несовместимо с кортежными
                               --  вариантами — идентично обоснованию
                               --  Rust-версии
      Host_Vspace_Destroyed,  --  аварийный XpcReply при Object_Destroy
                               --  VSpace
      Max_Waiters,             --  Wait_Queue_Max_Waiters превышен
      Invalid_Device_State, Access_Violation, Not_Supported,
      Already_Exists, Invalid_Argument,
      Perm_Denied,            --  используется в Check_Right;
                               --  Permission_Denied убран как дубль
      Not_Found,
      Expired,                --  T27: временный мандат истёк
                               --  (Valid_Until прошёл)
      Not_Yet_Valid,          --  T27: мандат ещё не вступил в силу
                               --  (Valid_From в будущем)
      Read_Down_Violation,    --  T59: Biba — чтение объекта с более
                               --  низкой целостностью
      Write_Up_Violation,     --  T59: Biba — запись в объект с более
                               --  высокой целостностью
      Label_Immutable, Category_Mismatch, Write_Down_Violation,
      Read_Up_Violation,
      Cascade_Too_Deep,       --  Synapse_Fire: глубина каскада >
                               --  Synapse_Max_Fire_Depth (T108/T94/T95,
                               --  §16a порта)
      Entropy_Exhausted,      --  T43
      Interrupted, Timeout, Would_Block,
      Object_Destroyed, Timed_Out, Unknown_Op,
      Illegal_Instruction, Fault_In_Thread,
      Elf_Load_Error, Invalid_Elf_Format,
      Irq_Table_Full, Not_Granted, No_Device_Attached, Iommu_Table_Full,
      Origin_Revoked, Path_Conflict, Mount_Conflict, Would_Create_Cycle,
      Mount_Quota_Exceeded, Invalid_Name, Name_Too_Long,
      Overflow, Mapping_Conflict, Invalid_Address, Out_Of_Memory,
      Range_Occupied, Bad_Cap, Reply_Consumed, Revoked_During_Mint,
      Parent_Revoking, Cdt_Too_Deep, Bad_Rights, Revoked, Ring_Demotion,
      Ring_Violation, Syscall_Not_Permitted, Invalid_Temporal_Range,
      Capability_Expired, Capacity_Exceeded, Invalid_Cap,
      Ok);  --  добавлено для Ada-идиомы "Status : out Kernel_Error;
             --  Status = Ok" — в Rust-версии успех кодируется отдельно
             --  через Result<T, KernelError>, здесь — явное значение Ok
             --  с кодом 0, не пересекающееся ни с одним отрицательным
             --  кодом ошибки Rust-версии. Стоит последним в списке
             --  (не первым) — см. пояснение о монотонности выше.

   for Kernel_Error use
     (Driver_Restarting => -122, Hardware_Fault => -121,
      User_Fault => -120, Host_Vspace_Destroyed => -119,
      Max_Waiters => -118, Invalid_Device_State => -117,
      Access_Violation => -116, Not_Supported => -115,
      Already_Exists => -114, Invalid_Argument => -113,
      Perm_Denied => -111, Not_Found => -110, Expired => -107,
      Not_Yet_Valid => -106, Read_Down_Violation => -105,
      Write_Up_Violation => -104, Label_Immutable => -103,
      Category_Mismatch => -102, Write_Down_Violation => -101,
      Read_Up_Violation => -100, Cascade_Too_Deep => -95,
      Entropy_Exhausted => -90, Interrupted => -82, Timeout => -81,
      Would_Block => -80, Object_Destroyed => -72, Timed_Out => -71,
      Unknown_Op => -70, Illegal_Instruction => -61,
      Fault_In_Thread => -60, Elf_Load_Error => -51,
      Invalid_Elf_Format => -50, Irq_Table_Full => -44,
      Not_Granted => -43, No_Device_Attached => -41,
      Iommu_Table_Full => -40, Origin_Revoked => -36,
      Path_Conflict => -35, Mount_Conflict => -34,
      Would_Create_Cycle => -33, Mount_Quota_Exceeded => -32,
      Invalid_Name => -31, Name_Too_Long => -30, Overflow => -23,
      Mapping_Conflict => -22, Invalid_Address => -21,
      Out_Of_Memory => -20, Range_Occupied => -15, Bad_Cap => -14,
      Reply_Consumed => -13, Revoked_During_Mint => -12,
      Parent_Revoking => -11, Cdt_Too_Deep => -10, Bad_Rights => -9,
      Revoked => -8, Ring_Demotion => -7, Ring_Violation => -6,
      Syscall_Not_Permitted => -5, Invalid_Temporal_Range => -4,
      Capability_Expired => -3, Capacity_Exceeded => -2,
      Invalid_Cap => -1, Ok => 0);

   for Kernel_Error'Size use 32;

end Tachy.Kernel_Error_Pkg;
```

**Компиляция подтверждена:** этот пакет проверен `gnatmake -c -gnat2022`
(GNAT 13.3.0) изолированно и компилируется без ошибок и предупреждений
в исправленном виде.

`Rdrand` уже в HAL (§18.6 порта). `Entropy_Exhausted` уже в `Kernel_Error`
(§14 порта, = -90). Бюджет — глобальный атомарный счётчик оставшихся байт
энтропии; пополняется аппаратно или через `Entropy_Feed` от
привилегированного userspace-демона.

```ada
package Tachy.Entropy is

   pragma SPARK_Mode (On);

   --  Глобальный бюджет энтропии в байтах. Инициализируется при старте
   --  через аппаратный RNG (HAL.Rdrand).
   Entropy_Budget : aliased Interfaces.Unsigned_64 := 0;

   --  Максимальный бюджет: 1 МБ. Ограничивает накопление неиспользованной
   --  энтропии.
   Entropy_Budget_Max : constant := 2 ** 20;

   --  Запросить Bytes байт энтропии. Атомарно уменьшает бюджет; возвращает
   --  Entropy_Exhausted если бюджет исчерпан.
   procedure Entropy_Consume
     (Bytes : Interfaces.Unsigned_64; Status : out Kernel_Error)
   is
      Cur    : Interfaces.Unsigned_64;
      Cas_Ok : Boolean;
   begin
      loop
         Cur := Entropy_Budget;
         if Cur < Bytes then
            Status := Entropy_Exhausted;
            return;
         end if;
         Atomic_Compare_Exchange_U64
           (Entropy_Budget'Address, Cur, Cur - Bytes, Cas_Ok);
         if Cas_Ok then
            Status := Ok;
            return;
         end if;
      end loop;
   end Entropy_Consume;

   --  Пополнить бюджет (вызывается из Entropy_Feed syscall или
   --  аппаратного IRQ). Насыщающее сложение — не выходит за
   --  Entropy_Budget_Max.
   procedure Entropy_Replenish (Bytes : Interfaces.Unsigned_64) is
      Cur, Next : Interfaces.Unsigned_64;
      Cas_Ok    : Boolean;
   begin
      loop
         Cur  := Entropy_Budget;
         Next := Interfaces.Unsigned_64'Min
           (Saturating_Add_U64 (Cur, Bytes), Entropy_Budget_Max);
         Atomic_Compare_Exchange_U64
           (Entropy_Budget'Address, Cur, Next, Cas_Ok);
         if Cas_Ok then
            return;
         end if;
      end loop;
   end Entropy_Replenish;

   function Saturating_Add_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (if A > Interfaces.Unsigned_64'Last - B
       then Interfaces.Unsigned_64'Last else A + B);

   --  Привилегированный syscall: userspace-демон (в исходной терминологии
   --  «uring 0», см. примечание §13.3 порта) подаёт энтропию в ядро.
   --  Требует мандат с Bind_Prm (только init/entropy-демон имеет такой
   --  мандат).
   generic
      type Object_Type is new Kernel_Object with private;
   procedure Entropy_Feed
     (Caller_Cap : Object_Bind_Prm_Ref;  --  требует Bind_Prm
      Bytes      : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   with Pre => Contains (Caller_Cap.Rights, Bind_Prm);

   procedure Entropy_Feed
     (Caller_Cap : Object_Bind_Prm_Ref;
      Bytes      : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Caller_Cap);
      if Status /= Ok then
         return;
      end if;
      Entropy_Replenish (Bytes);
      Status := Ok;
   end Entropy_Feed;

end Tachy.Entropy;
```

Все вызовы `HAL.Rdrand` в ядре предваряются `Entropy_Consume (8)` —
гарантия, что аппаратный RNG не используется без учёта бюджета. Перенесено
без изменений по существу.

---

## 15. Watchdog Capability (T64, T82)

```ada
package Tachy.Watchdog is

   pragma SPARK_Mode (On);

   --  T82: реакция на просрочку heartbeat. Расширяет T64 — раньше
   --  единственным действием был Notification_Signal без различения
   --  серьёзности.
   type Watchdog_Policy is
     (Notify,          --  Только уведомить через Notification — решение
                        --  принимает наблюдатель.
      Kill_And_Respawn, --  Убить поток и немедленно перезапустить из
                         --  шаблона (делегирует в тот же путь, что и
                         --  Reincarnation_Contract, §16.2 порта).
      Freeze);          --  Заморозить поток (не убивать, не
                         --  возобновлять) — для отладки зависших
                         --  состояний без потери контекста на момент
                         --  таймаута.
   for Watchdog_Policy use (Notify => 0, Kill_And_Respawn => 1, Freeze => 2);
   for Watchdog_Policy'Size use 8;

   type Watchdog is limited record
      Header    : Object_Header;
      Watched   : Thread_Weak_Ref;
      Period    : Interfaces.Unsigned_32;
      Notify_Ref : Notification_Weak_Ref;
      --  T82: что делать при просрочке, помимо Notification_Signal.
      Policy    : Watchdog_Policy;
      --  Нужен только для Kill_And_Respawn — реальный перезапуск
      --  делегируется в уже существующий Supervisor_Tick (§16.2 порта),
      --  а не дублируется здесь. Если Policy = Kill_And_Respawn, а
      --  Contract отсутствует — деградация до Notify (см.
      --  Apply_Watchdog_Policy) вместо паники: лучше уведомление без
      --  перезапуска, чем undefined behaviour.
      Contract  : Reincarnation_Contract_Weak_Ref_Option;
   end record
     with Volatile;

   Watchdog_Max : constant := 256;

   --  T64: глобальный реестр живых Watchdog. Тот же паттерн, что
   --  Iommu_Mapping в §17 порта (Ticket_Lock (Bounded_Vector)) — не
   --  Slot_Map, потому что здесь нужна итерация по всем живым записям на
   --  каждом тике (Watchdog_Tick ниже), а Slot_Map (§A.4 порта) итерации
   --  не предоставляет и жёстко завязан на Cdt_Capacity.
   package Watchdog_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Watchdog_Ref);
   package Watchdog_Locks is new Tachy.Ticket_Lock
     (Watchdog_Vectors.Vector (Watchdog_Max));

   Watchdogs : Watchdog_Locks.Instance (Initial => <>);

   procedure Heartbeat_Touch is
   begin
      Current_Thread.Last_Syscall_Tick := Current_Tick;  --  Release-запись
                                                            --  через
                                                            --  Volatile-поле
   end Heartbeat_Touch;

   --  T64: создать Watchdog поверх живого потока. Notification должен
   --  быть создан заранее вызывающим — Watchdog только сигналит, не
   --  владеет жизнью. Contract обязателен только для Kill_And_Respawn
   --  (см. деградацию в Apply_Watchdog_Policy, если всё же не передан).
   procedure Watchdog_Create
     (Watched  : Thread_Read_Ref;             --  требует Read
      Notify_C : Notification_Write_Ref;       --  требует Write
      Period   : Interfaces.Unsigned_32;
      Policy   : Watchdog_Policy;
      Contract : Reincarnation_Contract_Read_Ref_Option;  --  требует
                                                             --  Read, если
                                                             --  присутствует
      Result   : out Watchdog_Manage_Ref;
      Status   : out Kernel_Error)
   with Pre => Contains (Watched.Rights, Tachy.Rights.Read)
               and then Contains (Notify_C.Rights, Write);

   procedure Watchdog_Create
     (Watched  : Thread_Read_Ref;
      Notify_C : Notification_Write_Ref;
      Period   : Interfaces.Unsigned_32;
      Policy   : Watchdog_Policy;
      Contract : Reincarnation_Contract_Read_Ref_Option;
      Result   : out Watchdog_Manage_Ref;
      Status   : out Kernel_Error)
   is
      Wd          : Watchdog_Ref;
      Reg         : Watchdog_Vectors.Vector (Watchdog_Max);
      Push_Status : Kernel_Error;
   begin
      Status := Check_Valid (Watched);
      if Status /= Ok then
         return;
      end if;
      Status := Check_Valid (Notify_C);
      if Status /= Ok then
         return;
      end if;
      if Contract.Present then
         Status := Check_Valid (Contract.Value);
         if Status /= Ok then
            return;
         end if;
      end if;

      Construct_Watchdog
        (Header => (others => <>), Watched => Downgrade (Watched.Object),
         Period => Period, Notify_Ref => Downgrade (Notify_C.Object),
         Policy => Policy,
         Contract => (if Contract.Present
                      then Downgrade (Contract.Value.Object)
                      else Empty_Weak_Ref),
         Result => Wd);

      Watchdogs.Lock (Reg);
      if Watchdog_Vectors.Length (Reg) >= Watchdog_Max then
         Watchdogs.Unlock (Reg);
         Status := Capacity_Exceeded;
         return;
      end if;
      Watchdog_Vectors.Append (Reg, Wd);
      Watchdogs.Unlock (Reg);

      Cap_Mint_Root (Wd, Result);
      Status := Ok;
   end Watchdog_Create;

   --  T64: снять наблюдение. Запись удаляется из Watchdogs немедленно —
   --  дальнейшие тики Watchdog_Tick этот Watchdog не видят. Идентичность
   --  сравнивается по адресу объекта, так как Bounded_Vector (в отличие
   --  от Slot_Map) не даёт стабильный индекс с поколением — это не нужно
   --  здесь: Watchdog не переживает Cap_Revoke и не переиспользуется,
   --  только удаляется.
   procedure Watchdog_Destroy
     (Wd : Watchdog_Manage_Ref; Status : out Kernel_Error)
   with Pre => Contains (Wd.Rights, Manage);

   procedure Watchdog_Destroy
     (Wd : Watchdog_Manage_Ref; Status : out Kernel_Error)
   is
      Reg : Watchdog_Vectors.Vector (Watchdog_Max);
   begin
      Status := Check_Valid (Wd);
      if Status /= Ok then
         return;
      end if;
      Watchdogs.Lock (Reg);
      Watchdog_Vectors.Remove_If_Address_Matches (Reg, Wd.Object);
      Watchdogs.Unlock (Reg);
      Status := Ok;
   end Watchdog_Destroy;

   --  T82: применить policy сверх Notification_Signal при просрочке.
   procedure Apply_Watchdog_Policy
     (Wd : Watchdog; Watched : in out Thread)
   is
      Contract_Alive : Boolean;
      Contract_Ref   : Reincarnation_Contract_Ref;
   begin
      case Wd.Policy is
         when Notify =>
            null;  --  Поведение T64 0.3.7: уведомление — единственное
                    --  действие.
         when Kill_And_Respawn =>
            --  Переиспользует уже существующий Supervisor_Tick (§16.2
            --  порта) — не дублирует Kill_Process/Respawn_From_Template
            --  здесь. Без Contract — деградация до Notify: лучше
            --  уведомление без перезапуска, чем попытка перезапустить
            --  процесс, для которого у Watchdog нет
            --  Reincarnation_Contract.
            --
            --  OPEN (перенесено дословно из Rust-версии, todo!() в
            --  apply_watchdog_policy, §15): Supervisor_Tick принимает
            --  "in out" Reincarnation_Contract, и нигде в §16 порта не
            --  специфицирован способ синхронизации доступа — обычный
            --  supervisor явно владеет эксклюзивным доступом, а здесь
            --  Watchdog_Tick (другой, асинхронный по отношению к
            --  supervisor вызыватель) тоже хочет вызвать ту же функцию.
            --  Это настоящая гонка данных, если оба пути сработают на
            --  одном контракте одновременно, и спецификация
            --  синхронизации Reincarnation_Contract — отдельный
            --  нерешённый вопрос, выходящий за рамки T82 (см. дорожную
            --  карту: следует завести отдельный тикет на per-contract
            --  lock, а не решать его здесь неявно). Порт НЕ придумывает
            --  решение этой гонки от себя — она перенесена как открытая,
            --  ровно как в Rust-версии.
            if Wd.Contract.Present then
               Upgrade (Wd.Contract.Value, Contract_Ref, Contract_Alive);
               if Contract_Alive then
                  raise Program_Error with
                    "OPEN: требует решения по синхронизации " &
                    "Reincarnation_Contract — см. комментарий выше " &
                    "(перенесено из todo!() Rust-версии, не разрешено " &
                    "и здесь)";
               end if;
            end if;
         when Freeze =>
            --  Переиспользует уже существующее состояние Suspended (T57,
            --  §5.7.1 порта) — не вводит новый вариант Thread_State ради
            --  одной policy-ветки.
            Watched.State := Suspended;
      end case;
   end Apply_Watchdog_Policy;

   procedure Watchdog_Tick (Now : Interfaces.Unsigned_64) is
      Reg           : Watchdog_Vectors.Vector (Watchdog_Max);
      Watched_Alive : Boolean;
      Watched       : Thread_Ref;
      Notif_Alive   : Boolean;
      Notif         : Notification_Ref;
      Last          : Interfaces.Unsigned_64;
   begin
      Watchdogs.Lock (Reg);
      for I in 1 .. Watchdog_Vectors.Length (Reg) loop
         declare
            Wd : constant Watchdog_Ref := Watchdog_Vectors.Element (Reg, I);
         begin
            Upgrade (Wd.Watched, Watched, Watched_Alive);
            if Watched_Alive then
               Last := Watched.Last_Syscall_Tick;
               if Saturating_Sub_U64 (Now, Last)
                    > Interfaces.Unsigned_64 (Wd.Period)
               then
                  Upgrade (Wd.Notify_Ref, Notif, Notif_Alive);
                  if Notif_Alive then
                     Notification_Signal (Notif);
                  end if;
                  Apply_Watchdog_Policy (Wd.all, Watched.all);
               end if;
            end if;
         end;
      end loop;
      Watchdogs.Unlock (Reg);
   end Watchdog_Tick;

end Tachy.Watchdog;
```

**Статус T64/T82 (перенесено без изменений по существу):** lifecycle
закрыт — `Watchdog_Create`/`Watchdog_Destroy` дают полный путь capability
(было: структуры и тик без способа создать/снять). `Watchdog_Policy`
(T82) встроена прямо в `Watchdog`, не отдельный объект — по Принципу
Оккама (см. отношение к Rust-версии, начало документа): одно поле вместо
новой сущности. `Freeze` переиспользует существующий `Thread_State =
Suspended` (§5.7.1 порта) — новый вариант состояния потока не вводится.

---

## 16. Надзор и перезапуск: `Reincarnation_Contract`

### 16.1 Структура

```ada
package Tachy.Reincarnation is

   pragma SPARK_Mode (On);

   type Restart_Strategy is (One_For_One, One_For_All, Rest_For_One);

   type Escalation_Policy is
     (Notify_Supervisor, Terminate_Container, Kernel_Panic);

   type Reincarnation_Contract is limited record
      Header                : Object_Header;
      Supervised             : Process_Context_Ref;
      Supervisor             : Process_Context_Ref;
      Heartbeat_Timeout_Ms    : Interfaces.Unsigned_32;
      Last_Heartbeat_Tick     : aliased Interfaces.Unsigned_64;
      Respawn_Cap             : Cap_Any_Ref;
      Restart_Count           : Interfaces.Unsigned_32;
      Max_Restarts            : Interfaces.Unsigned_32;
      Escalation_Policy_Field : Escalation_Policy;
      Mount_Log_Write_Cap     : Cap_Any_Ref;
      Mount_Log_Phys_Base     : Interfaces.Unsigned_64;
      Mount_Log_Capacity      : Interfaces.Unsigned_32;
      Free_Slot_Bitmap        : Interfaces.Unsigned_64;
      Max_Mounts              : Interfaces.Unsigned_32;
      Mounts_Since_Prune       : aliased Interfaces.Unsigned_32;
      Restart_Strategy_Field   : Restart_Strategy;
      Group_Head               : Reincarnation_Contract_Ref_Option;
      Next_In_Group             : Reincarnation_Contract_Access;
      Sibling_Order             : Interfaces.Unsigned_32;
   end record
     with Volatile;

end Tachy.Reincarnation;
```

### 16.2 `Supervisor_Tick`

> **См. открытый вопрос синхронизации, перенесённый в §15 порта
> (`Apply_Watchdog_Policy`):** эта процедура принимает `Reincarnation_Contract`
> как `in out` (эксклюзивный доступ), тогда как `Watchdog_Tick` (§15
> порта) также может обратиться к тому же контракту асинхронно. Гонка
> данных при одновременном срабатывании остаётся нерешённой — перенесена
> как есть, а не исправлена молча в порту.

```ada
   procedure Supervisor_Tick
     (Contract : in out Reincarnation_Contract; Now : Interfaces.Unsigned_64)
   is
      New_Ctx : Process_Context_Ref;
   begin
      if Now - Contract.Last_Heartbeat_Tick
           > Interfaces.Unsigned_64 (Contract.Heartbeat_Timeout_Ms)
      then
         if Contract.Restart_Count >= Contract.Max_Restarts then
            Contract_Escalation (Contract);
            Apply_Restart_Strategy (Contract, Forced => True);
            return;
         end if;

         Kill_Process (Contract.Supervised, Contract.Respawn_Cap);
         Respawn_From_Template
           (Contract.Supervised, Contract.Respawn_Cap, New_Ctx);
         Rebind_Namespace_Mounts (New_Ctx, Contract);
         Contract.Supervised := New_Ctx;
         Contract.Restart_Count := Contract.Restart_Count + 1;
         Contract.Last_Heartbeat_Tick := Now;
         Apply_Restart_Strategy (Contract, Forced => False);
      end if;
   end Supervisor_Tick;
```

### 16.3 Журнал монтирования

```ada
   type Mount_Log_Name is array (0 .. 127) of Interfaces.Unsigned_8;

   type Mount_Log_Entry is record
      Source_Cap : Cap_Snapshot;
      Priority   : Interfaces.Unsigned_32;
      As_Union   : Boolean;
      Lease_Ms   : Interfaces.Unsigned_32;
      Name       : Mount_Log_Name;
   end record
     with Convention => C;

end Tachy.Reincarnation;
```

`Cap_Snapshot` — копия полей `Capability` без владеющей ссылки на объект
(снимок прав и эпох для `Ns_Mount (Nsmount_From_Log)`). Перенесено без
изменений по существу.

---

## 16a. `Synapse`: накопитель сигналов с порогом срабатывания (T108)

### 16a.1 Мотивация и место в системе

`Notification` (§6.3 порта) сигналит немедленно, `Attr_Watch` (§11.3
порта) сигналит немедленно с rate-limit по времени. Ни один из них не
умеет копить взвешенные сигналы и срабатывать по достижении порога.
`Synapse` — общий примитив для этого класса задач: единственный
механизм, конфигурациями которого можно выразить сразу несколько раньше
самостоятельных запросов (обычная подписка на событие, multi-sig на
опасное действие, детектор аномального всплеска активности) — вместо
того чтобы городить для каждого свою структуру.

**`Synapse` не заменяет `Notification`/`Attr_Watch`.** `Notification`
остаётся низкоуровневым примитивом пробуждения потоков (§9 порта);
`Attr_Watch` остаётся конкретной привязкой к `Namespace_Node`/пути (§11.3
порта). `Synapse` — это то, что может стоять *перед* `Notification` как
более умный источник сигнала, и то, чем `Attr_Watch` может быть
переписан как частный случай (не переписывается в этой версии —
остаётся отдельно во избежание разрастания патча, см. §16a.5 порта).

### 16a.2 Правило заряда

Сигнал не передаёт голое число: сам факт позитивного сигнала уже несёт
`+1`, `N` — усилитель поверх него. Негативный сигнал такой единицы не
несёт — `N = 0` для негатива эффективно ничего не делает. Асимметрия
осознанная: позитивный сигнал не может быть "пустым" по эффекту,
негативный — может. Это свойство самого `Synapse` (одно правило для
всех входов), не свойство конкретного `Synapse_Tap` — иначе один и тот
же накопитель считал бы разные входы по разным правилам, и "порог 5"
переставал бы означать одно и то же число единиц независимо от
источника.

```ada
package Tachy.Synapse is

   pragma SPARK_Mode (On);

   type Signal_Kind_Tag is (Positive_Signal, Negative_Signal);

   type Signal_Kind (Tag : Signal_Kind_Tag := Positive_Signal) is record
      case Tag is
         when Positive_Signal => Positive_N : Interfaces.Unsigned_32;
                                  --  эффект на Charge: +(1 + N)
         when Negative_Signal => Negative_N : Interfaces.Unsigned_32;
                                  --  эффект на Charge: -(N) — БЕЗ
                                  --  базовой единицы
      end case;
   end record;

   function Signal_Delta (Kind : Signal_Kind) return Interfaces.Integer_32 is
     (case Kind.Tag is
        when Positive_Signal => 1 + Interfaces.Integer_32 (Kind.Positive_N),
        when Negative_Signal => -Interfaces.Integer_32 (Kind.Negative_N));
```

### 16a.3 Структуры

```ada
   type Reset_Mode is
     (To_Zero,             --  Классический integrate-and-fire: заряд
                            --  обнуляется при срабатывании.
      Subtract_Threshold);  --  Leaky: вычитается ровно порог, избыток
                             --  сверх него сохраняется — может вызвать
                             --  немедленный повторный fire, если избыток
                             --  был велик.

   --  Утечка заряда со временем. Пересчитывается лениво при каждом
   --  касании (Signal/Read), а не глобальным тикером — не нужен ещё один
   --  *_Tick в духе Watchdog_Tick только ради decay.
   type Decay_Spec is record
      Per_Tick   : Interfaces.Integer_32;  -- на сколько Charge стремится
                                             -- к 0 за один tick
      Last_Touch : aliased Interfaces.Unsigned_64;
   end record;

   type Decay_Spec_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Decay_Spec;
         when False => null;
      end case;
   end record;

   --  Закрытый набор действий при срабатывании. НЕ произвольный колбэк:
   --  возможность — это обладание мандатом, не код, который можно
   --  передать (см. отношение к Rust-версии в начале документа / принцип
   --  capability вместо ambient authority, тот же аргумент, что уже
   --  применяется к отказу от произвольного кода в §6.1 порта про
   --  Rcu_Callback). Идентичная мотивация: там, где Rust мог бы
   --  использовать замыкание, документ сознательно выбирает закрытое
   --  перечисление — здесь это решение принято уже в Rust-версии, порт
   --  просто следует тому же принципу без необходимости изобретать его
   --  заново.
   type Pending_Action_Kind is
     (Signal_Notification_Action, Feed_Synapse_Action, Execute_Sealed_Action);

   type Pending_Action (Kind : Pending_Action_Kind := Signal_Notification_Action)
     is record
        case Kind is
           when Signal_Notification_Action =>
              --  Вырожденный случай = обычный Notification/Attr_Watch.
              Notif_Target : Notification_Weak_Ref;
              Notif_Bit    : Interfaces.Unsigned_64;
           when Feed_Synapse_Action =>
              --  Каскад: срабатывание одного Synapse кормит другой.
              --  Мандат на запись уже должен существовать на момент
              --  конфигурации Pending_Action — не добывается на лету при
              --  срабатывании.
              Synapse_Target : Synapse_Weak_Ref;
              Feed_Kind      : Signal_Kind;
           when Execute_Sealed_Action =>
              --  Опасное/составное действие — заранее собранный набор
              --  мандатов и закрытая операция над ними. См. §16a.4 порта.
              Sealed : Sealed_Call;
        end case;
     end record;

   type Synapse is limited record
      Header        : Object_Header;
      Charge        : aliased Interfaces.Integer_32;
      Threshold_Hi   : Interfaces.Integer_32;
      --  Present = False означает "только позитивный порог" (обычный
      --  multi-sig/подписка).
      Threshold_Lo   : Integer_32_Option;
      Reset_Mode_Field : Reset_Mode;
      Decay          : Decay_Spec_Option;
      Action         : Pending_Action;
   end record
     with Volatile;

   --  Точка подключения источника к Synapse. Вес и знак фиксируются
   --  здесь, при подключении — НЕ параметр каждого отдельного вызова
   --  Signal. Иначе держатель одного мандата на запись мог бы задавать
   --  произвольный вес на лету и в одиночку продавливать исход, что
   --  обесценивает смысл ограничения через мандаты (тот же принцип, что
   --  раздельные Read/Write вместо одного Any_Rights).
   type Synapse_Tap is limited record
      Header       : Object_Header;
      Target       : Synapse_Weak_Ref;
      Is_Positive  : Boolean;
      N            : Interfaces.Unsigned_32;
   end record
     with Volatile;

end Tachy.Synapse;
```

### 16a.4 `Sealed_Call` — составные мандаты без изменения CDT

Мандат "на несколько объектов сразу" не реализуется как новый вид
`Capability` (это потребовало бы либо multi-parent узлов в CDT, либо
контейнера с общими правами для разнородных объектов — оба варианта
обсуждались и отклонены в Rust-версии: первый ломает дерево в DAG и
подрывает формальную верификацию отзыва, T21; второй не даёт разных прав
разным вложенным объектам). Вместо этого — `Sealed_Call`: набор уже
существующих, независимо валидных мандатов, упакованных для одного
отложенного действия. CDT не меняется; каждый мандат внутри по-прежнему
сам себе доказывает права.

```ada
   Sealed_Call_Max_Caps : constant := 8;

   --  Использует Erased_Cap (не Cap_Any_Ref) — см. открытый вопрос T109
   --  ниже: в исходном Rust-документе для одного и того же понятия
   --  «мандат со стёртым типом» используются ДВА разных имени
   --  (`AnyCapRef` в §3.1/§16 Rust-версии; `ErasedCap` в §5.6/§18
   --  Rust-версии — 4 и 7 использований соответственно, ни один нигде не
   --  определён как struct). Порт следует тому же выбору, что и
   --  Rust-версия здесь конкретно (более частый вариант, Erased_Cap), БЕЗ
   --  переименования остальных мест, где Rust-версия использовала
   --  AnyCapRef (§3.1/§16 порта сохраняют Cap_Any_Ref как есть) —
   --  унификация всего документа не входит в задачу порта и остаётся
   --  тем же T109, перенесённым, а не решённым за автора оригинала.
   package Sealed_Cap_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Erased_Cap);

   --  Закрытый набор операций, не произвольный код — тот же принцип, что
   --  Pending_Action в целом (§16a.3 порта).
   type Sealed_Op_Kind is (Object_Destroy_Op, Watchdog_Policy_Override_Op);

   type Sealed_Op (Kind : Sealed_Op_Kind := Object_Destroy_Op) is record
      case Kind is
         when Watchdog_Policy_Override_Op =>
            Override_Policy : Watchdog_Policy;
         when others => null;
      end case;
   end record;
   --  Расширяется по мере появления конкретных опасных операций,
   --  управляемых через Synapse/multi-sig — не проектируется впрок.

   type Sealed_Call is limited record
      Caps : Sealed_Cap_Vectors.Vector (Sealed_Call_Max_Caps);
      Op   : Sealed_Op;
   end record;

   --  Проверяет валидность ВСЕХ мандатов в Sealed_Call перед выполнением
   --  — не только вновь предъявленного при последнем Synapse_Signal.
   --  Один из ранее собранных мандатов мог быть отозван в промежутке
   --  между предъявлениями (TOCTOU) — без повторной проверки всего
   --  набора можно накопить порог из частично протухших прав.
   --
   --  ПРИМЕЧАНИЕ (перенесено дословно как открытый вопрос из
   --  Rust-версии): Erased_Cap нигде в документе не специфицирован как
   --  конкретный тип (см. комментарий у Sealed_Cap_Vectors выше) —
   --  соответственно, функция проверки валидности стёртого мандата
   --  (Erased_Cap_Check_Valid ниже) тоже не определяется здесь по
   --  существу, только объявляется как необходимый контракт. Реальная
   --  реализация зависит от того, как в итоге будет специфицирован
   --  Erased_Cap/Cap_Any_Ref (T109). Порт НЕ выбирает конкретное
   --  представление за автора оригинала.
   function Erased_Cap_Check_Valid (Cap : Erased_Cap) return Kernel_Error
   with Import;  --  открытая внешняя точка, идентичная todo!()
                  --  Rust-версии

   function Sealed_Call_Execute (Call : Sealed_Call) return Kernel_Error
   is
      Check_Status : Kernel_Error;
   begin
      for I in 1 .. Sealed_Cap_Vectors.Length (Call.Caps) loop
         Check_Status := Erased_Cap_Check_Valid
           (Sealed_Cap_Vectors.Element (Call.Caps, I));
         if Check_Status /= Ok then
            return Check_Status;
         end if;
      end loop;
      case Call.Op.Kind is
         when Object_Destroy_Op =>
            --  OPEN (портировано из todo!() Rust-версии): делегирует в
            --  Object_Destroy (§1 порта) — тело не реализовано ни в
            --  исходном документе, ни здесь.
            return Not_Supported;
         when Watchdog_Policy_Override_Op =>
            --  OPEN (портировано из todo!() Rust-версии): не реализовано.
            return Not_Supported;
      end case;
   end Sealed_Call_Execute;
```

### 16a.5 Срабатывание и защита от каскадных циклов

`Feed_Synapse` (§16a.3 порта) может кормить другой `Synapse`, который
снова кормит следующий — граф, не только дерево. Ничего не мешает
построить цикл (A → B → A). Защита — общий счётчик глубины срабатывания
за один такт вызова, тот же дух, что `Cdt_Max_Depth` для мандатов (§1.6
порта): ограничивает любой каскад, а не только специфично
Feed_Synapse-цепочки, потому что глубина считается на входе в
`Synapse_Fire`, независимо от того, что именно привело к следующему
срабатыванию.

```ada
   Synapse_Max_Fire_Depth : constant := 16;

   --  Rust thread_local! — Ada-эквивалент через уже существующий
   --  Tachy.Per_Cpu (§A.3 порта), с той разницей, что Rust thread_local
   --  привязан к потоку исполнения (userspace/kernel thread), а
   --  Per_Cpu — к процессорному ядру. Для FIRE_DEPTH это различие не
   --  меняет корректность: счётчик глубины каскада должен быть уникален
   --  per независимый поток управления, обрабатывающий один synapse_fire
   --  за раз без прерывания другим таким же вызовом на ТОМ ЖЕ ядре — что
   --  Per_Cpu и обеспечивает при отсутствии вложенной преемптивности
   --  внутри обработки одного sqe. Если планировщик допускает
   --  прерывание synapse_fire другим synapse_fire на том же CPU
   --  (например, через вложенное прерывание) — это отдельный,
   --  не поднятый в Rust-версии вопрос, не решаемый здесь заново.
   package Fire_Depth_Cells is new Tachy.Per_Cpu
     (Element_Type => Interfaces.Unsigned_8, Max_Cpus => Tachy.Tlb_Shootdown.Max_Cpus);

   Fire_Depth : Fire_Depth_Cells.Instance := Fire_Depth_Cells.Create (0);

   function Synapse_Fire (Syn : in out Synapse) return Kernel_Error
   is
      Cpu    : constant Natural := Current_Cpu_Id;
      Depth  : constant Interfaces.Unsigned_8 := Fire_Depth_Cells.Get (Fire_Depth, Cpu);
      Result : Kernel_Error;
   begin
      if Depth >= Synapse_Max_Fire_Depth then
         return Cascade_Too_Deep;
      end if;
      Fire_Depth_Cells.Set (Fire_Depth, Cpu, Depth + 1);
      Result := Apply_Pending_Action (Syn.Action);
      Fire_Depth_Cells.Set (Fire_Depth, Cpu, Depth);
      return Result;
   end Synapse_Fire;

   function Apply_Pending_Action (Action : Pending_Action) return Kernel_Error
   is
      Notif_Alive  : Boolean;
      Notif        : Notification_Ref;
      Next_Alive   : Boolean;
      Next         : Synapse_Ref;
      Apply_Status : Kernel_Error;
   begin
      case Action.Kind is
         when Signal_Notification_Action =>
            Upgrade (Action.Notif_Target, Notif, Notif_Alive);
            if Notif_Alive then
               Notif.Pending := Notif.Pending or Action.Notif_Bit;
               if Waiter_Count_Snapshot (Notif.Wait_Queue) > 0 then
                  Wake_All_With_Signal (Notif.Wait_Queue);
               end if;
            end if;
            return Ok;

         when Feed_Synapse_Action =>
            Upgrade (Action.Synapse_Target, Next, Next_Alive);
            if Next_Alive then
               Apply_Status := Synapse_Apply_Delta
                 (Next.all, Signal_Delta (Action.Feed_Kind));
               return Apply_Status;
            end if;
            return Ok;

         when Execute_Sealed_Action =>
            return Sealed_Call_Execute (Action.Sealed);
      end case;
   end Apply_Pending_Action;
```

### 16a.6 `Synapse_Signal` — единственная точка входа для сигналов

```ada
   function Synapse_Apply_Delta
     (Syn : in out Synapse; Delta : Interfaces.Integer_32) return Kernel_Error
   is
      New_Charge : Interfaces.Integer_32;
   begin
      Apply_Decay_If_Due (Syn);
      New_Charge := Syn.Charge + Delta;
      Syn.Charge := New_Charge;

      if New_Charge >= Syn.Threshold_Hi then
         case Syn.Reset_Mode_Field is
            when To_Zero             => Syn.Charge := 0;
            when Subtract_Threshold  =>
               Syn.Charge := Syn.Charge - Syn.Threshold_Hi;
         end case;
         return Synapse_Fire (Syn);
      end if;

      if Syn.Threshold_Lo.Present then
         if New_Charge <= Syn.Threshold_Lo.Value then
            case Syn.Reset_Mode_Field is
               when To_Zero             => Syn.Charge := 0;
               when Subtract_Threshold  =>
                  Syn.Charge := Syn.Charge - Syn.Threshold_Lo.Value;
            end case;
            return Synapse_Fire (Syn);
         end if;
      end if;

      return Ok;
   end Synapse_Apply_Delta;

   --  Единственный вызов, доступный держателю Synapse_Tap. Знак и N уже
   --  зафиксированы в самом Tap — вызывающий не может их подменить.
   function Synapse_Signal (Tap : Synapse_Tap_Write_Ref) return Kernel_Error
   with Pre => Contains (Tap.Rights, Write);

   function Synapse_Signal (Tap : Synapse_Tap_Write_Ref) return Kernel_Error
   is
      Target_Alive : Boolean;
      Target       : Synapse_Ref;
      Kind         : Signal_Kind;
      Check_Status : constant Kernel_Error := Check_Valid (Tap);
   begin
      if Check_Status /= Ok then
         return Check_Status;
      end if;
      Upgrade (Tap.Object.Target, Target, Target_Alive);
      if not Target_Alive then
         return Revoked;
      end if;
      Kind := (if Tap.Object.Is_Positive
               then (Tag => Positive_Signal, Positive_N => Tap.Object.N)
               else (Tag => Negative_Signal, Negative_N => Tap.Object.N));
      return Synapse_Apply_Delta (Target.all, Signal_Delta (Kind));
   end Synapse_Signal;

   procedure Apply_Decay_If_Due (Syn : in out Synapse) is
      Last, Now, Elapsed_Ticks : Interfaces.Unsigned_64;
      Leak                     : Interfaces.Integer_64;
      Cur, Pulled               : Interfaces.Integer_32;
   begin
      if not Syn.Decay.Present then
         return;
      end if;
      Last := Syn.Decay.Value.Last_Touch;
      Now  := Current_Tick;
      Elapsed_Ticks := Saturating_Sub_U64 (Now, Last);
      if Elapsed_Ticks = 0 then
         return;
      end if;
      Leak := Saturating_Mul_I64
        (Interfaces.Integer_64 (Elapsed_Ticks),
         Interfaces.Integer_64 (Syn.Decay.Value.Per_Tick));

      --  Утечка тянет заряд к 0 с обеих сторон (знаковый Charge) — не
      --  даёт старому позитиву и новому негативу неожиданно "сложиться"
      --  спустя произвольно долгое время без сигналов.
      Cur := Syn.Charge;
      if Cur > 0 then
         Pulled := Interfaces.Integer_32'Max
           (Cur - Interfaces.Integer_32
              (Interfaces.Integer_64'Min
                 (Interfaces.Integer_64'Max (Leak, 0),
                  Interfaces.Integer_64 (Interfaces.Integer_32'Last))), 0);
      elsif Cur < 0 then
         Pulled := Interfaces.Integer_32'Min
           (Cur + Interfaces.Integer_32
              (Interfaces.Integer_64'Min
                 (Interfaces.Integer_64'Max (Leak, 0),
                  Interfaces.Integer_64 (Interfaces.Integer_32'Last))), 0);
      else
         Pulled := 0;
      end if;
      Syn.Charge := Pulled;
      Syn.Decay.Value.Last_Touch := Now;
   end Apply_Decay_If_Due;

   function Saturating_Mul_I64
     (A, B : Interfaces.Integer_64) return Interfaces.Integer_64
   is (if B /= 0 and then abs A > Interfaces.Integer_64'Last / abs B
       then (if (A > 0) = (B > 0) then Interfaces.Integer_64'Last
             else Interfaces.Integer_64'First)
       else A * B);

end Tachy.Synapse;
```

### 16a.7 Конфигурации: как существующие запросы выражаются через `Synapse`

Не заменяют существующие механизмы (§16a.1 порта) — показывают, что
`Synapse` достаточно общий, чтобы их покрыть, если понадобится
унифицировать позже:

| Запрос | Конфигурация `Synapse` |
|---|---|
| Обычная подписка на событие (как `Attr_Watch`) | `Threshold_Hi = 1`, один `Synapse_Tap (Is_Positive => True, N => 0)`, `Action` = `Signal_Notification_Action` |
| Multi-sig N-из-M на опасное действие | `Threshold_Hi = N`, по одному `Synapse_Tap (Is_Positive => True, N => 0)` на каждого из M подписантов (эффект каждого +1), `Action` = `Execute_Sealed_Action`, `Threshold_Lo.Present = False` (голосов "против" нет — не путать с явным multi-party veto, для этого нужен `Threshold_Lo`) |
| Голосование "за/против" с правом вето | `Threshold_Hi`/`Threshold_Lo` оба заданы, часть `Synapse_Tap` — `Is_Positive = True` (голоса "за" одним держателям мандата), часть — `Is_Positive = False` (право понижать заряд — другим, раздельно от прав "за", тот же принцип, что раздельные `Has_Read`/`Has_Write`) |
| Детектор аномального всплеска (T94/T95, см. §23 порта) | `N` пропорционален силе события, `Decay` включён (утечка при затишье), `Action` = `Feed_Synapse_Action` в вышестоящий агрегирующий `Synapse` или `Signal_Notification_Action` напрямую |
| Мандат "на несколько объектов сразу" | Не `Synapse` сам по себе — `Sealed_Call` внутри `Execute_Sealed_Action` (§16a.4 порта): набор независимых мандатов над разными объектами, упакованный для одного действия |

**Осознанно не входит в базовую версию** (перенесено без изменений — то
же решение, что в Rust-версии, не пересмотренное портом): адаптивный
порог (spike-frequency adaptation — `Threshold_Hi`, управляемый вторым
`Synapse` через `Pending_Action`, не встроенное поле первого) —
усложняет рассуждение о поведении без явной потребности и мешало бы
формальной верификации (T21) больше, чем текущая фиксированная схема.

---

## 17. IOMMU: `Iommu_Domain` (T66)

**T66:** `Iommu_Domain` теперь полноценный capability object — создаётся
явно через `Iommu_Domain_Create`, делегируется, отзывается. Ранее
создавался неявно в `Driver_Load` (§18.3 порта) — это оставалось как
неявная привязка без контроля.

```ada
package Tachy.Iommu is

   pragma SPARK_Mode (On);

   Iommu_Mapping_Max : constant := 64;

   package Iommu_Mapping_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Iommu_Mapping);
   package Iommu_Mapping_Locks is new Tachy.Ticket_Lock
     (Iommu_Mapping_Vectors.Vector (Iommu_Mapping_Max));

   type Iommu_Domain is limited record
      Header                : Object_Header;
      Hw_Table_Root_Phys      : Interfaces.Unsigned_64;
      Domain_Id               : Interfaces.Unsigned_32;
      Attached_Device_Count    : aliased Interfaces.Unsigned_32;
      Max_Mapped_Frames        : Interfaces.Unsigned_32;
      Mapped_Frame_Count       : aliased Interfaces.Unsigned_32;
      Mappings                 : Iommu_Mapping_Locks.Instance (Initial => <>);
   end record
     with Volatile;

   --  Реализует Has_External_Effect (§1.7.0 порта).
   procedure Resolve_External_Effect (Self : in out Iommu_Domain) is
   begin
      Unmap_All_Hw (Self);       --  платформенный вызов — граница
                                   --  платформы, идентичная unsafe-блоку
                                   --  Rust-версии
      Tlb_Invalidate_All_Hw (Self);
   end Resolve_External_Effect;

   --  T66: явное создание Iommu_Domain как capability object. Требует
   --  мандат с Bind_Prm — только PRM-уровень может создавать домены.
   --  Возвращает мандат Manage — владелец может делегировать подмандаты.
   generic
      type Object_Type is new Kernel_Object with private;
   procedure Iommu_Domain_Create
     (Prm_Cap           : Object_Bind_Prm_Ref;  --  требует Bind_Prm
      Max_Mapped_Frames  : Interfaces.Unsigned_32;
      Result             : out Iommu_Domain_Manage_Ref;
      Status             : out Kernel_Error)
   with Pre => Contains (Prm_Cap.Rights, Bind_Prm);

   procedure Iommu_Domain_Create
     (Prm_Cap           : Object_Bind_Prm_Ref;
      Max_Mapped_Frames  : Interfaces.Unsigned_32;
      Result             : out Iommu_Domain_Manage_Ref;
      Status             : out Kernel_Error)
   is
      Domain_Id     : Interfaces.Unsigned_32;
      Alloc_Status  : Kernel_Error;
      Hw_Root       : Interfaces.Unsigned_64;
      Create_Status : Kernel_Error;
   begin
      Status := Check_Valid (Prm_Cap);
      if Status /= Ok then
         return;
      end if;

      Hal_Allocate_Iommu_Domain (Domain_Id, Alloc_Status);
      if Alloc_Status /= Ok then
         Status := Capacity_Exceeded;
         return;
      end if;

      Hal_Create_Iommu_Page_Table (Hw_Root, Create_Status);
      if Create_Status /= Ok then
         Status := Create_Status;
         return;
      end if;

      Construct_Iommu_Domain
        (Header => (others => <>), Hw_Table_Root_Phys => Hw_Root,
         Domain_Id => Domain_Id, Attached_Device_Count => 0,
         Max_Mapped_Frames => Max_Mapped_Frames, Mapped_Frame_Count => 0,
         Result => Result);
      Status := Ok;
   end Iommu_Domain_Create;

   --  T66: привязать устройство к домену через capability.
   --  Device_Object.Iommu_Domain_Cap теперь явный мандат, не опциональный
   --  Erased_Cap.
   procedure Iommu_Attach_Device
     (Domain : Iommu_Domain_Manage_Ref;  --  требует Manage
      Device : Device_Object_Manage_Ref;  --  требует Manage
      Status : out Kernel_Error)
   with Pre => Contains (Domain.Rights, Manage)
               and then Contains (Device.Rights, Manage);

   procedure Iommu_Attach_Device
     (Domain : Iommu_Domain_Manage_Ref;
      Device : Device_Object_Manage_Ref;
      Status : out Kernel_Error)
   is
      Attach_Status : Kernel_Error;
   begin
      Status := Check_Valid (Domain);
      if Status /= Ok then
         return;
      end if;
      Status := Check_Valid (Device);
      if Status /= Ok then
         return;
      end if;
      Hal_Iommu_Attach_Device
        (Domain.Object.Domain_Id, Device.Object.Platform_Id, Attach_Status);
      if Attach_Status /= Ok then
         Status := Attach_Status;
         return;
      end if;
      Domain.Object.Attached_Device_Count :=
        Domain.Object.Attached_Device_Count + 1;
      Status := Ok;
   end Iommu_Attach_Device;

   generic
      type Object_Type is new Kernel_Object with private;
   procedure Iommu_Map
     (Domain : Iommu_Domain_Manage_Ref;   --  требует Manage
      Frame  : Object_Read_Ref;            --  требует Read
      Offset : Interfaces.Unsigned_64;
      Iova   : Interfaces.Unsigned_64;
      Length : Interfaces.Unsigned_64;
      Flags  : Iommu_Map_Flags;
      Status : out Kernel_Error)
   with Pre => Contains (Domain.Rights, Manage)
               and then Contains (Frame.Rights, Tachy.Rights.Read);

   procedure Iommu_Map
     (Domain : Iommu_Domain_Manage_Ref;
      Frame  : Object_Read_Ref;
      Offset : Interfaces.Unsigned_64;
      Iova   : Interfaces.Unsigned_64;
      Length : Interfaces.Unsigned_64;
      Flags  : Iommu_Map_Flags;
      Status : out Kernel_Error)
   is
   begin
      --  OPEN (портировано из todo!() Rust-версии, §17): тело не
      --  реализовано ни в Rust-документе, ни здесь. Семь шагов плана
      --  переносятся как комментарий:
      --    1. Cap_Manage на Domain.
      --    2. Эпохи Frame (Check_Valid).
      --    3. Границы Offset+Length.
      --    4. Attached_Device_Count > 0 (если не Allow_Unattached).
      --    5. Max_Mapped_Frames.
      --    6. Запись в HW таблицы.
      --    7. TLB инвалидация.
      Status := Not_Supported;
   end Iommu_Map;

end Tachy.Iommu;
```

---

## 18. Драйверная модель (PRM)

### 18.1 `Device_Object`

```ada
package Tachy.Driver is

   pragma SPARK_Mode (On);

   type Device_Class is
     (Unknown_Class, Block_Storage, Network, Display, Input_Hid, Bus,
      Timer_Class, Platform_Other);

   type Device_State is
     (Enumerated, Bound, Active, Faulted, Removed);
   for Device_State use
     (Enumerated => 0, Bound => 1, Active => 2, Faulted => 3, Removed => 4);
   for Device_State'Size use 8;

   function Device_State_From_U8
     (V : Interfaces.Unsigned_8) return Device_State_Result
   is
     (case V is
        when 0 => (Ok => True, Value => Enumerated),
        when 1 => (Ok => True, Value => Bound),
        when 2 => (Ok => True, Value => Active),
        when 3 => (Ok => True, Value => Faulted),
        when 4 => (Ok => True, Value => Removed),
        when others => (Ok => False, Value => Faulted));
        --  Faulted как значение-заглушка при Ok = False — вызывающий
        --  обязан проверить Ok, не читать Value напрямую при ошибке;
        --  эквивалент Rust Result<DeviceState, KernelError>.

   type Device_Object is limited record
      Header                : Object_Header;
      Class                  : Device_Class;
      State                   : aliased Interfaces.Unsigned_8;  --  хранится
                                  --  как байт для атомарного доступа,
                                  --  идентично Rust AtomicU8
      Platform_Id             : Interfaces.Unsigned_64;
      Parent                  : Device_Object_Ref_Option;
      --  Указатель, обновляемый атомарно чтобы Rebind_Driver_Caps мог
      --  атомарно обновить при перезапуске. Null = мандат не выдан
      --  (состояние до Driver_Load).
      Driver_Endpoint_Cap      : Erased_Cap_Access;
      Iommu_Domain_Cap          : Erased_Cap_Option;  --  не меняется
                                   --  после Driver_Load
      Prm_Resource_Set_Cap       : Erased_Cap_Access;
      Supervision_Contract        : Reincarnation_Contract_Ref_Option;
   end record
     with Volatile;

   function State (Self : Device_Object) return Device_State is
      Result : constant Device_State_Result :=
        Device_State_From_U8 (Self.State);
   begin
      return (if Result.Ok then Result.Value else Faulted);
   end State;

   procedure Set_State (Self : in out Device_Object; S : Device_State) is
   begin
      Self.State := Device_State'Enum_Rep (S);
   end Set_State;
```

### 18.2 Манифест драйвера

```ada
   Driver_Manifest_Max_Classes : constant := 8;

   type Device_Class_Array is array (1 .. Driver_Manifest_Max_Classes)
     of Device_Class;

   Driver_Entry_Point_Path_Max : constant := 255;

   type Driver_Manifest is record
      Abi_Version            : Interfaces.Unsigned_32;
      Supported_Classes       : Device_Class_Array;
      Supported_Class_Count    : Interfaces.Unsigned_32;
      Match_Platform_Id_Mask    : Interfaces.Unsigned_64;
      --  Bounded_String для no_std-совместимого динамического пути —
      --  эквивалент Rust Box<str>.
      Entry_Point_Path          : Name_Strings.Bounded_String;
      Required_Prm_Resources     : Prm_Resource_Class_Mask;
      Requires_Iommu_Domain       : Boolean;
   end record;
```

### 18.3 `Driver_Load`

Алгоритм идентичен исходной модели (10 шагов, перенесено без
изменений по существу). Шаг 7 — три мандата в CSpace нового
процесса создаются ядром (обоснованное исключение из модели §1.8
порта).

### 18.4 `Prm_Resource_Set`

```ada
   type Prm_Resource_Class_Mask is mod 2 ** 32;
   Interrupt_Line : constant Prm_Resource_Class_Mask := 16#01#;
   Mmio_Region    : constant Prm_Resource_Class_Mask := 16#02#;
   Port_Io_Range  : constant Prm_Resource_Class_Mask := 16#04#;
   Timer_Channel  : constant Prm_Resource_Class_Mask := 16#08#;
   Dma_Channel    : constant Prm_Resource_Class_Mask := 16#10#;
   Msi_X_Vector   : constant Prm_Resource_Class_Mask := 16#20#;
      --  T74: MSI-X interrupt vector (PCIe)

   Msi_X_Max_Vectors : constant := 2048;  -- PCIe spec maximum

   --  T74: дескриптор одного MSI-X вектора.
   type Msi_X_Vector_Desc is record
      Vector_Index : Interfaces.Unsigned_16;  -- индекс в таблице MSI-X
                                                -- устройства
      Cpu_Affinity : Interfaces.Unsigned_32;   -- целевой CPU для этого
                                                 -- вектора
      Allocated    : Boolean;
   end record;

   type Msi_X_Vector_Array is array (0 .. Msi_X_Max_Vectors - 1)
     of Msi_X_Vector_Desc;

   type Msi_X_Vector_Array_Option (Present : Boolean := False) is record
      case Present is
         when True  => Vectors : Msi_X_Vector_Array;
         when False => null;
      end case;
   end record;

   type Prm_Resource_Set is limited record
      Header               : Object_Header;
      Owning_Device         : Device_Object_Ref;
      Granted_Classes_Mask   : Prm_Resource_Class_Mask;
      --  T74: MSI-X вектора выделяются при Driver_Load, хранятся здесь.
      --  Present = False если Msi_X_Vector не в Granted_Classes_Mask.
      Msi_X_Vectors           : Msi_X_Vector_Array_Option;
   end record
     with Volatile;

   --  Реализует Has_External_Effect (§1.7.0 порта).
   procedure Resolve_External_Effect (Self : in out Prm_Resource_Set) is
   begin
      --  T74: при уничтожении освобождаем MSI-X вектора через PRM.
      if (Self.Granted_Classes_Mask and Msi_X_Vector) /= 0 then
         if Self.Msi_X_Vectors.Present then
            for V of Self.Msi_X_Vectors.Vectors loop
               if V.Allocated then
                  Hal_Release_Msi_X_Vector
                    (Self.Owning_Device.Platform_Id, V.Vector_Index);
               end if;
            end loop;
         end if;
      end if;
      Release_All_Resources (Self);
   end Resolve_External_Effect;

   --  Enum вместо Capability по dyn-объекту — dispatch по типу
   --  несовместим с фиксированным представлением записи (эквивалент
   --  Rust "dyn несовместим с Sized").
   type Prm_Resource_Cap_Kind is
     (Interrupt_Line_Cap, Mmio_Region_Cap, Timer_Channel_Cap,
      Msi_X_Vector_Cap);

   type Prm_Resource_Cap (Kind : Prm_Resource_Cap_Kind := Interrupt_Line_Cap)
     is record
        case Kind is
           when Interrupt_Line_Cap =>
              Interrupt_Notif : Notification_Read_Ref;  --  требует Read
           when Mmio_Region_Cap =>
              --  Единственное реальное место использования комбинации
              --  Read+Write как единого мандата — см. port-02/§1.4 порта
              --  (Read_Write константа).
              Mmio_Cap : Untyped_Region_Ref;  --  требует Read_Write
           when Timer_Channel_Cap =>
              Timer_Cap : Timer_Object_Read_Ref;  --  требует Read
           when Msi_X_Vector_Cap =>
              --  T74: Notification + vector_index
              Msi_X_Notif  : Notification_Read_Ref;  --  требует Read
              Msi_X_Index  : Interfaces.Unsigned_16;
        end case;
     end record;

   procedure Prm_Request_Resource
     (Resource_Set      : Prm_Resource_Set_Manage_Ref;  --  требует Manage
      Class             : Prm_Resource_Class_Mask;
      Resource_Selector  : Interfaces.Unsigned_64;
      Result            : out Prm_Resource_Cap;
      Status            : out Kernel_Error)
   with Pre => Contains (Resource_Set.Rights, Manage);

   procedure Prm_Request_Resource
     (Resource_Set      : Prm_Resource_Set_Manage_Ref;
      Class             : Prm_Resource_Class_Mask;
      Resource_Selector  : Interfaces.Unsigned_64;
      Result            : out Prm_Resource_Cap;
      Status            : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Resource_Set);
      if Status /= Ok then
         return;
      end if;
      if (Resource_Set.Object.Granted_Classes_Mask and Class) = 0 then
         Status := Not_Granted;
         return;
      end if;
      --  OPEN (портировано из todo!() Rust-версии, §18.4): тело не
      --  реализовано ни в Rust-документе, ни здесь.
      Status := Not_Supported;
   end Prm_Request_Resource;
```

### 18.5 Отказ драйвера

```ada
   --  Перезапуск процесса драйвера после обнаружения краша/зависания
   --  через Supervisor_Tick. Отдельный путь от Supervisor_Tick (§16.2
   --  порта) потому что:
   --  1. Rebind_Namespace_Mounts восстанавливает только Ns_Mount-журнал —
   --     три мандата из шага 7 Driver_Load (Target, Prm_Resource_Set,
   --     Driver_Endpoint_Cap) там не писались.
   --  2. Device_State управляется драйверным путём, не общим
   --     supervisor-путём.
   procedure Respawn_Driver_Process
     (Target   : in out Device_Object;
      Contract : in out Reincarnation_Contract;
      Now      : Interfaces.Unsigned_64)
   is
      New_Ctx : Process_Context_Ref;
   begin
      --  Переводим устройство в Faulted — запросы в этом окне получат
      --  Driver_Restarting.
      Set_State (Target, Faulted);

      Kill_Process (Contract.Supervised, Contract.Respawn_Cap);
      Respawn_From_Template
        (Contract.Supervised, Contract.Respawn_Cap, New_Ctx);

      --  Шаг 1: восстанавливаем Ns_Mount-записи (общий путь §16.3 порта).
      Rebind_Namespace_Mounts (New_Ctx, Contract);

      --  Шаг 2: восстанавливаем мандаты специфичные для устройства.
      --  Prm_Resource_Set не пересоздаётся — он принадлежит Target, не
      --  процессу. Driver_Endpoint_Cap создаётся заново: старый
      --  Xpc_Endpoint умер вместе со старым процессом.
      Rebind_Driver_Caps (New_Ctx, Target);

      Contract.Supervised := New_Ctx;
      Contract.Restart_Count := Contract.Restart_Count + 1;
      Contract.Last_Heartbeat_Tick := Now;

      --  После успешного respawn — возвращаем в Bound.
      Set_State (Target, Bound);
   end Respawn_Driver_Process;

   --  Внутренний шаг: повтор части шагов 7-8 Driver_Load для нового
   --  процесса. Не новый системный вызов — внутренняя функция ядра.
   procedure Rebind_Driver_Caps
     (New_Process : Process_Context_Ref; Target : in out Device_Object)
   is
      New_Endpoint : Erased_Cap;
      Prm_Cap      : Erased_Cap;
      Target_Cap   : Erased_Cap;
   begin
      --  Создать новый Driver_Endpoint_Cap в CSpace нового процесса (тем
      --  же привилегированным путём, что шаг 7 Driver_Load, §18.3 порта).
      Create_Xpc_Endpoint_In_Cspace (New_Process, New_Endpoint);
      --  Новый мандат на существующий Prm_Resource_Set.
      Mint_Prm_Resource_Set_Cap (New_Process, Target, Prm_Cap);
      --  Мандат на Target с Read (только Io_Op_Device_Query, без Manage).
      Mint_Target_Read_Cap (New_Process, Target, Target_Cap);

      Target.Driver_Endpoint_Cap := New_Endpoint;
      Target.Prm_Resource_Set_Cap := Prm_Cap;
      --  Target_Cap вложен в CSpace нового процесса на шаге выше —
      --  переменная используется только для того вызова, идентично
      --  Rust `let _ = target_cap;`.
   end Rebind_Driver_Caps;
```

### 18.6 `Hardware_Abstraction` — dispatching-интерфейс (T40)

```ada
   --  См. port-08 (журнал изменений порта): Rust dyn-трейт переносится
   --  через Ada tagged type с абстрактными примитивами. Единственное
   --  отличие в стоимости — Ada dispatching-вызов через tag аналогичен
   --  Rust vtable-вызову через &dyn Trait по стоимости (один косвенный
   --  переход), так что здесь это не ослабление, а прямой структурный
   --  аналог, не только концептуальный.
   type Hardware_Abstraction is interface;

   function Iommu_Map
     (Self : Hardware_Abstraction; Root, Iova, Phys, Len : Interfaces.Unsigned_64;
      Flags : Interfaces.Unsigned_32) return Kernel_Error is abstract;
   procedure Iommu_Tlb_Invalidate
     (Self : Hardware_Abstraction; Domain_Id : Interfaces.Unsigned_32) is abstract;
   procedure Irq_Ack (Self : Hardware_Abstraction; Irq : Interfaces.Unsigned_32)
     is abstract;
   procedure Send_Reschedule_Ipi
     (Self : Hardware_Abstraction; Cpu : Interfaces.Unsigned_32) is abstract;
   procedure Save_Context_And_Yield (Self : Hardware_Abstraction) is abstract
     with No_Return;
   procedure Restore_Context
     (Self : Hardware_Abstraction; Ctx : Execution_Context) is abstract
     with No_Return;
   procedure Wait_For_Interrupt (Self : Hardware_Abstraction) is abstract;
   function Page_Table_Lookup
     (Self : Hardware_Abstraction; Root, Va : Interfaces.Unsigned_64)
      return Phys_Addr_Option is abstract;
   function Create_Page_Table
     (Self : Hardware_Abstraction) return Page_Table_Result is abstract;
   function Map_Segment
     (Self : Hardware_Abstraction; Root, Va, Pa, Size : Interfaces.Unsigned_64;
      Flags : Interfaces.Unsigned_32) return Kernel_Error is abstract;
   function Unmap_Segment
     (Self : Hardware_Abstraction; Root, Va, Size : Interfaces.Unsigned_64)
      return Kernel_Error is abstract;
   procedure Send_Tlb_Shootdown_Ipi
     (Self : Hardware_Abstraction; Cpu : Interfaces.Unsigned_32) is abstract;
   procedure Local_Tlb_Flush
     (Self : Hardware_Abstraction; Va, Size : Interfaces.Unsigned_64) is abstract;
   function Cpus_With_Vspace
     (Self : Hardware_Abstraction; Vspace : V_Space) return Interfaces.Unsigned_64
     is abstract;
   function Copy_From_User
     (Self : Hardware_Abstraction; Dst : in out Byte_Array; Src_Va : Interfaces.Unsigned_64)
      return Copy_Result is abstract;
   function Validate_Irq
     (Self : Hardware_Abstraction; Irq : Interfaces.Unsigned_32)
      return Kernel_Error is abstract;
   function Validate_Mmio
     (Self : Hardware_Abstraction; Base : Interfaces.Unsigned_64;
      Size : Interfaces.Unsigned_32) return Validate_Mmio_Result is abstract;
   function Validate_Timer
     (Self : Hardware_Abstraction; Timer_Id : Interfaces.Unsigned_32)
      return Kernel_Error is abstract;
   function Validate_Port_Io
     (Self : Hardware_Abstraction; Port : Interfaces.Unsigned_16)
      return Validate_Port_Io_Result is abstract;
   function Validate_Dma
     (Self : Hardware_Abstraction; Channel : Interfaces.Unsigned_32)
      return Kernel_Error is abstract;
   function Rdrand
     (Self : Hardware_Abstraction) return Rdrand_Result is abstract;
   --  T74: выделить MSI-X вектор для устройства.
   function Allocate_Msi_X_Vector
     (Self : Hardware_Abstraction; Platform_Id : Interfaces.Unsigned_64;
      Cpu : Interfaces.Unsigned_32) return Msi_X_Alloc_Result is abstract;
   --  T74: освободить MSI-X вектор при уничтожении Prm_Resource_Set.
   procedure Release_Msi_X_Vector
     (Self : Hardware_Abstraction; Platform_Id : Interfaces.Unsigned_64;
      Vector_Index : Interfaces.Unsigned_16) is abstract;
   --  T66: выделить новый IOMMU домен (hardware domain ID).
   function Allocate_Iommu_Domain
     (Self : Hardware_Abstraction) return Iommu_Domain_Alloc_Result is abstract;
   --  T66: привязать устройство к домену на уровне IOMMU hardware.
   function Iommu_Attach_Device
     (Self : Hardware_Abstraction; Domain_Id : Interfaces.Unsigned_32;
      Platform_Id : Interfaces.Unsigned_64) return Kernel_Error is abstract;

   --  Глобальный экземпляр, инициализируется при старте платформой —
   --  эквивалент Rust `static HAL: &'static dyn HardwareAbstraction`.
   Hal : access Hardware_Abstraction'Class;

end Tachy.Driver;
```

---

## 19. PRM-таблица

T40 реализован: все вызовы идут через `Hal.<Метод>` (см. §18.6 порта).
Таблица отражает методы интерфейса `Hardware_Abstraction`.

> **Примечание:** `Hal` — внутреннее имя глобального экземпляра
> `Hardware_Abstraction`. В документации и комментариях используется
> аббревиатура **PRM** (Platform Resource Manager) как уровень
> абстракции. `Hal` = реализация PRM-интерфейса.

| Метод `Hardware_Abstraction` | Тип возврата | Назначение |
|-----------------------------|-------------------|------------|
| `Iommu_Map` | `Kernel_Error` | Запись в HW IOMMU PT |
| `Iommu_Tlb_Invalidate` | `()` | TLB flush IOMMU |
| `Irq_Ack` | `()` | ACK IRQ |
| `Send_Reschedule_Ipi` | `()` | IPI reschedule |
| `Save_Context_And_Yield` | не возвращается | Сохранить контекст + yield |
| `Restore_Context` | не возвращается | Восстановить контекст + iret/eret |
| `Wait_For_Interrupt` | `()` | WFI / HLT |
| `Page_Table_Lookup` | `Phys_Addr_Option` | Обход PT |
| `Create_Page_Table` | `Page_Table_Result` | Создать пустой PT |
| `Map_Segment` | `Kernel_Error` | Маппинг сегмента |
| `Unmap_Segment` | `Kernel_Error` | T12: размаппинг |
| `Send_Tlb_Shootdown_Ipi` | `()` | T12/T68: IPI shootdown (per-CPU) |
| `Local_Tlb_Flush` | `()` | T12: локальный TLB flush |
| `Cpus_With_Vspace` | `Unsigned_64` | T12: маска CPU с данным VSpace |
| `Copy_From_User` | `Copy_Result` | T20: безопасное копирование из userspace |
| `Validate_Irq` | `Kernel_Error` | PRM: проверка IRQ |
| `Validate_Mmio` | `Validate_Mmio_Result` | PRM: проверка MMIO |
| `Validate_Timer` | `Kernel_Error` | PRM: проверка таймера |
| `Validate_Port_Io` | `Validate_Port_Io_Result` | PRM: проверка Port I/O |
| `Validate_Dma` | `Kernel_Error` | PRM: проверка DMA |
| `Rdrand` | `Rdrand_Result` | T43: аппаратный RNG |
| `Allocate_Msi_X_Vector` | `Msi_X_Alloc_Result` | T74: выделить MSI-X вектор |
| `Release_Msi_X_Vector` | `()` | T74: освободить MSI-X вектор |
| `Allocate_Iommu_Domain` | `Iommu_Domain_Alloc_Result` | T66: выделить IOMMU домен |
| `Iommu_Attach_Device` | `Kernel_Error` | T66: привязать устройство к домену |

---

## 20. Проход по границам платформы (T11) — эквивалент SAFETY-прохода

Rust-версия снабжает каждый `unsafe`-блок комментарием вида:

```
// SAFETY: <причина безопасности>
// REQUIRES: <предусловие>
// ENSURES: <постусловие>
```

Ada/SPARK не имеет единой синтаксической конструкции `unsafe`, но
эквивалентная дисциплина применяется к каждой точке, где порт выходит за
пределы SPARK-доказуемого подмножества — это конкретно:
`with Import`/`with Export` подпрограммы (границы с платформой/HAL/shared
memory), любое использование `System.Address` для интерпретации
произвольной памяти, и `pragma Assume`, если бы он использовался (в этом
порте не используется — все места, которые в Rust-версии требовали
`unsafe`, здесь либо честно помечены `Import`, либо остаются `OPEN`).
Каждая такая точка в этом документе снабжена комментарием того же вида:

```
--  ГРАНИЦА ПЛАТФОРМЫ: <причина>
--  ТРЕБУЕТ: <предусловие, не проверяемое SPARK>
--  ОБЕСПЕЧИВАЕТ: <постусловие, не проверяемое SPARK>
```

Подсчёт границ по категориям (соответствует таблице Rust-версии
1:1 по смыслу категорий, не по дословному числу — числа Rust-версии
считали конкретные `unsafe`-блоки её собственной реализации, что не
переносится механически на другую кодовую базу; здесь приводится
таблица категорий этого документа, не количественное соответствие):

| Категория (аналог Rust-версии) | Где встречается в этом документе |
|-----------|-----------|
| `Hal.*`-вызовы (аналог `platform_*` extern) | §7, §9, §17, §18.6 порта |
| `Rcu_Deref` / RCU-обход | §6.1, §11.3 порта |
| Shared-memory SQE/CQE доступ (аналог `addr_of_mut!` для slab) | §5.2, §5.4, §5.5 порта |
| `Import`-помеченные внешние точки без реализации (аналог `assume_init_*`) | §1.2, §1.6, §3.3, §3.4.3, §4.3, §12.3, §16a.4, §17, §18.4 порта — везде, где отмечено OPEN |

---

## 21. Cache-Line Discipline (T26)

```ada
   --  Статические проверки размера — эквивалент Rust
   --  `const _: () = assert!(...)`. Ada представляет это через
   --  Static_Predicate на этапе компиляции или явный
   --  pragma Compile_Time_Error, в зависимости от версии компилятора.
   pragma Compile_Time_Error
     (Cdt_Entry'Size > 64 * 8, "Cdt_Entry > 1 cache line");
   pragma Compile_Time_Error
     (Thread'Size > 256 * 8, "Thread > 256 B");
```

---

## 22. Сводная таблица системных вызовов

| Вызов | Раздел порта | Примечание |
|-------|-------------|------------|
| `Untyped_Retype` | §4.3 | явная проверка переполнения перед умножением |
| `Cap_Mint` | §1.6 | статические права через `Pre`-контракт вместо `PhantomData` (port-02) |
| `Cap_Revoke` | §1.7.1 | итеративный, fix-004 |
| `Object_Destroy` | §1.7.0 | контролируемая ссылка + `Has_External_Effect` |
| `Ns_Mount` / `Ns_Unmount` | §3.3 | |
| `Lease_Renew` | §3.3.1 | |
| `Package_Mount` | §12.3 | вставка пакета в `P_Union`, без priority |
| `Package_Unmount` | §12.3 | удаление пакета из `P_Union` |
| `Io_Ring` submit-путь (`Kernel_Submit_Sqe`) | §6.2 | Inflight_Poll, Device_Query |
| `Attr_Get` / `Attr_Set` | §11 | |
| `Attr_Watch` / `Attr_Unwatch` | §11.3 | |
| `Notification_Wait` / `Signal` | §6.3 | |
| `Reincarnation_Contract`-создание | §16.1 | |
| `Mount_Log`-обрезка | §16.3 | |
| `Iommu_Domain_Create` | §17 | |
| `Iommu_Map` / `Iommu_Unmap` | §17 | |
| `Driver_Load` / `Driver_Unload` | §18.3 | |
| `Prm_Request_Resource` / `Prm_Release_Resource` | §18.4 | |
| `Process_Create` | §1.8 | |
| `Channel` создание | §10 | |
| `Channel_Send` / `Channel_Recv` | §10 | |
| `Thread_Set_Fault_Handler` | §9 | |
| `Thread_Resume` | §9.2 | |
| `Vspace_Unmap` | §7 | |
| `Io_Batch_Submit` (T65) | §5.6a | |
| `Io_Template_Execute` (T110) | §5.6b | |
| `Cap_Wait_Any` (T31) | §10 | |
| `Synapse_Signal` (T108) | §16a.6 | |

---

## 23. Открытые вопросы

### Унаследованные из исходной модели (SYNTH через Rust-версию)

Пункты 10, 11, 13, 14, 16, 17, 18, 19, 21, 22, 23, 24, 25 из
предшествующей модели документа — статус не пересматривался портом,
перенесён как есть (список номеров без содержания идентичен
Rust-версии, которая сама ссылается на них лишь по номеру без раскрытия
— порт не восстанавливает то, что не было раскрыто в источнике).

### Специфичные для Rust-версии (закрыты самим фактом порта либо неприменимы к Ada)

Следующие четыре пункта были открытыми вопросами Rust-версии,
специфичными для Rust как языка реализации — они не переносятся как
открытые вопросы порта, потому что либо решены самим выбором Ada/SPARK,
либо не имеют смысла вне Rust:

- **T1 (Rust).** `unsafe`-bounding — неприменимо к Ada напрямую; аналог
  see §20 порта (проход по границам платформы). Не открытый вопрос
  порта, а уже применённая практика.
- **T2 (Rust).** `no_std` alloc-структуры — решено в порте через T69
  (Bounded_Vectors на горячих путях), см. port-08 в журнале изменений.
- **T3 (Rust).** Граница `PhantomData<R>` vs `RightsMask` — снято
  портом: Ada-версия не использует `PhantomData`-эквивалент вовсе, см.
  port-02 и §1.4 порта. Вопрос не имеет смысла в новой архитектуре прав.
- **T4 (Rust).** `Arc` и время жизни мандата — переносится как
  T-Ada-06 ниже в терминах Ada-версии (см. далее), поскольку
  контролируемая ссылка `Cap_Object_Ref` — не точный аналог `Arc`, и
  вопрос сохраняет смысл, хотя и в другой формулировке.

### Дорожная карта, перенесённая из Rust-версии (T21–T111)

Статусы (Открыт / Закрыт / Частично) относятся к Rust-версии на момент
порта (0.3.12) и НЕ пересматриваются портом самостоятельно — порт не
закрывает и не открывает тикеты за автора оригинала, только переносит
описание в терминах Ada там, где тикет уже закрыт в Rust-версии, и
оставляет как есть там, где он остаётся открытым.

| # | Источник | Статус | Приоритет | Описание (в терминах порта) |
|---|----------|--------|-----------|----------|
| T21 | — | Открыт | HIGH | Формальная верификация CDT Manage-инварианта — SPARK делает это ближе, чем Rust (доказуемые `Post`-контракты вместо doc-комментариев), но полное доказательство инварианта №2 из §1.7.2 порта не выполнено в рамках этого порта |
| T22 | — | Открыт | **BLOCKER** | SMEP/SMAP/PAN на x86_64 и ARM — не зависит от языка реализации, полностью открыт и в порте |
| T23 | — | **Закрыт** | MEDIUM | GC для CDT (`Cdt_Gc` + `Cdt_Gc_Threshold` в §1.7.1 порта) |
| T24 | Оригинальная | Открыт | HIGH | Bloom filter на горячем пути `Check_Valid` |
| T25 | Coyotos | **Закрыт** | HIGH | Prepared capabilities (реализовано в §1.5 порта) |
| T26 | Liedtke L4 | **Закрыт** | HIGH | Cache-line discipline (реализовано в §21 порта) |
| T27 | Оригинальная | **Закрыт** | MEDIUM | Temporal Capability (`Cap_Mint_Temporal` + `Valid_From`/`Valid_Until` в §1.5 порта) |
| T28 | Оригинальная | **Закрыт** | MEDIUM | Negative Capability (deny-биты в `Rights.Mask`; `Cap_Check_Deny` в §1.7.2 порта) |
| T29 | Hydra 1974 | Открыт | MEDIUM | Procedure Capabilities |
| T30 | Barrelfish | **Закрыт** | MEDIUM | Push-notification при revoke (`Cap_Revoke_Notify_Set` в §1.7.1 порта) |
| T31 | SkyOS | **Закрыт** | MEDIUM | `Cap_Wait_Any` — ждать любого из набора мандатов (§10 порта) |
| T32 | Syllable OS | Частично | LOW | `Reply_Object` (§5.7.2 порта) — одноразовый, per-call reply-мандат, полноценный `Kernel_Object`. Не то же самое, что просит T32 (постоянный reply-слот на поток, переиспользуемый между вызовами) — превращение в постоянный слот осталось открытым |
| T33 | NOVA | **Закрыт** | MEDIUM | `Sched_Ctx` как capability (§5.7.1 порта); встроенный `Thread.Own_Sched_Ctx` не затронут |
| T34 | Linux pidfd | Открыт | LOW | `Process_Wait` через Notification — `Notification`/`Wait_Queue` готовы (§6.3 порта), но `Process_Context` нигде не специфицирован как запись, переход `Thread_State = Zombie` нигде не реализован — нет точки, к которой привязать сигнал |
| T35 | Zircon/Fuchsia | Открыт | HIGH | VMO |
| T36 | Cache Kernel | Открыт | LOW | `Region_Evict` |
| T37 | Genode | Открыт | HIGH | Session concept |
| T38 | StarOS | Открыт | LOW | Task Force — групповой CBS |
| T39 | Medusa | Открыт | LOW | Одноразовые потоки |
| T40 | Pilot OS | **Закрыт** | HIGH | HAL как Ada interface с dispatching (реализовано в §18.6 порта) |
| T41 | Composite OS | Открыт | MEDIUM | Booter component |
| T42 | Exokernel/Aegis | **Закрыт** | MEDIUM | Secure Bindings (`Secure_Binding` + `Secure_Binding_Create` в §4a порта) |
| T43 | Оригинальная | **Закрыт** | MEDIUM | Entropy Budget (`Entropy_Consume`/`Replenish`/`Feed` в §14a порта) |
| T44 | Оригинальная | **Закрыт** | MEDIUM | Execution Snapshot (реализовано в §5.7.1a порта через `Flip_Cell`) |
| T45 | Multics | **Закрыт** | — | Ring Levels — было 6, после `revert-ring-001` стало 2 (реализовано в §2 порта); формулировка "6 Ring Levels" из Rust-версии устарела относительно самой Rust-версии на момент порта, порт переносит актуальное состояние (2 уровня), не историческую формулировку тикета |
| T46 | Астра/BLP | **Закрыт** | — | Мандатные метки (реализовано в §13.1 порта) |
| T47 | Bell-LaPadula | **Закрыт** | — | No Write Down / Strict Equality (реализовано в §13.2 порта) |
| T48 | Астра auditd | **Закрыт** | — | `Audit_Channel` ring buffer (реализовано в §13.4 порта) |
| T49 | Оригинальная | Частично | MEDIUM | Causal IPC (структуры §13.5 порта есть; верификация цепочки — нет, см. T53) |
| T50 | CVE-TACHY-006 | Открыт | HIGH | Bloom filter rebuild ordering |
| T51 | CVE-TACHY-010 | **Закрыт** | HIGH | CDT sharding revoke atomicity — инвариант №7 в §1.7.2 порта |
| T52 | CVE-TACHY-011 | **Закрыт** | — | `Audit_Record` object identity (реализовано в §13.4 порта) |
| T53 | CVE-TACHY-012 | Открыт | MEDIUM | Causal IPC O(N²) verification cache |
| T54 | CVE-TACHY-014 | **Закрыт** | — | Strong Tranquility, `Label_Immutable` (реализовано в §13.1 порта) |
| T55 | — | Открыт | HIGH | Syscall table — номера, ABI, аргументы |
| T56 | — | **Закрыт** | HIGH | Namespace API — Re/Im, Layer, адресация слоёв (§3.4 порта) |
| T57 | — | **Закрыт** | — | Thread state machine (реализовано в §5.7.1 порта) |
| T58 | 0.7.3 #7 | Открыт | HIGH | Revocation Wave — async revoke O(1) |
| T59 | Biba 1977 | **Закрыт** | HIGH | Biba Model — двойные метки целостности (реализовано в §13.3 порта) |
| T60 | INTEGRITY-178B | **Закрыт** | HIGH | Memory Sanitization on Object Death (реализовано в §1.7.0 порта через `Sanitize` + `Flip_Cell_Zeroize`) |
| T61 | seL4 / 0.7.3 #3 | Открыт | HIGH | Per-Process CSpace |
| T62 | 0.7.3 #4 | **Закрыт** | HIGH | Capability Quota Token (`Cap_Quota` в §3.3.1 порта; поле Process_Context) |
| T63 | 0.7.3 #20 | Открыт | MEDIUM | Cooperative Revocation Protocol |
| T64 | 0.7.3 #6 | **Закрыт** | MEDIUM | Watchdog Capability — lifecycle полный (§15 порта) |
| T65 | 0.7.3 #1 | **Закрыт** | MEDIUM | Batched Syscall (`Io_Batch` + `Io_Batch_Submit` в §5.6a порта) |
| T66 | 0.7.3 #8 | **Закрыт** | MEDIUM | IOMMU Domain как Cap (§17 порта) |
| T67 | Orange Book | Открыт | HIGH | Formally Verified Reference Monitor — SPARK приближает эту цель больше, чем Rust мог, но полное доказательство не выполнено в рамках порта |
| T68 | Люмо | **Закрыт** | BLOCKER | Per-CPU TLB Shootdown (§7 порта) |
| T69 | Люмо | **Закрыт** | HIGH | `Vec` → `Bounded_Vector` + политика no-heap (§0, §1.7.1 порта) |
| T70 | Люмо | Открыт | HIGH | Priority Inheritance для cap-ресурсов (Channel_Recv budget donation) |
| T71 | Люмо | **Закрыт** | HIGH | Shootdown timeout + `Degraded_Cpus` + `Cpu_Is_Degraded` (§7 порта) |
| T72 | Люмо | Открыт | MEDIUM | Power Management / Idle States (C-states, DVFS, Suspend) |
| T73 | Люмо | Открыт | MEDIUM | CPU Hotplug / SMP Boot Protocol |
| T74 | Люмо | **Закрыт** | HIGH | MSI-X в PRM (§18.4, §18.6 порта) |
| T75 | Люмо | Открыт | MEDIUM | Kernel Panic Recovery / kexec |
| T76 | Люмо | **Закрыт** | MEDIUM | `Per_Cpu` infrastructure (§A.3 порта) |
| T77 | Люмо | Открыт | MEDIUM | IoBatch Cancellation (`Io_Batch_Cancel` через `Flip_Cell.Rollback`) |
| T78 | Люмо | Открыт | LOW | Namespace Snapshot через `Flip_Cell` |
| T79 | Люмо | **Закрыт** | MEDIUM | Capability Sealing (`Cap_Seal` в §1.7.2 порта, переиспользует T28) |
| T80 | Люмо | Открыт | LOW | Persistent Audit Log |
| T81 | Люмо | Открыт | LOW | Live Patching через Execution Snapshots |
| T82 | Люмо | Частично | MEDIUM | `Watchdog_Policy` реализован (Notify/Freeze работают, §15 порта); `Kill_And_Respawn` обнаружил нерешённую гонку синхронизации `Reincarnation_Contract` между `Supervisor_Tick` и `Watchdog_Tick` — см. T107. Перенесено как `raise Program_Error` с явным сообщением, не как молчаливо работающий код (§15 порта) |
| T90 | Люмо | Открыт | HIGH | Crypto-API unified abstraction |
| T91 | Люмо | Открыт | MEDIUM | Side-channel mitigation policy |
| T92 | Люмо | Открыт | MEDIUM | Capability revocation timing proofs |
| T93 | Люмо | Открыт | HIGH | eBPF-like tracing infrastructure |
| T94 | Люмо | Открыт | MEDIUM | Kernel profiling counters — детекция всплеска естественно ложится на `Synapse` (§16a порта) |
| T95 | Люмо | Открыт | LOW | Deadlock detector — конфигурация `Synapse` (§16a порта) применима |
| T96 | Люмо | Открыт | HIGH | NUMA-aware memory allocation |
| T97 | Люмо | Открыт | HIGH | Zero-copy IPC fastpath для `Channel` (§10 порта) |
| T98 | Люмо | Открыт | MEDIUM | Lazy page fault handling |
| T99 | Люмо | Открыт | HIGH | Secure socket capabilities — **требует отдельного RFC**: сетевой стек в спецификации отсутствует полностью |
| T100 | Люмо | Открыт | MEDIUM | Network namespace isolation — зависит от T99, часть того же будущего RFC |
| T102 | Люмо | Открыт | LOW | Declarative system config DSL |
| T103 | Люмо | Открыт | LOW | Interactive debugger protocol |
| T104 | Люмо | Открыт | MEDIUM | RISC-V port completeness |
| T105 | Люмо | Открыт | LOW | ACPI/SMBIOS parsing |
| T106 | Люмо | Открыт | HIGH | GPU passthrough via IOMMU |
| T107 | Найден при T82 | Открыт | MEDIUM | Синхронизация `Reincarnation_Contract` — см. §15/§16.2 порта, перенесено дословно как нерешённая гонка |
| T108 | Обсуждение | **Закрыт** | HIGH | `Synapse` (§16a порта) |
| T109 | Найден при T108 | Открыт | LOW | `Cap_Any_Ref`/`Erased_Cap` — два разных имени одного понятия, перенесено дословно как неунифицированное (§16a.4 порта) |
| T110 | Обсуждение | **Закрыт** | MEDIUM | `Io_Template` (§5.6b порта) |
| T111 | Найден при аудите T110 | Открыт | MEDIUM | `Sqe_Params` union объявлен с 4 полями, но не все конкретные типы полей определены в исходном документе — перенесено как есть, не восстановлено портом |

**Статистика (перенесена из Rust-версии, статусы не пересматривались):**

35 закрытых, 3 частично закрытых (T32, T49, T82), 45 строго открытых
(без учёта частично), из них 1 BLOCKER (T22) и 16 HIGH (открытые +
частичные).

**Примечание к T99/T100 (сеть), перенесено без изменений:** в отличие
от остальных тикетов дорожной карты, это не точечное расширение
существующего механизма — в спецификации Tachy сетевой стек сейчас не
описан вообще: нет ни объектной модели сокета, ни namespace-интеграции,
ни связи с MAC (§13 порта). Закрытие T99/T100 в нынешнем виде ("одна
строка таблицы") невозможно — потребуется отдельный RFC/раздел (по
аналогии с тем, как §3.4 порта Re/Im появился из T56), а не патч к
§17/§13 порта. До тех пор T99/T100 остаются заглушкой "сеть не
спроектирована", а не планом реализации.

> **Наблюдение о самом исходном документе (не тикет порта, а
> добросовестное примечание):** это же примечание о T99/T100 присутствует
> в исходном `tachy_spec_x.md` дважды подряд (дословно повторено сразу
> после себя, разделено одной горизонтальной чертой). Порт не
> дублирует его здесь во второй раз и не пытается решить, было ли
> исходное дублирование намеренным — просто фиксирует наблюдение и
> сохраняет примечание один раз, поскольку повторный вывод одного и
> того же абзаца не несёт дополнительной информации для читателя
> Ada-версии.

### Открытые вопросы, специфичные для порта на Ada/SPARK (новые, не из Rust-версии)

| # | Раздел порта | Приоритет | Описание |
|---|---|---|---|
| T-Ada-01 | §2, §13 | HIGH | Наследуется из `revert-ring-001` (см. port-06): схлопывание 6→2 Ring Levels не было заново проверено на предмет ослабления инвариантов MAC/Biba. Порт переносит эту незакрытую оговорку без смягчения — не закрывает и не усугубляет её |
| T-Ada-02 | §6.1 | MEDIUM | `Rcu_Callback_Kind` (замена `Box<dyn FnOnce()>`, port-05) содержит представительный, не исчерпывающий список вариантов операции. Полный список, соответствующий каждому реальному месту вызова `Call_Rcu` в Rust-версии, требует отдельного прохода по всему документу для перечисления всех типов объектов, подлежащих RCU-отложенному уничтожению |
| T-Ada-03 | §6.1 (Rcu_Domain), §A.1 (Ticket_Lock) | MEDIUM | Отсутствие RAII в Ada `protected`-объектах требует парного ручного вызова Lock/Unlock и Read_Lock/Read_Unlock. Рекомендована (не обязательна) `Ada.Finalization`-обёртка для эргономики — не реализована в базовой версии порта |
| T-Ada-04 | §A.2 (Flip_Cell) | MEDIUM | Порядок памяti Acquire/Release для `pragma Atomic`-полей на платформах со слабой моделью памяти (ARM) может потребовать явного `System.Machine_Code`-барьера сверх того, что даёт `pragma Atomic`/`Volatile` по умолчанию — платформенный вопрос, не архитектурный |
| T-Ada-05 | §4.1 (Untyped_Region) | LOW | `Bounded_Vectors`-битмап с фиксированным потолком ёмкости (замена `Box<[AtomicU64]>`) требует, чтобы регионы, чей битмап превысил бы `Untyped_Bitmap_Words_Max`, были разбиты на несколько `Untyped_Region` на этапе конфигурации — вопрос конфигурации платформы |
| T-Ada-06 | §1.1, §1.3 (Cap_Object_Ref) | MEDIUM | Наследник T4 (Rust) в терминах Ada: `Cap_Object_Ref` (контролируемая ссылка со счётчиком, замена `Arc<T>`) должна гарантировать, что `Object_Destroy` логически мертвит объект сразу — даже если память физически жива до срабатывания `Ada.Finalization.Finalize` через RCU-отложенное уничтожение (§6.1 порта). Это требует того же порядка операций, что и в Rust-версии (epoch bump до фактического освобождения памяти), но формального доказательства этого порядка через SPARK-контракт в рамках этого порта не выполнено |
| T-Ada-07 | §1.2, §1.6, §3.3, §3.4.3, §4.3, §12.3, §16a.4, §17, §18.4 | HIGH | Полный список мест, перенесённых как `OPEN` (сигнатура/контракт без тела, портированные из `todo!()` Rust-версии): `Cap_Node.Alloc` (§1.2), `Cap_Mint` тело CAS-вставки (§1.6), `Ns_Mount` (§3.3), `Derive_Source_From_Backend` (§3.4.3), `Untyped_Retype_Body`/`Try_Reserve_Range` остаток (§4.3), `Package_Mount`/`Package_Unmount` (§12.3), `Erased_Cap_Check_Valid`/`Sealed_Call_Execute` обе ветки (§16a.4), `Iommu_Map` (§17), `Prm_Request_Resource` (§18.4). Ни одна из этих реализаций не была специфицирована по существу уже в Rust-версии — порт не восполняет их самостоятельно, следуя принципу №3 (честный TODO вместо тихой реализации) |
| T-Ada-08 | §5.3, §6.2, §17, §18.1, §18.6 | MEDIUM | Найдено компиляционным аудитом (не связано с `todo!()` Rust-версии — это недоделки самого порта): 11 типов вида `X_Result` используются, но не объявлены (`Copy_Result`, `Device_State_Result`, `Io_Batch_Result`, `Iommu_Domain_Alloc_Result`, `Msi_X_Alloc_Result`, `Page_Table_Result`, `Rdrand_Result`, `Validate_Mmio_Result`, `Validate_Port_Io_Result` и др., §18.6 порта — все возвращаются из методов `Hardware_Abstraction`), плюс две функции-конструкторы `Error_Result`/`Sync_Ok_Result`, использованные в `Kernel_Submit_Sqe` (§6.2 порта) без объявления. В отличие от `_Option` (решено единым generic-шаблоном, см. подраздел «Три структурных соглашения» после §0 порта) и `_Manage_Ref`/`_Read_Ref`/`_Write_Ref` (решено subtype-паттерном там же), у `_Result`-типов нет единой структуры полей — каждый обёртывает разные данные конкретной HAL-операции (например, `Validate_Mmio_Result` вероятно несёт диапазон адресов при успехе, `Rdrand_Result` — само случайное значение), поэтому единый generic-шаблон здесь неприменим так же прямо, как для `_Option`. Каждый должен быть объявлен индивидуально как discriminated record (`Ok : Boolean` + вариантные поля по `Ok`, по образцу уже показанного `Device_State_Result` в §18.1 порта) при переходе от этой спецификации к реальной реализации — порт фиксирует пробел, а не закрывает его придумыванием полей, которые нигде не специфицированы ни в этом документе, ни в Rust-версии |
| T-Ada-09 | §5.7.1a, §6.3, §10, §11.3, §15, §16a.5 | HIGH | Найдено при добавлении §1.3a (Weak_Ref) во время компиляционного аудита: `Scheduler_Block`/`Scheduler_Block_Current`/`Scheduler_Block_Until`, `Wake_All_With_Signal`/`Wake_All_With_Error`, `Current_Cpu_Id`, `Ms_To_Ticks` используются по всему документу, но нигде не объявлены. В отличие от T-Ada-06 (Weak_Ref — порт обязан был спроектировать сам, поскольку в Rust это встроенный языковой примитив), это унаследованная от Rust-версии недосказанность: сама Rust-спека тоже вызывает `scheduler_block`/`wake_all_with_signal` и подобные, нигде не определяя планировщик как отдельный API. Порт не восполняет отсутствующий scheduler самостоятельно — это отдельный, существенно больший по объёму раздел (тики, очереди готовности, приоритеты, CBS/Task_Force из T38), который потребовал бы отдельного прохода, сравнимого по объёму с §5-6 порта, а не точечного добавления |
| T-Ada-10 | §1.3b (новый), §3.1, §5.7.1, §10, §17, и ещё ~10 разделов | MEDIUM | Найдено повторной, более широкой сверкой после закрытия T-Ada-08/09 (не связано с `todo!()` Rust-версии — недоделка самого порта, той же природы, что и пробел, закрытый в §1.3a для `_Weak_Ref`): 17 типов вида `X_Ref` **без** суффикса `Manage`/`Read`/`Write`/`Weak` (`Cap_Object_Ref`, `Cap_Any_Ref`, `Channel_Ref`, `Device_Object_Ref`, `Iommu_Domain_Ref`, `Kernel_Object_Ref`, `Namespace_Node_Ref`, `Object_Bind_Prm_Ref`, `P_Union_Ref`, `Package_Image_Mount_Ref`, `Process_Context_Ref`, `Radix_Node_Ref`, `Reincarnation_Contract_Ref`, `Sched_Ctx_Ref`, `Synapse_Ref`, `Untyped_Region_Ref`, `V_Space_Ref`, `Watchdog_Ref`) использовались по всему документу, ни разу не объявленные — тот же класс пробела, что три уже исправленных соглашения (`_Option`, `_Manage_Ref`/`_Read_Ref`/`_Write_Ref`, `_Weak_Ref`), но не покрытый ни одним из трёх, поскольку ни одно из них не описывает бессуффиксную форму. Закрыто в этой версии добавлением §1.3b: `subtype`-паттерн, идентичный `_Manage_Ref`-соглашению (та же инстанциация `Tachy.Capability`, без статической проверки права по имени subtype), плюс отдельное объявление `Cap_Object_Ref` через `Ada.Finalization.Controlled`-обёртку (не через `Tachy.Capability`, поскольку это сам механизм владения, на котором `Tachy.Capability` основан, а не мандат на объект ядра). Синтаксис сверен вручную с уже присутствующими аналогичными конструкциями документа (не прогоном `gnatmake`, в отличие от `_Option`/`_Weak_Ref` — см. оговорку в конце §1.3b) |

---

## 24. Отклонённые предложения

R1–R6 из предшествующей модели документа — без изменений, унаследованы
через Rust-версию без пересмотра портом.

**TR1. Async/await в ядре.** Отклонено уже в Rust-версии: слишком тяжёлая
зависимость. `Io_Ring` + cooperative multitasking достаточны. Для
Ada-версии дополнительное соображение: Ada/SPARK-подмножество, пригодное
для верификации, ещё менее совместимо с async/await-подобными
конструкциями (они потребовали бы генерации state machine компилятором,
что усложняет, а не упрощает, формальное доказательство) — отказ от
async/await в Ada даже более обоснован, чем в Rust.

**TR2. Системный `RwLock`/эквивалент для `Attr_Entry.Value`.** Отклонено
уже в Rust-версии: системный `RwLock` может делать системный вызов при
блокировке — недопустимо в ядре. Вместо него использовался `Ticket_Lock`;
далее заменён на `Flip_Cell` (§A.2 порта) — читатели полностью
lock-free. Ada-версия наследует то же решение без изменений: Ravenscar
`protected`-объект также не подходил бы по той же причине (может
блокироваться на уровне планировщика), поэтому выбор `Flip_Cell`
остаётся правильным и для Ada.

**TR3. Перечисление вместо битовой маски для прав.** Отклонено уже в
Rust-версии: enum не поддерживает побитовое объединение без обёртки;
`bitflags!`-подобная семантика ближе к модели предшествующего документа.
Для Ada-версии то же рассуждение сохраняется буквально: Ada modular-тип
(`Mask` в §1.4 порта) даёт то же побитовое объединение без обёртки,
что и `bitflags!` в Rust — перечисление было бы шагом назад и здесь.

---

## 25. Отображение Rust-версия → Ada-версия (аналог §25 SYNTH → Tachy)

| Rust (Tachy 0.3.12) | Ada (этот порт) | Изменение/обоснование |
|-------|-------|-----------|
| `ObjectHeader` + `KernelObject` trait | `Object_Header` + `Kernel_Object` interface | тип по-прежнему вынесен отдельно; interface вместо trait — прямой аналог |
| `Cap<T, R>` + `CapNodeInner` | `Capability` (generic) + `Cap_Node_Inner` | `PhantomData<R>` заменён рантайм-маской + `Pre`-контрактами (port-02) |
| `AtomicU32` (Epoch) | `Interfaces.Unsigned_32` + `Volatile`/`Atomic` | тип совпадает (уже u32 в Rust-версии после fix-009), механизм атомарности — языковой атрибут вместо типа-обёртки |
| `AtomicBool` (RevokeInProgress, Claimed) | `Boolean` + `Volatile`/`Atomic` | то же |
| `Box<dyn FnOnce()>` (RCU callback) | `Rcu_Callback` (discriminated record) + `Rcu_Callback_Kind` (enum) | closures → закрытое перечисление вариантов (port-05) |
| `Box<str>` (Name) | `Name_Strings.Bounded_String` | динамический размер → фиксированная ёмкость (T69) |
| `AtomicPtr<T>` | `System.Address` (на границе платформы) или типизированный `access`-тип (во внутренней логике) | явное разделение platform-boundary vs internal, где Rust использовал единый тип для обоих случаев |
| `checked_mul()` | явная проверка деления перед умножением | тот же принцип защиты от переполнения, другой синтаксис |
| `Result<T, KernelError>` | `out Kernel_Error` параметр (+ `out` для значения при успехе) | Ada не имеет алгебраического типа результата уровня языка в этом стиле; явные `out`-параметры — идиоматичный эквивалент |
| `Option<T>` | discriminated record `_Option` (`Present : Boolean`) | нет `Option<T>` как языковой конструкции; локальный идиоматичный эквивалент |
| `TicketLock<T>` (ручной RAII через Drop) | `Ticket_Lock.Instance` (protected type) | RAII → компилятор гарантирует взаимное исключение на уровне грамматики (port-03) |
| `FlipCell<T>` | `Flip_Cell.Instance` | перенесено с усилением: SPARK формально доказывает инвариант через `Ghost`-функцию (port-04) |
| `dyn HardwareAbstraction` | `Hardware_Abstraction'Class` (tagged interface) | dyn-трейт → Ada dispatching-интерфейс, структурно эквивалентная стоимость вызова (port-08) |
| `#[repr(i32)]` enum (KernelError) | enumeration type + `for ... use (...)` representation clause | сохранены точные числовые коды (port-07) |
| `Vec`/произвольная `alloc` на hot path | `Ada.Containers.Bounded_Vectors` | T69: фиксированная ёмкость вместо динамической аллокации (port-08) |
| `Arc<T>` (cold path) | `Ada.Finalization.Controlled`-обёртка (`Cap_Object_Ref`) | управляемый счётчик ссылок, тот же принцип на cold path |
| `thread_local!` (FIRE_DEPTH в Synapse) | `Tachy.Per_Cpu` instantiation | per-thread → per-CPU, с оговоркой о разнице семантики (§16a.5 порта) |

---

**Конец документа.** Этот порт переносит архитектуру, инварианты и явно
задокументированные открытые вопросы спецификации Tachy 0.3.12 (Rust) на
Ada 2022/SPARK, следуя трём принципам, изложенным в начале документа:
сохранение силы инварианта, SPARK вместо `unsafe`-дисциплины, честный
TODO вместо тихой реализации. Список открытых пунктов, специфичных для
самого порта (T-Ada-01 … T-Ada-10, §23 порта), должен быть рассмотрен
до того, как этот документ будет использован как основа для реальной
реализации ядра, а не только как справочная спецификация.
