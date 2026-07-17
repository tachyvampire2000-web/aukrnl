--  AURA Kernel — Memory of Scar (Persistent Reincarnation Checkpoints)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Object; use Aura.Object;
with Aura.Reincarnation;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;

package Aura.Proposals.Scar_Memory is

   pragma SPARK_Mode (On);

   --  Memory of Scar keeps a persistent checkpoint context of recent crash causes
   --  and fault parameters. Inspired by KeyKOS/EROS persistent checkpointing and
   --  fail-fast container systems, it allows AURA to detect repeated failure patterns
   --  (e.g., repeating Page_Faults at the exact same Instruction Pointer) and escalate
   --  the recovery strategy prematurely, bypassing standard Max_Restarts loops.

   type Crash_Reason is (Page_Fault, Syscall_Abort, Hardware_Irq_Hang, Unknown);

   type Scar_Entry is record
      Reason    : Crash_Reason;
      Fault_Pc  : Interfaces.Unsigned_64;
      Timestamp : Interfaces.Unsigned_64;
   end record;

   Max_Scars : constant := 4;
   type Scar_Log is array (1 .. Max_Scars) of Scar_Entry;

   type Persistent_Scar_Context is limited record
      Header            : Object_Header;
      Contract_Addr     : System.Address; -- Address of Reincarnation_Contract
      History           : Scar_Log;
      History_Length    : Natural range 0 .. Max_Scars;
      Next_Write_Idx    : Positive range 1 .. Max_Scars;
      Repeat_Threshold  : Positive;       -- Consecutive matching faults before escalation
   end record;

   --  Records a new crash event in the Scar history log.
   procedure Record_Crash_Scar
     (Context  : in out Persistent_Scar_Context;
      Reason   : Crash_Reason;
      Fault_Pc : Interfaces.Unsigned_64;
      Now      : Interfaces.Unsigned_64);

   --  Analyzes the scar log for matching crash pattern cycles.
   --  Returns True if identical crash reasons and PCs repeat >= Repeat_Threshold.
   function Check_Pattern_Escalation
     (Context : Persistent_Scar_Context) return Boolean;

end Aura.Proposals.Scar_Memory;
