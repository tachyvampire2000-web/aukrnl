--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Aura.Flip_Cell;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Ada.Containers.Bounded_Vectors;
with Interfaces;

package Aura.Io_Ring is

   pragma SPARK_Mode (Off);
   pragma Elaborate_Body;

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

   type Io_Ring_Sqe_Inner is record
      Op_Code : Io_Op_Code;
      Cap_Index : Interfaces.Unsigned_32;
   end record;

   package Sqe_Cells is new Aura.Flip_Cell (Io_Ring_Sqe_Inner);

   type Read_Write_Params is record
      Offset : Interfaces.Unsigned_64;
      Length : Interfaces.Unsigned_32;
   end record;

   type Xpc_Call_Params is record
      Method_Id : Interfaces.Unsigned_32;
   end record;

   type Attr_Watch_Params is record
      Attr_Id : Interfaces.Unsigned_32;
   end record;

   type Mount_Params is record
      Flags : Interfaces.Unsigned_32;
   end record;

   type Thread_Access is access all Integer; -- Placeholder

   subtype Io_Ring_Sqe is Sqe_Cells.Instance;

   --  Io_Batch
   Io_Batch_Max_Ops : constant := 32;

   type Io_Batch_Result_Step is record
      Status    : Kernel_Error;
      New_Value : Io_Ring_Sqe_Inner;
   end record;

   type Io_Batch_Step_Array is array (1 .. Io_Batch_Max_Ops) of Io_Ring_Sqe_Inner;
   type Io_Batch_Result_Step_Array is array (1 .. Io_Batch_Max_Ops) of Io_Batch_Result_Step;

   type Io_Batch_Result is record
      Step_Results : Io_Batch_Result_Step_Array;
      Failed_At    : Natural; -- 0 = success, otherwise 1-based index of failed step
   end record;

   type Io_Ring_Sqe_Inner_Access is access all Io_Ring_Sqe_Inner;

   package Batch_Target_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Io_Ring_Sqe_Inner_Access);

   type Io_Batch is record
      Targets : Batch_Target_Vectors.Vector (Io_Batch_Max_Ops);
      Steps   : Io_Batch_Step_Array;
      Count   : Natural range 0 .. Io_Batch_Max_Ops;
   end record;

   type Io_Ring is limited record
      Dummy : Integer := 0;
   end record;

   type Io_Ring_Sqe_Array is array (Positive range <>) of Io_Ring_Sqe_Inner;

   function Io_Batch_Compile (Sqes : Io_Ring_Sqe_Array) return Io_Batch;

   function Io_Batch_Execute (Ring : in out Io_Ring; Batch : in out Io_Batch) return Io_Batch_Result;

   function Io_Batch_Submit (Ring : in out Io_Ring; Sqes : Io_Ring_Sqe_Array) return Io_Batch_Result;

   procedure Io_Batch_Free (Batch : in out Io_Batch);

   --  Io_Template
   type Io_Template_Id is (Read_Then_Write, Map_Then_Set_Attr);

   type Template_Step is record
      Op_Code : Io_Op_Code;
      Cap_Index : Interfaces.Unsigned_32;
   end record;

   function Io_Template_Execute
     (Ring     : in out Io_Ring;
      Template : Io_Template_Id) return Io_Batch_Result;


   --  (продолжение из источника, doc-lines 2530-2571, после
   --  первоначального закрытия Aura.Io_Ring — см. MANIFEST §Находки)

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


   --  (декларации из продолжения-фрагмента, doc-lines 3131-3167,
   --  после первоначального закрытия Aura.Io_Ring — тела того же
   --  фрагмента вынесены в .adb — см. MANIFEST §Находки)
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

end Aura.Io_Ring;
