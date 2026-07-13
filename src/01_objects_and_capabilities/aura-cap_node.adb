--  AURA Kernel — Capability Node allocator implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Cap_Node is

   procedure Alloc
     (Obj_Epoch : Interfaces.Unsigned_32;
      Result    : out Cap_Node_Access;
      Status    : out Kernel_Error)
   is
   begin
      Result := new Cap_Node_Inner'(
         Cap_Epoch          => 1,
         Creation_Epoch      => 1,
         Obj_Creation_Epoch  => Obj_Epoch,
         Depth               => 0,
         Badge               => 0,
         Rights_Mask         => 0,
         Revoke_In_Progress  => False,
         Cap_Token           => 12345,
         Parent              => null,
         First_Child          => null,
         Next_Sibling         => null,
         Prev_Sibling         => null,
         Valid_From          => 0,
         Valid_Until         => 0,
         Rights              => 0,
         Revoke_Notify        => null
      );
      Status := Ok;
   exception
      when others =>
         Result := null;
         Status := Out_Of_Memory;
   end Alloc;

end Aura.Cap_Node;
