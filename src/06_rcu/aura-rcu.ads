--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Capability;
with System;
with Interfaces;

package Aura.Rcu is

   pragma SPARK_Mode (On);

   type Layer_Access is access all Integer; -- Placeholder
   type Attr_Entry_Access is access all Integer; -- Placeholder
   type Namespace_Node_Access is access all Integer; -- Placeholder
   type Element_Access is access all Integer; -- Placeholder

   subtype Cap_Object_Ref is System.Address; -- Placeholder

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
      Entries : Callback_Array := [others => (Present => False)];
      Len     : Natural := 0;
   end Rcu_Queue;

   type Rcu_Queue_Array is array (0 .. 1) of Rcu_Queue;

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
      Pending_Queues : Rcu_Queue_Array;
   end Rcu_Domain;


   --  (декларации из продолжения-фрагмента, doc-lines 3292-3317,
   --  после первоначального закрытия Aura.Rcu — тела того же
   --  фрагмента вынесены в .adb — см. MANIFEST §Находки)
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

   --  Общий RCU-домен ядра — для подсистем, не заводящих свой.
   Global_Domain : aliased Rcu_Domain;

   function Rcu_Read_Lock_Held return Boolean is (True) with Ghost;

end Aura.Rcu;
