--  AURA Kernel — aura-thread.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Flip_Cell;
with Aura.Ring;
with Aura.Mac;
with Aura.Vspace;
with System.Storage_Elements;
with Interfaces;

package Aura.Thread is

   pragma SPARK_Mode (Off);

   type Register_File is array (1 .. 16) of Interfaces.Unsigned_64;
   type Fpu_State_Area is array (1 .. 512) of Interfaces.Unsigned_8;
   type V_Space_Ref is access all Aura.Vspace.V_Space;
   type V_Space_Weak_Ref is access all Aura.Vspace.V_Space;
   type Sched_Ctx is limited record
      Header       : Object_Header;
      Budget_Us    : Interfaces.Unsigned_64;
      Period_Us    : Interfaces.Unsigned_64;
      Remaining_Us : aliased Interfaces.Unsigned_64;
      Deadline_Tick : aliased Interfaces.Unsigned_64 := 0;
      Numa_Node     : aliased Interfaces.Unsigned_32 := 0;
      Cpu_Affinity  : aliased Interfaces.Unsigned_64 := 1;
   end record
     with Volatile;

   type Sched_Ctx_Access is access all Sched_Ctx;
   subtype Sched_Ctx_Manage_Ref is Sched_Ctx_Access;
   type Thread;
   type Thread_Access is access all Thread;
   type Fault_Endpoint_Weak_Ref is access all Aura.Object.Object_Header;

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

   package Snap_Cells is new Aura.Flip_Cell (Execution_Context_Snap);

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
      Own_Sched_Ctx        : aliased Sched_Ctx;
      Migration_List_Next  : Thread_Access;
      Fault_Endpoint       : Fault_Endpoint_Weak_Ref;
      Last_Syscall_Tick    : aliased Interfaces.Unsigned_64;  -- T64: watchdog
      Ring_Level           : Aura.Ring.Ring_Level;            -- fix-013
      State                : aliased Thread_State;
      Taint                : aliased Aura.Mac.Causal_Taint;   -- CIFC Taint tracking
   end record
     with Volatile;


   procedure Sched_Ctx_Create
     (Budget_Us, Period_Us : Interfaces.Unsigned_64;
      Result : out Sched_Ctx_Manage_Ref);

   procedure Sched_Ctx_Destroy
     (Ctx : in out Sched_Ctx_Manage_Ref);

   --  T60: зачистка обеих сторон снимка при уничтожении потока.

end Aura.Thread;
