--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package body Aura.Fault is

   function Check_Valid (C : Fault_Endpoint_Write_Ref) return Kernel_Error is (Ok);
   function Check_Valid (C : Thread_Manage_Ref) return Kernel_Error is (Ok);
   function Downgrade (C : Integer) return Xpc_Endpoint_Weak_Ref is (null);

   procedure Plat_Map_Segment
     (Root : Interfaces.Unsigned_64; Va, Pa, Size : Interfaces.Unsigned_64;
      Flags : Interfaces.Unsigned_32; Status : out Kernel_Error) is
   begin
      Status := Ok;
   end Plat_Map_Segment;

   procedure Sched_Resume (Th : in out Thread) is begin null; end;

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
      Th.Fault_Endpoint := null; -- Placeholder
      Status := Ok;
   end Thread_Set_Fault_Handler;

   procedure Thread_Resume
     (Thread_Cap : Thread_Manage_Ref;
      Map_Phys   : Phys_Addr_Option;
      Map_Va     : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   is
      Vspace_Root : Interfaces.Unsigned_64 := 0;
      Map_Status  : Kernel_Error;
      Flags       : constant Interfaces.Unsigned_32 := 3;
   begin
      Status := Check_Valid (Thread_Cap);
      if Status /= Ok then
         return;
      end if;

      if Map_Phys.Present then
         --  Платформенный вызов — граница платформы, идентичная
         --  unsafe-блоку Rust-версии.
         Plat_Map_Segment
           (Vspace_Root, Map_Va, Map_Phys.Value, 4096, Flags,
            Map_Status);
         if Map_Status /= Ok then
            Status := Map_Status;
            return;
         end if;
      end if;

      --  Sched_Resume (Th); Placeholder
      Status := Ok;
   end Thread_Resume;

end Aura.Fault;
