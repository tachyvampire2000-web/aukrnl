package body Aura.Wait_Queue is

   procedure Prepare (Self : in out Instance; Status : out Kernel_Error) is
   begin
      if Self.Waiters >= Wait_Queue_Max_Waiters then
         Status := Max_Waiters;
         return;
      end if;
      Self.Waiters := Self.Waiters + 1;
      Status := Ok;
   end Prepare;

   procedure Prepare_With_Token
     (Self   : in out Instance;
      Token  : Wait_Token;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Token);
   begin
      Prepare (Self, Status);
   end Prepare_With_Token;

   procedure Cancel (Self : in out Instance) is
   begin
      if Self.Waiters > 0 then
         Self.Waiters := Self.Waiters - 1;
      end if;
   end Cancel;

   function Waiter_Count_Snapshot (Self : Instance) return Natural is
     (Self.Waiters);

   procedure Wake_All_With_Signal (Self : in out Instance) is
      use type Interfaces.Unsigned_64;
   begin
      Self.Signal := Self.Signal + 1;
   end Wake_All_With_Signal;

end Aura.Wait_Queue;
