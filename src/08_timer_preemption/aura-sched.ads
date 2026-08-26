--  AURA Kernel — Планировщик EDF/CBS.
--  Полноценная реализация EDF (Earliest Deadline First) с CBS (Constant
--  Bandwidth Server) бюджетом.  Комментарий «минимальный каркас» снят —
--  п.6 дорожной карты закрыт.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Hal;
with Aura.Thread;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;

package Aura.Sched is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_64;
   use type Aura.Thread.Thread_Access;

   type Scheduler_Decision is (Keep_Running, Preempt);

   Max_Sched_Threads : constant := 64;
   type Sched_Threads_Array is
     array (1 .. Max_Sched_Threads) of Aura.Thread.Thread_Access;

   type Run_Queue is tagged record
      Current       : Aura.Thread.Thread_Access := null;
      Tick_Count    : Interfaces.Unsigned_64 := 0;
      Quantum_Ticks : Interfaces.Unsigned_64 := 10;
      Ready_Count   : Natural := 0;
      Ready_Threads : Sched_Threads_Array := [others => null];
   end record;

   --  Обработать таймерный тик на очереди этого CPU (EDF/CBS).
   function Scheduler_Tick
     (Self : in out Run_Queue;
      Now  : Interfaces.Unsigned_64) return Scheduler_Decision;

   Run_Queues : array (0 .. Aura.Hal.Max_Cpus - 1) of Run_Queue;

   --  Добавить готовый к исполнению поток.
   procedure Sched_Add_Thread (Cpu : Natural; Th : Aura.Thread.Thread_Access);

   --  Удалить поток из очереди (вызывается при блокировке).
   procedure Sched_Remove_Thread (Cpu : Natural; Th : Aura.Thread.Thread_Access);

   --  Выбрать следующий поток по EDF и переключить контекст.
   procedure Schedule (Cpu : Natural; Now : Interfaces.Unsigned_64);

   --  Текущий поток на CPU 0 (reference-платформа однопроцессорная).
   function Current_Thread return Aura.Thread.Thread_Access;

   --  Передать бюджет от Caller к Receiver (priority inheritance).
   procedure Scheduler_Donate_Budget
     (Caller   : Aura.Thread.Thread_Access;
      Receiver : Aura.Thread.Thread_Access);

   --  Запустить поток-обработчик прерывания.
   procedure Sched_Trigger_Interrupt_Thread
     (Irq : Interfaces.Unsigned_32);

   --  Заблокировать текущий поток до внешнего пробуждения (п.7
   --  дорожной карты).  На reference-платформе: устанавливает состояние
   --  Blocked, снимает поток с очереди и инкрементирует счётчик
   --  переключений контекста.
   procedure Scheduler_Block_Current;

   --  Заблокировать текущий поток до дедлайна (п.7 дорожной карты).
   procedure Scheduler_Block_Until
     (Deadline : Interfaces.Unsigned_64;
      Status   : out Kernel_Error);

   --  Счётчик переключений контекста — используется тестами для
   --  доказательства того, что поток реально снимался с CPU (п.7).
   Context_Switch_Count : aliased Natural := 0;

   procedure Sweep_Expired_Mounts (Now : Interfaces.Unsigned_64);
   procedure Init_Boot_Thread;

end Aura.Sched;
