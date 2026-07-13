--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива).

package body Aura.Weak_Ref is

   function Downgrade (Strong : Element_Access) return Instance is
   begin
      return Result : Instance := (Target => Strong, Expected_Epoch => (if Strong = null then 0 else 1));
   end Downgrade;

   procedure Upgrade
     (Self  : Instance;
      Value : out Element_Access;
      Alive : out Boolean) is
   begin
      Value := Self.Target;
      Alive := Value /= null;
   end Upgrade;

end Aura.Weak_Ref;
