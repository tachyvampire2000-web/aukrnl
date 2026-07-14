--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package body Aura.Mac is

   protected body Audit_Channel is
      procedure dummy is begin null; end;
   end Audit_Channel;

   procedure Set_Mandatory_Label
     (Node : in out Aura.Namespace.Namespace_Node; New_Label : Mandatory_Label;
      Status : out Kernel_Error)
   is
   begin
      Status := Label_Immutable;  --  всегда — метка неизменяема после
                                    --  создания, идентично Rust-версии
   end Set_Mandatory_Label;

   procedure Propagate_Taint (Taint : in out Causal_Taint; Label : Mandatory_Label) is
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_64;
   begin
      Taint.Tainted := True;
      if Label.Level > Taint.Taint_Level then
         Taint.Taint_Level := Label.Level;
      end if;
      Taint.Taint_Categories := Taint.Taint_Categories or Label.Categories;
   end Propagate_Taint;

   function Check_Flow (Taint : Causal_Taint; Target : Mandatory_Label) return Kernel_Error is
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_64;
   begin
      if Taint.Tainted then
         -- Dynamic Bell-LaPadula No-Write-Down:
         -- Cannot write to a target with a lower security level,
         -- or to a target lacking our tainted categories!
         if Taint.Taint_Level > Target.Level
           or else (Taint.Taint_Categories and not Target.Categories) /= 0
         then
            return Write_Down_Violation;
         end if;
      end if;
      return Ok;
   end Check_Flow;

end Aura.Mac;
