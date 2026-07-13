package body Aura.Sched is

   use type Interfaces.Unsigned_64;

   Boot_Thread : aliased Aura.Thread.Thread;

   function Scheduler_Tick
     (Self : in out Run_Queue;
      Now  : Interfaces.Unsigned_64) return Scheduler_Decision
   is
      pragma Unreferenced (Now);
   begin
      Self.Tick_Count := Self.Tick_Count + 1;
      if Self.Tick_Count mod Self.Quantum_Ticks = 0 then
         return Preempt;
      end if;
      return Keep_Running;
   end Scheduler_Tick;

   procedure Schedule (Cpu : Natural; Now : Interfaces.Unsigned_64) is
      pragma Unreferenced (Now);
   begin
      --  Reference-каркас: единственный поток — переключение вырождается
      --  в no-op; точка входа переключения контекста остаётся здесь.
      Run_Queues (Cpu).Current := Boot_Thread'Access;
   end Schedule;

   function Current_Thread return Aura.Thread.Thread_Access is
      use type Aura.Thread.Thread_Access;
      Cur : constant Aura.Thread.Thread_Access :=
        Run_Queues (Aura.Hal.Current_Cpu_Id).Current;
   begin
      return (if Cur /= null then Cur else Boot_Thread'Access);
   end Current_Thread;

   procedure Scheduler_Block_Current is
   begin
      Aura.Hal.Spin_Loop_Hint;
   end Scheduler_Block_Current;

   procedure Scheduler_Block_Until
     (Deadline : Interfaces.Unsigned_64;
      Status   : out Kernel_Error)
   is
      pragma Unreferenced (Deadline);
   begin
      Aura.Hal.Spin_Loop_Hint;
      Status := Timeout;
   end Scheduler_Block_Until;

   procedure Sweep_Expired_Mounts (Now : Interfaces.Unsigned_64) is
      pragma Unreferenced (Now);
   begin
      null;
   end Sweep_Expired_Mounts;

end Aura.Sched;
