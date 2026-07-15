--  AURA Kernel — aura-cap_object_ref_pkg.adb
--  SPDX-License-Identifier: GPL-2.0-only


package body Aura.Cap_Object_Ref_Pkg is

   overriding procedure Adjust (Self : in out Instance) is
   begin
      --  Placeholder: increment refcount
      null;
   end Adjust;

   overriding procedure Finalize (Self : in out Instance) is
   begin
      --  Placeholder: decrement refcount
      null;
   end Finalize;

end Aura.Cap_Object_Ref_Pkg;
