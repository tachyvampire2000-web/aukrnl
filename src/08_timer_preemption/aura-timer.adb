--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Hal;      use Aura.Hal;
with Aura.Sched;    use Aura.Sched;
with Aura.Watchdog; use Aura.Watchdog;

package body Aura.Timer is

   procedure Timer_Interrupt_Handler is
      Cpu      : constant Natural := Current_Cpu_Id;
      Now      : Interfaces.Unsigned_64;
      Decision : Scheduler_Decision;
   begin
      Platform_Irq_Ack (Timer_Irq);
      Now := Global_Tick;
      Global_Tick := Global_Tick + 1;  --  Relaxed-эквивалент — простое
                                          --  инкрементирование Volatile-поля

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
