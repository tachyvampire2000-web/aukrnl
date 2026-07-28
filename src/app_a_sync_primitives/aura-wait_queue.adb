with Aura.Sched;
with Aura.Thread;
with Ada.Unchecked_Conversion;

package body Aura.Wait_Queue is

   use type System.Address;
   use type Aura.Thread.Thread_Access;

   function To_Thread_Access is new Ada.Unchecked_Conversion
     (System.Address, Aura.Thread.Thread_Access);
   function To_Address is new Ada.Unchecked_Conversion
     (Aura.Thread.Thread_Access, System.Address);

   procedure Prepare_With_Token
     (Self   : in out Instance;
      Token  : Wait_Token;
      Status : out Kernel_Error)
   is
      Current : constant Aura.Thread.Thread_Access := Aura.Sched.Current_Thread;
   begin
      if Self.Waiters >= Wait_Queue_Max_Waiters then
         Status := Max_Waiters;
         return;
      end if;

      for I in 1 .. Wait_Queue_Max_Waiters loop
         if not Self.Waiters_List (I).Active then
            Self.Waiters_List (I) := (Thread_Addr => To_Address (Current), Token => Token, Active => True);
            Self.Waiters := Self.Waiters + 1;
            Status := Ok;
            return;
         end if;
      end loop;

      Status := Max_Waiters;
   end Prepare_With_Token;

   procedure Prepare (Self : in out Instance; Status : out Kernel_Error) is
   begin
      Prepare_With_Token (Self, (Id => 0), Status);
   end Prepare;

   procedure Cancel (Self : in out Instance) is
      Current : constant Aura.Thread.Thread_Access := Aura.Sched.Current_Thread;
   begin
      for I in 1 .. Wait_Queue_Max_Waiters loop
         if Self.Waiters_List (I).Active and then Self.Waiters_List (I).Thread_Addr = To_Address (Current) then
            Self.Waiters_List (I) := (Thread_Addr => System.Null_Address, Token => (Id => 0), Active => False);
            if Self.Waiters > 0 then
               Self.Waiters := Self.Waiters - 1;
            end if;
            return;
         end if;
      end loop;
   end Cancel;

   function Waiter_Count_Snapshot (Self : Instance) return Natural is
     (Self.Waiters);

   procedure Wake_All_With_Signal (Self : in out Instance) is
      use type Interfaces.Unsigned_64;
      use type Aura.Thread.Thread_State;
      Th : Aura.Thread.Thread_Access;
   begin
      Self.Signal := Self.Signal + 1;

      for I in 1 .. Wait_Queue_Max_Waiters loop
         if Self.Waiters_List (I).Active then
            if Self.Waiters_List (I).Thread_Addr /= System.Null_Address then
               Th := To_Thread_Access (Self.Waiters_List (I).Thread_Addr);
               if Th /= null then
                  Th.State := Aura.Thread.Ready;
                  Aura.Sched.Sched_Add_Thread (0, Th);
               end if;
            end if;
            Self.Waiters_List (I) := (Thread_Addr => System.Null_Address, Token => (Id => 0), Active => False);
         end if;
      end loop;

      Self.Waiters := 0;
   end Wake_All_With_Signal;

   procedure Wake_With_Token (Self : in out Instance; Token : Wait_Token) is
      use type Interfaces.Unsigned_64;
      use type Aura.Thread.Thread_State;
      Th : Aura.Thread.Thread_Access;
   begin
      for I in 1 .. Wait_Queue_Max_Waiters loop
         if Self.Waiters_List (I).Active and then Self.Waiters_List (I).Token.Id = Token.Id then
            if Self.Waiters_List (I).Thread_Addr /= System.Null_Address then
               Th := To_Thread_Access (Self.Waiters_List (I).Thread_Addr);
               if Th /= null then
                  Th.State := Aura.Thread.Ready;
                  Aura.Sched.Sched_Add_Thread (0, Th);
               end if;
            end if;
            Self.Waiters_List (I) := (Thread_Addr => System.Null_Address, Token => (Id => 0), Active => False);
            if Self.Waiters > 0 then
               Self.Waiters := Self.Waiters - 1;
            end if;
         end if;
      end loop;
   end Wake_With_Token;

end Aura.Wait_Queue;
