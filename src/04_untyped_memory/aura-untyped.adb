--  AURA Kernel — aura-untyped.adb
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Containers;

package body Aura.Untyped is

   use type Interfaces.Unsigned_32;
   use type Ada.Containers.Count_Type;

   procedure Try_Reserve_Range
     (Region : in out Untyped_Region;
      Offset : Interfaces.Unsigned_64;
      Total  : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      First_G : constant Interfaces.Unsigned_64 := Offset / Alloc_Granule_Bytes;
      Count_G : constant Interfaces.Unsigned_64 :=
        (Total + Alloc_Granule_Bytes - 1) / Alloc_Granule_Bytes;

      G           : Interfaces.Unsigned_64;
      W           : Positive;
      B           : Natural;
      Word        : Interfaces.Unsigned_64;
      Mask        : Interfaces.Unsigned_64;

      -- Copy to local non-volatile vector to satisfy Ada RM C.6(12) volatile restrictions
      Bitmap      : Bitmap_Vectors.Vector (Untyped_Bitmap_Words_Max) := Region.Allocated_Bitmap;
   begin
      if Total = 0 then
         Status := Invalid_Argument;
         return;
      end if;

      -- 1. Dry run: Verify all granules in the range are free
      for I in 0 .. Count_G - 1 loop
         G := First_G + I;
         -- 0-based word, converted to 1-based Positive index for Bounded_Vectors
         W := Natural (G / 64) + 1;
         B := Natural (G mod 64);

         -- Word bounds check against bitmap words maximum
         if W > Untyped_Bitmap_Words_Max then
            Status := Out_Of_Memory;
            return;
         end if;

         -- Get word or default to 0 if we haven't allocated it yet
         Word := (if Ada.Containers.Count_Type (W) <= Bitmap_Vectors.Length (Bitmap)
                  then Bitmap_Vectors.Element (Bitmap, W)
                  else 0);

         Mask := Interfaces.Shift_Left (1, B);
         if (Word and Mask) /= 0 then
            Status := Already_Exists; -- Granule already allocated
            return;
         end if;
      end loop;

      -- 2. Commit phase: Set all granules in the range as allocated
      for I in 0 .. Count_G - 1 loop
         G := First_G + I;
         W := Natural (G / 64) + 1;
         B := Natural (G mod 64);

         -- Pad bitmap vector up to index W if necessary
         while Bitmap_Vectors.Length (Bitmap) < Ada.Containers.Count_Type (W) loop
            Bitmap_Vectors.Append (Bitmap, 0);
         end loop;

         Word := Bitmap_Vectors.Element (Bitmap, W);
         Mask := Interfaces.Shift_Left (1, B);
         Word := Word or Mask;

         Bitmap_Vectors.Replace_Element (Bitmap, W, Word);
      end loop;

      -- Write back to the volatile field
      Region.Allocated_Bitmap := Bitmap;

      Status := Ok;
   end Try_Reserve_Range;

   procedure Untyped_Retype
     (Cap      : Untyped_Manage_Ref;
      Offset   : Interfaces.Unsigned_64;
      Count    : Interfaces.Unsigned_64;
      Obj_Size : Interfaces.Unsigned_64;
      Status   : out Kernel_Error)
   is
      Total_Size  : Interfaces.Unsigned_64;
      Overflowed  : Boolean;
      Region_Size : Interfaces.Unsigned_64;
   begin
      if Cap.Object = null then
         Status := Bad_Cap;
         return;
      end if;

      -- checked_mul -> check overflow before multiplication
      Overflowed := Count /= 0
        and then Obj_Size > Interfaces.Unsigned_64'Last / Count;
      if Overflowed then
         Status := Overflow;
         return;
      end if;
      Total_Size := Count * Obj_Size;

      if Cap.Object.Size_Bits >= 64 then
         Region_Size := Interfaces.Unsigned_64'Last;
      else
         Region_Size := Interfaces.Shift_Left (1, Natural (Cap.Object.Size_Bits));
      end if;

      if Offset > Region_Size or else Total_Size > Region_Size - Offset then
         Status := Overflow;
         return;
      end if;

      Try_Reserve_Range (Cap.Object.all, Offset, Total_Size, Status);
   end Untyped_Retype;

end Aura.Untyped;
