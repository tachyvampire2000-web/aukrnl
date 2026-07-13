--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Interfaces;

package Aura.Synapse is

   pragma SPARK_Mode (On);

   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;

   type Notification_Weak_Ref is access all Integer; -- Placeholder
   type Synapse;
   type Synapse_Weak_Ref is access all Synapse;
   type Sealed_Call is access all Integer; -- Placeholder
   type Integer_32_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Integer_32;
         when False => null;
      end case;
   end record;
   type Synapse_Tap_Write_Ref is access all Integer; -- Placeholder
   type Synapse_Ref is access all Synapse;

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
     (Signal_Notification_Action, Feed_Synapse_Action, Execute_Sealed_Action);

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
              Sealed : Sealed_Call;
        end case;
     end record;

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
   end record
     with Volatile;

   --  Точка подключения источника к Synapse. Вес и знак фиксируются
   --  здесь, при подключении — НЕ параметр каждого отдельного вызова
   --  Signal. Иначе держатель одного мандата на запись мог бы задавать
   --  произвольный вес на лету и в одиночку продавливать исход, что
   --  обесценивает смысл ограничения через мандаты (тот же принцип, что
   --  раздельные Read/Write вместо одного Any_Rights).
   type Synapse_Tap is limited record
      Header       : Object_Header;
      Target       : Synapse_Weak_Ref;
      Is_Positive  : Boolean;
      N            : Interfaces.Unsigned_32;
   end record
     with Volatile;


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
