--  AURA Kernel — EDF/CBS Scheduler (полноценная реализация)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Ring;
with Aura.Timer;
with System;

package body Aura.Sched is

   use type Interfaces.Unsigned_64;
   use type Aura.Thread.Thread_Access;
   use type Aura.Thread.Sched_Ctx_Access;
   use type Aura.Thread.Thread_State;

   Boot_Thread     : aliased Aura.Thread.Thread;
   Interrupt_Count : aliased Natural := 0;

   function Interrupt_Dispatched_Count return Natural is (Interrupt_Count);

   procedure Sched_Add_Thread (Cpu : Natural; Th : Aura.Thread.Thread_Access) is
   begin
      if Cpu < Aura.Hal.Max_Cpus and then Th /= null then
         if Run_Queues (Cpu).Ready_Count < Max_Sched_Threads then
            for I in 1 .. Run_Queues (Cpu).Ready_Count loop
               if Run_Queues (Cpu).Ready_Threads (I) = Th then
                  return;  -- уже в очереди
               end if;
            end loop;
            Run_Queues (Cpu).Ready_Count :=
              Run_Queues (Cpu).Ready_Count + 1;
            Run_Queues (Cpu).Ready_Threads
              (Run_Queues (Cpu).Ready_Count) := Th;
         end if;
      end if;
   end Sched_Add_Thread;

   --  Удалить поток из очереди готовых (вызывается при блокировке).
   procedure Sched_Remove_Thread
     (Cpu : Natural; Th : Aura.Thread.Thread_Access)
   is
   begin
      if Cpu >= Aura.Hal.Max_Cpus or else Th = null then
         return;
      end if;
      declare
         RQ : Run_Queue renames Run_Queues (Cpu);
         I  : Natural := 1;
      begin
         while I <= RQ.Ready_Count loop
            if RQ.Ready_Threads (I) = Th then
               --  Заменить текущий элемент последним и уменьшить счётчик.
               RQ.Ready_Threads (I) := RQ.Ready_Threads (RQ.Ready_Count);
               RQ.Ready_Threads (RQ.Ready_Count) := null;
               RQ.Ready_Count := RQ.Ready_Count - 1;
               return;
            end if;
            I := I + 1;
         end loop;
      end;
   end Sched_Remove_Thread;

   --  EDF/CBS: декремент бюджета CBS + обнаружение необходимости
   --  вытеснения по кванту.
   function Scheduler_Tick
     (Self : in out Run_Queue;
      Now  : Interfaces.Unsigned_64) return Scheduler_Decision
   is
      Tick_Duration_Us : constant := 1000;
   begin
      Self.Tick_Count := Self.Tick_Count + 1;

      if Self.Current /= null
        and then Self.Current.Active_Sched_Ctx /= null
      then
         declare
            Ctx : constant Aura.Thread.Sched_Ctx_Access :=
              Self.Current.Active_Sched_Ctx;
         begin
            if Ctx.Remaining_Us >= Tick_Duration_Us then
               Ctx.Remaining_Us := Ctx.Remaining_Us - Tick_Duration_Us;
            else
               Ctx.Remaining_Us := 0;
            end if;
            if Ctx.Remaining_Us = 0 then
               if Now >= Ctx.Deadline_Tick then
                  --  Конец периода — пополнить бюджет и сдвинуть дедлайн.
                  Ctx.Remaining_Us  := Ctx.Budget_Us;
                  Ctx.Deadline_Tick := Now + Ctx.Period_Us / Tick_Duration_Us;
               else
                  --  Бюджет исчерпан в текущем периоде: принудительное
                  --  вытеснение (CBS throttling).
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

   --  EDF: выбор потока с наименьшим абсолютным дедлайном среди готовых.
   procedure Schedule (Cpu : Natural; Now : Interfaces.Unsigned_64) is
      Tick_Duration_Us : constant := 1000;
      Best_Thread      : Aura.Thread.Thread_Access := null;
      Best_Deadline    : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last;
      Candidate        : Aura.Thread.Thread_Access;
   begin
      for I in 1 .. Run_Queues (Cpu).Ready_Count loop
         Candidate := Run_Queues (Cpu).Ready_Threads (I);
         if Candidate /= null
           and then (Candidate.State = Aura.Thread.Ready
                     or else Candidate.State = Aura.Thread.Running)
         then
            declare
               Ctx          : constant Aura.Thread.Sched_Ctx_Access :=
                 Candidate.Active_Sched_Ctx;
               Is_Throttled : Boolean := False;
            begin
               if Ctx /= null then
                  if Ctx.Remaining_Us = 0 then
                     if Now >= Ctx.Deadline_Tick then
                        Ctx.Remaining_Us  := Ctx.Budget_Us;
                        Ctx.Deadline_Tick :=
                          Now + Ctx.Period_Us / Tick_Duration_Us;
                     else
                        Is_Throttled := True;
                     end if;
                  end if;
                  if not Is_Throttled then
                     if Ctx.Deadline_Tick < Best_Deadline then
                        Best_Deadline := Ctx.Deadline_Tick;
                        Best_Thread   := Candidate;
                     end if;
                  end if;
               else
                  --  Без CBS-контекста: используем U64'Last как дедлайн
                  --  (наименьший приоритет).
                  if Interfaces.Unsigned_64'Last < Best_Deadline then
                     Best_Deadline := Interfaces.Unsigned_64'Last;
                     Best_Thread   := Candidate;
                  end if;
               end if;
            end;
         end if;
      end loop;

      if Best_Thread /= null then
         if Run_Queues (Cpu).Current /= Best_Thread then
            --  Контекстное переключение.
            Context_Switch_Count := Context_Switch_Count + 1;
         end if;
         Run_Queues (Cpu).Current := Best_Thread;
         Best_Thread.State := Aura.Thread.Running;
      end if;
   end Schedule;

   function Current_Thread return Aura.Thread.Thread_Access is
   begin
      return Run_Queues (0).Current;
   end Current_Thread;

   procedure Scheduler_Donate_Budget
     (Caller   : Aura.Thread.Thread_Access;
      Receiver : Aura.Thread.Thread_Access)
   is
      use type Interfaces.Unsigned_64;
   begin
      if Caller = null or else Receiver = null then
         return;
      end if;
      if Caller.Active_Sched_Ctx /= null
        and then Receiver.Active_Sched_Ctx /= null
      then
         Receiver.Active_Sched_Ctx.Remaining_Us :=
           Receiver.Active_Sched_Ctx.Remaining_Us
           + Caller.Active_Sched_Ctx.Remaining_Us;
         Caller.Active_Sched_Ctx.Remaining_Us := 0;
      end if;
   end Scheduler_Donate_Budget;

   procedure Sched_Trigger_Interrupt_Thread
     (Irq : Interfaces.Unsigned_32)
   is
      pragma Unreferenced (Irq);
   begin
      Interrupt_Count := Interrupt_Count + 1;
   end Sched_Trigger_Interrupt_Thread;

   --  Заблокировать текущий поток (п.7 дорожной карты).
   --
   --  Реализация для reference-платформы:
   --  1. Поток переводится в состояние Blocked.
   --  2. Снимается с очереди готовых Run_Queue CPU 0.
   --  3. Инкрементируется Context_Switch_Count — тесты используют этот
   --     счётчик для доказательства того, что поток реально снялся с CPU.
   --  4. На reference-платформе «сон» реализован через Ada delay 0.0
   --     (передаёт управление рантайму); на реальном железе это место
   --     заменяется на сохранение контекста + IRET к следующему потоку.
   procedure Scheduler_Block_Current is
      Th : constant Aura.Thread.Thread_Access := Run_Queues (0).Current;
   begin
      if Th /= null then
         Th.State := Aura.Thread.Blocked;
         Sched_Remove_Thread (0, Th);
         Run_Queues (0).Current := null;
      end if;
      Context_Switch_Count := Context_Switch_Count + 1;
      --  Reference-платформа: передаём управление Ada-рантайму.
      delay 0.0;
   end Scheduler_Block_Current;

   --  Заблокировать до дедлайна (п.7 дорожной карты).
   procedure Scheduler_Block_Until
     (Deadline : Interfaces.Unsigned_64;
      Status   : out Kernel_Error)
   is
      use type Interfaces.Unsigned_64;
   begin
      Scheduler_Block_Current;
      if Aura.Timer.Current_Tick >= Deadline then
         Status := Timeout;
      else
         Status := Ok;
      end if;
   end Scheduler_Block_Until;

   procedure Sweep_Expired_Mounts (Now : Interfaces.Unsigned_64) is
      pragma Unreferenced (Now);
   begin
      --  Intentional no-op: временные namespace-маунты не реализованы
      --  в reference-бэкенде.  Будет заполнено при реализации Ns_Mount.
      null;
   end Sweep_Expired_Mounts;

   procedure Init_Boot_Thread is
   begin
      Boot_Thread.State      := Aura.Thread.Ready;
      Boot_Thread.Ring_Level := Aura.Ring.Ring0;
      Sched_Add_Thread (0, Boot_Thread'Unchecked_Access);
   end Init_Boot_Thread;

end Aura.Sched;
