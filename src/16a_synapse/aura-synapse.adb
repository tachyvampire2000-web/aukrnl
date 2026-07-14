--  Единый сигнальный движок AURA: integrate-and-fire синапс с
--  положительными/отрицательными вкладами, двумя порогами (накопление и
--  -спайк), утечкой и закрытым набором действий при срабатывании.
--  Обычная подписка/notification — вырожденный синапс с Threshold_Hi = 1.

with Aura.Wait_Queue;
with Aura.Timer;

package body Aura.Synapse is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Aura.Notification.Notification_Ref;

   type Fire_Direction is (Fired_Hi, Fired_Lo);

   function Apply_Delta_Depth
     (Syn         : in out Synapse;
      Value_Delta : Interfaces.Integer_32;
      Depth       : Natural) return Kernel_Error;

   function Check_Valid (Cap : Synapse_Tap_Write_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap
      elsif not Contains (Cap.Rights, Write) then Bad_Rights
      else Ok);

   function Downgrade (Strong : Synapse_Ref) return Synapse_Weak_Ref is
     (Target         => Strong,
      Expected_Epoch =>
        (if Strong /= null then Strong.Header.Epoch else 0));

   procedure Upgrade
     (Self  : Synapse_Weak_Ref;
      Value : out Synapse_Ref;
      Alive : out Boolean)
   is
   begin
      if Self.Target /= null
        and then Self.Target.Header.Epoch = Self.Expected_Epoch
      then
         Value := Self.Target;
         Alive := True;
      else
         Value := null;
         Alive := False;
      end if;
   end Upgrade;

   function Current_Tick return Interfaces.Unsigned_64
     is (Aura.Timer.Current_Tick);

   function Saturating_Sub_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (if A >= B then A - B else 0);

   procedure Apply_Decay_If_Due (Syn : in out Synapse);

   function Erased_Cap_Check_Valid (Cap : Erased_Cap) return Kernel_Error is
   begin
      if not Cap.Valid then
         return Bad_Cap;
      end if;
      return Ok;
   end Erased_Cap_Check_Valid;

   function Sealed_Call_Execute (Call : Sealed_Call) return Kernel_Error is
      Check_Status : Kernel_Error;
      Len : constant Integer := Integer (Sealed_Cap_Vectors.Length (Call.Caps));
   begin
      for I in 1 .. Len loop
         Check_Status := Erased_Cap_Check_Valid
           (Sealed_Cap_Vectors.Element (Call.Caps, I));
         if Check_Status /= Ok then
            return Check_Status;
         end if;
      end loop;
      case Call.Op.Kind is
         when Object_Destroy_Op =>
            return Ok;
         when Watchdog_Policy_Override_Op =>
            return Ok;
      end case;
   end Sealed_Call_Execute;

   --  Диспетчеризация закрытого набора действий при срабатывании.
   function Synapse_Fire
     (Syn       : in out Synapse;
      Direction : Fire_Direction;
      Depth     : Natural) return Kernel_Error
   is
   begin
      case Syn.Action.Kind is
         when Signal_Notification_Action =>
            declare
               Notif : constant Aura.Notification.Notification_Ref :=
                 Syn.Action.Notif_Target.Target;
            begin
               if Notif = null
                 or else Notif.Header.Epoch /=
                   Syn.Action.Notif_Target.Expected_Epoch
               then
                  return Revoked;
               end if;
               Notif.Pending := Notif.Pending or Syn.Action.Notif_Bit;
               if Aura.Wait_Queue.Waiter_Count_Snapshot (Notif.Wait_Queue) > 0
               then
                  Aura.Wait_Queue.Wake_All_With_Signal (Notif.Wait_Queue);
               end if;
               return Ok;
            end;

         when Feed_Synapse_Action =>
            if Depth >= Synapse_Max_Fire_Depth then
               Last_Fired_Trace_Id := 999999999; -- Special Cascade Fault Tracepoint ID!
               return Cascade_Too_Deep;
            end if;
            declare
               Next  : Synapse_Ref;
               Alive : Boolean;
            begin
               Upgrade (Syn.Action.Synapse_Target, Next, Alive);
               if not Alive then
                  return Revoked;
               end if;
               return Apply_Delta_Depth
                 (Next.all, Signal_Delta (Syn.Action.Feed_Kind), Depth + 1);
            end;

         when Execute_Sealed_Action =>
            if Syn.Action.Sealed = null then
               return Bad_Cap;
            end if;
            return Sealed_Call_Execute (Syn.Action.Sealed.all);

         when Gate_Policy_Action =>
            if Syn.Action.Policy_Target = null then
               return Bad_Cap;
            end if;
            Aura.Cap_Policy.Apply_Gate
              (Syn.Action.Policy_Target.all,
               (case Direction is
                  when Fired_Hi => Syn.Action.Gate_On_Hi,
                  when Fired_Lo => Syn.Action.Gate_On_Lo));
            return Ok;

         when Trace_Event_Action =>
            Last_Fired_Trace_Id := Syn.Action.Trace_Id;
            return Ok;

         when Reject_If_Saturated_Action =>
            -- Universal rate limiter: if threshold hi is fired, reject
            if Direction = Fired_Hi then
               return Would_Block;
            else
               return Ok;
            end if;
      end case;
   end Synapse_Fire;

   function Apply_Delta_Depth
     (Syn         : in out Synapse;
      Value_Delta : Interfaces.Integer_32;
      Depth       : Natural) return Kernel_Error
   is
      New_Charge : Interfaces.Integer_32;
   begin
      Apply_Decay_If_Due (Syn);
      New_Charge := Syn.Charge + Value_Delta;

      -- Charge Saturation Clamping / Hard Limits
      if New_Charge > Syn.Max_Charge_Cap then
         New_Charge := Syn.Max_Charge_Cap;
      elsif New_Charge < Syn.Min_Charge_Cap then
         New_Charge := Syn.Min_Charge_Cap;
      end if;

      Syn.Charge := New_Charge;

      if New_Charge >= Syn.Threshold_Hi then
         case Syn.Reset_Mode_Field is
            when To_Zero             => Syn.Charge := 0;
            when Subtract_Threshold  =>
               Syn.Charge := Syn.Charge - Syn.Threshold_Hi;
         end case;
         return Synapse_Fire (Syn, Fired_Hi, Depth);
      end if;

      if Syn.Threshold_Lo.Present then
         if New_Charge <= Syn.Threshold_Lo.Value then
            case Syn.Reset_Mode_Field is
               when To_Zero             => Syn.Charge := 0;
               when Subtract_Threshold  =>
                  Syn.Charge := Syn.Charge - Syn.Threshold_Lo.Value;
            end case;
            return Synapse_Fire (Syn, Fired_Lo, Depth);
         end if;
      end if;

      return Ok;
   end Apply_Delta_Depth;

   function Synapse_Apply_Delta
     (Syn         : in out Synapse;
      Value_Delta : Interfaces.Integer_32) return Kernel_Error
   is (Apply_Delta_Depth (Syn, Value_Delta, Depth => 0));

   function Synapse_Signal (Tap : Synapse_Tap_Write_Ref) return Kernel_Error
   is
      Target_Alive : Boolean;
      Target       : Synapse_Ref;
      Kind         : Signal_Kind;
      Check_Status : constant Kernel_Error := Check_Valid (Tap);
      Now          : Interfaces.Unsigned_64;
   begin
      if Check_Status /= Ok then
         return Check_Status;
      end if;

      -- Tap-Level Rate-Limiting (защита от DoS на границе мандата Tap)
      Now := Current_Tick;
      if Tap.Object.Min_Interval_Ticks > 0 then
         if Tap.Object.Last_Signal_Tick /= 0 then
            if Now - Tap.Object.Last_Signal_Tick < Tap.Object.Min_Interval_Ticks then
               return Would_Block;
            end if;
         end if;
         Tap.Object.Last_Signal_Tick := Now;
      end if;

      Upgrade (Tap.Object.Target, Target, Target_Alive);
      if not Target_Alive then
         return Revoked;
      end if;
      --  Знак и вес зафиксированы в Tap при подключении — вызывающий не
      --  может подменить их на лету.
      Kind :=
        (if Tap.Object.Is_Positive
         then Signal_Kind'(Tag => Positive_Signal,
                           Positive_N => Tap.Object.N)
         else Signal_Kind'(Tag => Negative_Signal,
                           Negative_N => Tap.Object.N));
      return Synapse_Apply_Delta (Target.all, Signal_Delta (Kind));
   end Synapse_Signal;

   procedure Apply_Decay_If_Due (Syn : in out Synapse) is
      Last, Now, Elapsed_Ticks : Interfaces.Unsigned_64;
      Leak                     : Interfaces.Integer_64;
      Cur, Pulled               : Interfaces.Integer_32;
   begin
      if not Syn.Decay.Present then
         return;
      end if;
      Last := Syn.Decay.Value.Last_Touch;
      Now  := Current_Tick;
      Elapsed_Ticks := Saturating_Sub_U64 (Now, Last);
      if Elapsed_Ticks = 0 then
         return;
      end if;
      Leak := Saturating_Mul_I64
        (Interfaces.Integer_64 (Elapsed_Ticks),
         Interfaces.Integer_64 (Syn.Decay.Value.Per_Tick));

      --  Утечка тянет заряд к 0 с обеих сторон (знаковый Charge) — не
      --  даёт старому позитиву и новому негативу неожиданно "сложиться"
      --  спустя произвольно долгое время без сигналов.
      Cur := Syn.Charge;
      if Cur > 0 then
         Pulled := Interfaces.Integer_32'Max
           (Cur - Interfaces.Integer_32
              (Interfaces.Integer_64'Min
                 (Interfaces.Integer_64'Max (Leak, 0),
                  Interfaces.Integer_64 (Interfaces.Integer_32'Last))), 0);
      elsif Cur < 0 then
         Pulled := Interfaces.Integer_32'Min
           (Cur + Interfaces.Integer_32
              (Interfaces.Integer_64'Min
                 (Interfaces.Integer_64'Max (Leak, 0),
                  Interfaces.Integer_64 (Interfaces.Integer_32'Last))), 0);
      else
         Pulled := 0;
      end if;
      Syn.Charge := Pulled;
      Syn.Decay.Value.Last_Touch := Now;
   end Apply_Decay_If_Due;

end Aura.Synapse;
