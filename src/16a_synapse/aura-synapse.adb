--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package body Aura.Synapse is

   use type Interfaces.Unsigned_64;

   function Synapse_Fire (Syn : in out Synapse) return Kernel_Error is (Ok);
   function Check_Valid (Tap : Synapse_Tap_Write_Ref) return Kernel_Error is (Ok);
   procedure Upgrade (W : Synapse_Weak_Ref; R : out Synapse_Ref; A : out Boolean) is begin R := null; A := False; end;
   function Current_Tick return Interfaces.Unsigned_64 is (0);
   function Saturating_Sub_U64 (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64 is (A - B);

   procedure Apply_Decay_If_Due (Syn : in out Synapse);

   function Synapse_Apply_Delta
     (Syn : in out Synapse; Value_Delta : Interfaces.Integer_32) return Kernel_Error
   is
      New_Charge : Interfaces.Integer_32;
   begin
      Apply_Decay_If_Due (Syn);
      New_Charge := Syn.Charge + Value_Delta;
      Syn.Charge := New_Charge;

      if New_Charge >= Syn.Threshold_Hi then
         case Syn.Reset_Mode_Field is
            when To_Zero             => Syn.Charge := 0;
            when Subtract_Threshold  =>
               Syn.Charge := Syn.Charge - Syn.Threshold_Hi;
         end case;
         return Synapse_Fire (Syn);
      end if;

      if Syn.Threshold_Lo.Present then
         if New_Charge <= Syn.Threshold_Lo.Value then
            case Syn.Reset_Mode_Field is
               when To_Zero             => Syn.Charge := 0;
               when Subtract_Threshold  =>
                  Syn.Charge := Syn.Charge - Syn.Threshold_Lo.Value;
            end case;
            return Synapse_Fire (Syn);
         end if;
      end if;

      return Ok;
   end Synapse_Apply_Delta;

   function Synapse_Signal (Tap : Synapse_Tap_Write_Ref) return Kernel_Error
   is
      Target_Alive : Boolean;
      Target       : Synapse_Ref;
      Kind         : Signal_Kind;
      Check_Status : constant Kernel_Error := Check_Valid (Tap);
   begin
      if Check_Status /= Ok then
         return Check_Status;
      end if;
      Upgrade (null, Target, Target_Alive);
      if not Target_Alive then
         return Revoked;
      end if;
      Kind := (Tag => Positive_Signal, Positive_N => 0);
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
