--  AURA Kernel — Timer (deadline timer implementation, атомарный тик)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Hal;      use Aura.Hal;
with Aura.Sched;    use Aura.Sched;
with Aura.Watchdog; use Aura.Watchdog;
with System;

package body Aura.Timer is

   --  Защищённый объект для атомарного инкремента Global_Tick (п.4
   --  дорожной карты).  Interrupt_Priority'Last запрещает прерывания во
   --  время операции, устраняя потерянные инкременты при параллельном
   --  вызове Timer_Interrupt_Handler с нескольких CPU.
   protected Tick_State is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      procedure Increment (New_Val : out Interfaces.Unsigned_64);
   private
      null;
   end Tick_State;

   protected body Tick_State is
      procedure Increment (New_Val : out Interfaces.Unsigned_64) is
         use type Interfaces.Unsigned_64;
      begin
         Global_Tick := Global_Tick + 1;
         New_Val     := Global_Tick;
      end Increment;
   end Tick_State;

   --  Реестр дедлайн-таймеров (п.5 дорожной карты: защита от гонки
   --  Register vs Fire_Expired на разных CPU).
   protected body Timer_Registry is

      procedure Register
        (Deadline : Interfaces.Unsigned_64;
         Callback : Deadline_Timer_Callback;
         Success  : out Boolean)
      is
      begin
         Success := False;
         for I in 1 .. Max_Deadline_Timers loop
            if not Slots (I).Active then
               Slots (I) := (Deadline => Deadline,
                             Callback => Callback,
                             Active   => True);
               Success := True;
               return;
            end if;
         end loop;
      end Register;

      procedure Fire_Expired (Now : Interfaces.Unsigned_64) is
         use type Interfaces.Unsigned_64;
      begin
         for I in 1 .. Max_Deadline_Timers loop
            if Slots (I).Active and then Now >= Slots (I).Deadline then
               Slots (I).Active := False;
               if Slots (I).Callback /= null then
                  Slots (I).Callback.all;
               end if;
            end if;
         end loop;
      end Fire_Expired;

   end Timer_Registry;

   procedure Register_Deadline_Timer
     (Deadline : Interfaces.Unsigned_64;
      Callback : Deadline_Timer_Callback;
      Success  : out Boolean)
   is
   begin
      Timers.Register (Deadline, Callback, Success);
   end Register_Deadline_Timer;

   procedure Timer_Interrupt_Handler is
      Cpu      : constant Natural := Current_Cpu_Id;
      Now      : Interfaces.Unsigned_64;
      Decision : Scheduler_Decision;
   begin
      Platform_Irq_Ack (Timer_Irq);
      --  Атомарный инкремент через Tick_State (п.4 дорожной карты).
      Tick_State.Increment (Now);

      --  Проверка и срабатывание дедлайн-таймеров через защищённый
      --  реестр (п.5 дорожной карты).
      Timers.Fire_Expired (Now);

      Decision := Run_Queues (Cpu).Scheduler_Tick (Now);
      if Decision = Preempt then
         Schedule (Cpu, Now);
      end if;

      if Cpu = 0 and then (Now mod 64) = 0 then
         Sweep_Expired_Mounts (Now);
      end if;

      Watchdog_Tick (Now);
   end Timer_Interrupt_Handler;

end Aura.Timer;
