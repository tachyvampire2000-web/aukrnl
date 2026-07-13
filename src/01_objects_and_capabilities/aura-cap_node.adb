--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива).

package body Aura.Cap_Node is

   procedure Alloc
     (Obj_Epoch : Interfaces.Unsigned_32;
      Result    : out Cap_Node_Access;
      Status    : out Kernel_Error) is
   begin
      Result := null;
      Status := Not_Supported;
   end Alloc;

end Aura.Cap_Node;
