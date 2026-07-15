--  AURA Kernel — aura-per_cpu.ads
--  SPDX-License-Identifier: GPL-2.0-only


generic
   type Element_Type is private;
   Max_Cpus : Positive;
package Aura.Per_Cpu is

   pragma SPARK_Mode (On);

   type Instance is limited private;

   function Create (Val : Element_Type) return Instance;

   function Get (Self : Instance; Cpu_Id : Natural) return Element_Type
     with Pre => Cpu_Id < Max_Cpus;

   procedure Set (Self : in out Instance; Cpu_Id : Natural; Val : Element_Type)
     with Pre => Cpu_Id < Max_Cpus;

private
   type Element_Array is array (0 .. Max_Cpus - 1) of Element_Type;
   type Instance is limited record
      Data : Element_Array;
   end record;
end Aura.Per_Cpu;
