--  AURA Kernel — aura-untyped.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Ada.Containers.Bounded_Vectors;
with Interfaces;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

use type Interfaces.Unsigned_64;
package Aura.Untyped is

   pragma SPARK_Mode (Off);

   Untyped_Bitmap_Words_Max : constant := 1024;  --  фиксированная ёмкость
                                                    --  для Bounded-массива,
                                                    --  заменяющего Box<[AtomicU64]>

   package Bitmap_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Interfaces.Unsigned_64);

   type Untyped_Region is limited record
      Header            : Object_Header;
      Phys_Addr_Base    : Interfaces.Unsigned_64;
      Size_Bits         : Interfaces.Unsigned_32;
      Is_Device         : Boolean;
      Allocated_Bitmap  : Bitmap_Vectors.Vector (Untyped_Bitmap_Words_Max);
   end record
     with Volatile;

   type Untyped_Region_Access is access all Untyped_Region;
   type Untyped_Manage_Ref is record
      Object : Untyped_Region_Access;
   end record;

   Alloc_Granule_Bytes : constant := 64;

   procedure Try_Reserve_Range
     (Region : in out Untyped_Region;
      Offset : Interfaces.Unsigned_64;
      Total  : Interfaces.Unsigned_64;
      Status : out Kernel_Error);

   procedure Untyped_Retype
     (Cap      : Untyped_Manage_Ref;
      Offset   : Interfaces.Unsigned_64;
      Count    : Interfaces.Unsigned_64;
      Obj_Size : Interfaces.Unsigned_64;
      Status   : out Kernel_Error);

end Aura.Untyped;
