--  AURA Kernel — Package_Fs Subsystem implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Package_Fs is

   procedure Package_Mount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;
      Status : out Kernel_Error)
   is
      use type Interfaces.Unsigned_64;
      Overlaps : Boolean := False;
      Has_Bits : Boolean := False;
   begin
      if Image = null then
         Status := Invalid_Argument;
         return;
      end if;

      if Union.Image_Count = Package_Union_Max then
         Status := Capacity_Exceeded;
         return;
      end if;

      -- Check if already exists/mounted
      for I in 1 .. Union.Image_Count loop
         if Union.Images (I) = Package_Image_Ref (Image) then
            Status := Already_Exists;
            return;
         end if;
      end loop;

      -- Check for Bloom filter conflict (path conflict)
      for W in 0 .. Path_Bloom_Filter_Words - 1 loop
         if Image.Bloom (W) /= 0 then
            Has_Bits := True;
            if (Union.Combined_Bloom.Combined (W) and Image.Bloom (W)) /= 0 then
               Overlaps := True;
            end if;
         end if;
      end loop;

      if Has_Bits and Overlaps then
         Status := Path_Conflict;
         return;
      end if;

      -- Add the image to the union
      Union.Image_Count := Union.Image_Count + 1;
      Union.Images (Union.Image_Count) := Package_Image_Ref (Image);

      -- Update Combined_Bloom by OR-ing the new Bloom filter
      for W in 0 .. Path_Bloom_Filter_Words - 1 loop
         Union.Combined_Bloom.Combined (W) := Union.Combined_Bloom.Combined (W) or Image.Bloom (W);
      end loop;

      Status := Ok;
   end Package_Mount;

   procedure Package_Unmount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;
      Status : out Kernel_Error)
   is
      use type Interfaces.Unsigned_64;
      Found_Idx : Natural := 0;
   begin
      if Image = null then
         Status := Invalid_Argument;
         return;
      end if;

      -- Find image in the Union
      for I in 1 .. Union.Image_Count loop
         if Union.Images (I) = Package_Image_Ref (Image) then
            Found_Idx := I;
            exit;
         end if;
      end loop;

      if Found_Idx = 0 then
         Status := Not_Found;
         return;
      end if;

      -- Shift remaining images
      for I in Found_Idx .. Union.Image_Count - 1 loop
         Union.Images (I) := Union.Images (I + 1);
      end loop;
      Union.Images (Union.Image_Count) := null;
      Union.Image_Count := Union.Image_Count - 1;

      -- Recompute Combined_Bloom from scratch based on remaining images
      for W in 0 .. Path_Bloom_Filter_Words - 1 loop
         Union.Combined_Bloom.Combined (W) := 0;
      end loop;

      for I in 1 .. Union.Image_Count loop
         for W in 0 .. Path_Bloom_Filter_Words - 1 loop
            Union.Combined_Bloom.Combined (W) :=
              Union.Combined_Bloom.Combined (W) or Union.Images (I).Bloom (W);
         end loop;
      end loop;

      Status := Ok;
   end Package_Unmount;

end Aura.Package_Fs;
