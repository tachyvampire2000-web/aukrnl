package body Aura.Cap_Policy is

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
                  Saw_Deny := True;
                  Last     := Forbidden;
            end case;
         end if;
      end loop;

      case Mode is
         when Last_Wins =>
            return Last;
         when Deny_Wins =>
            return (if Saw_Deny then Forbidden
                    elsif Saw_Allow then Permitted
                    else No_Opinion);
         when Allow_Wins =>
            return (if Saw_Allow then Permitted
                    elsif Saw_Deny then Forbidden
                    else No_Opinion);
      end case;
   end Evaluate;

   procedure Apply_Gate (P : in out Policy; Act : Gate_Action) is
   begin
      case Act is
         when No_Op              => null;
         when Activate           => P.Active := True;
         when Deactivate         => P.Active := False;
         when Revoke_Permanently => P.Dead := True;
      end case;
   end Apply_Gate;

end Aura.Cap_Policy;
