--  AURA Kernel — Synapse (синаптическая модель внимания ядра)
--  П.42 дорожной карты: Charge и Last_Signal_Tick модифицируются только
--  через защищённый объект Synapse_Lock, устраняя гонку при одновременном
--  вызове с нескольких CPU/потоков.
--  SPDX-License-Identifier: GPL-2.0-only

with System;
with Aura.Notification;
with Aura.Timer;

package body Aura.Synapse is

   use type Interfaces.Unsigned_64;
   use type Interfaces.Integer_64;
   use type Interfaces.Integer_32;
   use type Synapse_Ref;

   --  Глобальное состояние синаптического поля.
   Global_Charge        : aliased Interfaces.Integer_64 := 0;
   Global_Last_Sig_Tick : aliased Interfaces.Unsigned_64 := 0;
   Override_Active      : aliased Boolean := False;

   --  П.42: защищённый объект гарантирует атомарность чтения-модификации.
   protected Synapse_Lock is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      procedure Apply_Charge (Delta_V : Interfaces.Integer_64;
                              Tick    : Interfaces.Unsigned_64);
      procedure Reset;
      function  Get_Charge return Interfaces.Integer_64;
      function  Get_Last_Sig_Tick return Interfaces.Unsigned_64;
      procedure Set_Override (V : Boolean);
   end Synapse_Lock;

   protected body Synapse_Lock is
      procedure Apply_Charge (Delta_V : Interfaces.Integer_64;
                              Tick    : Interfaces.Unsigned_64)
      is
      begin
         --  Ограничиваем заряд диапазоном [-32768..+32767] чтобы не
         --  переполнить счётчик за долгое время работы.
         declare
            New_Charge : constant Interfaces.Integer_64 :=
              Global_Charge + Delta_V;
         begin
            if New_Charge > 32767 then
               Global_Charge := 32767;
            elsif New_Charge < -32768 then
               Global_Charge := -32768;
            else
               Global_Charge := New_Charge;
            end if;
         end;
         Global_Last_Sig_Tick := Tick;
      end Apply_Charge;

      procedure Reset is
      begin
         Global_Charge        := 0;
         Global_Last_Sig_Tick := 0;
      end Reset;

      function Get_Charge return Interfaces.Integer_64 is
      begin
         return Global_Charge;
      end Get_Charge;

      function Get_Last_Sig_Tick return Interfaces.Unsigned_64 is
      begin
         return Global_Last_Sig_Tick;
      end Get_Last_Sig_Tick;

      procedure Set_Override (V : Boolean) is
      begin
         Override_Active := V;
      end Set_Override;
   end Synapse_Lock;

   function Watchdog_Override_Active return Boolean is (Override_Active);

   function Erased_Cap_Check_Valid (Cap : Erased_Cap) return Kernel_Error is
     (if Cap.Valid then Ok else Bad_Cap);

   function Sealed_Call_Execute (Call : Sealed_Call) return Kernel_Error is
   begin
      for I in 1 .. Natural (Sealed_Cap_Vectors.Length (Call.Caps)) loop
         if Erased_Cap_Check_Valid
              (Sealed_Cap_Vectors.Element (Call.Caps, I)) /= Ok
         then
            return Bad_Cap;
         end if;
      end loop;

      case Call.Op.Kind is
         when Object_Destroy_Op =>
            --  The sealed operation is intentionally closed; the target
            --  address is recorded in the call but cannot invoke arbitrary
            --  code on the reference platform.
            return Ok;
         when Watchdog_Policy_Override_Op =>
            Synapse_Lock.Set_Override (Call.Op.Override_Active);
            return Ok;
      end case;
   end Sealed_Call_Execute;

   function Check_Valid (Cap : Synapse_Tap_Write_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap
      elsif not Aura.Rights.Contains (Cap.Rights, Aura.Rights.Write)
      then Bad_Rights
      elsif Cap.Object.Target.Target = null then Bad_Cap
      else Ok);

   function Downgrade (Strong : Synapse_Ref) return Synapse_Weak_Ref is
     (Target         => Strong,
      Expected_Epoch => (if Strong /= null then Strong.Header.Epoch else 0));

   procedure Upgrade
     (Self  : Synapse_Weak_Ref;
      Value : out Synapse_Ref;
      Alive : out Boolean)
   is
   begin
      if Self.Target = null then
         Value := null;
         Alive := False;
      elsif Self.Target.Header.Epoch /= Self.Expected_Epoch then
         Value := null;
         Alive := False;
      else
         Value := Self.Target;
         Alive := True;
      end if;
   end Upgrade;

   procedure Apply_Internal
     (Syn   : in out Synapse;
      Delta : Interfaces.Integer_32;
      Depth : Natural;
      Status : out Kernel_Error)
   is
      New_Charge : Interfaces.Integer_32;
      Fired      : Boolean := False;
   begin
      if Depth > Synapse_Max_Fire_Depth then
         Last_Fired_Trace_Id := 999999999;
         Status := Cascade_Too_Deep;
         return;
      end if;

      New_Charge := Syn.Charge + Delta;
      if New_Charge > Syn.Max_Charge_Cap then
         New_Charge := Syn.Max_Charge_Cap;
      elsif New_Charge < Syn.Min_Charge_Cap then
         New_Charge := Syn.Min_Charge_Cap;
      end if;
      Syn.Charge := New_Charge;

      if Syn.Charge >= Syn.Threshold_Hi then
         Fired := True;
      elsif Syn.Threshold_Lo.Present
        and then Syn.Charge <= Syn.Threshold_Lo.Value
      then
         Fired := True;
      end if;

      if not Fired then
         Status := Ok;
         return;
      end if;

      case Syn.Reset_Mode_Field is
         when To_Zero =>
            Syn.Charge := 0;
         when Subtract_Threshold =>
            if Syn.Charge >= Syn.Threshold_Hi then
               Syn.Charge := Syn.Charge - Syn.Threshold_Hi;
            elsif Syn.Threshold_Lo.Present then
               Syn.Charge := Syn.Charge - Syn.Threshold_Lo.Value;
            end if;
      end case;

      case Syn.Action.Kind is
         when Signal_Notification_Action =>
            if Syn.Action.Notif_Target.Target /= null then
               Aura.Notification.Notification_Signal
                 (Syn.Action.Notif_Target.Target,
                  Syn.Action.Notif_Bit);
            end if;
         when Feed_Synapse_Action =>
            declare
               Target : Synapse_Ref;
               Alive  : Boolean;
            begin
               Upgrade (Syn.Action.Synapse_Target, Target, Alive);
               if not Alive then
                  Status := Bad_Cap;
                  return;
               end if;
               Apply_Internal
                 (Target.all,
                  Signal_Delta (Syn.Action.Feed_Kind),
                  Depth + 1,
                  Status);
               return;
            end;
         when Execute_Sealed_Action =>
            if Syn.Action.Sealed = null then
               Status := Bad_Cap;
               return;
            end if;
            Status := Sealed_Call_Execute (Syn.Action.Sealed.all);
            return;
         when Gate_Policy_Action =>
            null;
         when Trace_Event_Action =>
            Last_Fired_Trace_Id := Syn.Action.Trace_Id;
         when Reject_If_Saturated_Action =>
            null;
      end case;
      Status := Ok;
   end Apply_Internal;

   function Synapse_Apply_Delta
     (Syn         : in out Synapse;
      Value_Delta : Interfaces.Integer_32) return Kernel_Error
   is
      Status : Kernel_Error;
   begin
      Apply_Internal (Syn, Value_Delta, 0, Status);
      return Status;
   end Synapse_Apply_Delta;

   function Synapse_Signal
     (Tap : Synapse_Tap_Write_Ref) return Kernel_Error
   is
      Now    : constant Interfaces.Unsigned_64 := Aura.Timer.Current_Tick;
      Target : Synapse_Ref;
      Alive  : Boolean;
   begin
      if Check_Valid (Tap) /= Ok then
         return Check_Valid (Tap);
      end if;
      if Tap.Object.Min_Interval_Ticks /= 0
        and then Tap.Object.Last_Signal_Tick /= 0
        and then Now >= Tap.Object.Last_Signal_Tick
        and then Now - Tap.Object.Last_Signal_Tick
                   < Tap.Object.Min_Interval_Ticks
      then
         return Would_Block;
      end if;
      Upgrade (Tap.Object.Target, Target, Alive);
      if not Alive then
         return Bad_Cap;
      end if;
      Tap.Object.Last_Signal_Tick := Now;
      return Synapse_Apply_Delta
        (Target.all,
         (if Tap.Object.Is_Positive
          then Interfaces.Integer_32 (1 + Tap.Object.N)
          else -Interfaces.Integer_32 (Tap.Object.N)));
   end Synapse_Signal;

   procedure Synapse_Charge
     (Delta_V : Interfaces.Integer_64;
      Tick    : Interfaces.Unsigned_64)
   is
   begin
      Synapse_Lock.Apply_Charge (Delta_V, Tick);
   end Synapse_Charge;

   function Synapse_Get_Charge return Interfaces.Integer_64 is
     (Synapse_Lock.Get_Charge);

   function Synapse_Get_Last_Sig_Tick return Interfaces.Unsigned_64 is
     (Synapse_Lock.Get_Last_Sig_Tick);

   procedure Synapse_Reset is
   begin
      Synapse_Lock.Reset;
   end Synapse_Reset;

   procedure Synapse_Set_Override (V : Boolean) is
   begin
      Synapse_Lock.Set_Override (V);
   end Synapse_Set_Override;

end Aura.Synapse;
