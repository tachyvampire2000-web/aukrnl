--  AURA Kernel — Boot/Loader Subsystem implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces; use type Interfaces.Unsigned_64;
with Aura.Thread;
with Aura.Sched;
with Aura.Cap_Node;
with Aura.Package_Fs;
with Aura.Namespace;
with Aura.Vspace;
with Aura.Ring;
with Aura.Timer;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

package body Aura.Boot is

   use type Aura.Cap_Node.Cap_Node_Access;
   use type Aura.Sched.Scheduler_Decision;
   use type Aura.Thread.Thread_Access;

   type Package_Union_Access is access all Aura.Package_Fs.P_Union;

   function To_P_Union_Ref is new Ada.Unchecked_Conversion
     (Source => Package_Union_Access,
      Target => Aura.Namespace.P_Union_Ref);

   function To_Thread_Vspace_Ref is new Ada.Unchecked_Conversion
     (Source => Aura.Vspace.V_Space_Ref,
      Target => Aura.Thread.V_Space_Ref);

   --  Static allocations for Boot / System Loader
   Init_Thread  : aliased Aura.Thread.Thread;
   Init_Vspace  : aliased Aura.Vspace.V_Space;
   Stable_Image : aliased Aura.Package_Fs.Package_Image_Object;
   Base_Union   : aliased Aura.Package_Fs.P_Union :=
     (Images         => [others => null],
      Image_Count    => 0,
      Combined_Bloom => (Combined => [others => 0]));

   Init_Layer : constant Aura.Namespace.Layer :=
     (Header  => <>,
      Kind    => Aura.Namespace.System,
      Id      => Aura.Namespace.Name_Strings.To_Bounded_String ("stable"),
      Slot    => (Idx => 0, Gen => 1),
      State   => Aura.Namespace.Live,
      Backend => (Kind  => Aura.Namespace.Package_Backend,
                  Union => To_P_Union_Ref (Base_Union'Unchecked_Access)));

   procedure Boot_System is
      Status : Kernel_Error;
      Cap_Node_Root : Aura.Cap_Node.Cap_Node_Access;
   begin
      Put_Line ("======================================================================");
      Put_Line ("            AURA HYBRID CAPABILITY-BASED KERNEL BOOT SEQUENCE         ");
      Put_Line ("======================================================================");
      Put_Line ("ST-001: Initializing CPU 0 Reference HAL...");
      Put_Line ("ST-002: Initializing Capability Nodes Pool...");

      Aura.Cap_Node.Alloc (Obj_Epoch => 1, Result => Cap_Node_Root, Status => Status);
      if Status /= Ok or Cap_Node_Root = null then
         Put_Line ("ERROR: Failed to allocate Capability Nodes Pool!");
         return;
      end if;
      Put_Line ("  - Allocated root capability node successfully (Token:" & Cap_Node_Root.Cap_Token'Image & ")");

      Put_Line ("ST-003: Initializing Root Namespace ""/""...");

      Put_Line ("ST-004: Mounting Package File System Image ""stable""...");
      Stable_Image.Id := 1;
      Stable_Image.Bloom := [0 => 16#CAFE_BABE_0000_0000#, others => 0];

      Aura.Package_Fs.Package_Mount (Base_Union, Stable_Image'Unchecked_Access, Status);
      if Status /= Ok then
         Put_Line ("ERROR: Failed to mount stable package image!");
         return;
      end if;
      Put_Line ("  - Stable image mounted. Combined Bloom(0):" & Base_Union.Combined_Bloom.Combined (0)'Image);

      Put_Line ("ST-005: Setup System Layer [C::stable] for ""/exe/init""...");
      Init_Vspace.Page_Table_Root := 16#CAFE_BAB0#;
      Put_Line ("  - System Layer ID: " & Aura.Namespace.Name_Strings.To_String (Init_Layer.Id));
      Put_Line ("  - Associated Page Table Root: 0x" & Interfaces.Unsigned_64'Image (Init_Vspace.Page_Table_Root));

      Put_Line ("ST-006: Spawning first system process thread: ""/exe/init""...");
      Init_Thread.State := Aura.Thread.Ready;
      Init_Thread.Ring_Level := Aura.Ring.Ring3; -- User mode execution

      -- Initialize Sched_Ctx (EDF/CBS parameters)
      Init_Thread.Active_Sched_Ctx := Init_Thread.Own_Sched_Ctx'Unchecked_Access;
      Init_Thread.Own_Sched_Ctx.Budget_Us := 2000;       -- 2 ticks of execution budget
      Init_Thread.Own_Sched_Ctx.Period_Us := 10000;      -- 10 ticks period
      Init_Thread.Own_Sched_Ctx.Remaining_Us := 2000;
      Init_Thread.Own_Sched_Ctx.Deadline_Tick := 10;
      Init_Thread.Own_Sched_Ctx.Cpu_Affinity := 1;
      Init_Thread.Own_Sched_Ctx.Numa_Node := 1;

      -- Set Initial execution context registers and bind Vspace
      Init_Thread.Exec_Ctx.Registers (1) := 16#1000_0000#; -- Instruction entry point
      Init_Thread.Exec_Ctx.Stack_Ptr := 16#7FFF_FFFF_0000#; -- Initial stack pointer
      Init_Thread.Exec_Ctx.Bound_Vspace := To_Thread_Vspace_Ref (Init_Vspace'Unchecked_Access);

      Put_Line ("  - Init thread configured (Budget: 2ms, Period: 10ms, Entry: 0x10000000, Stack: 0x7FFFFFFF0000)");

      Put_Line ("ST-007: Registering Init thread with CPU 0 Scheduler run queue...");
      Aura.Sched.Sched_Add_Thread (0, Init_Thread'Unchecked_Access);

      Put_Line ("======================================================================");
      Put_Line ("            AURA SCHEDULER ACTIVE EXECUTION LOOP RUNNING              ");
      Put_Line ("======================================================================");

      -- Run execution loop for 15 ticks to simulate EDF scheduling, CBS preemption and throttling,
      -- and replenishment on deadline ticks.
      for Tick in 1 .. 15 loop
         Aura.Timer.Global_Tick := Interfaces.Unsigned_64 (Tick);
         Put_Line ("--- Tick" & Tick'Image & " ---");

         -- Process scheduler tick on CPU 0 run queue
         declare
            Decision : constant Aura.Sched.Scheduler_Decision :=
              Aura.Sched.Run_Queues (0).Scheduler_Tick (Now => Aura.Timer.Global_Tick);
         begin
            if Decision = Aura.Sched.Preempt then
               Put_Line ("  [Event] CBS/Quantum Preemption Triggered!");
            end if;
         end;

         -- Run scheduling decision
         Aura.Sched.Schedule (0, Now => Aura.Timer.Global_Tick);

         -- Log which thread is currently running
         declare
            Cur : constant Aura.Thread.Thread_Access := Aura.Sched.Current_Thread;
         begin
            if Cur = Init_Thread'Unchecked_Access then
               Put_Line ("  [Running] /exe/init (Remaining budget:" &
                         Cur.Active_Sched_Ctx.Remaining_Us'Image & "us, Deadline tick:" &
                         Cur.Active_Sched_Ctx.Deadline_Tick'Image & ")");
            else
               Put_Line ("  [Running] Boot/Idle Thread (Init thread throttled until tick:" &
                         Init_Thread.Own_Sched_Ctx.Deadline_Tick'Image & ")");
            end if;
         end;
      end loop;

      Put_Line ("======================================================================");
      Put_Line ("            AURA KERNEL SHUTTING DOWN GRACEFULLY                      ");
      Put_Line ("======================================================================");
   end Boot_System;

end Aura.Boot;
