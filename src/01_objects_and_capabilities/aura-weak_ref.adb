--  AURA Kernel — Capability Weak Reference implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;

package body Aura.Weak_Ref is

   use type Interfaces.Unsigned_32;

   function Downgrade (Strong : Element_Access) return Instance is
   begin
      return Result : Instance :=
        (Target         => Strong,
         Expected_Epoch => (if Strong = null then 0 else Get_Epoch (Strong.all)));
   end Downgrade;

   procedure Upgrade
     (Self  : Instance;
      Value : out Element_Access;
      Alive : out Boolean) is
   begin
      if Self.Target /= null
        and then Get_Epoch (Self.Target.all) = Self.Expected_Epoch
      then
         Value := Self.Target;
         Alive := True;
      else
         Value := null;
         Alive := False;
      end if;
   end Upgrade;

end Aura.Weak_Ref;
