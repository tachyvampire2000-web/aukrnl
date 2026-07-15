--  AURA Kernel — Capability Validity implementation
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Timer;

package body Aura.Capability.Validity is

   function Current_Tick return Interfaces.Unsigned_64 is
   begin
      return Aura.Timer.Current_Tick;
   end Current_Tick;

   function Check_Right (Self : Instance; Required : Mask) return Kernel_Error is
   begin
      if not Contains (Self.Node.Rights_Mask, Required) then
         return Bad_Rights;
      end if;
      return Ok;
   end Check_Right;

   procedure Process_Create
     (Untyped                   : Instance;
      Offset                    : Interfaces.Unsigned_64;
      Initial_Cspace_Slot_Bits  : Interfaces.Unsigned_32;
      Result                    : out Process_Context_Ref;
      Status                    : out Kernel_Error) is
   begin
      Result := null;
      Status := Not_Supported;
   end Process_Create;

   procedure Check_Valid_Fast
     (Self  : in out Instance;
      Valid : out Boolean)
   is
      Epoch  : constant Interfaces.Unsigned_32 :=
        Epoch_Of (Self.Object.all);
      Cached : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Self.Prepared / 2 ** 32);
   begin
      if Self.Node.Valid_Until /= 0 then
         Valid := Check_Valid (Self) = Ok;
         return;
      end if;

      if Cached = Epoch then
         Valid := True;
         return;
      end if;

      if Check_Valid (Self) = Ok then
         Self.Prepared := Interfaces.Unsigned_64 (Epoch) * 2 ** 32;
         Valid := True;
      else
         Valid := False;
      end if;
   end Check_Valid_Fast;

end Aura.Capability.Validity;
