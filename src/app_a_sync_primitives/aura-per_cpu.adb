--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива).

package body Aura.Per_Cpu is

   function Create (Val : Element_Type) return Instance is
   begin
      return Result : Instance do
         for I in Result.Data'Range loop
            Result.Data (I) := Val;
         end loop;
      end return;
   end Create;

   function Get (Self : Instance; Cpu_Id : Natural) return Element_Type is
   begin
      return Self.Data (Cpu_Id);
   end Get;

   procedure Set (Self : in out Instance; Cpu_Id : Natural; Val : Element_Type) is
   begin
      Self.Data (Cpu_Id) := Val;
   end Set;

end Aura.Per_Cpu;
