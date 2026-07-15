--  AURA Kernel — aura-channel.adb
--  SPDX-License-Identifier: GPL-2.0-only


with System;
with Aura.Hal;
with Aura.Sched;
with Aura.Timer;

package body Aura.Channel is

   use Aura.Wait_Queue;
   use type Aura.Notification.Notification_Ref;

   function Check_Valid
     (Cap : Channel_Endpoint_Write_Ref) return Kernel_Error
   is (if Cap.Object = null or else Cap.Object.Channel = null
       then Bad_Cap
       elsif not Contains (Cap.Rights, Write) then Bad_Rights
       else Ok);

   function Check_Valid
     (Cap : Channel_Endpoint_Read_Ref) return Kernel_Error
   is (if Cap.Object = null or else Cap.Object.Channel = null
       then Bad_Cap
       elsif not Contains (Cap.Rights, Aura.Rights.Read) then Bad_Rights
       else Ok);

   function Check_Valid (Cap : Notification_Read_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap
      elsif not Contains (Cap.Rights, Aura.Rights.Read) then Bad_Rights
      else Ok);

   --  Снять головное сообщение очереди (FIFO).
   procedure Pop
     (V        : in out Channel_Msg_Vectors.Vector;
      Msg      : out Channel_Message;
      Have_Msg : out Boolean)
   is
   begin
      if Channel_Msg_Vectors.Length (V) = 0 then
         Have_Msg := False;
         return;
      end if;
      Msg := Channel_Msg_Vectors.First_Element (V);
      Channel_Msg_Vectors.Delete_First (V);
      Have_Msg := True;
   end Pop;

   --  Есть ли входящие сообщения на стороне Ep.
   function Channel_Has_Pending
     (Ep : Channel_Endpoint_Read_Ref) return Boolean
   is
      Ch      : Channel renames Ep.Object.Channel.all;
      Q       : Channel_Queue;
      Pending : Boolean;
   begin
      case Ep.Object.Side is
         when Side_A => Ch.B_To_A.Lock (Q);
         when Side_B => Ch.A_To_B.Lock (Q);
      end case;
      Pending := Channel_Msg_Vectors.Length (Q.Msgs) > 0;
      case Ep.Object.Side is
         when Side_A => Ch.B_To_A.Unlock (Q);
         when Side_B => Ch.A_To_B.Unlock (Q);
      end case;
      return Pending;
   end Channel_Has_Pending;

   procedure Channel_Prepare_With_Token
     (Ep     : Channel_Endpoint_Read_Ref;
      Token  : Wait_Token;
      Status : out Kernel_Error)
   is
      Ch : Channel renames Ep.Object.Channel.all;
      Q  : Channel_Queue;
   begin
      case Ep.Object.Side is
         when Side_A => Ch.B_To_A.Lock (Q);
         when Side_B => Ch.A_To_B.Lock (Q);
      end case;
      Q.Wait.Prepare_With_Token (Token, Status);
      case Ep.Object.Side is
         when Side_A => Ch.B_To_A.Unlock (Q);
         when Side_B => Ch.A_To_B.Unlock (Q);
      end case;
   end Channel_Prepare_With_Token;

   procedure Channel_Cancel_Wait (Ep : Channel_Endpoint_Read_Ref) is
      Ch : Channel renames Ep.Object.Channel.all;
      Q  : Channel_Queue;
   begin
      case Ep.Object.Side is
         when Side_A => Ch.B_To_A.Lock (Q);
         when Side_B => Ch.A_To_B.Lock (Q);
      end case;
      Q.Wait.Cancel;
      case Ep.Object.Side is
         when Side_A => Ch.B_To_A.Unlock (Q);
         when Side_B => Ch.A_To_B.Unlock (Q);
      end case;
   end Channel_Cancel_Wait;

   procedure Channel_Send
     (Ep     : Channel_Endpoint_Write_Ref;
      Msg    : Channel_Message;
      Status : out Kernel_Error)
   is
      Ch       : Channel renames Ep.Object.Channel.all;
      Q        : Channel_Queue;
      Push_Status : Kernel_Error;
   begin
      Status := Check_Valid (Ep);
      if Status /= Ok then
         return;
      end if;

      case Ep.Object.Side is
         when Side_A =>
            Ch.A_To_B.Lock (Q);
            Channel_Msg_Vectors.Append (Q.Msgs, Msg);
            --  Waiter_Count читается напрямую только для проверки «есть
            --  ли кто» — пробуждение безопасно даже при
            --  ложно-положительном чтении.
            if Waiter_Count_Snapshot (Q.Wait) > 0 then
               Wake_All_With_Signal (Q.Wait);
            end if;
            Ch.A_To_B.Unlock (Q);
         when Side_B =>
            Ch.B_To_A.Lock (Q);
            Channel_Msg_Vectors.Append (Q.Msgs, Msg);
            if Waiter_Count_Snapshot (Q.Wait) > 0 then
               Wake_All_With_Signal (Q.Wait);
            end if;
            Ch.B_To_A.Unlock (Q);
      end case;
      Status := Ok;
   end Channel_Send;

   procedure Channel_Recv
     (Ep      : Channel_Endpoint_Read_Ref;
      Timeout : Tick_Option;
      Msg     : out Channel_Message;
      Status  : out Kernel_Error)
   is
      Ch          : Channel renames Ep.Object.Channel.all;
      Q           : Channel_Queue;
      Have_Msg    : Boolean;
      Prep_Status : Kernel_Error;
      Block_Status : Kernel_Error;
      Deadline    : Interfaces.Unsigned_64;
   begin
      Status := Check_Valid (Ep);
      if Status /= Ok then
         return;
      end if;

      loop
         --  Сначала проверяем без инкремента счётчика.
         case Ep.Object.Side is
            when Side_A => Ch.B_To_A.Lock (Q);
            when Side_B => Ch.A_To_B.Lock (Q);
         end case;

         Pop (Q.Msgs, Msg, Have_Msg);
         if Have_Msg then
            case Ep.Object.Side is
               when Side_A => Ch.B_To_A.Unlock (Q);
               when Side_B => Ch.A_To_B.Unlock (Q);
            end case;
            Status := Ok;
            return;
         end if;

         --  Сообщений нет — регистрируемся как waiter через Prepare
         --  (проверяет Max_Waiters, тот же контракт, что
         --  Notification_Wait).
         Q.Wait.Prepare (Prep_Status);
         case Ep.Object.Side is
            when Side_A => Ch.B_To_A.Unlock (Q);
            when Side_B => Ch.A_To_B.Unlock (Q);
         end case;
         if Prep_Status /= Ok then
            Status := Prep_Status;
            return;
         end if;

         if not Timeout.Present then
            Aura.Sched.Scheduler_Block_Current;
            Block_Status := Ok;
         else
            Deadline := Aura.Timer.Current_Tick + Timeout.Value;
            Aura.Sched.Scheduler_Block_Until (Deadline, Block_Status);
         end if;

         case Ep.Object.Side is
            when Side_A => Ch.B_To_A.Lock (Q); Q.Wait.Cancel; Ch.B_To_A.Unlock (Q);
            when Side_B => Ch.A_To_B.Lock (Q); Q.Wait.Cancel; Ch.A_To_B.Unlock (Q);
         end case;

         if Block_Status /= Ok then
            Status := Block_Status;  -- пробрасываем Timeout если истёк дедлайн
            return;
         end if;
      end loop;
   end Channel_Recv;

   procedure Cap_Wait_Any
     (Sources : Wait_Any_Source_Vectors.Vector;
      Timeout : Tick_Option;
      Index   : out Natural;
      Status  : out Kernel_Error)
   is
      Ready         : Boolean;
      Token         : Wait_Token;
      Prep_Status   : Kernel_Error;
      Block_Status  : Kernel_Error;
      Deadline      : Interfaces.Unsigned_64;
      Check_Status  : Kernel_Error;
   begin
      Index := 0;
      if Wait_Any_Source_Vectors.Length (Sources) = 0
        or else Wait_Any_Source_Vectors.Length (Sources) > Wait_Any_Max
      then
         Status := Invalid_Argument;
         return;
      end if;

      --  Проверяем все мандаты до блокировки.
      Index := 0;
      for I in 1 .. Natural (Wait_Any_Source_Vectors.Length (Sources)) loop
         declare
            S : constant Wait_Any_Source :=
              Wait_Any_Source_Vectors.Element (Sources, I);
         begin
            Check_Status := (case S.Kind is
                               when Notification_Source =>
                                 Check_Valid (S.Notification_Cap),
                               when Channel_Source =>
                                 Check_Valid (S.Channel_Cap));
            if Check_Status /= Ok then
               Status := Check_Status;
               return;
            end if;
         end;
      end loop;

      loop
         --  Фаза 1: poll — проверить без блокировки.
         for I in 1 .. Natural (Wait_Any_Source_Vectors.Length (Sources)) loop
            declare
               S : constant Wait_Any_Source :=
                 Wait_Any_Source_Vectors.Element (Sources, I);
            begin
               Ready := (case S.Kind is
                           when Notification_Source =>
                             S.Notification_Cap.Object.Pending > 0,
                           when Channel_Source =>
                             Channel_Has_Pending (S.Channel_Cap));
               if Ready then
                  Index := I - 1;  --  0-based индекс, идентично Rust enumerate()
                  Status := Ok;
                  return;
               end if;
            end;
         end loop;

         --  Фаза 2: регистрируемся как waiter на всех источниках.
         --  Используем общий Wait_Token — пробуждение любым источником
         --  разбудит нас.
         for I in 1 .. Natural (Wait_Any_Source_Vectors.Length (Sources)) loop
            declare
               S : constant Wait_Any_Source :=
                 Wait_Any_Source_Vectors.Element (Sources, I);
            begin
               case S.Kind is
                  when Notification_Source =>
                     S.Notification_Cap.Object.Wait_Queue.Prepare_With_Token
                       (Token, Prep_Status);
                  when Channel_Source =>
                     Channel_Prepare_With_Token (S.Channel_Cap, Token, Prep_Status);
               end case;
               if Prep_Status /= Ok then
                  Status := Prep_Status;
                  return;
               end if;
            end;
         end loop;

         --  Фаза 3: заблокироваться.
         if not Timeout.Present then
            Aura.Sched.Scheduler_Block_Current;
            Block_Status := Ok;
         else
            Deadline := Aura.Timer.Current_Tick + Timeout.Value;
            Aura.Sched.Scheduler_Block_Until (Deadline, Block_Status);
         end if;

         --  Отменить регистрацию на всех источниках.
         for I in 1 .. Natural (Wait_Any_Source_Vectors.Length (Sources)) loop
            declare
               S : constant Wait_Any_Source :=
                 Wait_Any_Source_Vectors.Element (Sources, I);
            begin
               case S.Kind is
                  when Notification_Source =>
                     S.Notification_Cap.Object.Wait_Queue.Cancel;
                  when Channel_Source =>
                     Channel_Cancel_Wait (S.Channel_Cap);
               end case;
            end;
         end loop;

         if Block_Status /= Ok then
            Status := Block_Status;  --  Timeout → возврат ошибки
            return;
         end if;
         --  Иначе — повторить poll (кто-то стал ready).
      end loop;
   end Cap_Wait_Any;

   function Task_Force_Decrement_Budget
     (Tf : in out Task_Force; Ticks : Interfaces.Unsigned_64) return Boolean
   is
      Cur, Next : Interfaces.Unsigned_64;
      Cas_Ok    : Boolean;
   begin
      loop
         Cur  := Tf.Shared_Budget_Us;
         --  saturating_sub эквивалент — Ada mod-типы не насыщают
         --  автоматически, явная проверка снизу необходима.
         Next := (if Cur >= Ticks then Cur - Ticks else 0);
         Aura.Hal.Atomic_Compare_Exchange_U64
           (Tf.Shared_Budget_Us'Address, Cur, Next, Cas_Ok);
         if Cas_Ok then
            return Next = 0;
         end if;
      end loop;
   end Task_Force_Decrement_Budget;

   function Task_Force_Decrement_Memory
     (Tf : in out Task_Force; Bytes : Interfaces.Unsigned_64) return Boolean
   is
      Cur, Next : Interfaces.Unsigned_64;
      Cas_Ok    : Boolean;
   begin
      loop
         Cur  := Tf.Shared_Memory_Budget;
         Next := (if Cur >= Bytes then Cur - Bytes else 0);
         Aura.Hal.Atomic_Compare_Exchange_U64
           (Tf.Shared_Memory_Budget'Address, Cur, Next, Cas_Ok);
         if Cas_Ok then
            return Next = 0;
         end if;
      end loop;
   end Task_Force_Decrement_Memory;

   function Task_Force_Decrement_Io
     (Tf : in out Task_Force; Operations : Interfaces.Unsigned_64) return Boolean
   is
      Cur, Next : Interfaces.Unsigned_64;
      Cas_Ok    : Boolean;
   begin
      loop
         Cur  := Tf.Shared_Io_Budget;
         Next := (if Cur >= Operations then Cur - Operations else 0);
         Aura.Hal.Atomic_Compare_Exchange_U64
           (Tf.Shared_Io_Budget'Address, Cur, Next, Cas_Ok);
         if Cas_Ok then
            return Next = 0;
         end if;
      end loop;
   end Task_Force_Decrement_Io;

end Aura.Channel;
