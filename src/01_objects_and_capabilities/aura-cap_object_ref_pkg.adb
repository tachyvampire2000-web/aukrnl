--  AURA Kernel — aura-cap_object_ref_pkg.adb
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Cap_Object_Ref_Pkg is

   pragma SPARK_Mode (Off);

   use type System.Address;

   type Ref_Entry is record
      Addr  : System.Address := System.Null_Address;
      Epoch : Interfaces.Unsigned_32 := 0;
      Count : Natural := 0;
   end record;

   Max_Refs : constant := 1024;
   type Ref_Array is array (1 .. Max_Refs) of Ref_Entry;

   protected Tracker is
      procedure Inc (Addr : System.Address; Ep : Interfaces.Unsigned_32);
      procedure Dec (Addr : System.Address);
      procedure Reg (Addr : System.Address; Ep : Interfaces.Unsigned_32);
      function Get (Addr : System.Address) return Natural;
   private
      Table : Ref_Array;
   end Tracker;

   overriding procedure Adjust (Self : in out Instance) is
   begin
      Tracker.Inc (Self.Target, Self.Epoch);
   end Adjust;

   overriding procedure Finalize (Self : in out Instance) is
   begin
      Tracker.Dec (Self.Target);
   end Finalize;

   function Get_Ref_Count (Addr : System.Address) return Natural is
   begin
      return Tracker.Get (Addr);
   end Get_Ref_Count;

   procedure Register_Target (Addr : System.Address; Ep : Interfaces.Unsigned_32) is
   begin
      Tracker.Reg (Addr, Ep);
   end Register_Target;

   protected body Tracker is
      procedure Inc (Addr : System.Address; Ep : Interfaces.Unsigned_32) is
      begin
         if Addr = System.Null_Address then
            return;
         end if;
         for I in Table'Range loop
            if Table (I).Addr = Addr then
               Table (I).Count := Table (I).Count + 1;
               return;
            end if;
         end loop;
         -- Not found, look for empty slot
         for I in Table'Range loop
            if Table (I).Addr = System.Null_Address then
               Table (I).Addr := Addr;
               Table (I).Epoch := Ep;
               Table (I).Count := 1;
               return;
            end if;
         end loop;
      end Inc;

      procedure Dec (Addr : System.Address) is
      begin
         if Addr = System.Null_Address then
            return;
         end if;
         for I in Table'Range loop
            if Table (I).Addr = Addr then
               if Table (I).Count > 0 then
                  Table (I).Count := Table (I).Count - 1;
                  if Table (I).Count = 0 then
                     Table (I).Addr := System.Null_Address;
                     Table (I).Epoch := 0;
                  end if;
               end if;
               return;
            end if;
         end loop;
      end Dec;

      procedure Reg (Addr : System.Address; Ep : Interfaces.Unsigned_32) is
      begin
         if Addr = System.Null_Address then
            return;
         end if;
         for I in Table'Range loop
            if Table (I).Addr = Addr then
               Table (I).Epoch := Ep;
               Table (I).Count := Table (I).Count + 1;
               return;
            end if;
         end loop;
         for I in Table'Range loop
            if Table (I).Addr = System.Null_Address then
               Table (I).Addr := Addr;
               Table (I).Epoch := Ep;
               Table (I).Count := 1;
               return;
            end if;
         end loop;
      end Reg;

      function Get (Addr : System.Address) return Natural is
      begin
         if Addr = System.Null_Address then
            return 0;
         end if;
         for I in Table'Range loop
            if Table (I).Addr = Addr then
               return Table (I).Count;
            end if;
         end loop;
         return 0;
      end Get;
   end Tracker;

end Aura.Cap_Object_Ref_Pkg;
