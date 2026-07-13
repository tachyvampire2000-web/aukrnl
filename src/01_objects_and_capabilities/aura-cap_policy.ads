--  AURA — политика мандатов: позитивные (Allow) и негативные (Deny)
--  мандаты с временным окном, счётчиком использований и
--  активацией/деактивацией/отзывом по сигналу (через Synapse-гейт).
--
--  Комбинации покрываются ортогонально:
--    Effect (Allow/Deny) x окно [Valid_From, Valid_Until)
--      x бюджет использований x Active-флаг x необратимый Dead.
--  «Сначала запретить, потом разрешить» (и наоборот) выражается порядком
--  политик в наборе + режимом свёртки Evaluate (Last_Wins), либо жёстким
--  Deny_Wins/Allow_Wins независимо от порядка.

with Interfaces;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

package Aura.Cap_Policy is

   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   type Effect_Kind is (Allow, Deny);

   --  Итог свёртки набора политик. No_Opinion — ни одна политика не
   --  применима: вызывающий слой решает default-deny/default-allow сам
   --  (ядро по умолчанию трактует как Forbidden).
   type Decision is (Permitted, Forbidden, No_Opinion);

   --  Бюджет использований. Unlimited = True — без счётчика.
   type Use_Budget (Unlimited : Boolean := True) is record
      case Unlimited is
         when False => Left : Interfaces.Unsigned_32;
         when True  => null;
      end case;
   end record;

   type Policy is record
      Effect      : Effect_Kind := Allow;
      --  Окно действия в тиках: [Valid_From, Valid_Until).
      --  Valid_Until = 0 — без ограничения по времени.
      Valid_From  : Interfaces.Unsigned_64 := 0;
      Valid_Until : Interfaces.Unsigned_64 := 0;
      Budget      : Use_Budget;
      --  Обратимое состояние (сигнал может включать и выключать).
      Active      : Boolean := True;
      --  Необратимый отзыв: Dead-политика никогда не применима вновь.
      Dead        : Boolean := False;
   end record;

   --  Политика применима: жива, активна, окно наступило и не истекло,
   --  бюджет не исчерпан.
   function Applicable
     (P : Policy; Now : Interfaces.Unsigned_64) return Boolean
   is (not P.Dead
       and then P.Active
       and then Now >= P.Valid_From
       and then (P.Valid_Until = 0 or else Now < P.Valid_Until)
       and then (P.Budget.Unlimited or else P.Budget.Left > 0));

   --  Списать одно использование. Expired — политика неприменима либо
   --  бюджет уже исчерпан; исчерпание бюджета делает политику Dead
   --  (мандат «дохнет», как и по таймеру — Applicable сам гасит окно).
   procedure Consume_Use
     (P      : in out Policy;
      Now    : Interfaces.Unsigned_64;
      Status : out Kernel_Error);

   type Combine_Mode is
     (Last_Wins,   --  порядок важен: последняя применимая решает
                    --  («сначала запретить, потом разрешить» и наоборот)
      Deny_Wins,   --  любой применимый Deny побеждает
      Allow_Wins); --  любой применимый Allow побеждает

   type Policy_Array is array (Positive range <>) of Policy;

   function Evaluate
     (Set  : Policy_Array;
      Now  : Interfaces.Unsigned_64;
      Mode : Combine_Mode) return Decision;

   --  Действие гейта, применяемое к политике при срабатывании синапса.
   type Gate_Action is
     (No_Op,
      Activate,             --  разрешить/включить по сигналу
      Deactivate,           --  запретить/выключить по сигналу (обратимо)
      Revoke_Permanently);  --  необратимый отзыв по сигналу

   procedure Apply_Gate (P : in out Policy; Act : Gate_Action);

end Aura.Cap_Policy;
