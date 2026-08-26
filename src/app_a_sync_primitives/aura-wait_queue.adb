--  AURA — Wait_Queue (реализация с хранением потоков и реальным пробуждением)
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Wait_Queue is

   use type Interfaces.Unsigned_64;

   --  Найти свободный слот; вернуть 0 если нет места.
   function Find_Free_Slot (Self : Instance) return Natural is
   begin
      for I in 1 .. Wait_Queue_Max_Waiters loop
         if Self.Thread_Addrs (I) = Null_Thread_Handle
           and then Self.Tokens (I) = 0
         then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Free_Slot;

   procedure Prepare (Self : in out Instance; Status : out Kernel_Error) is
   begin
      if Self.Waiters >= Wait_Queue_Max_Waiters then
         Status := Max_Waiters;
         return;
      end if;
      Self.Waiters := Self.Waiters + 1;
      --  Без адреса потока — просто инкрементируем счётчик.
      Status := Ok;
   end Prepare;

   procedure Prepare_Thread
     (Self   : in out Instance;
      Thread : Thread_Handle;
      Status : out Kernel_Error)
   is
      Slot : Natural;
   begin
      if Self.Waiters >= Wait_Queue_Max_Waiters then
         Status := Max_Waiters;
         return;
      end if;
      Slot := Find_Free_Slot (Self);
      if Slot = 0 then
         Status := Max_Waiters;
         return;
      end if;
      Self.Thread_Addrs (Slot) := Thread;
      Self.Waiters := Self.Waiters + 1;
      Status := Ok;
   end Prepare_Thread;

   --  П.9 дорожной карты: токен реально сохраняется и используется для
   --  адресной доставки через Wake_With_Token.
   procedure Prepare_With_Token
     (Self   : in out Instance;
      Token  : Wait_Token;
      Status : out Kernel_Error)
   is
      Slot : Natural;
   begin
      if Self.Waiters >= Wait_Queue_Max_Waiters then
         Status := Max_Waiters;
         return;
      end if;
      Slot := Find_Free_Slot (Self);
      if Slot = 0 then
         Status := Max_Waiters;
         return;
      end if;
      Self.Tokens (Slot) := Token.Id;
      Self.Waiters := Self.Waiters + 1;
      Status := Ok;
   end Prepare_With_Token;

   procedure Cancel (Self : in out Instance) is
   begin
      if Self.Waiters > 0 then
         Self.Waiters := Self.Waiters - 1;
      end if;
   end Cancel;

   procedure Cancel_Thread (Self : in out Instance; Thread : Thread_Handle) is
   begin
      for I in 1 .. Wait_Queue_Max_Waiters loop
         if Self.Thread_Addrs (I) = Thread then
            Self.Thread_Addrs (I) := Null_Thread_Handle;
            Self.Tokens (I) := 0;
            if Self.Waiters > 0 then
               Self.Waiters := Self.Waiters - 1;
            end if;
            return;
         end if;
      end loop;
      --  Если не нашли по адресу — уменьшаем общий счётчик.
      if Self.Waiters > 0 then
         Self.Waiters := Self.Waiters - 1;
      end if;
   end Cancel_Thread;

   function Waiter_Count_Snapshot (Self : Instance) return Natural is
     (Self.Waiters);

   --  П.8 дорожной карты: Wake_All реально обходит сохранённые адреса
   --  потоков и вызывает Wake_Proc для каждого.
   procedure Wake_All_With_Signal (Self : in out Instance) is
   begin
      Self.Signal := Self.Signal + 1;
      if Wake_Proc /= null then
         for I in 1 .. Wait_Queue_Max_Waiters loop
            if Self.Thread_Addrs (I) /= Null_Thread_Handle then
               Wake_Proc (Self.Thread_Addrs (I));
               Self.Thread_Addrs (I) := Null_Thread_Handle;
            end if;
         end loop;
      end if;
      --  Сбрасываем токены — широковещательное пробуждение снимает всех.
      Self.Tokens := [others => 0];
      Self.Waiters := 0;
   end Wake_All_With_Signal;

   --  П.9 дорожной карты: адресная доставка по токену.
   procedure Wake_With_Token
     (Self  : in out Instance;
      Token : Wait_Token)
   is
   begin
      for I in 1 .. Wait_Queue_Max_Waiters loop
         if Self.Tokens (I) = Token.Id and then Token.Id /= 0 then
            if Wake_Proc /= null
              and then Self.Thread_Addrs (I) /= Null_Thread_Handle
            then
               Wake_Proc (Self.Thread_Addrs (I));
               Self.Thread_Addrs (I) := Null_Thread_Handle;
            end if;
            Self.Tokens (I) := 0;
            if Self.Waiters > 0 then
               Self.Waiters := Self.Waiters - 1;
            end if;
            return;
         end if;
      end loop;
   end Wake_With_Token;

end Aura.Wait_Queue;
