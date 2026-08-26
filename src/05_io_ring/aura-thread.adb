--  AURA Kernel — Thread lifecycle implementation
--  Пп.27,60 дорожной карты.
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Unchecked_Deallocation;

package body Aura.Thread is

   procedure Sanitize_Fields (Self : in out Thread) is
      Zero : Execution_Context_Snap;
   begin
      Zero.Registers        := (others => 0);
      Zero.Stack_Ptr        := 0;
      Zero.Vspace_Phys_Root := 0;
      Zero.Vspace_Ref       := null;
      Zero.Fpu_State        := (others => 0);
      --  П.60 дорожной карты: зачистка обеих сторон снимка.
      Snap_Cells.Zeroize (Self.Exec_Snapshot, Zero);
      Self.Snapshot_Valid := False;
   end Sanitize_Fields;

   procedure Sched_Ctx_Create
     (Budget_Us, Period_Us : Interfaces.Unsigned_64;
      Result               : out Sched_Ctx_Manage_Ref)
   is
      Ctx : Sched_Ctx_Access;
   begin
      Ctx := new Sched_Ctx;
      Ctx.Header.Epoch      := 1;
      Ctx.Header.Min_Ring   := Aura.Ring.Ring3;
      Ctx.Header.Rcu_Domain := null;
      Ctx.Budget_Us    := Budget_Us;
      Ctx.Period_Us    := Period_Us;
      Ctx.Remaining_Us := Budget_Us;
      Ctx.Deadline_Tick := 0;
      Ctx.Numa_Node     := 0;
      Ctx.Cpu_Affinity  := 1;
      Result := Sched_Ctx_Manage_Ref (Ctx);
   end Sched_Ctx_Create;

   procedure Sched_Ctx_Destroy (Ctx : in out Sched_Ctx_Manage_Ref) is
      procedure Free_Context is new Ada.Unchecked_Deallocation
        (Sched_Ctx, Sched_Ctx_Access);
   begin
      if Ctx /= null then
         Free_Context (Ctx);
      end if;
   end Sched_Ctx_Destroy;

   --  П.27 дорожной карты: полноценное создание потока с CBS-контекстом.
   procedure Thread_Create
     (Ring_Level : Aura.Ring.Ring_Level;
      Budget_Us  : Interfaces.Unsigned_64;
      Period_Us  : Interfaces.Unsigned_64;
      Result     : out Thread_Access)
   is
      Th  : Thread_Access;
      Ctx : Sched_Ctx_Access;
   begin
      Th := new Thread;
      Th.Header.Epoch      := 1;
      Th.Header.Min_Ring   := Ring_Level;
      Th.Header.Rcu_Domain := null;
      Th.Ring_Level        := Ring_Level;
      Th.State             := Created;
      Th.Mac_Level         := 0;
      Th.Taint             := (Tainted => False, Taint_Level => 0,
                               Categories => 0);
      Th.Fault_Endpoint    := null;
      Th.Last_Syscall_Tick := 0;

      if Budget_Us > 0 and then Period_Us > 0 then
         Ctx := new Sched_Ctx;
         Ctx.Header.Epoch      := 1;
         Ctx.Header.Min_Ring   := Ring_Level;
         Ctx.Header.Rcu_Domain := null;
         Ctx.Budget_Us    := Budget_Us;
         Ctx.Period_Us    := Period_Us;
         Ctx.Remaining_Us := Budget_Us;
         Ctx.Deadline_Tick := 0;
         Th.Active_Sched_Ctx := Ctx;
      else
         Th.Active_Sched_Ctx := null;
      end if;

      Sanitize_Fields (Th.all);
      Th.State := Ready;
      Result := Th;
   end Thread_Create;

   --  П.27,60 дорожной карты: уничтожение потока с зачисткой снимков.
   procedure Thread_Destroy (Th : in out Thread_Access) is
      procedure Free_Thread is new Ada.Unchecked_Deallocation
        (Thread, Thread_Access);
      procedure Free_Ctx is new Ada.Unchecked_Deallocation
        (Sched_Ctx, Sched_Ctx_Access);
   begin
      if Th = null then return; end if;
      --  П.60: зачищаем оба слота Flip_Cell перед освобождением.
      Sanitize_Fields (Th.all);
      if Th.Active_Sched_Ctx /= null then
         declare
            Ctx : Sched_Ctx_Access := Th.Active_Sched_Ctx;
         begin
            Free_Ctx (Ctx);
         end;
         Th.Active_Sched_Ctx := null;
      end if;
      Th.State := Zombie;
      Free_Thread (Th);
   end Thread_Destroy;

end Aura.Thread;
