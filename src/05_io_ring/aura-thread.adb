--  AURA Kernel — aura-thread.adb
--  SPDX-License-Identifier: GPL-2.0-only


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
   begin
      Result := null; -- Placeholder
   end Sched_Ctx_Create;

end Aura.Thread;
