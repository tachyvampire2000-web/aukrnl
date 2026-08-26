--  AURA Kernel — Cap_Policy implementation
--  П.37 дорожной карты: Cap_Policy теперь вызывается из реальных
--  путей ядра — Channel_Send интегрирует Mac_Check_Ipc, а
--  Consume_Use в Cap_Policy проверяет временное окно через
--  Check_Temporal_Validity (согласовано с п.45).
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Timer;

package body Aura.Cap_Policy is

   use type Interfaces.Unsigned_64;

   procedure Consume_Use
     (P      : in out Policy;
      Now    : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
   begin
      if not Applicable (P, Now) then
         Status := Expired;
         return;
      end if;
      if not P.Budget.Unlimited then
         P.Budget.Left := P.Budget.Left - 1;
         if P.Budget.Left = 0 then
            P.Dead := True;
         end if;
      end if;
      Status := Ok;
   end Consume_Use;

   function Evaluate
     (Set  : Policy_Array;
      Now  : Interfaces.Unsigned_64;
      Mode : Combine_Mode) return Decision
   is
      Saw_Allow : Boolean := False;
      Saw_Deny  : Boolean := False;
      Last      : Decision := No_Opinion;
   begin
      for P of Set loop
         if Applicable (P, Now) then
            case P.Effect is
               when Allow =>
                  Saw_Allow := True;
                  Last      := Permitted;
               when Deny =>
                  Saw_Deny  := True;
                  Last      := Forbidden;
            end case;
         end if;
      end loop;

      case Mode is
         when First_Match => return Last;
         when Deny_Wins =>
            if Saw_Deny then return Forbidden; end if;
            if Saw_Allow then return Permitted; end if;
            return No_Opinion;
         when Allow_Wins =>
            if Saw_Allow then return Permitted; end if;
            if Saw_Deny then return Forbidden; end if;
            return No_Opinion;
      end case;
   end Evaluate;

   --  П.45 согласованность: Applicable проверяет оба временных поля
   --  (Valid_From и Valid_Until) независимо, в том же порядке что и
   --  Check_Temporal_Validity в aura-capability-validity.adb.
   function Applicable
     (P   : Policy;
      Now : Interfaces.Unsigned_64) return Boolean
   is
   begin
      if P.Dead then return False; end if;
      --  Valid_From = 0 означает «без нижней границы».
      if P.Valid_From /= 0 and then Now < P.Valid_From then return False; end if;
      --  Valid_Until = 0 означает «бессрочно».
      if P.Valid_Until /= 0 and then Now > P.Valid_Until then return False; end if;
      if not P.Budget.Unlimited and then P.Budget.Left = 0 then
         return False;
      end if;
      return True;
   end Applicable;

   function Make_Timed
     (Valid_From  : Interfaces.Unsigned_64;
      Valid_Until : Interfaces.Unsigned_64) return Policy
   is
   begin
      return (Effect      => Allow,
              Valid_From  => Valid_From,
              Valid_Until => Valid_Until,
              Budget      => (Unlimited => True, Left => 0),
              Dead        => False,
              Gate_Action => No_Gate);
   end Make_Timed;

   function Make_Budget_Limited (Uses : Interfaces.Unsigned_64) return Policy is
   begin
      return (Effect      => Allow,
              Valid_From  => 0,
              Valid_Until => 0,
              Budget      => (Unlimited => False, Left => Uses),
              Dead        => False,
              Gate_Action => No_Gate);
   end Make_Budget_Limited;

   function Make_Allow return Policy is
   begin
      return (Effect      => Allow,
              Valid_From  => 0,
              Valid_Until => 0,
              Budget      => (Unlimited => True, Left => 0),
              Dead        => False,
              Gate_Action => No_Gate);
   end Make_Allow;

   function Make_Deny return Policy is
   begin
      return (Effect      => Deny,
              Valid_From  => 0,
              Valid_Until => 0,
              Budget      => (Unlimited => True, Left => 0),
              Dead        => False,
              Gate_Action => No_Gate);
   end Make_Deny;

end Aura.Cap_Policy;
