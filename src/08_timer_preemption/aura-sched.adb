--  AURA — Scheduler (EDF / Earliest Deadline First implementation)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Ring;
with Aura.Timer;
with System;

package body Aura.Sched is

   use type Interfaces.Unsigned_64;
   use type Aura.Thread.Thread_Access;
   use type Aura.Thread.Sched_Ctx_Access;

   Boot_Thread : aliased Aura.Thread.Thread;
   Interrupt_Count : aliased Natural := 0;

   type Wakeup_Entry is record
      Thread   : Aura.Thread.Thread_Access := null;
      Deadline : Interfaces.Unsigned_64 := 0;
      Active   : Boolean := False;
   end record;

   Wakeups_List : array (1 .. 16) of Wakeup_Entry := [others => <>];

   procedure Process_Wakeups (Now : Interfaces.Unsigned_64) is
      use type Aura.Thread.Thread_State;
   begin
      for I in 1 .. 16 loop
         if Wakeups_List (I).Active and then Now >= Wakeups_List (I).Deadline then
            if Wakeups_List (I).Thread /= null then
               if Wakeups_List (I).Thread.State = Aura.Thread.Blocked then
                  Wakeups_List (I).Thread.State := Aura.Thread.Ready;
                  -- Add thread back to CPU 0 run queue
                  if Run_Queues (0).Ready_Count < Max_Sched_Threads then
                     -- Check for duplicates
                     declare
                        Duplicate : Boolean := False;
                     begin
                        for J in 1 .. Run_Queues (0).Ready_Count loop
                           if Run_Queues (0).Ready_Threads (J) = Wakeups_List (I).Thread then
                              Duplicate := True;
                              exit;
                           end if;
                        end loop;
                        if not Duplicate then
                           Run_Queues (0).Ready_Count := Run_Queues (0).Ready_Count + 1;
                           Run_Queues (0).Ready_Threads (Run_Queues (0).Ready_Count) := Wakeups_List (I).Thread;
                        end if;
                     end;
                  end if;
               end if;
            end if;
            Wakeups_List (I) := (Thread => null, Deadline => 0, Active => False);
         end if;
      end loop;
   end Process_Wakeups;

   function Interrupt_Dispatched_Count return Natural is
   begin
      return Interrupt_Count;
   end Interrupt_Dispatched_Count;

   procedure Sched_Add_Thread (Cpu : Natural; Th : Aura.Thread.Thread_Access) is
   begin
      if Cpu < Aura.Hal.Max_Cpus and then Th /= null then
         if Run_Queues (Cpu).Ready_Count < Max_Sched_Threads then
            -- Avoid duplicates
            for I in 1 .. Run_Queues (Cpu).Ready_Count loop
               if Run_Queues (Cpu).Ready_Threads (I) = Th then
                  return;
               end if;
            end loop;
            Run_Queues (Cpu).Ready_Count := Run_Queues (Cpu).Ready_Count + 1;
            Run_Queues (Cpu).Ready_Threads (Run_Queues (Cpu).Ready_Count) := Th;
         end if;
      end if;
   end Sched_Add_Thread;

   function Scheduler_Tick
     (Self : in out Run_Queue;
      Now  : Interfaces.Unsigned_64) return Scheduler_Decision
   is
      Tick_Duration_Us : constant := 1000;
   begin
      -- Process any pending thread wakeups whose deadlines have expired
      Process_Wakeups (Now);

      Self.Tick_Count := Self.Tick_Count + 1;

      -- Apply CBS budget decrement to current running thread
      if Self.Current /= null and then Self.Current.Active_Sched_Ctx /= null then
         declare
            Ctx : constant Aura.Thread.Sched_Ctx_Access := Self.Current.Active_Sched_Ctx;
         begin
            if Ctx.Remaining_Us >= Tick_Duration_Us then
               Ctx.Remaining_Us := Ctx.Remaining_Us - Tick_Duration_Us;
            else
               Ctx.Remaining_Us := 0;
            end if;

            if Ctx.Remaining_Us = 0 then
               if Now >= Ctx.Deadline_Tick then
                  -- Period ended, replenish budget and set next deadline
                  Ctx.Remaining_Us := Ctx.Budget_Us;
                  Ctx.Deadline_Tick := Now + Ctx.Period_Us / Tick_Duration_Us;
               else
                  -- Exhausted within current period: force preemption (throttling)
                  return Preempt;
               end if;
            end if;
         end;
      end if;

      if Self.Tick_Count mod Self.Quantum_Ticks = 0 then
         return Preempt;
      end if;
      return Keep_Running;
   end Scheduler_Tick;

   procedure Schedule (Cpu : Natural; Now : Interfaces.Unsigned_64) is
      use type Aura.Thread.Thread_State;
      use type Aura.Thread.Sched_Ctx_Access;
      Best_Thread   : Aura.Thread.Thread_Access := null;
      Best_Deadline : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last;
      Candidate     : Aura.Thread.Thread_Access;
      Tick_Duration_Us : constant := 1000;
   begin
      -- EDF algorithm: find ready/running thread with the earliest absolute deadline tick, accounting for CBS budget exhaustion/replenishment
      for I in 1 .. Run_Queues (Cpu).Ready_Count loop
         Candidate := Run_Queues (Cpu).Ready_Threads (I);
         if Candidate /= null
           and then (Candidate.State = Aura.Thread.Ready or else Candidate.State = Aura.Thread.Running)
         then
            declare
               Is_Throttled : Boolean := False;
               Ctx          : constant Aura.Thread.Sched_Ctx_Access := Candidate.Active_Sched_Ctx;
            begin
               if Ctx /= null then
                  if Ctx.Remaining_Us = 0 then
                     if Now >= Ctx.Deadline_Tick then
                        -- Replenish on demand
                        Ctx.Remaining_Us := Ctx.Budget_Us;
                        Ctx.Deadline_Tick := Now + Ctx.Period_Us / Tick_Duration_Us;
                     else
                        Is_Throttled := True;
                     end if;
                  end if;
               end if;

               if not Is_Throttled then
                  if Ctx /= null then
                     if Ctx.Deadline_Tick < Best_Deadline then
                        Best_Deadline := Ctx.Deadline_Tick;
                        Best_Thread   := Candidate;
                     end if;
                  else
                     -- No deadline (best-effort), treat as max deadline
                     if Best_Thread = null then
                        Best_Thread := Candidate;
                     end if;
                  end if;
               end if;
            end;
         end if;
      end loop;

      if Best_Thread /= null then
         Run_Queues (Cpu).Current := Best_Thread;
      else
         Run_Queues (Cpu).Current := Boot_Thread'Access;
      end if;
   end Schedule;

   function Current_Thread return Aura.Thread.Thread_Access is
      Cur : constant Aura.Thread.Thread_Access :=
        Run_Queues (Aura.Hal.Current_Cpu_Id).Current;
   begin
      return (if Cur /= null then Cur else Boot_Thread'Access);
   end Current_Thread;

   procedure Scheduler_Donate_Budget
     (Caller   : Aura.Thread.Thread_Access;
      Receiver : Aura.Thread.Thread_Access)
   is
   begin
      if Caller /= null and then Receiver /= null then
         Receiver.Active_Sched_Ctx := Caller.Active_Sched_Ctx;
      end if;
   end Scheduler_Donate_Budget;

   procedure Sched_Trigger_Interrupt_Thread
     (Irq : Interfaces.Unsigned_32)
   is
      pragma Unreferenced (Irq);
   begin
      Interrupt_Count := Interrupt_Count + 1;
   end Sched_Trigger_Interrupt_Thread;

   procedure Init_Boot_Thread is
   begin
      Boot_Thread.Header.Epoch       := 1;
      Boot_Thread.Header.Min_Ring    := Aura.Ring.Ring3;
      Boot_Thread.Header.Rcu_Domain  := null;
      Boot_Thread.Exec_Ctx           := (Registers    => [others => 0],
                                         Stack_Ptr    => 0,
                                         Bound_Vspace => null,
                                         Fpu_State    => [others => 0]);
      Boot_Thread.Snapshot_Valid     := False;
      Boot_Thread.Active_Sched_Ctx   := null;
      Boot_Thread.Own_Sched_Ctx.Header.Epoch      := 1;
      Boot_Thread.Own_Sched_Ctx.Header.Min_Ring   := Aura.Ring.Ring3;
      Boot_Thread.Own_Sched_Ctx.Header.Rcu_Domain := null;
      Boot_Thread.Own_Sched_Ctx.Budget_Us    := 10_000_000;
      Boot_Thread.Own_Sched_Ctx.Period_Us    := 10_000_000;
      Boot_Thread.Own_Sched_Ctx.Remaining_Us := 10_000_000;
      Boot_Thread.Own_Sched_Ctx.Deadline_Tick := 0;
      Boot_Thread.Own_Sched_Ctx.Numa_Node    := 0;
      Boot_Thread.Own_Sched_Ctx.Cpu_Affinity := 1;
      Boot_Thread.Migration_List_Next := null;
      Boot_Thread.Fault_Endpoint     := null;
      Boot_Thread.Last_Syscall_Tick  := 0;
      Boot_Thread.Ring_Level         := Aura.Ring.Ring0;
      Boot_Thread.State              := Aura.Thread.Running;
      Boot_Thread.Taint              := (Tainted => False, Taint_Level => 0, Taint_Categories => 0);
      Boot_Thread.Active_Sched_Ctx   := Boot_Thread.Own_Sched_Ctx'Access;
      Run_Queues (0).Current         := Boot_Thread'Access;
   end Init_Boot_Thread;

   procedure Scheduler_Block_Current is
      use type Aura.Thread.Thread_State;
      Cpu : constant Natural := Aura.Hal.Current_Cpu_Id;
      Current : constant Aura.Thread.Thread_Access := Run_Queues (Cpu).Current;
   begin
      if Current /= null and then Current /= Boot_Thread'Access then
         Current.State := Aura.Thread.Blocked;
      end if;
      -- Force context switch to next ready thread
      Schedule (Cpu, Aura.Timer.Current_Tick);
   end Scheduler_Block_Current;

   procedure Scheduler_Block_Until
     (Deadline : Interfaces.Unsigned_64;
      Status   : out Kernel_Error)
   is
      use type Aura.Thread.Thread_State;
      Cpu : constant Natural := Aura.Hal.Current_Cpu_Id;
      Current : constant Aura.Thread.Thread_Access := Run_Queues (Cpu).Current;
   begin
      if Current /= null and then Current /= Boot_Thread'Access then
         -- Register the deadline wakeup
         declare
            Registered : Boolean := False;
         begin
            for I in 1 .. 16 loop
               if not Wakeups_List (I).Active then
                  Wakeups_List (I) := (Thread => Current, Deadline => Deadline, Active => True);
                  Registered := True;
                  exit;
               end if;
            end loop;
            if not Registered then
               Status := Out_Of_Memory;
               return;
            end if;
         end;

         Current.State := Aura.Thread.Blocked;
      end if;

      -- Force context switch to next ready thread
      Schedule (Cpu, Aura.Timer.Current_Tick);

      -- Check if we timed out
      if Aura.Timer.Current_Tick >= Deadline then
         Status := Timeout;
      else
         Status := Ok;
      end if;
   end Scheduler_Block_Until;

   procedure Sweep_Expired_Mounts (Now : Interfaces.Unsigned_64) is
      pragma Unreferenced (Now);
   begin
      null;
   end Sweep_Expired_Mounts;

end Aura.Sched;
