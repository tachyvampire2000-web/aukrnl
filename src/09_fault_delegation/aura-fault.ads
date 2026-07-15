--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Aura.Thread;
with Interfaces;

package Aura.Fault is

   pragma SPARK_Mode (On);

   type Process_Context_Weak_Ref is access all Integer; -- Placeholder
   type Xpc_Endpoint_Weak_Ref is access all Integer; -- Placeholder

   subtype Thread is Aura.Thread.Thread;

   type Fault_Endpoint is limited record
      Header       : Object_Header;
      Handler_Proc : Process_Context_Weak_Ref;
      Handler_Ep   : Xpc_Endpoint_Weak_Ref;
   end record;

   type Fault_Endpoint_Access is access all Fault_Endpoint;

   type Fault_Endpoint_Write_Ref is record
      Object : Fault_Endpoint_Access;
   end record;

   type Thread_Manage_Ref is record
      Object : Aura.Thread.Thread_Access;
   end record;

   type Phys_Addr_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Unsigned_64;
         when False => null;
      end case;
   end record;

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
      Status   : out Kernel_Error);



   --  (декларации из продолжения-фрагмента, doc-lines 3792-3833,
   --  после первоначального закрытия Aura.Fault — тела того же
   --  фрагмента вынесены в .adb — см. MANIFEST §Находки)
   procedure Thread_Resume
     (Thread_Cap : Thread_Manage_Ref;   --  требует Manage
      Map_Phys   : Phys_Addr_Option;      --  0/None-состояние эквивалентно
                                            --  Rust Option<u64>
      Map_Va     : Interfaces.Unsigned_64;
      Status     : out Kernel_Error);

   procedure Dispatch_Fault_To_Userspace
     (Th     : in out Thread;
      Msg    : Fault_Message;
      Status : out Kernel_Error);

end Aura.Fault;
