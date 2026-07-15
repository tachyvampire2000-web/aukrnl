--  AURA Kernel — aura-synapse.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Aura.Notification;
with Aura.Cap_Policy;
with Aura.Thread;
with Ada.Containers.Bounded_Vectors;
with Interfaces;
with System;

package Aura.Synapse is

   pragma SPARK_Mode (Off);

   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;

   --  Глубина каскада Feed_Synapse: глубже — Cascade_Too_Deep
   --  (T108/T94/T95, §16a порта).
   Synapse_Max_Fire_Depth : constant := 8;

   type Notification_Weak_Ref is record
      Target         : Aura.Notification.Notification_Ref;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   type Synapse;
   type Synapse_Ref is access all Synapse;

   type Synapse_Weak_Ref is record
      Target         : Synapse_Ref;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   Sealed_Call_Max_Caps : constant := 8;

   type Erased_Cap is record
      Cap_Token : Interfaces.Unsigned_64 := 0;
      Valid     : Boolean := True;
   end record;

   package Sealed_Cap_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Erased_Cap);

   type Sealed_Op_Kind is (Object_Destroy_Op, Watchdog_Policy_Override_Op);

   type Sealed_Op (Kind : Sealed_Op_Kind := Object_Destroy_Op) is record
      case Kind is
         when Object_Destroy_Op =>
            Target_Obj_Addr : System.Address := System.Null_Address;
         when Watchdog_Policy_Override_Op =>
            Override_Active : Boolean := False;
      end case;
   end record;

   type Sealed_Call is record
      Caps : Sealed_Cap_Vectors.Vector (Sealed_Call_Max_Caps);
      Op   : Sealed_Op;
   end record;

   type Sealed_Call_Access is access all Sealed_Call;

   function Erased_Cap_Check_Valid (Cap : Erased_Cap) return Kernel_Error;
   function Sealed_Call_Execute (Call : Sealed_Call) return Kernel_Error;

   type Integer_32_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Integer_32;
         when False => null;
      end case;
   end record;

   type Signal_Kind_Tag is (Positive_Signal, Negative_Signal);

   type Signal_Kind (Tag : Signal_Kind_Tag := Positive_Signal) is record
      case Tag is
         when Positive_Signal => Positive_N : Interfaces.Unsigned_32;
                                  --  эффект на Charge: +(1 + N)
         when Negative_Signal => Negative_N : Interfaces.Unsigned_32;
                                  --  эффект на Charge: -(N) — БЕЗ
                                  --  базовой единицы
      end case;
   end record;

   function Signal_Delta (Kind : Signal_Kind) return Interfaces.Integer_32 is
     (case Kind.Tag is
        when Positive_Signal => 1 + Interfaces.Integer_32 (Kind.Positive_N),
        when Negative_Signal => -Interfaces.Integer_32 (Kind.Negative_N));
   type Reset_Mode is
     (To_Zero,             --  Классический integrate-and-fire: заряд
                            --  обнуляется при срабатывании.
      Subtract_Threshold);  --  Leaky: вычитается ровно порог, избыток
                             --  сверх него сохраняется — может вызвать
                             --  немедленный повторный fire, если избыток
                             --  был велик.

   --  Утечка заряда со временем. Пересчитывается лениво при каждом
   --  касании (Signal/Read), а не глобальным тикером — не нужен ещё один
   --  *_Tick в духе Watchdog_Tick только ради decay.
   type Decay_Spec is record
      Per_Tick   : Interfaces.Integer_32;  -- на сколько Charge стремится
                                             -- к 0 за один tick
      Last_Touch : aliased Interfaces.Unsigned_64;
   end record;

   type Decay_Spec_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Decay_Spec;
         when False => null;
      end case;
   end record;

   --  Закрытый набор действий при срабатывании. НЕ произвольный колбэк:
   --  возможность — это обладание мандатом, не код, который можно
   --  передать (см. отношение к Rust-версии в начале документа / принцип
   --  capability вместо ambient authority, тот же аргумент, что уже
   --  применяется к отказу от произвольного кода в §6.1 порта про
   --  Rcu_Callback). Идентичная мотивация: там, где Rust мог бы
   --  использовать замыкание, документ сознательно выбирает закрытое
   --  перечисление — здесь это решение принято уже в Rust-версии, порт
   --  просто следует тому же принципу без необходимости изобретать его
   --  заново.
   type Pending_Action_Kind is
     (Signal_Notification_Action, Feed_Synapse_Action, Execute_Sealed_Action,
      Gate_Policy_Action, Trace_Event_Action, Reject_If_Saturated_Action);

   type Pending_Action (Kind : Pending_Action_Kind := Signal_Notification_Action)
     is record
        case Kind is
           when Signal_Notification_Action =>
              --  Вырожденный случай = обычный Notification/Attr_Watch.
              Notif_Target : Notification_Weak_Ref;
              Notif_Bit    : Interfaces.Unsigned_64;
           when Feed_Synapse_Action =>
              --  Каскад: срабатывание одного Synapse кормит другой.
              --  Мандат на запись уже должен существовать на момент
              --  конфигурации Pending_Action — не добывается на лету при
              --  срабатывании.
              Synapse_Target : Synapse_Weak_Ref;
              Feed_Kind      : Signal_Kind;
           when Execute_Sealed_Action =>
              --  Опасное/составное действие — заранее собранный набор
              --  мандатов и закрытая операция над ними. См. §16a.4 порта.
              Sealed : Sealed_Call_Access;
           when Gate_Policy_Action =>
              --  Сигнал управляет мандатом: активация/деактивация/
              --  отзыв политики при срабатывании. Различает направление:
              --  верхний порог (накопление) и нижний (-спайк/снижение).
              Policy_Target : access Aura.Cap_Policy.Policy;
              Gate_On_Hi    : Aura.Cap_Policy.Gate_Action;
              Gate_On_Lo    : Aura.Cap_Policy.Gate_Action;
           when Trace_Event_Action =>
              Trace_Id : Interfaces.Unsigned_64;
           when Reject_If_Saturated_Action =>
              null;
        end case;
     end record;

   Last_Fired_Trace_Id : aliased Interfaces.Unsigned_64 := 0;

   type Synapse is limited record
      Header        : Object_Header;
      Charge        : aliased Interfaces.Integer_32;
      Threshold_Hi   : Interfaces.Integer_32;
      --  Present = False означает "только позитивный порог" (обычный
      --  multi-sig/подписка).
      Threshold_Lo   : Integer_32_Option;
      Reset_Mode_Field : Reset_Mode;
      Decay          : Decay_Spec_Option;
      Action         : Pending_Action;
      --  Предотвращение переполнения заряда (Charge Saturation)
      Max_Charge_Cap : Interfaces.Integer_32 := 100000;
      Min_Charge_Cap : Interfaces.Integer_32 := -100000;
      --  SDRP (Synapse-driven Adaptive Real-time Priority)
      Sdrp_Thread    : Aura.Thread.Thread_Access := null;
      --  Synapse-Level Rate-Limiting (защита от DoS на уровне синапса)
      Min_Interval_Ticks : Interfaces.Unsigned_64 := 0; -- 0 = без ограничений
      Last_Signal_Tick   : aliased Interfaces.Unsigned_64 := 0;
   end record
     with Volatile;

   --  Точка подключения источника к Synapse. Вес и знак фиксируются
   --  здесь, при подключении — НЕ параметр каждого отдельного вызова
   --  Signal. Иначе держатель одного мандата на запись мог бы задавать
   --  произвольный вес на лету и в одиночку продавливать исход, что
   --  обесценивает смысл ограничения через мандаты (тот же принцип, что
   --  раздельные Read/Write вместо одного Any_Rights).
   type Synapse_Tap is limited record
      Header             : Object_Header;
      Target             : Synapse_Weak_Ref;
      Is_Positive        : Boolean;
      N                  : Interfaces.Unsigned_32;
      --  Tap-Level Rate-Limiting (защита от DoS на границе мандата Tap)
      Min_Interval_Ticks : Interfaces.Unsigned_64 := 0; -- 0 = без ограничений
      Last_Signal_Tick   : aliased Interfaces.Unsigned_64 := 0;
   end record
     with Volatile;

   type Synapse_Tap_Access is access all Synapse_Tap;

   --  Мандат на подачу сигнала через конкретный Tap.
   type Synapse_Tap_Write_Ref is record
      Object : Synapse_Tap_Access;
      Rights : Aura.Rights.Mask := Aura.Rights.Write;
   end record;

   function Check_Valid (Cap : Synapse_Tap_Write_Ref) return Kernel_Error;

   function Downgrade (Strong : Synapse_Ref) return Synapse_Weak_Ref;

   procedure Upgrade
     (Self  : Synapse_Weak_Ref;
      Value : out Synapse_Ref;
      Alive : out Boolean);

   --  Прямая подача дельты (ядерный путь, без Tap-мандата) —
   --  единая точка входа всех сигналов системы: «резкий» сигнал —
   --  вырожденный синапс с Threshold_Hi = 1.
   function Synapse_Apply_Delta
     (Syn         : in out Synapse;
      Value_Delta : Interfaces.Integer_32) return Kernel_Error;


   --  (декларации из продолжения-фрагмента, doc-lines 5793-5898,
   --  после первоначального закрытия Aura.Synapse — тела того же
   --  фрагмента вынесены в .adb — см. MANIFEST §Находки)

   --  Единственный вызов, доступный держателю Synapse_Tap. Знак и N уже
   --  зафиксированы в самом Tap — вызывающий не может их подменить.
   function Synapse_Signal (Tap : Synapse_Tap_Write_Ref) return Kernel_Error;



   function Saturating_Mul_I64
     (A, B : Interfaces.Integer_64) return Interfaces.Integer_64
   is (if B /= 0 and then abs A > Interfaces.Integer_64'Last / abs B
       then (if (A > 0) = (B > 0) then Interfaces.Integer_64'Last
             else Interfaces.Integer_64'First)
       else A * B);

end Aura.Synapse;
