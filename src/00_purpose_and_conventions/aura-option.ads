--  AURA Kernel — aura-option.ads
--  SPDX-License-Identifier: GPL-2.0-only


generic
   type Element_Type is private;
package Aura.Option is

   pragma Pure;

   type Instance (Present : Boolean := False) is record
      case Present is
         when True  => Value : Element_Type;
         when False => null;
      end case;
   end record;

end Aura.Option;
