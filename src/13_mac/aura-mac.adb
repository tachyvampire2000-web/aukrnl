--  AURA Kernel — Mandatory Access Control (MAC) implementation
--  SPDX-License-Identifier: GPL-2.0-only


package body Aura.Mac is

   protected body Audit_Channel is
      procedure dummy is begin null; end;
   end Audit_Channel;

   procedure Set_Mandatory_Label
     (Node : in out Aura.Namespace.Namespace_Node; New_Label : Mandatory_Label;
      Status : out Kernel_Error)
   is
   begin
      if Node.Mac_Label_Set then
         Status := Label_Immutable;
      else
         Node.Mac_Level      := New_Label.Level;
         Node.Mac_Categories := New_Label.Categories;
         Node.Mac_Label_Set  := True;
         Status := Ok;
      end if;
   end Set_Mandatory_Label;

   procedure Propagate_Taint (Taint : in out Causal_Taint; Label : Mandatory_Label) is
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_64;
   begin
      Taint.Tainted := True;
      if Label.Level > Taint.Taint_Level then
         Taint.Taint_Level := Label.Level;
      end if;
      Taint.Taint_Categories := Taint.Taint_Categories or Label.Categories;
   end Propagate_Taint;

   function Check_Flow (Taint : Causal_Taint; Target : Mandatory_Label) return Kernel_Error is
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_64;
   begin
      if Taint.Tainted then
         -- Dynamic Bell-LaPadula No-Write-Down:
         -- Cannot write to a target with a lower security level,
         -- or to a target lacking our tainted categories!
         if Taint.Taint_Level > Target.Level
           or else (Taint.Taint_Categories and not Target.Categories) /= 0
         then
            return Write_Down_Violation;
         end if;
      end if;
      return Ok;
   end Check_Flow;

end Aura.Mac;
