--  AURA Kernel — aura-thread.adb
--  SPDX-License-Identifier: GPL-2.0-only


with Ada.Unchecked_Deallocation;

package body Aura.Thread is

   procedure Sanitize_Fields (Self : in out Thread) is
      Zero : Execution_Context_Snap;
   begin
      Zero.Registers := (others => 0);
      Zero.Stack_Ptr := 0;
      Zero.Vspace_Phys_Root := 0;
      Zero.Vspace_Ref := null;
      Zero.Fpu_State := (others => 0);
      Snap_Cells.Zeroize (Self.Exec_Snapshot, Zero);
   end Sanitize_Fields;

   procedure Sched_Ctx_Create
     (Budget_Us, Period_Us : Interfaces.Unsigned_64;
      Result : out Sched_Ctx_Manage_Ref) is
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

   procedure Sched_Ctx_Destroy
     (Ctx : in out Sched_Ctx_Manage_Ref) is
      procedure Free_Context is new Ada.Unchecked_Deallocation (Sched_Ctx, Sched_Ctx_Access);
   begin
      if Ctx /= null then
         Free_Context (Ctx);
      end if;
   end Sched_Ctx_Destroy;

end Aura.Thread;
