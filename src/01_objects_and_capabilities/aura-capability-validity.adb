--  AURA Kernel — Capability validity implementation
--  Пп.25,26,45 дорожной карты.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Timer;
with Aura.Vspace;

package body Aura.Capability.Validity is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Aura.Cap_Node.Cap_Node_Access;

   function Current_Tick return Interfaces.Unsigned_64 is
     (Aura.Timer.Current_Tick);

   procedure Check_Valid_Fast
     (Self  : in out Instance;
      Valid : out Boolean)
   is
      Now       : constant Interfaces.Unsigned_64 := Current_Tick;
      Has_Window : constant Boolean :=
        Self.Node /= null
        and then (Self.Node.Valid_From /= 0
                  or else Self.Node.Valid_Until /= 0);
   begin
      Valid := False;

      --  Временные мандаты никогда не используют epoch-cache:
      --  оба края окна проверяются на каждом вызове (п.45).
      if Has_Window then
         if Self.Node.Valid_From /= 0
           and then Now < Self.Node.Valid_From
         then
            return;
         end if;
         if Self.Node.Valid_Until /= 0
           and then Now >= Self.Node.Valid_Until
         then
            return;
         end if;
         Valid := Check_Valid (Self) = Ok;
         return;
      end if;

      if Self.Node = null or else Self.Object = null then
         return;
      end if;

      --  Fast path: high 32 bits contain the object epoch for which the
      --  capability was last accepted.  A zero cache means cold start.
      declare
         Obj_Epoch : constant Interfaces.Unsigned_32 :=
           Epoch_Of (Self.Object.all);
         Cached : constant Interfaces.Unsigned_32 :=
           Interfaces.Unsigned_32 (Self.Prepared / 2**32);
      begin
         if Cached = Obj_Epoch
           and then Self.Node.Creation_Epoch = Self.Node.Cap_Epoch
           and then Self.Node.Obj_Creation_Epoch = Obj_Epoch
         then
            Valid := True;
            return;
         end if;

         if Check_Valid (Self) = Ok then
            Self.Prepared := Interfaces.Unsigned_64 (Obj_Epoch) * 2**32;
            Valid := True;
         end if;
      end;
   end Check_Valid_Fast;

   function Check_Right
     (Self : Instance; Required : Mask) return Kernel_Error
   is
   begin
      if Check_Valid (Self) /= Ok then
         return Check_Valid (Self);
      end if;
      if not Contains (Self.Rights, Required) then
         return Bad_Rights;
      end if;
      return Ok;
   end Check_Right;

   procedure Process_Create
     (Untyped                   : Instance;
      Offset                    : Interfaces.Unsigned_64;
      Initial_Cspace_Slot_Bits  : Interfaces.Unsigned_32;
      Result                    : out Process_Context_Ref;
      Status                    : out Kernel_Error)
   is
      Vs : Aura.Vspace.V_Space_Ref;
   begin
      pragma Unreferenced (Offset, Initial_Cspace_Slot_Bits);
      Result := null;

      if Check_Right (Untyped, Manage) /= Ok then
         Status := Perm_Denied;
         return;
      end if;

      Aura.Vspace.Vspace_Create (Vs, Status);
      if Status /= Ok then
         return;
      end if;

      Result := new Aura.Vspace.Process_Context'(Vspace => Vs);
      Status := Ok;
   exception
      when others =>
         if Vs /= null then
            Aura.Vspace.Vspace_Destroy (Vs);
         end if;
         Result := null;
         Status := Out_Of_Memory;
   end Process_Create;

end Aura.Capability.Validity;