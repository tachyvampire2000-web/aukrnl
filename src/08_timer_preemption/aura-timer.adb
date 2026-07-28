--  AURA — Timer (absolute deadline timer implementation)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Hal;      use Aura.Hal;
with Aura.Sched;    use Aura.Sched;
with Aura.Watchdog; use Aura.Watchdog;

package body Aura.Timer is

   type Deadline_Timer_Array is array (1 .. Max_Deadline_Timers) of Deadline_Timer;

   protected Timers_Manager is
      procedure Register
        (Deadline : Interfaces.Unsigned_64;
         Callback : Deadline_Timer_Callback;
         Success  : out Boolean);
      procedure Process_Timers
        (Now : Interfaces.Unsigned_64);
   private
      Timers_List : Deadline_Timer_Array;
   end Timers_Manager;

   protected body Timers_Manager is
      procedure Register
        (Deadline : Interfaces.Unsigned_64;
         Callback : Deadline_Timer_Callback;
         Success  : out Boolean) is
      begin
         Success := False;
         for I in 1 .. Max_Deadline_Timers loop
            if not Timers_List (I).Active then
               Timers_List (I) := (Deadline => Deadline, Callback => Callback, Active => True);
               Success := True;
               return;
            end if;
         end loop;
      end Register;

      procedure Process_Timers
        (Now : Interfaces.Unsigned_64) is
      begin
         for I in 1 .. Max_Deadline_Timers loop
            if Timers_List (I).Active and then Now >= Timers_List (I).Deadline then
               Timers_List (I).Active := False;
               if Timers_List (I).Callback /= null then
                  Timers_List (I).Callback.all;
               end if;
            end if;
         end loop;
      end Process_Timers;
   end Timers_Manager;

   procedure Register_Deadline_Timer
     (Deadline : Interfaces.Unsigned_64;
      Callback : Deadline_Timer_Callback;
      Success  : out Boolean)
   is
   begin
      Timers_Manager.Register (Deadline, Callback, Success);
   end Register_Deadline_Timer;

   procedure Timer_Interrupt_Handler is
      Cpu      : constant Natural := Current_Cpu_Id;
      Now      : Interfaces.Unsigned_64;
      Decision : Scheduler_Decision;
   begin
      Platform_Irq_Ack (Timer_Irq);

      -- Atomic increment of Global_Tick using a CAS loop across all CPUs
      declare
         Expected : Interfaces.Unsigned_64;
         Success  : Boolean;
      begin
         loop
            Expected := Global_Tick;
            Atomic_Compare_Exchange_U64 (Global_Tick'Address, Expected, Expected + 1, Success);
            exit when Success;
         end loop;
      end;

      Now := Global_Tick;

      -- Check and fire absolute deadline timers
      Timers_Manager.Process_Timers (Now);

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
