--  AURA — Timer (absolute deadline timer implementation)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Hal;      use Aura.Hal;
with Aura.Sched;    use Aura.Sched;
with Aura.Watchdog; use Aura.Watchdog;

package body Aura.Timer is

   Timers_List : array (1 .. Max_Deadline_Timers) of Deadline_Timer;

   procedure Register_Deadline_Timer
     (Deadline : Interfaces.Unsigned_64;
      Callback : Deadline_Timer_Callback;
      Success  : out Boolean)
   is
   begin
      Success := False;
      for I in 1 .. Max_Deadline_Timers loop
         if not Timers_List (I).Active then
            Timers_List (I) := (Deadline => Deadline, Callback => Callback, Active => True);
            Success := True;
            return;
         end if;
      end loop;
   end Register_Deadline_Timer;

   procedure Timer_Interrupt_Handler is
      Cpu      : constant Natural := Current_Cpu_Id;
      Now      : Interfaces.Unsigned_64;
      Decision : Scheduler_Decision;
   begin
      Platform_Irq_Ack (Timer_Irq);
      Global_Tick := Global_Tick + 1;  --  Relaxed-эквивалент — простое
                                          --  инкрементирование Volatile-поля
      Now := Global_Tick;

      -- Check and fire absolute deadline timers
      for I in 1 .. Max_Deadline_Timers loop
         if Timers_List (I).Active and then Now >= Timers_List (I).Deadline then
            Timers_List (I).Active := False;
            if Timers_List (I).Callback /= null then
               Timers_List (I).Callback.all;
            end if;
         end if;
      end loop;

      Decision := Run_Queues (Cpu).Scheduler_Tick (Now);
      if Decision = Preempt then
         Schedule (Cpu, Now);
      end if;

      if Cpu = 0 and then Now mod 64 = 0 then
         Sweep_Expired_Mounts (Now);
      end if;

      Watchdog_Tick (Now);  --  T64
   end Timer_Interrupt_Handler;

end Aura.Timer;
