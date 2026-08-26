--  AURA Kernel — Entropy pool implementation
--  SPDX-License-Identifier: GPL-2.0-only

with System;

package body Aura.Entropy is

   use type Interfaces.Unsigned_64;

   Pool_Value : aliased Interfaces.Unsigned_64 := 16#DEAD_BEEF_CAFE_0042#;
   Pool_Bits  : Natural := 64;

   protected Entropy_Lock is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      procedure Feed (Data : Interfaces.Unsigned_64; Bits : Natural);
      procedure Consume (N       : Natural;
                         Value   : out Interfaces.Unsigned_64;
                         Actual  : out Natural);
      function Level return Natural;
   end Entropy_Lock;

   protected body Entropy_Lock is

      procedure Feed (Data : Interfaces.Unsigned_64; Bits : Natural) is
         Rot : constant Natural := Bits mod 64;
         Shifted : Interfaces.Unsigned_64;
      begin
         Shifted := Interfaces.Rotate_Left (Data, Rot);
         Pool_Value := Pool_Value xor Shifted;
         Pool_Bits  := Natural'Min (Pool_Bits + Bits, 256);
      end Feed;

      procedure Consume
        (N       : Natural;
         Value   : out Interfaces.Unsigned_64;
         Actual  : out Natural)
      is
      begin
         if Pool_Bits = 0 then
            Value  := Pool_Value;
            Actual := 0;
            return;
         end if;
         Actual     := Natural'Min (N, Pool_Bits);
         Value      := Pool_Value;
         Pool_Value := Interfaces.Rotate_Left (Pool_Value, 13)
                         xor 16#6C62_272E_07BB_0142#;
         if Pool_Bits >= Actual then
            Pool_Bits := Pool_Bits - Actual;
         else
            Pool_Bits := 0;
         end if;
      end Consume;

      function Level return Natural is (Pool_Bits);

   end Entropy_Lock;

   procedure Entropy_Feed (Data : Interfaces.Unsigned_64; Bits : Natural) is
   begin
      Entropy_Lock.Feed (Data, Bits);
   end Entropy_Feed;

   procedure Entropy_Consume
     (N           : Natural;
      Value       : out Interfaces.Unsigned_64;
      Actual_Bits : out Natural)
   is
   begin
      Entropy_Lock.Consume (N, Value, Actual_Bits);
   end Entropy_Consume;

   function Entropy_Level return Natural is (Entropy_Lock.Level);

end Aura.Entropy;
