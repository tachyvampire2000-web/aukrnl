--  AURA — планировщик (per-CPU run queues).
--  Вытесняющее планирование с бюджетом Sched_Ctx (§5 порта): таймерный
--  тик уменьшает остаток бюджета текущего потока; исчерпание — Preempt.
--  Reference-реализация — минимальный каркас, честно документирующий
--  контракт; полноценный EDF/CBS-класс — предмет отдельного тикета.

with Interfaces;
with Aura.Hal;
with Aura.Thread;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

package Aura.Sched is

   pragma SPARK_Mode (Off);

   type Scheduler_Decision is (Keep_Running, Preempt);

   Max_Sched_Threads : constant := 16;
   type Sched_Threads_Array is array (1 .. Max_Sched_Threads) of Aura.Thread.Thread_Access;

   type Run_Queue is tagged limited record
      Current       : Aura.Thread.Thread_Access;
      Tick_Count    : Interfaces.Unsigned_64 := 0;
      Quantum_Ticks : Interfaces.Unsigned_64 := 10;

      Ready_Count   : Natural := 0;
      Ready_Threads : Sched_Threads_Array := [others => null];
   end record;

   -- Добавить готовый к исполнению поток в планировщик.
   procedure Sched_Add_Thread (Cpu : Natural; Th : Aura.Thread.Thread_Access);

   --  Обработать таймерный тик на очереди этого CPU.
   function Scheduler_Tick
     (Self : in out Run_Queue;
      Now  : Interfaces.Unsigned_64) return Scheduler_Decision;

   Run_Queues : array (0 .. Aura.Hal.Max_Cpus - 1) of Run_Queue;

   --  Переключить контекст на следующий готовый поток CPU.
   procedure Schedule (Cpu : Natural; Now : Interfaces.Unsigned_64);

   --  Текущий поток на текущем CPU.
   function Current_Thread return Aura.Thread.Thread_Access;

   --  Передать (пожертвовать) бюджет планирования от Caller к Receiver.
   procedure Scheduler_Donate_Budget
     (Caller   : Aura.Thread.Thread_Access;
      Receiver : Aura.Thread.Thread_Access);

   Interrupt_Thread_Dispatched_Count : aliased Natural := 0;

   -- Запустить потоковый обработчик прерывания (Interrupt Threading)
   procedure Sched_Trigger_Interrupt_Thread
     (Irq : Interfaces.Unsigned_32);

   --  Заблокировать текущий поток до внешнего пробуждения.
   procedure Scheduler_Block_Current;

   --  Заблокировать текущий поток до Deadline (в тиках);
   --  Timeout, если дедлайн истёк раньше пробуждения.
   procedure Scheduler_Block_Until
     (Deadline : Interfaces.Unsigned_64;
      Status   : out Kernel_Error);

   --  Периодическая уборка истёкших временных маунтов (§3 порта);
   --  вызывается с CPU 0 каждые 64 тика.
   procedure Sweep_Expired_Mounts (Now : Interfaces.Unsigned_64);

end Aura.Sched;
